"""MRDR-CAL of Hu et al. (TKDE 2025, Table VI): MRDR on a NeuMF backbone with Platt-calibrated propensities.

Stages 1-2 follow the public author code (sunxin000/uncertainty4recsys @ 36dc7c6): train_propensity_platt.py
trains a logit NeuMF on observed pairs plus as many sampled unobserved pairs (90% random split, BCE, Adam 1e-3,
Coat 100 epochs, others 20), platt_scale.py fits a, b on a fresh sample and the observed rows get
sigmoid(a * logit + b). The author code computes those logits without model.eval(), so dropout stays on; kept.
Stage 3 is missing from the author repository (train_rec_with_MRDR.py is referenced by a script but absent) and
follows Guo et al. MRDR-DL (guosyjlu/MRDR-DL @ a89d2aa, real-world/MRDR-DL.py, FM.py drFM): every
epoch copies the prediction model into the imputation model, trains the imputation model on observed pairs with
the MRDR weight (1 - p) / p^2, then trains the prediction model with the DR loss on observed pairs mixed with six
times as many unobserved pairs, and keeps the epoch with the lowest validation cross-entropy. Both models are
the NeuMF of the paper appendix (64, [64, 32, 16], dropout 0.2, batch 1024, lr 1e-3, L2 1e-4); the imputation
L2 1e-3 is Guo's. Adam weight decay replaces the explicit tf.nn.l2_loss terms of Guo's TF1 code.
"""
import copy
import time

import numpy as np
import torch
import torch.nn.functional as F

from src.models.mrdr_cal.data import load, sample_unobserved
from src.models.mrdr_cal.metrics import evaluate
from src.models.mrdr_cal.model import NeuMF, Platt

BASE = dict(embedding_size=64, mlp_layers=[64, 32, 16], batch_size=1024, lr=1e-3, dropout=.2, weight_decay=1e-4,
            weight_decay_imputation=1e-3, propensity_sample_ratio=1, label_smoothing=0.0, missing_ratio=6,
            patience=100)
# Epoch budgets: propensity epochs from the author code; MRDR epochs are a local CPU budget (Guo: patience 100).
MRDR_CAL_CONFIG = {"coat": dict(BASE, propensity_epochs=100, max_epochs=200),
                   "yahoo": dict(BASE, propensity_epochs=20, max_epochs=50),
                   "kuairand": dict(BASE, propensity_epochs=20, max_epochs=20)}
PAPER_MRDR_CAL = {  # Table VI, AUC, DCG@2/4/6, Recall@2/4/6 (mean over 10 repeats)
    "coat": dict(AUC=.7728, **{"DCG@2": .7648, "DCG@4": 1.0155, "DCG@6": 1.2223,
                               "Recall@2": .8987, "Recall@4": 1.4688, "Recall@6": 1.9957}),
    "yahoo": dict(AUC=.6988, **{"DCG@2": .5623, "DCG@4": .7571, "DCG@6": .8858,
                                "Recall@2": .6687, "Recall@4": 1.0862, "Recall@6": 1.4326}),
    "kuairand": dict(AUC=.6247, **{"DCG@2": .4928, "DCG@4": .7259, "DCG@6": .8963,
                                   "Recall@2": .5971, "Recall@4": 1.0972, "Recall@6": 1.5549})}


def mrdr_imputation_loss(imp_logits, y, p):
    """drFM.loss_il_mrdr without the L2 term: mean(CE(imputation, y) / p * (1 - p) / p) on observed pairs."""
    ce = F.binary_cross_entropy_with_logits(imp_logits, y, reduction="none")
    return torch.mean(ce / p * (1.0 - p) / p)


def dr_loss(pred_logits, imp_logits, y, o, p):
    """drFM.dr_loss: (e - e_il) * o / p + e_il, e_il = CE(prediction, stop_gradient(sigmoid(imputation)))."""
    label = torch.sigmoid(imp_logits).detach()
    e_il = F.binary_cross_entropy_with_logits(pred_logits, label, reduction="none")
    e = F.binary_cross_entropy_with_logits(pred_logits, y, reduction="none")
    return torch.mean((e - e_il) * o / p + e_il)


def _neumf(data, config, logits=True):
    return NeuMF(data["num_users"], data["num_items"], config["embedding_size"], config["embedding_size"],
                 config["mlp_layers"], dropout=config["dropout"], output_logits=logits)


def _batches(n, size, rng, shuffle=True):
    order = rng.permutation(n) if shuffle else np.arange(n)
    for start in range(0, n, size):
        yield order[start:start + size]


def _observe(train, data, ratio, rng):
    """Observe(sample_ratio): observed pairs (click 1) followed by sampled unobserved pairs (click 0)."""
    nu, ni = sample_unobserved(train["user"], train["item"], data["num_users"], data["num_items"],
                               len(train["user"]) * ratio, rng)
    users = np.concatenate([train["user"], nu]).astype(np.int64)
    items = np.concatenate([train["item"], ni]).astype(np.int64)
    clicks = np.concatenate([np.ones(len(train["user"])), np.zeros(len(nu))]).astype(np.float32)
    return users, items, clicks


def train_propensity(data, config, rng):
    users, items, clicks = _observe(data["train"], data, config["propensity_sample_ratio"], rng)
    keep = rng.permutation(len(clicks))[:int(0.9 * len(clicks))]  # random_split 90/10 (the 10% is only monitored)
    model = _neumf(data, config)
    optimizer = torch.optim.Adam(model.parameters(), lr=config["lr"])
    smooth = config["label_smoothing"]
    for _ in range(config["propensity_epochs"]):
        model.train()
        for batch in _batches(len(keep), config["batch_size"], rng):
            rows = keep[batch]
            target = torch.as_tensor(clicks[rows]) * (1.0 - smooth) + 0.5 * smooth
            loss = F.binary_cross_entropy_with_logits(model(torch.as_tensor(users[rows]), torch.as_tensor(items[rows])),
                                                      target)
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
    return model


def calibrated_propensity(model, data, config, rng):
    """platt_scale.py: logits of a fresh Observe sample (model left in train mode), Platt fit, observed rows."""
    users, items, clicks = _observe(data["train"], data, 1, rng)
    with torch.no_grad():
        logits = torch.cat([model(torch.as_tensor(users[b]), torch.as_tensor(items[b]))
                            for b in _batches(len(users), config["batch_size"], rng, shuffle=False)])
    platt = Platt()
    info = platt.fit(logits, torch.as_tensor(clicks))
    with torch.no_grad():
        propensity = torch.sigmoid(platt(logits[:len(data["train"]["user"])])).numpy()
    info.update(raw_mean=float(torch.sigmoid(logits[:len(propensity)]).mean()), calibrated_mean=float(propensity.mean()),
                calibrated_min=float(propensity.min()))
    return propensity.astype(np.float32), info


def _predict(model, users, items, batch_size=8192):
    model.eval()
    with torch.no_grad():
        return torch.cat([torch.sigmoid(model(torch.as_tensor(users[i:i + batch_size], dtype=torch.long),
                                              torch.as_tensor(items[i:i + batch_size], dtype=torch.long)))
                          for i in range(0, len(users), batch_size)]).numpy()


def train_mrdr(data, propensity, config, rng, max_epochs=None):
    fit_idx = data["fit_idx"]
    u = data["train"]["user"][fit_idx].astype(np.int64)
    i = data["train"]["item"][fit_idx].astype(np.int64)
    y = data["train"]["target"][fit_idx].astype(np.float32)
    p = propensity[fit_idx]
    val = data["val"]
    prediction, imputation = _neumf(data, config), _neumf(data, config)
    opt_pred = torch.optim.Adam(prediction.parameters(), lr=config["lr"], weight_decay=config["weight_decay"])
    opt_imp = torch.optim.Adam(imputation.parameters(), lr=config["lr"],
                               weight_decay=config["weight_decay_imputation"])
    best = {"ce": float("inf"), "epoch": 0, "state": None}
    history, stale = [], 0
    for epoch in range(1, (max_epochs or config["max_epochs"]) + 1):
        imputation.load_state_dict(prediction.state_dict())  # sess.run(copy)
        imputation.train()
        for b in _batches(len(y), config["batch_size"], rng):
            loss = mrdr_imputation_loss(imputation(torch.as_tensor(u[b]), torch.as_tensor(i[b])),
                                        torch.as_tensor(y[b]), torch.as_tensor(p[b]))
            opt_imp.zero_grad()
            loss.backward()
            opt_imp.step()
        # get_training_data(sample_ratio=6): observed + 6x unobserved, then len(observed) rows without replacement.
        mu, mi = sample_unobserved(data["train"]["user"], data["train"]["item"], data["num_users"],
                                   data["num_items"], config["missing_ratio"] * len(y), rng)
        pool_u, pool_i = np.concatenate([u, mu]), np.concatenate([i, mi])
        pool_y = np.concatenate([y, np.zeros(len(mu), np.float32)])
        pool_o = np.concatenate([np.ones(len(y), np.float32), np.zeros(len(mu), np.float32)])
        pool_p = np.concatenate([p, np.ones(len(mu), np.float32)])
        pick = rng.choice(len(pool_y), len(y), replace=False)
        prediction.train()
        imputation.eval()
        for b in _batches(len(pick), config["batch_size"], rng, shuffle=False):
            rows = pick[b]
            uu, ii = torch.as_tensor(pool_u[rows]), torch.as_tensor(pool_i[rows])
            with torch.no_grad():
                imp_logits = imputation(uu, ii)
            loss = dr_loss(prediction(uu, ii), imp_logits, torch.as_tensor(pool_y[rows]), torch.as_tensor(pool_o[rows]),
                           torch.as_tensor(pool_p[rows]))
            opt_pred.zero_grad()
            loss.backward()
            opt_pred.step()
        score = _predict(prediction, val["user"], val["item"])
        ce = float(F.binary_cross_entropy(torch.as_tensor(np.clip(score, 1e-7, 1 - 1e-7)),
                                          torch.as_tensor(val["target"], dtype=torch.float32)))
        history.append(ce)
        if ce < best["ce"]:
            best, stale = {"ce": ce, "epoch": epoch, "state": copy.deepcopy(prediction.state_dict())}, 0
        else:
            stale += 1
            if stale >= config["patience"]:
                break
    prediction.load_state_dict(best["state"])
    return prediction, {"best_epoch": best["epoch"], "best_val_ce": best["ce"], "epochs_run": len(history),
                        "val_ce": history}


def run(dataset, seed=0, data=None, overrides=None):
    config = dict(MRDR_CAL_CONFIG[dataset], **(overrides or {}))
    torch.manual_seed(seed)
    np.random.seed(seed)
    rng = np.random.default_rng(seed)
    data = data if data is not None else load(dataset)
    start = time.time()
    propensity_model = train_propensity(data, config, rng)
    propensity, platt = calibrated_propensity(propensity_model, data, config, rng)
    model, training = train_mrdr(data, propensity, config, rng)
    test = data["test"]
    score = _predict(model, test["user"], test["item"])
    per_user = data["items_per_test_user"]
    metrics = evaluate(test["target"], score, data["test_users"], per_user,
                       user_ids=None if per_user else test["user"])
    return dict(metrics, dataset=dataset, seed=seed, config=config, platt=platt, training=training,
                seconds=round(time.time() - start, 1), train_rows=int(len(data["train"]["user"])),
                mrdr_rows=int(len(data["fit_idx"])), val_rows=int(len(data["val"]["user"])),
                test_rows=int(len(test["user"])))
