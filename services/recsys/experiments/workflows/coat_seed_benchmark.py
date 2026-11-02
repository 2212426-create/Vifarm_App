"""Coat: MF, iDCF, IViDR (theo giai đoạn) và DR-BIAS + CDR, lặp 10 seed (42–51).

MF/iDCF select validation checkpoints; CDR uses source train-loss stopping.
Report mean/sample std; pair tests only within the same evaluation protocol.

    python experiments/run.py coat-seeds [--models MF iDCF IViDR "DR-BIAS + CDR"]
"""

import argparse
import json
from contextlib import nullcontext
import time
from pathlib import Path
from datetime import datetime
from uuid import uuid4

import numpy as np
from scipy.stats import wilcoxon

from src.models.mf.train_mf import train_baseline_mf
from src.models.cdr.train_dr_bias_cdr import train_dr_bias_cdr
from src.models.cdr.source_protocol import run_source
from src.models.ividr.ividr_staged import mf_item_embeddings
from src.models.idcf.train_idcf import fit_idcf_pipeline
from src.data_pipeline.coat_dataset import load_coat_processed
from src.training.config import mf_config, cdr_config
from src.evaluation.protocol import DEFAULT_SEEDS
from src.utils.artifacts import data_signature, digest, source_signature
from src.utils.helpers import RESULTS_DIR, CHECKPOINT_DIR

MODELS = ("MF", "iDCF", "IViDR", "DR-BIAS + CDR")
STANDARD_MODELS = MODELS  # User-selected suite; IViDR uses learned IV and BCE.
# Cấu hình MF của tác giả iDCF (MF.py); cũng là treatment T của IViDR.
MF_CONFIG = mf_config("coat")


def run_seed(name, data, seed, ckpt, cdr_implementation="released"):
    if name in ("MF", "IViDR"):
        mf = train_baseline_mf(dataset_name="coat", data_dict=data, seed=seed, checkpoint_dir=ckpt,
                               evaluate_test=name == "MF", checkpoint_tag=f"seeds_mf_{seed}", **MF_CONFIG)
        if name == "MF":
            return mf
        return fit_idcf_pipeline(data, "coat", seed, item_emb=mf_item_embeddings(mf["checkpoint_path"]),
                                 checkpoint_dir=ckpt, checkpoint_tag=f"seeds_ividr_{seed}")
    if name == "iDCF":
        return fit_idcf_pipeline(data, "coat", seed, checkpoint_dir=ckpt, checkpoint_tag=f"seeds_idcf_{seed}")
    if name != "DR-BIAS + CDR":
        raise ValueError(f"Unknown model: {name}")
    if cdr_implementation == "released":
        return run_source('coat',seed=seed,checkpoint_dir=ckpt)
    return train_dr_bias_cdr(dataset_name="coat", data_dict=data, seed=seed,
                             **cdr_config("coat"),
                             checkpoint_dir=ckpt, checkpoint_tag=f"seeds_cdr_{seed}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seeds", nargs="+", type=int, default=list(DEFAULT_SEEDS))
    parser.add_argument("--models", nargs="+", choices=MODELS, default=list(STANDARD_MODELS))
    parser.add_argument("--cdr-implementation", choices=["released", "equation"], default="released")
    parser.add_argument("--threads", type=int, default=2)
    args = parser.parse_args(argv)

    if len(set(args.seeds)) != len(args.seeds):
        parser.error("Seeds must be unique")
    if args.threads < 1:
        parser.error("--threads must be positive")
    import torch
    torch.set_num_threads(args.threads)
    data = load_coat_processed()
    identity = {"dataset": "coat", "seeds": args.seeds, "models": args.models,
                "data": data_signature(data), "code_sha256": source_signature(),
                "cdr_implementation": args.cdr_implementation}
    run_id = datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid4().hex[:8]
    path = Path(RESULTS_DIR) / f"coat_seeds_{digest(identity)}_{run_id}.json"
    rows = {name: [] for name in args.models}
    with nullcontext(str(Path(CHECKPOINT_DIR)/'coat_seed_runs'/run_id)) as ckpt:
        for name in args.models:
            for seed in args.seeds:
                t0 = time.time()
                r = run_seed(name, data, seed, ckpt, args.cdr_implementation)
                recall_key='Recall@5_bounded' if r.get('evaluation_scope')=='cdr_source_protocol' else 'Recall@5'
                rows[name].append({"seed": seed, "NDCG@5": r["NDCG@5"], "recall_value": r[recall_key],
                                   "recall_metric":recall_key,"evaluation_scope":r.get('evaluation_scope','shared_held_out'),
                                   "best_epoch": r["best_epoch"], "best_val_ndcg": r["best_val_ndcg"],
                                   "selection_origin": r.get("selection_origin"),
                                   "metadata": r["metadata"],
                                   "seconds": round(time.time() - t0, 1)})
                print(f"{name} seed {seed}: NDCG@5={r['NDCG@5']:.4f} {recall_key}={r[recall_key]:.4f}", flush=True)

    summary = {}
    for name, runs in rows.items():
        nd = np.array([x["NDCG@5"] for x in runs]); rc = np.array([x["recall_value"] for x in runs])
        summary[name] = {"NDCG@5_mean": float(nd.mean()), "NDCG@5_std": float(nd.std(ddof=1)) if len(nd) > 1 else None,
                         "recall_metric": runs[0]["recall_metric"], "recall_mean": float(rc.mean()), "recall_std": float(rc.std(ddof=1)) if len(rc) > 1 else None}
    pairs = {}
    for a in args.models:
        for b in args.models:
            if a < b and rows[a][0]['evaluation_scope']==rows[b][0]['evaluation_scope']:
                diff = np.array([x["NDCG@5"] for x in rows[a]]) - np.array([x["NDCG@5"] for x in rows[b]])
                p = float(wilcoxon(diff).pvalue) if np.any(diff) else 1.0
                pairs[f"{a} - {b}"] = {"mean_delta_ndcg": float(diff.mean()), "wilcoxon_p_over_seeds": p}
    report = {"identity": identity, "runs": rows, "summary": summary, "seed_pairs": pairs}
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    lines = [f"# Coat — {len(args.seeds)} seed ({args.seeds[0]}–{args.seeds[-1]})", "",
             "| Mô hình | NDCG@5 | Recall@5 |",
             "| :-- | --: | --: |"]
    for name, s in summary.items():
        nd_std = f"{s['NDCG@5_std']:.4f}" if s['NDCG@5_std'] is not None else "N/A"
        rc_std = f"{s['recall_std']:.4f}" if s['recall_std'] is not None else "N/A"
        label = (rows[name][0]['metadata']['config'].get('display_name','IViDR-approx')
                 if name == 'IViDR' else name)
        if rows[name][0]['evaluation_scope']=='cdr_source_protocol': label += ' (source; Recall bounded)'
        lines.append(f"| {label} | {s['NDCG@5_mean']:.4f} +/- {nd_std} | "
                     f"{s['recall_mean']:.4f} +/- {rc_std} |")
    lines += ["", "| So sánh | ΔNDCG@5 trung bình | Wilcoxon p (theo cặp seed) |", "| :-- | --: | --: |"]
    lines += [f"| {k} | {v['mean_delta_ndcg']:+.4f} | {v['wilcoxon_p_over_seeds']:.3g} |" for k, v in pairs.items()]
    lines += ["", "Các mô hình được huấn luyện độc lập; CDR không nạp checkpoint MF.",
              "MF/iDCF: >=4, user split 30/70; CDR released: source >=3/toàn random log/5% calibration/Recall bounded. Không kiểm định chéo hai giao thức.",
              "IViDR: BCE trên xác suất đã marginalize, giai đoạn 1 prior mean 0 và mẫu âm trọng số .1 (khác Eq. 42/25 của paper); coordinate adapter Eq. (10) ghi trong metadata, chưa chứng nhận tái lập tác giả.", ""]
    path.with_suffix(".md").write_text("\n".join(lines), encoding="utf-8")
    print("\n".join(lines))
    print(f"Report: {path}")


if __name__ == "__main__":
    main()
