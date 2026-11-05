"""CLEV-DR (Zhang et al., KDD 2025, "Ours-DR") on the author protocol: Coat, Yahoo! R3 and KuaiRand-Pure.

KuaiRand-Pure replaces the KuaiRec data of the paper, so it has no paper number to compare with.

Runs the alpha sweep of the author bash scripts for every seed and writes one JSON report per dataset under
results/. The report keeps every (alpha, seed) run and the paper numbers; choosing an alpha needs the test set,
which is what the author procedure does, so the best alpha is marked as selected on test. Separate from
`benchmark --model all` and from the H30 protocol.

    python experiments/run.py clev --dataset coat --seeds 0 1 2 3 4
"""
import argparse
from datetime import datetime
import hashlib
import json
import os
from uuid import uuid4

import numpy as np
import torch

from src.models.clev.data import DATASETS, load
from src.models.clev.train import ALPHA_SWEEP, CLEV_CONFIG, PAPER_OURS_DR, run_seed, setup_seed
from src.utils.artifacts import source_signature
from src.utils.helpers import RESULTS_DIR

SOURCE = {"repository": "https://github.com/WallaceSUI/kdd25-background-variable",
          "commit": "66a0e5f9041bf10f4ea04334ca1eeedd100a7d19", "class": "new_model.MF_BV_Multi_bin_JL_G_DR"}


def summarize(runs, k):
    keys = ("AUC", f"Recall@{k}", f"NDCG@{k}", f"Precision@{k}")
    out = {}
    for alpha in sorted({r["alpha"] for r in runs}):
        rows = [r for r in runs if r["alpha"] == alpha]
        out[str(alpha)] = {key: {"mean": float(np.mean([r[key] for r in rows])),
                                 "std": float(np.std([r[key] for r in rows], ddof=1)) if len(rows) > 1 else None,
                                 "n": len(rows)} for key in keys}
    return out


def data_digest(data):
    h = hashlib.sha256()
    for array in data[:4]:
        h.update(np.ascontiguousarray(array).tobytes())
    return h.hexdigest()[:16]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", choices=[*DATASETS, "all"], default="coat")
    parser.add_argument("--seeds", nargs="+", type=int, default=[0])
    parser.add_argument("--alphas", nargs="+", type=float, default=None, help="Default: the author bash sweep")
    parser.add_argument("--smoke", action="store_true", help="2 epochs per stage, one alpha")
    parser.add_argument("--threads", type=int, default=2)
    args = parser.parse_args(argv)
    torch.set_num_threads(args.threads)
    code = source_signature()
    run_id = datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid4().hex[:8]
    for dataset in (DATASETS if args.dataset == "all" else [args.dataset]):
        alphas = args.alphas or ALPHA_SWEEP[dataset]
        alphas = alphas[:1] if args.smoke else alphas
        k = CLEV_CONFIG[dataset]["k"]
        runs = []
        for seed in args.seeds:
            setup_seed(seed)
            data = load(dataset)  # Yahoo shuffles its rows with the seeded RNG
            for result in run_seed(dataset, alphas, seed=seed, data=data, num_epoch=2 if args.smoke else 1000):
                result["data_sha256"] = data_digest(data)
                runs.append(result)
                print(json.dumps({key: result[key] for key in ("dataset", "alpha", "seed", "AUC", f"Recall@{k}",
                                                               f"NDCG@{k}", "seconds")}), flush=True)
        summary = summarize(runs, k)
        best = max(summary, key=lambda a: summary[a][f"NDCG@{k}"]["mean"])
        report = {"model": "CLEV-DR", "paper_name": "Ours-DR", "dataset": dataset, "run_id": run_id,
                  "smoke": args.smoke, "seeds": args.seeds, "alphas": list(alphas), "runs": runs,
                  "summary_by_alpha": summary,
                  "best_alpha_by_test_ndcg": {"alpha": float(best), "selected_on": "test (author procedure)"},
                  "paper": PAPER_OURS_DR[dataset], "source": SOURCE, "code_sha256_at_start": code,
                  "protocol": "author protocol (Zhang et al. scripts): train on the biased log, test on the whole "
                              "random log, labels and metrics as in the author code; not H30"}
        path = os.path.join(RESULTS_DIR, f"clev_{dataset}_{'smoke_' if args.smoke else ''}{run_id}.json")
        with open(path, "x", encoding="utf-8") as stream:
            json.dump(report, stream, indent=2, ensure_ascii=False)
        print(json.dumps({"report": path, "best_alpha_on_test": best, "summary": summary[best]}, indent=2))
