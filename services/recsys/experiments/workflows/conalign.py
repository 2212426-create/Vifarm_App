"""Train ConAlign with the author's protocol (biased + small unbiased training data).

ConAlign uses its own random/temporal splits and metrics, so it is not part of
`benchmark --model all` and its scores are not on the iDCF H30 or CDR protocol.
"""
import argparse
from datetime import datetime
import json
import os
from uuid import uuid4

import torch

from src.models.conalign.data import load_conalign_data
from src.models.conalign.train import setup_seed, train_conalign
from src.utils.helpers import RESULTS_DIR


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", choices=["coat", "yahoo", "kuairand", "all"], default="coat")
    parser.add_argument("--seed", type=int, default=0, help="Author default seed")
    parser.add_argument("--smoke", action="store_true", help="2 + 2 epochs; KuaiRand user subset")
    parser.add_argument("--smoke-users", type=int, default=200)
    parser.add_argument("--threads", type=int, default=2)
    parser.add_argument("--device", choices=["cpu", "cuda"], default="cpu")
    parser.add_argument("--quiet", action="store_true")
    parser.add_argument("--kuairand-window", choices=["paper", "source"], default="paper",
                        help="paper: train 22/04-05/05 (Sec. 4.1); source: released loader, skips 01-05/05")
    args = parser.parse_args(argv)
    torch.set_num_threads(args.threads)
    datasets = ["coat", "yahoo", "kuairand"] if args.dataset == "all" else [args.dataset]
    run_id = datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid4().hex[:8]
    for dataset in datasets:
        setup_seed(args.seed)
        smoke_users = args.smoke_users if args.smoke and dataset == "kuairand" else None
        data = load_conalign_data(dataset, seed=args.seed, device=args.device, smoke_users=smoke_users,
                                  kuairand_window=args.kuairand_window)
        overrides = dict(pretrain_epochs=2, finetune_epochs=2) if args.smoke else None
        result = train_conalign(data, dataset, seed=args.seed, device=args.device, overrides=overrides,
                                verbose=not args.quiet)
        result.update(run_id=run_id, smoke=args.smoke,
                      protocol="ConAlign source protocol; metric names kept from utils/metrics.py")
        path = os.path.join(RESULTS_DIR, f"conalign_{dataset}_{'smoke_' if args.smoke else ''}{run_id}.json")
        with open(path, "x", encoding="utf-8") as stream:
            json.dump(result, stream, indent=2, ensure_ascii=False)
        print(json.dumps({"report": path, "stage1": result["stage1"], "stage2": result["stage2"],
                          "unbiased_test_unbiased_tower": result["source_metrics"]["test_unbiased"]["unbiased_tower"]},
                         indent=2))
