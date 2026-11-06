"""Run CLEV-DR with the hyperparameters of the author scripts (coat_test.py, yahoo_main.py, kuai_main.py).

The scripts hard-code values that their Optuna objective selected on test metrics (auc + ndcg + recall), and the
bash files sweep `alpha` (passed as --sigma_y). Both are kept as published; see source.json for the local choices.
KuaiRand-Pure has no author configuration: it takes the KuaiRec script values (kuai_main.py), the Yahoo
propensity batch and tolerance (207M pairs), K = 5 as the other thesis tables, and the low-memory CLEVDRLarge.
"""
import copy
import random
import time

import numpy as np
import torch

from src.models.clev.data import load
from src.models.clev.metrics import evaluate
from src.models.clev.model import CLEVDR, CLEVDRLarge

CLEV_CONFIG = {
    # coat_test.py (the DR script coat_test_dr.py is missing from the repository).
    "coat": dict(emb_dim=16, lr=0.001, weight_decay=0.001, batch_size=64, monte_sample_num=50, G=3,
                 lr_prop=0.001, weight_decay_prop=5e-05, batch_size_prop=1024, tol_prop=1e-5, tol=1e-5, k=5,
                 large=False),
    # yahoo_main.py (MF_BV_Multi_bin_JL_G_DR).
    "yahoo": dict(emb_dim=64, lr=0.05, weight_decay=1e-05, batch_size=8192, monte_sample_num=44, G=4,
                  lr_prop=0.01, weight_decay_prop=0.01, batch_size_prop=204800, tol_prop=1e-3, tol=1e-5, k=5,
                  large=False),
    # Local: kuai_main.py values (KuaiRec) with the Yahoo propensity batch/tolerance; no author KuaiRand config.
    "kuairand": dict(emb_dim=16, lr=0.005, weight_decay=0.0001, batch_size=2048, monte_sample_num=40, G=4,
                     lr_prop=0.01, weight_decay_prop=5e-05, batch_size_prop=204800, tol_prop=1e-3, tol=1e-5, k=5,
                     large=True),
}
ALPHA_SWEEP = {"coat": (.4, .6, .8), "yahoo": (.4, .6, .8), "kuairand": (.2, .4, .6, .8)}  # bash/*.sh --sigma_y
PAPER_OURS_DR = {"coat": {"AUC": .775, "Recall@5": .485, "NDCG@5": .679},
                 "yahoo": {"AUC": .715, "Recall@5": .486, "NDCG@5": .713},
                 "kuairand": None}  # the paper reports KuaiRec, not KuaiRand


def setup_seed(seed):
    """utils.setup_seed."""
    torch.manual_seed(seed)
    np.random.seed(seed)
    random.seed(seed)


def _rng_state():
    return torch.get_rng_state(), np.random.get_state(), random.getstate()


def _set_rng_state(state):
    torch.set_rng_state(state[0])
    np.random.set_state(state[1])
    random.setstate(state[2])


def run_seed(dataset, alphas, seed=0, data=None, num_epoch=1000, verbose=False, overrides=None):
    """One seed of the alpha sweep. The IPS stage does not depend on alpha, so it is trained once and the model and
    random state after it are restored for every alpha: the runs equal separate author-script runs."""
    config = dict(CLEV_CONFIG[dataset], **(overrides or {}))
    setup_seed(seed)
    x_train, y_train, x_test, y_test, num_user, num_item = data if data is not None else load(dataset)
    setup_seed(seed)
    cls = CLEVDRLarge if config["large"] else CLEVDR
    model = cls(num_user, num_item, batch_size=config["batch_size"], embedding_k=config["emb_dim"],
                batch_size_prop=config["batch_size_prop"], monte_sample_num=config["monte_sample_num"])
    start = time.time()
    ips = model.compute_ips(x_train, num_epoch=num_epoch, lr=config["lr_prop"], lamb=config["weight_decay_prop"],
                            tol=config["tol_prop"], verbose=verbose)
    ips_seconds = time.time() - start
    after_ips, state = copy.deepcopy(model.state_dict()), _rng_state()
    results = []
    for alpha in alphas:
        model.load_state_dict(after_ips)
        _set_rng_state(state)
        start = time.time()
        fit = model.fit(x_train, y_train, num_epoch=num_epoch, lr=config["lr"], lamb=config["weight_decay"],
                        tol=config["tol"], verbose=verbose, alpha=alpha, G=config["G"])
        metrics = evaluate(model, x_test, y_test, config["k"])
        results.append(dict(metrics, dataset=dataset, alpha=alpha, seed=seed, config=config, ips_training=ips,
                            training=fit, seconds=round(ips_seconds + time.time() - start, 1),
                            num_user=num_user, num_item=num_item, train_rows=int(len(x_train)),
                            test_rows=int(len(x_test))))
    return results


def run(dataset, alpha, seed=0, data=None, num_epoch=1000, verbose=False, overrides=None):
    return run_seed(dataset, (alpha,), seed=seed, data=data, num_epoch=num_epoch, verbose=verbose,
                    overrides=overrides)[0]
