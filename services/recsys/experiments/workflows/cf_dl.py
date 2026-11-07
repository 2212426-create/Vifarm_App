"""CF versus deep learning on the H30 protocol: MF against GMF, MLP and NeuMF.

Every model sees the same data, labels, evaluator and seeds.
MF uses the project defaults (iDCF author MF, MSE); the NCF models use the author's code defaults (log loss with
four sampled negatives). NeuMF-pre is NeuMF initialised from the GMF and MLP of the same seed.
Separate from `benchmark --model all`. Each dataset writes one JSON report under results/.

    python experiments/run.py cf-dl --dataset coat --seeds 42 43 44 45 46 47 48 49 50 51
"""
import argparse
from datetime import datetime
import json
import os
from uuid import uuid4

import numpy as np
from scipy.stats import wilcoxon
import torch

from src.data_pipeline.coat_dataset import load_coat_processed
from src.data_pipeline.kuairand_dataset import load_kuairand_processed, subset_kuairand_users
from src.data_pipeline.yahoo_dataset import load_yahoo_processed, subset_yahoo_users
from src.evaluation.diagnostics import paired_ndcg_difference
from src.evaluation.protocol import PRIMARY_METRICS
from src.models.mf.train_mf import train_baseline_mf
from src.models.ncf.train_ncf import NCF_CONFIG, train_ncf
from src.training.config import mf_config
from src.utils.artifacts import evaluate_checkpoint, source_signature
from src.utils.helpers import CHECKPOINT_DIR, RESULTS_DIR

LOADERS = {"coat": load_coat_processed, "yahoo": load_yahoo_processed, "kuairand": load_kuairand_processed}
SUBSETS = {"yahoo": subset_yahoo_users, "kuairand": subset_kuairand_users}
MODELS = ("MF", "GMF", "MLP", "NeuMF", "NeuMF-pre")
FAMILY = {"MF": "CF, model-based", "GMF": "NCF, linear", "MLP": "NCF, deep", "NeuMF": "NCF, deep", "NeuMF-pre": "NCF, deep"}
PAIRS = (("NeuMF", "MF"), ("NeuMF-pre", "MF"), ("MLP", "MF"), ("GMF", "MF"), ("MLP", "GMF"), ("NeuMF", "GMF"),
         ("NeuMF-pre", "NeuMF"))
KEPT = (*PRIMARY_METRICS, "Recall@5_bounded", "Precision@5", "HitRate@5", "AUC", "best_epoch", "best_val_ndcg",
        "checkpoint_path")


def row(result):
    return {key: result[key] for key in KEPT if key in result}


def run_seed(models, data, dataset, seed, epochs, folder, device):
    tag = f"cfdl_seed{seed}"
    out = {}
    if "MF" in models:
        config = mf_config(dataset, epochs=epochs)
        out["MF"] = train_baseline_mf(dataset_name=dataset, data_dict=data, seed=seed, checkpoint_dir=folder,
                                      checkpoint_tag=tag, device=device, **config)
    towers = {}
    for name, variant in (("GMF", "gmf"), ("MLP", "mlp"), ("NeuMF", "neumf")):
        if name in models or (name != "NeuMF" and "NeuMF-pre" in models):
            towers[name] = train_ncf(data, dataset, variant=variant, seed=seed, epochs=epochs,
                                     checkpoint_dir=folder, checkpoint_tag=tag, device=device,
                                     evaluate_test=True)
            if name in models:
                out[name] = towers[name]
    if "NeuMF-pre" in models:
        out["NeuMF-pre"] = train_ncf(data, dataset, variant="neumf", seed=seed, epochs=epochs,
                                     checkpoint_dir=folder, checkpoint_tag=tag, device=device,
                                     pretrain=(towers["GMF"]["checkpoint_path"], towers["MLP"]["checkpoint_path"]))
    return out


def user_ndcg(result, data, device):
    return evaluate_checkpoint(result["checkpoint_path"], data, device, return_user_ndcg=True)


def run(dataset, models, seeds, epochs, smoke_users, device):
    data = LOADERS[dataset]()
    if smoke_users is not None:
        data = SUBSETS[dataset](data, smoke_users)
    folder = os.path.join(CHECKPOINT_DIR, "cf_dl")
    report = {"dataset": dataset, "families": {name: FAMILY[name] for name in models},
              "per_seed": {}, "user_paired": {}, "seed_paired": {}}
    for seed in seeds:
        results = run_seed(models, data, dataset, seed, epochs, folder, device)
        report["per_seed"][str(seed)] = {name: row(result) for name, result in results.items()}
        scored = {name: user_ndcg(results[name], data, device) for name in models if name in results}
        report["user_paired"][str(seed)] = {f"{a} vs {b}": paired_ndcg_difference(scored[a], scored[b])
                                            for a, b in PAIRS if a in scored and b in scored}
    report["summary"] = summarize(report, models, seeds)
    if len(seeds) >= 5:
        report["seed_paired"] = seed_pairs(report, models, seeds)
    return report


def ndcg_by_seed(report, name, seeds):
    return np.array([report["per_seed"][str(seed)][name]["NDCG@5"] for seed in seeds])


def summarize(report, models, seeds):
    out = {}
    for name in models:
        rows = [report["per_seed"][str(seed)][name] for seed in seeds]
        out[name] = {metric: {"mean": float(np.mean([r[metric] for r in rows])),
                              "std": float(np.std([r[metric] for r in rows], ddof=1)) if len(rows) > 1 else None,
                              "n": len(rows)}
                     for metric in (*PRIMARY_METRICS, "Recall@5_bounded", "AUC") if metric in rows[0]}
    return out


def seed_pairs(report, models, seeds):
    out = {}
    for a, b in PAIRS:
        if a in models and b in models:
            diff = ndcg_by_seed(report, a, seeds) - ndcg_by_seed(report, b, seeds)
            out[f"{a} vs {b}"] = {"mean_delta_ndcg": float(diff.mean()), "wins": int((diff > 0).sum()),
                                  "seeds": len(seeds),
                                  "wilcoxon_p": float(wilcoxon(diff).pvalue) if np.any(diff) else 1.0}
    return out


def format_cfdl_tables(report, dataset):
    from src.evaluation.table_formatter import format_grid_table, format_markdown_table
    headers = ["Tập dữ liệu", "Mô hình", "Phân loại", "NDCG@5", "Recall@5 bounded", "Precision@5", "HitRate@5", "AUC"]
    rows = []
    dataset_title = {"coat": "Coat", "yahoo": "Yahoo! R3", "kuairand": "KuaiRand-Pure"}.get(dataset, dataset.capitalize())
    families = report.get("families", {})
    seeds = [str(s) for s in report.get("seeds", [42])]
    is_multi_seed = len(seeds) > 1
    first_seed = seeds[0]

    for name in report.get("models", []):
        family = families.get(name, "N/A")
        if not is_multi_seed and first_seed in report.get("per_seed", {}) and name in report["per_seed"][first_seed]:
            m = report["per_seed"][first_seed][name]
            def fmt(k, m=m):
                val = m.get(k)
                return f"{val:.6f}" if val is not None else "N/A"
        elif is_multi_seed and name in report.get("summary", {}):
            s_dict = report["summary"][name]
            def fmt(k, s_dict=s_dict):
                item = s_dict.get(k)
                if not item:
                    return "N/A"
                mean = item.get("mean")
                std = item.get("std")
                if mean is None:
                    return "N/A"
                return f"{mean:.4f}±{std:.4f}" if std is not None else f"{mean:.6f}"
        else:
            def fmt(k):
                return "N/A"

        rows.append([dataset_title, name, family, fmt("NDCG@5"), fmt("Recall@5_bounded"), fmt("Precision@5"), fmt("HitRate@5"), fmt("AUC")])

    grid = format_grid_table(headers, rows, col_aligns=["left", "left", "left", "right", "right", "right", "right", "right"],
                             title=f"KẾT QUẢ MODULE NCF & LỌC CỘNG TÁC (CF-DL) — {dataset_title.upper()}")

    md_rows = [[f"**{r[0]}**"] + r[1:] for r in rows]
    md = format_markdown_table(headers, md_rows, col_aligns=["left", "left", "left", "right", "right", "right", "right", "right"])

    markdown_content = f"""# Kết quả thực nghiệm NCF & Lọc cộng tác ({dataset_title})

- **Dataset:** {dataset_title}
- **Giao thức:** H30 (split 30/70, candidate pool và evaluator NDCG@5)
- **Thời gian chạy:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
- **Run ID:** `{report.get('run_id')}`

### Bảng tổng hợp chỉ số đánh giá:

{md}

- **Ghi chú phân loại:**
  - `MF`: Lọc cộng tác dựa trên mô hình phân rã ma trận (Model-based CF).
  - `GMF / MLP / NeuMF / NeuMF-pre`: Mạng nơ-ron lọc cộng tác học sâu (Neural Collaborative Filtering).
"""
    return grid, markdown_content


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", choices=["coat", "yahoo", "kuairand", "all"], default="coat")
    parser.add_argument("--models", nargs="+", choices=MODELS, default=list(MODELS))
    parser.add_argument("--seeds", nargs="+", type=int, default=[42])
    parser.add_argument("--epochs", type=int, default=None, help="Override MF and NCF epoch caps")
    parser.add_argument("--smoke", action="store_true", help="1 epoch, user subset")
    parser.add_argument("--smoke-users", type=int, default=64)
    parser.add_argument("--threads", type=int, default=2)
    parser.add_argument("--device", choices=["cpu", "cuda"], default="cpu")
    args = parser.parse_args(argv)
    torch.set_num_threads(args.threads)
    if "NeuMF-pre" in args.models and not {"GMF", "MLP"} <= set(args.models):
        args.models = list(dict.fromkeys([*args.models, "GMF", "MLP"]))
    models = [name for name in MODELS if name in args.models]
    epochs = 1 if args.smoke else args.epochs
    datasets = ["coat", "yahoo", "kuairand"] if args.dataset == "all" else [args.dataset]
    run_id = datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid4().hex[:8]
    for dataset in datasets:
        smoke_users = args.smoke_users if args.smoke and dataset in SUBSETS else None
        report = run(dataset, models, args.seeds, epochs, smoke_users, args.device)
        report.update(run_id=run_id, smoke=args.smoke, smoke_users=smoke_users, seeds=args.seeds, models=models,
                      epochs_override=epochs, ncf_config={k: list(v) if isinstance(v, tuple) else v
                                                          for k, v in NCF_CONFIG[dataset].items()},
                      mf_config=mf_config(dataset), code_sha256=source_signature(),
                      protocol="iDCF H30 (same data and evaluator as MF/iDCF); NCF follows the author code "
                               "defaults, not a reproduction of the NCF paper experiments")
        path = os.path.join(RESULTS_DIR, f"cf_dl_{dataset}_{'smoke_' if args.smoke else ''}{run_id}.json")
        with open(path, "x", encoding="utf-8") as stream:
            json.dump(report, stream, indent=2, ensure_ascii=False)
        grid, md_content = format_cfdl_tables(report, dataset)
        md_path = path[:-5] + ".md"
        with open(md_path, "x", encoding="utf-8") as stream:
            stream.write(md_content)
        print(f"\n{grid}\n")
        print(f"[HOÀN THÀNH] Báo cáo chi tiết JSON : {path}")
        print(f"[HOÀN THÀNH] Báo cáo khoa học Markdown: {md_path}")
