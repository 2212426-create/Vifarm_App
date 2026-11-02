"""Train LCDR on the iDCF H30 protocol, optionally next to iDCF with the same seeds.

LCDR is an experimental re-implementation (no public author code) and is not part of
`benchmark --model all`. Each run writes one JSON report under results/.
"""
import argparse
from datetime import datetime
import json
import os
from uuid import uuid4

import torch

from src.data_pipeline.coat_dataset import load_coat_processed
from src.data_pipeline.kuairand_dataset import load_kuairand_processed, subset_kuairand_users
from src.data_pipeline.yahoo_dataset import load_yahoo_processed, subset_yahoo_users
from src.evaluation.protocol import PRIMARY_METRICS, summarize_seeds
from src.models.idcf.train_idcf import fit_idcf_pipeline
from src.models.lcdr.train_lcdr import LCDR_CONFIG, fit_lcdr_pipeline
from src.utils.artifacts import source_signature
from src.utils.helpers import CHECKPOINT_DIR, RESULTS_DIR

LOADERS = {"coat": load_coat_processed, "yahoo": load_yahoo_processed, "kuairand": load_kuairand_processed}
SUBSETS = {"yahoo": subset_yahoo_users, "kuairand": subset_kuairand_users}
KEPT_METRICS = (*PRIMARY_METRICS, "Recall@5_bounded", "Precision@5", "HitRate@5", "AUC", "best_epoch",
                "best_val_ndcg", "checkpoint_path")


def report_row(result):
    return {key: result[key] for key in KEPT_METRICS if key in result}


def run(dataset, seeds, epochs, representation_epochs, compare_idcf, smoke_users, device):
    data = LOADERS[dataset]()
    if smoke_users is not None:
        data = SUBSETS[dataset](data, smoke_users)
    budget = "smoke" if smoke_users is not None or epochs < 5 else "full"
    tag = f"{budget}_e{epochs}_r{representation_epochs}"
    report = {"dataset": dataset, "lcdr": [], "idcf": []}
    for seed in seeds:
        result = fit_lcdr_pipeline(data, dataset, seed=seed, epochs=epochs,
                                   representation_epochs=representation_epochs,
                                   checkpoint_dir=os.path.join(CHECKPOINT_DIR, "lcdr"),
                                   checkpoint_tag=f"{tag}_seed{seed}", device=device)
        report["lcdr"].append(dict(seed=seed, **report_row(result), representation=result["representation_info"]))
        if compare_idcf:
            baseline = fit_idcf_pipeline(data, dataset, seed=seed, epochs=epochs, ivae_epochs=representation_epochs,
                                         checkpoint_dir=os.path.join(CHECKPOINT_DIR, "lcdr_idcf_reference"),
                                         checkpoint_tag=f"{tag}_seed{seed}", device=device)
            report["idcf"].append(dict(seed=seed, **report_row(baseline)))
    report["summary"] = {name: summarize_seeds(report[name]) for name in ("lcdr", "idcf") if report[name]}
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", choices=["coat", "yahoo", "kuairand", "all"], default="coat")
    parser.add_argument("--seeds", nargs="+", type=int, default=[42])
    parser.add_argument("--epochs", type=int, default=100)
    parser.add_argument("--representation-epochs", type=int, default=2000)
    parser.add_argument("--compare-idcf", action="store_true", help="Also train iDCF with the same seeds")
    parser.add_argument("--smoke", action="store_true", help="1 feedback epoch, 2 representation epochs, user subset")
    parser.add_argument("--smoke-users", type=int, default=64)
    parser.add_argument("--threads", type=int, default=2)
    parser.add_argument("--device", choices=["cpu", "cuda"], default="cpu")
    args = parser.parse_args(argv)
    torch.set_num_threads(args.threads)
    epochs, representation_epochs = (1, 2) if args.smoke else (args.epochs, args.representation_epochs)
    datasets = ["coat", "yahoo", "kuairand"] if args.dataset == "all" else [args.dataset]
    run_id = datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid4().hex[:8]
    for dataset in datasets:
        smoke_users = args.smoke_users if args.smoke and dataset in SUBSETS else None
        report = run(dataset, args.seeds, epochs, representation_epochs, args.compare_idcf, smoke_users, args.device)
        report.update(model="LCDR", run_id=run_id, smoke=args.smoke, smoke_users=smoke_users, epochs=epochs,
                      representation_epochs=representation_epochs, seeds=args.seeds,
                      config=LCDR_CONFIG[dataset], code_sha256=source_signature(),
                      protocol="iDCF H30 (same data and evaluator as iDCF); experimental "
                               "re-implementation, not a paper reproduction")
        path = os.path.join(RESULTS_DIR, f"lcdr_{dataset}_{'smoke_' if args.smoke else ''}{run_id}.json")
        with open(path, "x", encoding="utf-8") as stream:
            json.dump(report, stream, indent=2, ensure_ascii=False)
        print(json.dumps({"report": path, **report["summary"]}, indent=2, ensure_ascii=False))
