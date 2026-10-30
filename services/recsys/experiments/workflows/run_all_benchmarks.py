# -*- coding: utf-8 -*-
"""
Master Benchmark Runner: Thực hiện toàn diện thực nghiệm đối sánh
MF, iDCF, IViDR, LCDR, DR-BIAS + CDR, ConAlign trên Coat, Yahoo! R3 và KuaiRand-Pure.
LCDR dùng protocol H30 như iDCF; ConAlign giữ protocol và metric của source (C-src).
và hỗ trợ huấn luyện riêng lẻ, quét siêu tham số Grid Search.
Project: ViFarm (services/recsys)
"""

import os
import sys
import json
import time
import argparse
import hashlib
from datetime import datetime
from uuid import uuid4

try:
    sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)
except Exception:
    pass

# Thêm thư mục gốc dự án vào PYTHONPATH
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from src.utils.helpers import set_seed, get_device, RESULTS_DIR, CHECKPOINT_DIR
from src.utils.artifacts import validate_training, data_signature, source_signature, digest, evaluate_checkpoint
from src.data_pipeline.kuairand_dataset import subset_kuairand_users
from src.models.mf.train_mf import train_baseline_mf
from src.models.ividr.ividr_staged import DEFAULT_ALPHA_RESIDUAL, mf_item_embeddings
from src.models.idcf.train_idcf import IDCF_CONFIG, fit_idcf_pipeline
from src.models.cdr.train_dr_bias_cdr import train_dr_bias_cdr
from src.evaluation.diagnostics import evaluate_popularity, candidate_pool_diagnostics, paired_ndcg_difference
from src.data_pipeline.coat_dataset import load_coat_processed
from src.data_pipeline.yahoo_dataset import load_yahoo_processed, subset_yahoo_users
from src.models.cdr.train_released_cdr import train_released_cdr
from src.models.cdr.source_protocol import run_source
from src.data_pipeline.kuairand_dataset import load_kuairand_processed
from src.training.config import mf_config, cdr_config
from src.evaluation.protocol import protocol_metadata
from src.models.lcdr.train_lcdr import fit_lcdr_pipeline
from src.models.conalign.data import load_conalign_data
from src.models.conalign.train import setup_seed as conalign_setup_seed, train_conalign


MODEL_NAMES = ("MF", "iDCF", "IViDR", "LCDR", "DR-BIAS + CDR", "ConAlign")
# User-selected suite; IViDR uses learned reconstruction and BCE feedback.
STANDARD_MODELS = MODEL_NAMES
MODEL_KEYS = {"MF": "mf", "iDCF": "idcf", "IViDR": "ividr", "LCDR": "lcdr", "DR-BIAS + CDR": "cdr",
              "ConAlign": "conalign"}
# Rows trained and scored on their own source protocol: no shared-split paired tests.
SOURCE_SCOPES = ("cdr_source_protocol", "conalign_source_protocol")
CONALIGN_SEED = 0  # Author default seed (mymodel.py)


def paired_significance(dataset_results, data, device=None):
    """Wilcoxon theo cặp user trên test: mỗi mô hình so với Popularity và với MF."""
    per_user = {"Popularity": evaluate_popularity(data, return_user_ndcg=True)}
    for name in MODEL_NAMES:
        if (name in dataset_results and dataset_results[name].get("checkpoint_path")
                and dataset_results[name].get('evaluation_scope') not in SOURCE_SCOPES):
            per_user[name] = evaluate_checkpoint(dataset_results[name]["checkpoint_path"], data,
                                                 device, return_user_ndcg=True)
    out = {}
    for name in MODEL_NAMES:
        for base in ("Popularity", "MF"):
            if name in per_user and base in per_user and name != base:
                out[f"{name} vs {base}"] = paired_ndcg_difference(per_user[name], per_user[base])
    return out


def run_idcf_family(name, dataset, data, mf_result, mf_kwargs, tag, epochs, ivae_epochs,
                    train_overrides=None, ivae_overrides=None, device=None, checkpoint_dir=None):
    """iDCF hoặc IViDR theo giai đoạn; IViDR lấy treatment T từ checkpoint MF (huấn luyện nếu chưa có)."""
    item_emb = None
    if name == "IViDR":
        if not (mf_result or {}).get("checkpoint_path"):
            mf_result = train_baseline_mf(dataset_name=dataset, evaluate_test=False,
                                          checkpoint_tag=f"{tag}_treatment", **mf_kwargs)
        item_emb = mf_item_embeddings(mf_result["checkpoint_path"])
    if name == "LCDR":
        return fit_lcdr_pipeline(data, dataset, seed=42, checkpoint_tag=tag, epochs=epochs,
                                 representation_epochs=ivae_epochs, train_overrides=train_overrides,
                                 representation_overrides=ivae_overrides, device=device,
                                 checkpoint_dir=checkpoint_dir)
    return fit_idcf_pipeline(data, dataset, seed=42, item_emb=item_emb, checkpoint_tag=tag, epochs=epochs,
                             ivae_epochs=ivae_epochs, train_overrides=train_overrides,
                             ivae_overrides=ivae_overrides, device=device, checkpoint_dir=checkpoint_dir)


def run_conalign(dataset, quick_run=False, smoke_users=None, device=None, checkpoint_dir=None):
    """ConAlign trên dữ liệu/protocol riêng của source; bảng hiển thị tháp unbiased trên test unbiased."""
    conalign_setup_seed(CONALIGN_SEED)  # Trước khi nạp dữ liệu, giữ thứ tự RNG như source.
    data = load_conalign_data(dataset, seed=CONALIGN_SEED, device=device,
                              smoke_users=smoke_users if dataset == "kuairand" else None)
    result = train_conalign(data, dataset, seed=CONALIGN_SEED, device=device, checkpoint_dir=checkpoint_dir,
                            overrides=dict(pretrain_epochs=2, finetune_epochs=2) if quick_run else None)
    tower = result["source_metrics"]["test_unbiased"]["unbiased_tower"]
    return {"evaluation_scope": "conalign_source_protocol", "NDCG@5": tower["NDCG"], "UNDCG@5": tower["UNDCG"],
            "UAUC": tower["UAUC"], "AUC_global": tower["AUC"], "Precision@5": tower["Precision"],
            "Recall@5_source": tower["Recall"], "metadata": result["identity"],
            "checkpoint_path": result["checkpoint_path"], "stage1": result["stage1"], "stage2": result["stage2"],
            "source_metrics": result["source_metrics"], "seconds": result["seconds"]}


def run_all_benchmarks(
    quick_run: bool = False,
    epochs_coat: int = None,
    epochs_kr: int = None,
    dataset_filter: str = "all",
    model_filter: str = "all",
    dim: int = None,
    lr: float = None,
    batch_size: int = None,
    alpha: float = 0.0,
    grid_search: bool = False,
    smoke_users: int = None,
    device: str = None,
    ivae_epochs: int = None,
    ivae_lr: float = None,
    ivae_batch_size: int = None,
    latent_dim: int = None,
    init_scheme: str = None,
    cdr_propensity: str = None,
    threads: int = None,
    epochs_yahoo: int = None,
    cdr_implementation: str = "auto",
):
    validate_training(epochs_coat=epochs_coat, epochs_kr=epochs_kr, dim=dim,
                      lr=lr, batch_size=batch_size, smoke_users=smoke_users, ivae_epochs=ivae_epochs,
                      ivae_lr=ivae_lr, ivae_batch_size=ivae_batch_size, latent_dim=latent_dim,
                      threads=threads, epochs_yahoo=epochs_yahoo)
    if cdr_implementation not in ("auto","released","shared","equation"):
        raise ValueError("Unknown CDR implementation")
    if cdr_propensity is not None and (cdr_propensity not in ("provided_coat", "naive_bayes_validation")
            or dataset_filter != "coat" or model_filter not in ("all", "cdr")):
        raise ValueError("--cdr-propensity requires --dataset coat and --model all/cdr")
    if cdr_propensity is not None and cdr_implementation != "equation":
        raise ValueError("--cdr-propensity requires --cdr-implementation equation")
    if dataset_filter not in ("all", "coat", "kuairand", "yahoo") or model_filter not in ("all", *MODEL_KEYS.values()):
        raise ValueError("Unsupported dataset/model")
    import math
    if not math.isfinite(alpha) or alpha < 0:
        raise ValueError("alpha must be finite and nonnegative")
    if grid_search and (dataset_filter != "kuairand" or model_filter != "mf"):
        raise ValueError("--grid-search requires --dataset kuairand --model mf; use tune_coat_models.py for Coat")
    if grid_search and (lr is not None or quick_run or smoke_users is not None):
        raise ValueError("Grid search does not accept --lr, --quick or --smoke-users")
    if (grid_search or model_filter in ("mf", "cdr", "conalign")) and any(
            value is not None for value in (ivae_epochs, ivae_lr, ivae_batch_size, latent_dim)):
        raise ValueError("iVAE overrides require an iDCF/IViDR/LCDR benchmark")
    if init_scheme is not None and model_filter in ("cdr", "conalign"):
        raise ValueError("--init-scheme applies to MF/iDCF/IViDR/LCDR")
    if smoke_users is not None and (not quick_run or dataset_filter not in ("kuairand","yahoo")):
        raise ValueError("--smoke-users requires --quick --dataset kuairand/yahoo")
    if init_scheme not in (None, "normal", "author_uniform"):
        raise ValueError("Invalid MF initialization scheme")
    set_seed(42)
    if threads is not None:
        import torch
        torch.set_num_threads(threads)
    device = get_device(device)
    run_id = datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid4().hex[:8]
    checkpoint_root = os.path.join(CHECKPOINT_DIR, "benchmark_runs", run_id)
    train_overrides = {k: v for k, v in dict(embedding_dim=dim, lr=lr, batch_size=batch_size, init_scheme=init_scheme).items() if v is not None}
    cdr_budgets = dict(coat=epochs_coat, yahoo=epochs_yahoo, kuairand=epochs_kr)
    ivae_overrides = {k: v for k, v in dict(lr=ivae_lr, batch_size=ivae_batch_size, latent_dim=latent_dim).items() if v is not None}

    def train_cdr(dataset,data,epochs,tag):
        implementation = "released" if cdr_implementation == "auto" else cdr_implementation
        common = dict(dataset_name=dataset,data_dict=data,device=device,
                      checkpoint_tag=tag,checkpoint_dir=os.path.join(checkpoint_root,dataset,"cdr"))
        if implementation == "released":
            budget=cdr_budgets[dataset]
            return run_source(dataset,epochs=budget if budget is not None else (1 if quick_run else 1000),
                seed=2020,threads=threads or 2,data_dir=data.get('data_dir'),device=device,
                smoke_users=smoke_users if dataset=='kuairand' else None,
                embedding_dim=dim,lr=lr,batch_size=batch_size,
                checkpoint_dir=common['checkpoint_dir'])
        if implementation == "shared":
            effective_batch = batch_size
            if effective_batch is None and quick_run and smoke_users is not None:
                effective_batch = min(256, len(data["train_y"]))
            return train_released_cdr(**common,epochs=epochs,embedding_dim=dim,lr=lr,batch_size=effective_batch)
        return train_dr_bias_cdr(**common,**cdr_config(dataset,epochs=epochs,embedding_dim=dim,
            lr=lr,batch_size=batch_size,propensity_mode=cdr_propensity))

    def selected(name):
        return model_filter == MODEL_KEYS[name] or (model_filter == "all" and name in STANDARD_MODELS)

    def train_conalign_row(dataset):
        print(f"\n>>> Huấn luyện ConAlign ({dataset}, protocol source)...")
        return run_conalign(dataset, quick_run=quick_run, smoke_users=smoke_users, device=device,
                            checkpoint_dir=os.path.join(checkpoint_root, dataset, "conalign"))

    def checkpoint_tag(name, epoch_count):
        config = {"model": name, "epochs": epoch_count, "quick": quick_run,
                  "dim": dim, "lr": lr, "batch_size": batch_size, "alpha": alpha,
                  "kuairand_protocol": "paper_idcf", "coat_protocol": "paper_idcf"}
        digest = hashlib.sha256(json.dumps(config, sort_keys=True).encode()).hexdigest()[:10]
        return f"v4_e{epoch_count}_{'quick' if quick_run else 'full'}_{digest}"

    # Xử lý chế độ Quét Siêu Tham Số (Grid Search) nếu được yêu cầu
    if grid_search:
        from src.training.train_pipeline import run_grid_search
        data_dict = load_kuairand_processed(alpha=alpha)
        grid_mf = mf_config("kuairand", embedding_dim=dim, batch_size=batch_size,
                            epochs=epochs_kr, init_scheme=init_scheme)
        best_cfg, trials = run_grid_search(
            data_dict=data_dict,
            embedding_dim=grid_mf["embedding_dim"],
            batch_size=grid_mf["batch_size"],
            epochs=grid_mf["epochs"],
            device=device,
            training_options={key: grid_mf[key] for key in ("loss_name", "decay_scope", "scheduler_name",
                                "train_global_bias", "init_scheme", "patience")}
        )
        grid_config = {"data": data_signature(data_dict), "code_sha256": source_signature(),
                       "artifact_version": 4, "seed": 42,
                       "trial_metadata": [t["metadata"] for t in trials], "alpha": alpha,
                       "kuairand_protocol": "paper_idcf", "effective_config": grid_mf}
        grid_digest = hashlib.sha256(json.dumps(grid_config, sort_keys=True).encode()).hexdigest()[:10]
        summary_path = os.path.join(RESULTS_DIR, f"grid_search_v4_{grid_digest}.json")
        with open(summary_path, "w", encoding="utf-8") as f:
            json.dump({"protocol": "validation_tuning_then_one_held_out_test", "config": grid_config,
                       "evaluation_protocol": protocol_metadata(data_dict),
                       "best_config": best_cfg, "all_trials": trials}, f, indent=2)
        print(f"[OK] Đã lưu kết quả Grid Search tại: {summary_path}")
        return

    print("=" * 80)
    print(" BẮT ĐẦU CHẠY THỰC NGHIỆM ĐỐI SÁNH TRÊN COAT / YAHOO / KUAIRAND")
    print(f" Thiết bị: {device} | Dataset: {dataset_filter} | Model: {model_filter}")
    print("=" * 80)

    # Cấu hình số epoch linh hoạt
    # MF KuaiRand với lr 5e-5 của tác giả hội tụ chậm (val còn tăng sau epoch 19), nên mặc định
    # 100 epoch + patience 5 như MF.py (cả iDCF/IViDR); CDR dùng ngân sách từ config riêng.
    mf_epochs_kr = epochs_kr if epochs_kr is not None else (3 if quick_run else mf_config("kuairand")["epochs"])
    ivae_epochs = ivae_epochs if ivae_epochs is not None else (2 if quick_run else 2000)
    epochs_yahoo = epochs_yahoo if epochs_yahoo is not None else (3 if quick_run else mf_config("yahoo")["epochs"])
    if quick_run:
        epochs_coat = 5 if epochs_coat is None else epochs_coat
        epochs_kr = 3 if epochs_kr is None else epochs_kr
    else:
        epochs_coat = mf_config("coat")["epochs"] if epochs_coat is None else epochs_coat
        epochs_kr = cdr_config("kuairand")["epochs"] if epochs_kr is None else epochs_kr

    print(f" [CẤU HÌNH EPOCHS] Coat: {epochs_coat} | Yahoo: {epochs_yahoo} | KuaiRand-Pure: {epochs_kr} (MF: {mf_epochs_kr})")
    if cdr_implementation in ('auto','released'):
        print(f" [CDR SOURCE] seed 2020; epoch budgets: "
              f"{ {d: n if n is not None else (1 if quick_run else 1000) for d,n in cdr_budgets.items()} }; train-loss stopping")

    all_results = {
        "artifact_version": 4,
        "coat": {},
        "kuairand": {},
        "yahoo": {},
        "diagnostics": {},
        "significance": {},
        "evaluation_protocol": {},
        "protocol": {
            "selection": "validation_only",
            "run_id": run_id,
            "threads_override": threads,
            "test": "held_out_final_evaluation",
            "candidate_pool": "logged_exposures_only",
            "include_zero_positive_users": {"coat": False, "kuairand": False, "yahoo": False},
            "coat_protocol": "paper_idcf",
            "idcf_config": IDCF_CONFIG,
            "ividr_implementation": "ividr_reference_bce_v2",
            "lcdr_protocol": "H30, iDCF data/evaluator; stage 1 budget = ivae_epochs",
            "conalign_protocol": {"scope": "conalign_source_protocol", "seed": CONALIGN_SEED,
                                  "kuairand_window": "paper", "config": "source para()",
                                  "overrides_applied": False},
            "ivae_epochs": ivae_epochs,
            "stage2_overrides": train_overrides,
            "stage1_overrides": ivae_overrides,
            "device": str(device),
            "kuairand_protocol": "paper_idcf",
            "kuairand_random_val_fraction": 0.3,
            "paper_scores_directly_comparable": False,
            "coat_random_split_seed": 1234,
            "alpha": alpha,
            "alpha_applies_to": ["MF"],
            "kuairand_cdr_propensity": "item_exposure_frequency_proxy_clipped_0.05_to_1.0",
            "quick_run": quick_run,
            "seed": 42,
            "epochs_coat": epochs_coat,
            "epochs_kuairand": epochs_kr,
            "epochs_yahoo": epochs_yahoo,
            "cdr_implementation": cdr_implementation,
            "dimension_override": dim,
            "learning_rate_override": lr,
            "batch_size_override": batch_size,
        },
    }
    errors = []

    # =========================================================================
    # 1. THỰC NGHIỆM TRÊN COAT DATASET
    # =========================================================================
    if dataset_filter in ["all", "coat"]:
        print("\n" + "#" * 80)
        print(" PHẦN 1: THỰC NGHIỆM TRÊN TẬP DỮ LIỆU COAT (290 Users, 300 Items)")
        print("#" * 80)
        coat_data = load_coat_processed()
        all_results["evaluation_protocol"]["coat"] = protocol_metadata(coat_data)
        all_results["protocol"]["coat_split_info"] = coat_data["split_info"]
        coat_diagnostics = candidate_pool_diagnostics(coat_data)
        all_results["coat"]["Random (expected)"] = coat_diagnostics["random_expected"]
        all_results["coat"]["Popularity"] = evaluate_popularity(coat_data)
        all_results["diagnostics"]["coat"] = coat_diagnostics
        all_results["diagnostics"]["coat_validation"] = candidate_pool_diagnostics(coat_data, split="val")

        # Cấu hình MF của mã tác giả iDCF (MF.py): MSE trên điểm thô, Adam decay mọi tham số,
        # không scheduler, intercept cố định 0; Coat lr 5e-4, wd 1e-6, patience 5. Cũng là treatment của IViDR.
        mf_coat = mf_config("coat", embedding_dim=dim, epochs=epochs_coat, lr=lr,
                            batch_size=batch_size, device=device, data_dict=coat_data, init_scheme=init_scheme,
                            checkpoint_dir=os.path.join(checkpoint_root, "coat", "mf"))
        if model_filter in ["all", "mf"]:
            print("\n>>> Huấn luyện Baseline PyTorch MF (Coat)...")
            try:
                all_results["coat"]["MF"] = train_baseline_mf(
                    dataset_name="coat", checkpoint_tag=checkpoint_tag("coat_mf", epochs_coat), **mf_coat)
            except Exception as e:
                print(f"[LỖI] Huấn luyện MF trên Coat thất bại: {e}")
                errors.append(("coat", "MF", str(e)))

        for name in ("iDCF", "IViDR", "LCDR"):
            if selected(name):
                print(f"\n>>> Huấn luyện {name} (Coat)...")
                try:
                    all_results["coat"][name] = run_idcf_family(
                        name, "coat", coat_data, all_results["coat"].get("MF"), mf_coat,
                        checkpoint_tag(f"coat_{name.lower()}", epochs_coat), epochs_coat, ivae_epochs,
                        train_overrides=train_overrides, ivae_overrides=ivae_overrides, device=device,
                        checkpoint_dir=os.path.join(checkpoint_root, "coat", name.lower()))
                except Exception as e:
                    print(f"[LỖI] Huấn luyện {name} trên Coat thất bại: {e}")
                    errors.append(("coat", name, str(e)))

        if model_filter in ["all", "cdr"]:
            print("\n>>> Huấn luyện DR-BIAS + CDR (Coat)...")
            try:
                all_results["coat"]["DR-BIAS + CDR"] = train_cdr(
                    "coat",coat_data,epochs_coat,checkpoint_tag("coat_cdr",epochs_coat))
            except Exception as e:
                print(f"[LỖI] Huấn luyện DR-BIAS + CDR trên Coat thất bại: {e}")
                errors.append(("coat", "DR-BIAS + CDR", str(e)))

        if selected("ConAlign"):
            try:
                all_results["coat"]["ConAlign"] = train_conalign_row("coat")
            except Exception as e:
                print(f"[LỖI] Huấn luyện ConAlign trên Coat thất bại: {e}")
                errors.append(("coat", "ConAlign", str(e)))

        if not errors:
            all_results["significance"]["coat"] = paired_significance(all_results["coat"], coat_data, device)

    if dataset_filter in ("all","yahoo"):
        yahoo_data=load_yahoo_processed()
        if smoke_users is not None:
            yahoo_data=subset_yahoo_users(yahoo_data,smoke_users)
        all_results["evaluation_protocol"]["yahoo"]=protocol_metadata(yahoo_data)
        all_results["protocol"]["yahoo_split_info"]=yahoo_data["split_info"]
        all_results["protocol"]["yahoo_proxy_features"]=yahoo_data["user_feature_info"]
        diagnostics=candidate_pool_diagnostics(yahoo_data)
        all_results["diagnostics"]["yahoo"]=diagnostics
        all_results["diagnostics"]["yahoo_validation"]=candidate_pool_diagnostics(yahoo_data,split="val")
        all_results["yahoo"]["Random (expected)"]=diagnostics["random_expected"]
        all_results["yahoo"]["Popularity"]=evaluate_popularity(yahoo_data)
        mf_yahoo=mf_config("yahoo",embedding_dim=dim,epochs=epochs_yahoo,lr=lr,batch_size=batch_size,
            device=device,data_dict=yahoo_data,init_scheme=init_scheme,
            checkpoint_dir=os.path.join(checkpoint_root,"yahoo","mf"))
        for name in STANDARD_MODELS:
            if not selected(name):
                continue
            try:
                if name=="MF":
                    value=train_baseline_mf(dataset_name="yahoo",**mf_yahoo)
                elif name=="ConAlign":
                    value=train_conalign_row("yahoo")
                elif name in ("iDCF", "IViDR", "LCDR"):
                    value=run_idcf_family(name,"yahoo",yahoo_data,all_results['yahoo'].get('MF'),mf_yahoo,
                        checkpoint_tag(f"yahoo_{name.lower()}",epochs_yahoo),epochs_yahoo,ivae_epochs,
                        train_overrides=train_overrides,ivae_overrides=ivae_overrides,device=device,
                        checkpoint_dir=os.path.join(checkpoint_root,"yahoo",name.lower()))
                else:
                    value=train_cdr("yahoo",yahoo_data,epochs_yahoo,checkpoint_tag("yahoo_cdr",epochs_yahoo))
                all_results["yahoo"][name]=value
            except Exception as error:
                errors.append(("yahoo",name,str(error)))
        if not errors:
            all_results["significance"]["yahoo"]=paired_significance(all_results["yahoo"],yahoo_data,device)

    # =========================================================================
    # KUAIRAND-PURE DATASET (IS_CLICK)
    # =========================================================================
    if dataset_filter in ["all", "kuairand"]:
        print("\n" + "#" * 80)
        print(" PHẦN 2: THỰC NGHIỆM KUAIRAND-PURE (IS_CLICK, IDCF DATA SPLIT)")
        print("#" * 80)
        kr_data = load_kuairand_processed(alpha=alpha)
        if smoke_users is not None:
            kr_data = subset_kuairand_users(kr_data, smoke_users)
        all_results["evaluation_protocol"]["kuairand"] = protocol_metadata(kr_data)
        kr_diagnostics = candidate_pool_diagnostics(kr_data)
        all_results["kuairand"]["Random (expected)"] = kr_diagnostics["random_expected"]
        all_results["kuairand"]["Popularity"] = evaluate_popularity(kr_data)
        all_results["diagnostics"]["kuairand"] = kr_diagnostics
        all_results["diagnostics"]["kuairand_validation"] = candidate_pool_diagnostics(kr_data, split="val")
        all_results["protocol"]["kuairand_split_info"] = kr_data["split_info"]

        # Cấu hình MF KuaiRand của tác giả iDCF: MSE, lr 5e-5, wd 1e-6, dim 64, batch 2048.
        mf_kr = mf_config("kuairand", embedding_dim=dim, epochs=mf_epochs_kr, lr=lr,
                          batch_size=batch_size, device=device, alpha=alpha, data_dict=kr_data, init_scheme=init_scheme,
                          checkpoint_dir=os.path.join(checkpoint_root, "kuairand", "mf"))
        if model_filter in ["all", "mf"]:
            print("\n>>> Huấn luyện Baseline PyTorch MF (KuaiRand)...")
            try:
                all_results["kuairand"]["MF"] = train_baseline_mf(
                    dataset_name="kuairand", checkpoint_tag=checkpoint_tag("kuairand_mf", epochs_kr), **mf_kr)
            except Exception as e:
                print(f"[LỖI] Huấn luyện MF trên KuaiRand thất bại: {e}")
                errors.append(("kuairand", "MF", str(e)))

        for name in ("iDCF", "IViDR", "LCDR"):
            if selected(name):
                print(f"\n>>> Huấn luyện {name} (KuaiRand)...")
                try:
                    all_results["kuairand"][name] = run_idcf_family(
                        name, "kuairand", kr_data, all_results["kuairand"].get("MF"), mf_kr,
                        checkpoint_tag(f"kuairand_{name.lower()}", mf_epochs_kr), mf_epochs_kr, ivae_epochs,
                        train_overrides=train_overrides, ivae_overrides=ivae_overrides, device=device,
                        checkpoint_dir=os.path.join(checkpoint_root, "kuairand", name.lower()))
                except Exception as e:
                    print(f"[LỖI] Huấn luyện {name} trên KuaiRand thất bại: {e}")
                    errors.append(("kuairand", name, str(e)))

        if model_filter in ["all", "cdr"]:
            print("\n>>> Huấn luyện DR-BIAS + CDR (KuaiRand)...")
            try:
                all_results["kuairand"]["DR-BIAS + CDR"] = train_cdr(
                    'kuairand',kr_data,epochs_kr,checkpoint_tag('kuairand_cdr',epochs_kr))
            except Exception as e:
                print(f"[LỖI] Huấn luyện DR-BIAS + CDR trên KuaiRand thất bại: {e}")
                errors.append(("kuairand", "DR-BIAS + CDR", str(e)))

        if selected("ConAlign"):
            try:
                all_results["kuairand"]["ConAlign"] = train_conalign_row("kuairand")
            except Exception as e:
                print(f"[LỖI] Huấn luyện ConAlign trên KuaiRand thất bại: {e}")
                errors.append(("kuairand", "ConAlign", str(e)))

        if not errors:
            all_results["significance"]["kuairand"] = paired_significance(all_results["kuairand"], kr_data, device)

    # =========================================================================
    # 3. LƯU KẾT QUẢ VÀ TẠO BÁO CÁO TỔNG HỢP
    # =========================================================================
    if errors:
        raise RuntimeError(f"Benchmark incomplete; no report written. Failures: {errors}")
    run_tag = "all" if dataset_filter == model_filter == "all" and not quick_run else f"{dataset_filter}_{model_filter}{'_quick' if quick_run else ''}"
    model_metadata = {d: {name: value["metadata"] for name, value in all_results[d].items()
                          if "metadata" in value} for d in ("coat", "kuairand", "yahoo")}
    all_results["protocol"]["smoke_users"] = smoke_users
    report_config = {"effective_runs": model_metadata, "version": 4, "smoke_users": smoke_users, "dataset": dataset_filter, "model": model_filter, "epochs_coat": epochs_coat,
                     "epochs_kr": epochs_kr, "mf_epochs_kr": mf_epochs_kr, "dim": dim, "lr": lr, "batch_size": batch_size, "alpha": alpha,
                     "kuairand_protocol": "paper_idcf", "coat_protocol": "paper_idcf"}
    run_tag += "_" + hashlib.sha256(json.dumps(report_config, sort_keys=True).encode()).hexdigest()[:10]
    json_path = os.path.join(RESULTS_DIR, f"benchmark_{run_tag}_{run_id}_v4.json")

    with open(json_path, "x", encoding="utf-8") as f:
        json.dump(all_results, f, indent=2, ensure_ascii=False)
    print(f"\n[OK] Đã lưu kết quả chi tiết JSON tại: {json_path}")

    # Tạo bảng Markdown chuẩn duy nhất
    table_md = generate_markdown_report(all_results)
    table_path = os.path.join(RESULTS_DIR, f"benchmark_{run_tag}_{run_id}_v4.md")
    with open(table_path, "x", encoding="utf-8") as f:
        f.write(table_md)
    print(f"[OK] Đã lưu báo cáo khoa học Markdown tại: {table_path}")

    # In bảng lưới đóng khung chuyên nghiệp ra Console (có khoảng chắn giữa các hàng/cột)
    console_report = generate_console_grid_report(all_results)
    print(console_report)
    return all_results


def get_benchmark_tables_data(results):
    headers = ["Tập dữ liệu", "Mô hình", "Giao thức", "NDCG@5",
               "Recall@5 bounded", "Precision@5", "HitRate@5", "AUC", "Loại AUC"]
    rows = []
    for dataset, title in (("coat", "Coat"), ("yahoo", "Yahoo! R3"), ("kuairand", "KuaiRand-Pure")):
        for name in MODEL_NAMES:
            metric = results.get(dataset, {}).get(name)
            if metric is None:
                continue
            scope = metric.get("evaluation_scope")
            source = scope in SOURCE_SCOPES
            protocol = ("C-src" if scope == "conalign_source_protocol" else
                        ("S-KR" if dataset == "kuairand" else "S-full") if source else "H30")
            def value(key):
                actual = metric.get(key)
                return f"{actual:.6f}" if actual is not None else "N/A"
            label = (metric.get('metadata',{}).get('config',{}).get('display_name','IViDR-approx')
                     if name == "IViDR" else name)
            rows.append([title, label, protocol, value("NDCG@5"),
                         value("Recall@5_bounded"), value("Precision@5"), value("HitRate@5"),
                         value("AUC_global" if source else "AUC"), "global" if source else "macro-user"])
    return headers, rows


def conalign_notes(results):
    """UAUC/UNDCG của ConAlign: metric chính của paper, không có cột tương ứng trong bảng chung."""
    lines = []
    for dataset, title in (("coat", "Coat"), ("yahoo", "Yahoo! R3"), ("kuairand", "KuaiRand-Pure")):
        metric = results.get(dataset, {}).get("ConAlign")
        if metric is not None:
            lines.append(f"ConAlign {title}: UAUC {metric['UAUC']:.6f} | UNDCG@5 {metric['UNDCG@5']:.6f} "
                         f"| Recall (source) {metric['Recall@5_source']:.6f}")
    return lines


CONALIGN_NOTE = ("C-src: ConAlign theo source (seed 0, para()); tháp unbiased trên test unbiased; Coat/Yahoo chia "
                 "ngẫu nhiên, rating >=4; KuaiRand train 22/04-05/05 theo paper. NDCG@5 = NDCG của source "
                 "(user có cả hai nhãn); không có Recall bounded/HitRate.")


def generate_console_grid_report(results):
    from src.evaluation.table_formatter import format_grid_table
    headers, rows = get_benchmark_tables_data(results)
    grid = format_grid_table(headers=headers, rows=rows,
        col_aligns=["left", "left", "center"] + ["right"] * 5 + ["left"],
        title="KẾT QUẢ THEO GIAO THỨC TỪNG MÔ HÌNH", row_divider=True)
    extra = "".join(f"{line}\n" for line in conalign_notes(results))
    return (f"\n{grid}\n{extra}"
            "H30: held-out user split 30/70, Coat/Yahoo >=4.\n"
            "S-full: CDR Coat/Yahoo >=3, toàn random log, 5% nhãn random để calibration.\n"
            "S-KR: CDR KuaiRand local split, calibration 5% validation; adaptation theo metadata.\n"
            f"{CONALIGN_NOTE}\n"
            "Recall@5 bounded: hits/min(5, tổng positive). Recall/all positives vẫn lưu trong JSON.\n"
            "CDR S-full giữ quy ước empty-positive Recall=1; precision/hit-rate=0.\n"
            "Bảng gộp để đọc; không xếp hạng hay paired-test chéo giao thức.\n")


def generate_markdown_report(results):
    from src.evaluation.table_formatter import format_markdown_table
    headers_local, rows_local = get_benchmark_tables_data(results)

    r_local_md = [[f"**{row[0]}**"] + row[1:] for row in rows_local]
    md_local = format_markdown_table(
        headers=headers_local,
        rows=r_local_md,
        col_aligns=["left", "left", "center"] + ["right"] * 5 + ["left"]
    )

    lines = [
        "# Benchmark v4: kết quả theo giao thức từng mô hình",
        "",
        (f"**SMOKE TEST — MF/iDCF subset {results['protocol']['smoke_users']} user; dữ liệu CDR theo metadata riêng, không dùng so điểm bài báo.**"
         if results["protocol"].get("smoke_users") else
         "**SMOKE TEST — kiểm tra vận hành, chưa phải kết quả hội tụ.**" if results["protocol"].get("quick_run") else
         "**Đầy đủ dữ liệu; mỗi mô hình huấn luyện và đánh giá theo giao thức ghi ở từng dòng.**"),
        "",
        f"**Thời gian cập nhật:** {time.strftime('%Y-%m-%d %H:%M:%S')}",
        "",
        "Ranking trên exposure đã ghi log. MF/iDCF chọn checkpoint bằng validation; CDR source dừng theo train loss.",
        "Bảng chỉ hiển thị Recall@5 bounded; JSON giữ cả hai Recall. AUC có giá trị và loại riêng ở từng dòng.",
        "H30: split 30/70 theo user, loại zero-positive; S-full: toàn random log và giữ empty-positive Recall=1; S-KR: dữ liệu KuaiRand địa phương.",
        "LCDR cài đặt lại từ paper (không có mã tác giả) trên pipeline iDCF, cùng protocol H30. " + CONALIGN_NOTE,
        "MF/iDCF/LCDR giữ MSE; IViDR, CDR và ConAlign dùng BCE. IViDR: BCE trên xác suất đã marginalize, giai đoạn 1 prior mean 0 và mẫu âm trọng số .1 (khác Eq. 42/25 của paper); coordinate adapter Eq. (10) ghi trong metadata, chưa chứng nhận tái lập tác giả. Không paired-test chéo protocol.",
        "Tất cả điểm đo từ checkpoint thực, không thay bằng số paper. CDR source dùng một phần nhãn random chấm điểm để calibration, không phải held-out độc lập.",
        "",
        "### Kết quả theo giao thức từng mô hình:",
        "",
        md_local,
        ""
    ]
    notes = conalign_notes(results)
    if notes:
        lines.extend([f"- {line}" for line in notes] + [""])
    lines.extend([
        "Recall@5 bounded = hits/min(5,n_positive). CDR S-full giữ empty-positive Recall=1; Precision/HitRate=0. Recall/all positives vẫn lưu trong JSON.",
        "Gộp để đọc kết quả; các dòng khác protocol không tương đương về điều kiện thực nghiệm.", ""])
    for name in ("coat", "yahoo", "kuairand"):
        d = results.get("diagnostics", {}).get(name)
        if d:
            val_d = results["diagnostics"].get(f"{name}_validation", {})
            lines.extend([
                f"### Candidate pool {name}",
                "",
                f"- Users: {d['users']:,}; zero-positive users: {d['zero_positive_users']:,}; candidates: {d['candidate_pairs']:,}.",
                f"- Positive prevalence: {d['pooled_positive_rate']:.4f}; candidate size p10/p50/p90: {d['candidate_size_p10_p50_p90']}.",
                f"- Cold users: {d['cold_user_fraction']:.2%}; cold candidates: {d['cold_candidate_fraction']:.2%}.",
                f"- Validation positive prevalence: {val_d.get('pooled_positive_rate', 0.0):.4f}; validation candidate p50: {val_d.get('candidate_size_p10_p50_p90', [0, 0, 0])[1]:.0f}.",
                "",
            ])
            popularity = results[name]["Popularity"]["NDCG@5"]
            for model_name in MODEL_NAMES:
                if model_name in results[name] and results[name][model_name].get('evaluation_scope') not in SOURCE_SCOPES:
                    metric = results[name][model_name]
                    lines.append(
                        f"- {model_name}: ΔNDCG@5 so với Popularity = "
                        f"{metric['NDCG@5'] - popularity:+.4f}; "
                        f"CI95 NDCG của mô hình, theo user ≈ ±{metric['NDCG@5_CI95_halfwidth']:.4f}."
                    )
            lines.append("")
    for name, tests in results.get("significance", {}).items():
        if not tests:
            continue
        lines.extend([f"### Kiểm định theo cặp user ({name}, test)", "",
                      "| So sánh | ΔNDCG@5 | CI95 | Wilcoxon p | Thắng / thua (user) |",
                      "| :-- | --: | --: | --: | :--: |"])
        for label, t in tests.items():
            lines.append(f"| {label} | {t['mean_delta_ndcg']:+.4f} | ±{t['CI95_halfwidth']:.4f} | "
                         f"{t['wilcoxon_p']:.3g} | {t['wins']} / {t['losses']} |")
        lines.extend(["", "p < 0.05: khác biệt có ý nghĩa thống kê trên tập user này (một seed huấn luyện; chưa tính biến thiên seed).", ""])
    coat_split = results["protocol"].get("coat_split_info")
    if coat_split:
        lines.extend([
            f"Coat train/random overlap: {coat_split['train_random_overlap_pairs']} cặp; "
            f"test overlap: {coat_split['test_overlap_pairs']} cặp, "
            f"gồm {coat_split['test_overlap_positive_pairs']} cặp dương.",
            "",
        ])
    cdr_meta = results.get("coat", {}).get("DR-BIAS + CDR", {}).get("metadata", {}).get("config", {})
    if cdr_meta:
        lines.extend(["### Cấu hình CDR Coat", "",
            f"- Implementation: `{cdr_meta.get('implementation', 'equation')}`; selection: `{cdr_meta.get('selection')}`.",
            f"- LR {cdr_meta.get('lr')}, weight decay {cdr_meta.get('weight_decay')}, "
            f"batch {cdr_meta.get('batch_size')}, eta {cdr_meta.get('un_thres')}, "
            f"patience {cdr_meta.get('patience')}.", ""])
        if cdr_meta.get("propensity") == "naive_bayes_validation":
            lines.extend(["Validation được dùng để hiệu chỉnh propensity và chọn checkpoint; "
                          "test giữ riêng, không dùng nhãn test để huấn luyện hoặc chọn cấu hình.", ""])
    lines.extend([
        "### Giới hạn sai số",
        "",
        "- Khoảng tin cậy trong JSON là xấp xỉ theo người dùng của một lần chạy; chưa bao gồm biến thiên do seed hoặc chọn cấu hình.",
        "- Random (expected) là kỳ vọng xếp hạng ngẫu nhiên có điều kiện trên candidate pool hiện có; Popularity dùng tần suất exposure trong train.",
        "- KuaiRand dùng is_click, ghép hai standard log, lọc user/item tối thiểu 10 exposure một lượt và chia random log theo user. CDR source calibration 5% validation; dữ liệu/sampler là adaptation địa phương.",
        "- Coat H30 dùng rating ≥4 và split user seed 1234; CDR S-full dùng rating ≥3, toàn bộ 4.640 random ratings. Giữ overlap train/random.",
        "- Yahoo H30 dùng rating ≥4, raw IDs trừ 1; CDR S-full dùng ≥3 và giữ raw IDs. iDCF dùng survey thật, user thiếu survey có missing category; đây là mở rộng địa phương.",
        "- iDCF dùng exposure iVAE rồi feedback MSE. IViDR dùng learned IV và hai posterior, feature embedding học được, sau đó tối ưu BCE trên xác suất đã marginalize; Eq. (10) có coordinate adapter được công bố trong metadata.",
        "",
    ])
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Master Benchmark Runner: Huấn luyện và đánh giá Causal Debiasing trên nhãn is_click")
    parser.add_argument("--quick", action="store_true", help="Chạy nhanh kiểm thử (ít epoch)")
    parser.add_argument("--dataset", type=str, default="all", choices=["all", "coat", "kuairand", "yahoo"], help="Chọn dataset thực thi")
    parser.add_argument("--model", type=str, default="all", choices=["all", *MODEL_KEYS.values()],
                        help="Chọn mô hình thực thi (mặc định all: MF, iDCF, IViDR, LCDR, CDR, ConAlign)")
    parser.add_argument("--epochs", type=int, default=None, help="Số epoch chung cho các dataset")
    parser.add_argument("--epochs-coat", type=int, default=None, help="Số epoch cho Coat (mặc định 100)")
    parser.add_argument("--epochs-kr", type=int, default=None, help="Số epoch cho KuaiRand (mặc định 100)")
    parser.add_argument("--epochs-yahoo",type=int,default=None,help="Yahoo feedback epoch budget (default 100)")
    parser.add_argument("--cdr-implementation",choices=["auto","released","shared","equation"],default="auto",
                        help="auto/released: source algorithm and protocol; shared: released algorithm on common held-out split; equation: legacy Eq7")
    parser.add_argument("--dim", type=int, default=None, help="Số chiều embedding (mặc định theo từng mô hình)")
    parser.add_argument("--lr", type=float, default=None, help="Tốc độ học Adam")
    parser.add_argument("--batch-size", type=int, default=None, help="Kích thước batch")
    parser.add_argument("--alpha", type=float, default=0.0, help="Trọng số positive cho MF (mặc định 0; không áp dụng cho iDCF/IViDR/CDR)")
    parser.add_argument("--grid-search", action="store_true", help="Kích hoạt quét siêu tham số Grid Search trên KuaiRand")
    parser.add_argument("--smoke-users", type=int, default=None, help="Subset of KuaiRand users for smoke testing; requires --quick")
    parser.add_argument("--init-scheme", choices=["normal", "author_uniform"], default=None)
    parser.add_argument("--device", default=None, help="cpu or cuda; default is automatic")
    parser.add_argument("--ivae-epochs", type=int, default=None)
    parser.add_argument("--ivae-lr", type=float, default=None)
    parser.add_argument("--ivae-batch-size", type=int, default=None)
    parser.add_argument("--latent-dim", type=int, default=None)
    parser.add_argument("--cdr-propensity", choices=["naive_bayes_validation", "provided_coat"], default=None,
                        help="Coat CDR propensity; default calibrates Naive Bayes on validation only")
    parser.add_argument("--threads", type=int, default=None, help="PyTorch CPU threads (e.g. 2)")
    args = parser.parse_args(argv)

    ep_coat = args.epochs if args.epochs is not None else args.epochs_coat
    ep_kr = args.epochs if args.epochs is not None else args.epochs_kr

    run_all_benchmarks(
        quick_run=args.quick,
        epochs_coat=ep_coat,
        epochs_kr=ep_kr,
        dataset_filter=args.dataset,
        model_filter=args.model,
        dim=args.dim,
        lr=args.lr,
        batch_size=args.batch_size,
        alpha=args.alpha,
        grid_search=args.grid_search,
        smoke_users=args.smoke_users, device=args.device, ivae_epochs=args.ivae_epochs,
        ivae_lr=args.ivae_lr, ivae_batch_size=args.ivae_batch_size, latent_dim=args.latent_dim, init_scheme=args.init_scheme,
        cdr_propensity=args.cdr_propensity, threads=args.threads,
        epochs_yahoo=args.epochs if args.epochs is not None else args.epochs_yahoo,
        cdr_implementation=args.cdr_implementation,
    )
