"""MRDR-CAL (Hu et al., TKDE 2025, Table VI) on the author protocol: Coat, Yahoo! R3, KuaiRand-Pure.

Writes one JSON report per dataset under results/ with every seed, the mean/std and the paper numbers.
Separate from `benchmark --model all` and from the H30 protocol.

    python experiments/run.py mrdr-cal --dataset coat --seeds 0 1 2 3 4 5 6 7 8 9
"""
import argparse
from datetime import datetime
import json
import os
from uuid import uuid4

import numpy as np
import torch

from src.models.mrdr_cal.data import DATASETS, load
from src.models.mrdr_cal.train import PAPER_MRDR_CAL, run
from src.utils.artifacts import source_signature
from src.utils.helpers import RESULTS_DIR

SOURCES = [{"repository": "https://github.com/sunxin000/uncertainty4recsys",
            "commit": "36dc7c6198c4f7722ee4634c41254e8fe48decdf", "used": "NeuMF, propensity, Platt, metrics"},
           {"repository": "https://github.com/guosyjlu/MRDR-DL", "commit": "a89d2aa4aba929e48e61415d593b46d4b5f0170d",
            "used": "MRDR imputation and DR losses, alternating training, validation cross-entropy selection"}]
KEYS = ("AUC", "UAUC", "DCG@2", "DCG@4", "DCG@6", "Recall@2", "Recall@4", "Recall@6",
        "NDCG@5", "Recall@5", "Recall@5_bounded")


def summarize(runs):
    keys = [k for k in KEYS + ("Recall@2_count", "Recall@4_count", "Recall@6_count") if k in runs[0]]
    return {k: {"mean": float(np.mean([r[k] for r in runs])),
                "std": float(np.std([r[k] for r in runs], ddof=1)) if len(runs) > 1 else None, "n": len(runs)}
            for k in keys}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", choices=[*DATASETS, "all"], default="coat")
    parser.add_argument("--seeds", nargs="+", type=int, default=[0])
    parser.add_argument("--smoke", action="store_true", help="1 propensity epoch, 2 MRDR epochs")
    parser.add_argument("--threads", type=int, default=2)
    args = parser.parse_args(argv)
    torch.set_num_threads(args.threads)
    code = source_signature()
    run_id = datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid4().hex[:8]
    for dataset in (DATASETS if args.dataset == "all" else [args.dataset]):
        data = load(dataset)
        overrides = dict(propensity_epochs=1, max_epochs=2) if args.smoke else None
        runs = []
        for seed in args.seeds:
            result = run(dataset, seed=seed, data=data, overrides=overrides)
            runs.append(result)
            print(json.dumps({k: result[k] for k in ("dataset", "seed", "AUC", "DCG@2", "Recall@2", "NDCG@5", "Recall@5", "seconds")}))
        report = {"model": "MRDR-CAL", "dataset": dataset, "run_id": run_id, "smoke": args.smoke, "seeds": args.seeds,
                  "runs": runs, "summary": summarize(runs), "paper": PAPER_MRDR_CAL[dataset], "sources": SOURCES,
                  "code_sha256_at_start": code,
                  "protocol": "author protocol (Hu et al.): train on the MNAR/biased log, test on the MAR/random log, "
                              "conversion = rating > 3 (Coat, Yahoo) or is_click (KuaiRand); not H30"}
        path = os.path.join(RESULTS_DIR, f"mrdr_cal_{dataset}_{'smoke_' if args.smoke else ''}{run_id}.json")
        with open(path, "x", encoding="utf-8") as stream:
            json.dump(report, stream, indent=2, ensure_ascii=False)
        print(json.dumps({"report": path, "summary": {k: round(v["mean"], 4) for k, v in report["summary"].items()}},
                         indent=2))
