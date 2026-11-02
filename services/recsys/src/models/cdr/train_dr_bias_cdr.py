# -*- coding: utf-8 -*-
"""
Script huấn luyện mô hình Causal Debiasing: DR-BIAS + CDR trên Coat và KuaiRand
Tích hợp lọc Poisonous Imputation bằng Monte Carlo Dropout và đối sánh Unbiased Top-5
Biến thể địa phương tham khảo CDR CIKM 2023 (Song et al.)
Project: ViFarm (services/recsys)
"""

import os
import sys

# Đảm bảo nhận diện đúng package src từ PROJECT_ROOT
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

try:
    sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)
except Exception:
    pass

import argparse
import time
import math
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim

from src.utils.helpers import set_seed, get_device, CHECKPOINT_DIR
from src.data_pipeline.coat_dataset import load_coat_raw_features, load_coat_processed
from src.data_pipeline.yahoo_dataset import load_yahoo_processed
from src.data_pipeline.kuairand_dataset import load_kuairand_processed
from src.models.cdr.cdr_model import CDRFramework
from src.models.cdr.sampling import CounterfactualSampler
from src.models.cdr.observations import aggregate_observed_pairs
from src.models.cdr.propensity import naive_bayes_propensity, validation_labels, propensity_diagnostics
from src.models.cdr.dr_bias_loss import PAPER_OBJECTIVE_REVISION
from src.training.config import cdr_config
from src.evaluation.evaluator import evaluate_unbiased_model
from src.evaluation.protocol import TOP_K
from src.utils.artifacts import (validate_training, make_metadata, checkpoint_path,
                                 save_checkpoint, evaluate_checkpoint,
                                 load_checkpoint, data_signature)


def train_dr_bias_cdr(dataset_name="coat", embedding_dim=None, un_thres=None,
                      epochs=None, lr=None, batch_size=None, patience=None, device=None,
                      alpha=0.0, checkpoint_tag="manual", data_dict=None,
                      evaluate_test=True, seed=42, max_inverse_propensity=None,
                      population_counterfactual_weight=False,
                      initial_rec_checkpoint=None, filter_mode="cv", ips_weighting="paper",
                      counterfactual_pool="all", checkpoint_dir=None, mc_samples=10, weight_decay=None,
                      training_profile="paper", backbone="paper_dot", scheduler_name="none",
                      propensity_mode=None):
    """Train the population-normalized Eq. (7); author/dr are explicit legacy ablations."""
    if ips_weighting not in ("paper", "author", "dr"):
        raise ValueError("Unknown CDR estimator")
    if training_profile not in ("paper", "experimental"):
        raise ValueError("Unknown CDR training profile")
    if scheduler_name not in ("none", "plateau"):
        raise ValueError("Unknown CDR scheduler")
    if training_profile == "paper" and (
            initial_rec_checkpoint is not None or ips_weighting != "paper" or filter_mode != "cv"
            or backbone != "paper_dot" or scheduler_name != "none"
            or max_inverse_propensity is not None or population_counterfactual_weight):
        raise ValueError("Paper CDR trains from scratch with Eq. (7), CV filter, dot MF, "
                         "fixed Adam learning rate and no propensity cap. "
                         "Use training_profile='experimental' for explicit ablations.")
    if ips_weighting == "paper" and population_counterfactual_weight:
        raise ValueError("Eq. (7) already normalizes the population; remove the legacy scaling flag")
    if counterfactual_pool not in ("unobserved", "all"):
        raise ValueError("counterfactual_pool must be unobserved or all")
    validate_training(epochs=epochs, embedding_dim=embedding_dim, lr=lr,
                      batch_size=batch_size, patience=patience, mc_samples=mc_samples)
    if dataset_name.lower() not in ("coat", "kuairand", "yahoo"):
        raise ValueError("Unsupported dataset")
    if max_inverse_propensity is not None:
        if not np.isfinite(max_inverse_propensity) or max_inverse_propensity < 1:
            raise ValueError("max_inverse_propensity must be finite and at least 1")
        if dataset_name.lower() != "coat":
            raise ValueError("max_inverse_propensity is only supported for Coat")
    if population_counterfactual_weight and dataset_name.lower() != "coat":
        raise ValueError("population_counterfactual_weight is only supported for Coat")
    if initial_rec_checkpoint is not None and dataset_name.lower() != "coat":
        raise ValueError("initial_rec_checkpoint is only supported for Coat")
    set_seed(seed)
    if not np.isfinite(alpha) or alpha < 0:
        raise ValueError("alpha must be finite and nonnegative")
    device = get_device(device)

    defaults = cdr_config(dataset_name.lower())
    propensity_mode = propensity_mode or defaults.get("propensity_mode", "item_frequency")
    allowed_propensity = (("provided_coat", "naive_bayes_validation") if dataset_name.lower() == "coat" else
                          ("naive_bayes_validation",) if dataset_name.lower() == "yahoo" else ("item_frequency",))
    if propensity_mode not in allowed_propensity:
        raise ValueError("Unsupported propensity mode for dataset")
    if max_inverse_propensity is not None and propensity_mode != "provided_coat":
        raise ValueError("Propensity cap requires provided_coat mode")
    embedding_dim = defaults["embedding_dim"] if embedding_dim is None else embedding_dim
    lr = defaults["lr"] if lr is None else lr
    epochs = defaults["epochs"] if epochs is None else epochs
    batch_size = defaults["batch_size"] if batch_size is None else batch_size
    patience = defaults["patience"] if patience is None else patience
    un_thres = defaults["un_thres"] if un_thres is None else un_thres
    weight_decay = defaults["weight_decay"] if weight_decay is None else weight_decay
    if not np.isfinite(weight_decay) or weight_decay < 0:
        raise ValueError("weight_decay must be finite and nonnegative")
    G = 4 if dataset_name.lower() == "coat" else 1

    print(f"\n=======================================================")
    print(f" HUẤN LUYỆN MÔ HÌNH CAUSAL DEBIASING: DR-BIAS + CDR [{dataset_name.upper()}]")
    print(f" Thiết bị: {device} | Dim: {embedding_dim} | Unc Threshold: {un_thres} | LR: {lr}")
    print(f"=======================================================")

    proc_data = data_dict if data_dict is not None else (
        load_coat_processed() if dataset_name.lower() == "coat" else
        load_yahoo_processed() if dataset_name.lower() == "yahoo" else load_kuairand_processed(alpha=alpha))
    n_users, n_items = proc_data["n_users"], proc_data["n_items"]
    val_candidates, val_ground_truth = proc_data["val_candidates"], proc_data["val_ground_truth"]
    train_u, train_i, train_r = proc_data["train_u"], proc_data["train_i"], proc_data["train_y"]
    raw_training_rows = len(train_r)
    if not raw_training_rows:
        raise ValueError("Training data is empty")
    if ips_weighting == "paper":
        train_u, train_i, train_r = aggregate_observed_pairs(train_u, train_i, train_r, n_items)
    n_samples = len(train_r)
    n_unique = len(np.unique(train_u * n_items + train_i))
    observed_fraction = n_unique / (n_users * n_items)
    clipped_propensity_fraction = 0.0
    calibration = None
    if propensity_mode == "naive_bayes_validation":
        inv_props, calibration = naive_bayes_propensity(
            train_r, validation_labels(proc_data), observed_fraction)
        calibration["source"] = "random_validation_log_only"
        calibration["test_labels_used"] = False
    elif dataset_name.lower() == "coat":
        raw = load_coat_raw_features(proc_data.get("data_dir"))
        inv_props = 1.0 / np.clip(raw["propensities"][train_u, train_i], 1e-4, 1.0)
        if max_inverse_propensity is not None:
            clipped_propensity_fraction = float(np.mean(inv_props > max_inverse_propensity))
            inv_props = np.minimum(inv_props, max_inverse_propensity)
    else:
        # An item-frequency proxy is still an approximation to exposure propensity.
        item_pop = proc_data["train_item_exposure_counts"].astype(np.float32)
        item_prop = np.clip(item_pop / (item_pop.max() + 1e-6), 0.05, 1.0)
        inv_props = (1.0 / item_prop[train_i]).astype(np.float32)

    n_all_pairs = n_users * n_items - (n_unique if counterfactual_pool == "unobserved" else 0)
    sampler = (CounterfactualSampler(n_users, n_items, train_u, train_i, counterfactual_pool, device)
               if n_all_pairs else None)
    # Preserve the old Coat sampler only for explicitly requested historical modes.
    if ips_weighting != "paper" and dataset_name.lower() == "coat":
        raw = load_coat_raw_features(proc_data.get("data_dir"))
        all_pairs = (np.argwhere(raw["train_matrix"] == 0) if counterfactual_pool == "unobserved"
                     else np.argwhere(np.ones_like(raw["train_matrix"], dtype=bool)))
    counterfactual_scale = n_all_pairs / (G * n_samples) if population_counterfactual_weight else 1.0
    propensity_ess = float(np.sum(inv_props.astype(np.float64)) ** 2 /
                           np.sum(np.square(inv_props.astype(np.float64))))

    if not np.isfinite(un_thres) or un_thres < 0:
        raise ValueError("un_thres must be finite and nonnegative")
    model = CDRFramework(
        num_users=n_users,
        num_items=n_items,
        embedding_dim=embedding_dim,
        un_thres=un_thres,
        dropout_rate=0.5,
        filter_mode=filter_mode,
        ips_weighting=ips_weighting,
        backbone=backbone,
    ).to(device)

    if initial_rec_checkpoint is not None:
        initial_state = load_checkpoint(initial_rec_checkpoint, device)
        initial_meta = initial_state["metadata"]
        if (initial_meta.get("model") != "mf" or
                initial_meta.get("dataset") != "coat" or
                initial_meta.get("data") != data_signature(proc_data) or
                initial_meta.get("model_kwargs", {}).get("embedding_dim") != embedding_dim or
                initial_meta.get("config", {}).get("seed") != seed):
            raise ValueError("MF warm-start checkpoint must match Coat data, dimension and seed")
        model.rec_model.load_state_dict(initial_state["model_state_dict"])

    # The source CDR backbone has only two embedding matrices, no biases.
    rec_groups = [{"params": [model.rec_model.user_embedding.weight,
                              model.rec_model.item_embedding.weight], "weight_decay": weight_decay}]
    if model.rec_model.use_bias:
        rec_groups.append({"params": [model.rec_model.user_bias.weight,
            model.rec_model.item_bias.weight, model.rec_model.global_bias], "weight_decay": 0.0})
    opt_rec = optim.Adam(rec_groups, lr=lr)
    opt_imp = optim.Adam(model.imp_model.parameters(), lr=lr, weight_decay=weight_decay)
    sched_rec = (optim.lr_scheduler.ReduceLROnPlateau(opt_rec, mode="max", factor=0.5, patience=3, min_lr=1e-5)
                 if scheduler_name == "plateau" else None)
    sched_imp = (optim.lr_scheduler.ReduceLROnPlateau(opt_imp, mode="max", factor=0.5, patience=3, min_lr=1e-5)
                 if scheduler_name == "plateau" else None)

    import hashlib
    effective_train_hash = hashlib.sha256()
    for array in (train_u, train_i, train_r):
        effective_train_hash.update(np.ascontiguousarray(array).tobytes())
    metadata = make_metadata("cdr", dataset_name, proc_data,
        dict(epochs=epochs, lr=lr, batch_size=batch_size, patience=patience, alpha=alpha,
             seed=seed, device=str(device), weight_decay=weight_decay, G=G,
             training_profile=training_profile, backbone=backbone, loss="bce",
             initialization="random_independent" if initial_rec_checkpoint is None else "mf_checkpoint",
             method_reference="CDR_CIKM2023_Eq7_section3.1_DRBIAS",
             paper_reproduction=False,
             mc_samples=mc_samples, un_thres=un_thres,
             update_order="recommendation_then_imputation_current_rec",
             objective_revision=PAPER_OBJECTIVE_REVISION if ips_weighting == "paper" else f"legacy_{ips_weighting}_v1",
             observed_fraction=observed_fraction, observed_pairs=n_unique, raw_training_rows=raw_training_rows,
             pair_label_policy="mean_label_per_observed_pair" if ips_weighting == "paper" else "logged_rows",
             effective_train_sha256=effective_train_hash.hexdigest(),
             propensity_ess=propensity_ess,
             propensity_calibration=calibration,
             propensity_diagnostics=propensity_diagnostics(inv_props),
             propensity_sha256=hashlib.sha256(inv_props.tobytes()).hexdigest(),
             max_inverse_propensity=max_inverse_propensity,
             clipped_propensity_fraction=clipped_propensity_fraction,
             population_counterfactual_weight=population_counterfactual_weight,
             counterfactual_scale=counterfactual_scale,
             initial_rec_checkpoint=str(initial_rec_checkpoint) if initial_rec_checkpoint else None,
             propensity=propensity_mode if dataset_name.lower() in ("coat", "yahoo") else "item_frequency_clip_0.05_1",
             counterfactuals="unobserved_pairs" if counterfactual_pool == "unobserved" else "all_catalog_pairs",
             counterfactual_pair_count=n_all_pairs,
             warm_start_selection="include_epoch_zero" if initial_rec_checkpoint else "not_used",
             optimizer="Adam", scheduler=scheduler_name,
             filter_mode=filter_mode, ips_weighting=ips_weighting, counterfactual_pool=counterfactual_pool),
        dict(num_users=n_users, num_items=n_items, embedding_dim=embedding_dim,
             un_thres=un_thres, dropout_rate=0.5, filter_mode=filter_mode, ips_weighting=ips_weighting,
             backbone=backbone))
    save_path = checkpoint_path(checkpoint_dir or os.path.join(CHECKPOINT_DIR, "cdr"),
                                f"{dataset_name}_cdr_{checkpoint_tag}", metadata)
    os.makedirs(os.path.dirname(save_path), exist_ok=True)

    if n_samples == 0:
        raise ValueError("Training data is empty")
    best_val_ndcg = -1.0
    best_epoch = 0
    patience_cnt = 0
    total_batches = math.ceil(n_samples / batch_size)
    training_history = []
    best_training = {"epoch": 0, "selection_origin": "warm_start"}

    # A fine-tuning run must be allowed to retain its unmodified warm start.
    if initial_rec_checkpoint is not None:
        initial_val = evaluate_unbiased_model(
            model, val_candidates, val_ground_truth, k=TOP_K, device=device,
            include_zero_positive_users=proc_data.get("evaluation_include_zero_positive_users", True))
        best_val_ndcg = initial_val["NDCG@5"]
        save_checkpoint(model, save_path, metadata, 0, {**initial_val, "cdr_training": best_training})
        print(f"Warm-start epoch 0 | Val NDCG@5: {best_val_ndcg:.4f}", flush=True)

    for epoch in range(1, epochs + 1):
        model.train()
        perm_obs = np.random.permutation(n_samples)
        if ips_weighting != "paper" and dataset_name.lower() == "coat":
            perm_all = np.random.permutation(n_all_pairs)

        total_rec_loss = 0.0
        total_imp_loss = 0.0
        filter_totals = dict(observed_count=0, direct_count=0, filtered_observed=0, filtered_direct=0)
        n_b = 0

        for b_idx in range(total_batches):
            sel_obs = perm_obs[b_idx * batch_size : (b_idx + 1) * batch_size]
            current_size = len(sel_obs)
            u_o = torch.tensor(train_u[sel_obs], dtype=torch.long, device=device)
            i_o = torch.tensor(train_i[sel_obs], dtype=torch.long, device=device)
            r_o = torch.tensor(train_r[sel_obs], dtype=torch.float32, device=device)
            p_o = torch.tensor(inv_props[sel_obs], dtype=torch.float32, device=device)

            if ips_weighting != "paper" and dataset_name.lower() == "coat":
                sel_unobs = perm_all[G * b_idx * batch_size : G * b_idx * batch_size + G * current_size]
                sampled_pairs = all_pairs[sel_unobs]
                u_un = torch.tensor(sampled_pairs[:, 0], dtype=torch.long, device=device)
                i_un = torch.tensor(sampled_pairs[:, 1], dtype=torch.long, device=device)
            elif sampler is not None:
                u_un, i_un = sampler.sample(current_size * G)
            else:
                u_un = i_un = torch.empty(0, dtype=torch.long, device=device)

            # Alternate as in the released method: imputation must fit the rec
            # errors AFTER this batch's recommendation step, not stale logits.
            opt_rec.zero_grad()
            loss_rec, f_ratio = model.compute_recommendation_loss(
                u_obs=u_o, i_obs=i_o, r_obs=r_o, inv_p_obs=p_o,
                u_unobs=u_un, i_unobs=i_un, mc_samples=mc_samples,
                observed_fraction=observed_fraction, counterfactual_pool=counterfactual_pool,
                counterfactual_scale=counterfactual_scale,
            )
            if not torch.isfinite(loss_rec):
                raise FloatingPointError("Non-finite CDR recommendation loss")
            loss_rec.backward()
            opt_rec.step()
            opt_imp.zero_grad()
            loss_imp = model.compute_imputation_loss(u_o, i_o, r_o, p_o)
            if not torch.isfinite(loss_imp):
                raise FloatingPointError("Non-finite CDR imputation loss")
            loss_imp.backward()
            opt_imp.step()


            total_rec_loss += loss_rec.item()
            total_imp_loss += loss_imp.item()
            for key in filter_totals:
                filter_totals[key] += model.last_filter_stats[key]
            n_b += 1

        avg_rec_loss = total_rec_loss / max(n_b, 1)
        avg_imp_loss = total_imp_loss / max(n_b, 1)
        observed_filtered = filter_totals["filtered_observed"] / max(filter_totals["observed_count"], 1)
        direct_filtered = filter_totals["filtered_direct"] / max(filter_totals["direct_count"], 1)
        epoch_training = dict(epoch=epoch, rec_loss=avg_rec_loss, imp_loss=avg_imp_loss,
            filtered_observed_fraction=observed_filtered, filtered_direct_fraction=direct_filtered,
            **filter_totals)

        # Đánh giá Unbiased Validation NDCG@5
        val_metrics = evaluate_unbiased_model(model, val_candidates, val_ground_truth, k=TOP_K, device=device,
                                               include_zero_positive_users=proc_data.get("evaluation_include_zero_positive_users", True))
        val_ndcg = val_metrics["NDCG@5"]
        epoch_training["validation_ndcg"] = val_ndcg
        training_history.append(epoch_training)
        if not np.isfinite(val_ndcg):
            raise FloatingPointError("Non-finite validation score")
        val_rec = val_metrics["Recall@5"]
        val_hr = val_metrics["HitRate@5"]

        if sched_rec is not None:
            sched_rec.step(val_ndcg)
            sched_imp.step(val_ndcg)

        print(f"Epoch {epoch:02d}/{epochs:02d} | CDR Rec Loss: {avg_rec_loss:.4f} | Imp Loss: {avg_imp_loss:.4f} | "
              f"Imputation filtered O/D: {observed_filtered:.1%}/{direct_filtered:.1%} | Val NDCG@5: {val_ndcg:.4f} | Recall@5: {val_rec:.4f} | HR@5: {val_hr:.4f}",
              flush=True)

        if val_ndcg > best_val_ndcg:
            best_val_ndcg = val_ndcg
            best_epoch = epoch
            patience_cnt = 0
            best_training = epoch_training
            save_checkpoint(model, save_path, metadata, epoch, {**val_metrics, "cdr_training": best_training})
        else:
            patience_cnt += 1
            if patience_cnt >= patience:
                print(f"  -> Early stopping kích hoạt tại Epoch {epoch} (Best NDCG@5: {best_val_ndcg:.4f} tại Epoch {best_epoch})")
                break

    if not evaluate_test:
        return {"best_val_ndcg": best_val_ndcg, "best_epoch": best_epoch,
                "checkpoint_path": save_path, "metadata": metadata,
                "selection_origin": "warm_start" if best_epoch == 0 else "cdr_update",
                "cdr_training": best_training, "training_history": training_history}

    return {**evaluate_checkpoint(save_path, proc_data, device), "training_history": training_history}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", type=str, default="coat", choices=["coat", "yahoo", "kuairand"])
    parser.add_argument("--epochs", type=int, default=1000)
    parser.add_argument("--dim", type=int, default=None)
    parser.add_argument("--un_thres", type=float, default=None)
    parser.add_argument("--lr", type=float, default=None)
    args = parser.parse_args()

    from src.models.cdr.source_protocol import run_source
    run_source(args.dataset,embedding_dim=args.dim,un_thres=args.un_thres,epochs=args.epochs,lr=args.lr)
