"""Data of Hu et al. (utils/dataset.py) for Coat, Yahoo! R3 and KuaiRand.

Coat/Yahoo: the MNAR file is the training set (click = rated, conversion = rating > 3) and the MAR file is the
test set (16 and 10 items per user). The paper holds out 10% of the MNAR ratings for validation; the public IPS
script does not, MRDR here uses that 10% for its early stopping (Guo et al. select on validation cross-entropy).
KuaiRand-Pure (following CDR, as the paper says): both standard logs are the training set, the random log is
split 10% validation / 90% test, target is_click. Users and videos are mapped jointly over all logs.
"""
from pathlib import Path

import numpy as np
import pandas as pd

from src.models.conalign.data import KUAIRAND_LOGS
from src.utils.helpers import RAW_DATA_DIR

DATASETS = ("coat", "yahoo", "kuairand")
ITEMS_PER_TEST_USER = {"coat": 16, "yahoo": 10, "kuairand": None}


def implicit_target(target, threshold=3):
    """ObservedData._preprocess_target: rating <= 3 -> 0, otherwise 1."""
    target = np.array(target, dtype=np.float32, copy=True)
    target[target <= threshold] = 0
    target[target > threshold] = 1
    return target


def sample_unobserved(users, items, num_users, num_items, count, rng):
    """Observe: uniform (user, item) pairs not in the observed set, without duplicates."""
    observed = np.unique(np.asarray(users, dtype=np.int64) * num_items + np.asarray(items, dtype=np.int64))
    if num_users * num_items - len(observed) < count:
        raise ValueError("Not enough unobserved pairs")
    chosen = np.empty(0, dtype=np.int64)
    while len(chosen) < count:
        draw = rng.integers(0, num_users, count) * num_items + rng.integers(0, num_items, count)
        draw = draw[~np.isin(draw, observed)]
        chosen = np.unique(np.concatenate([chosen, draw]))
    chosen = rng.permutation(chosen)[:count]
    return chosen // num_items, chosen % num_items


def _split(rows, fraction, seed):
    order = np.random.default_rng(seed).permutation(rows)
    cut = int(round(fraction * rows))
    return order[cut:], order[:cut]


def _part(user, item, target, idx):
    return {"user": user[idx], "item": item[idx], "target": target[idx]}


def build_kuairand(biased, random_log, val_fraction=0.1, seed=0):
    users = np.unique(np.concatenate([biased.user_id.to_numpy(), random_log.user_id.to_numpy()]))
    videos = np.unique(np.concatenate([biased.video_id.to_numpy(), random_log.video_id.to_numpy()]))
    def encode(frame):
        return (np.searchsorted(users, frame.user_id.to_numpy()), np.searchsorted(videos, frame.video_id.to_numpy()),
                frame.is_click.to_numpy().astype(np.float32))
    tu, ti, tt = encode(biased)
    ru, ri, rt = encode(random_log)
    test_idx, val_idx = _split(len(rt), val_fraction, seed)
    return {"dataset": "kuairand", "num_users": len(users), "num_items": len(videos),
            "train": {"user": tu, "item": ti, "target": tt}, "fit_idx": np.arange(len(tu)),
            "val": _part(ru, ri, rt, np.sort(val_idx)), "test": _part(ru, ri, rt, np.sort(test_idx)),
            "items_per_test_user": None, "test_users": None}


def load(dataset, data_dir=None, val_fraction=0.1, split_seed=0):
    root = Path(data_dir or RAW_DATA_DIR)
    if dataset == "kuairand":
        frames = {name: pd.read_csv(next((root / "kuairand_pure").rglob(name)),
                                    usecols=["user_id", "video_id", "is_click"]) for name in KUAIRAND_LOGS}
        biased = pd.concat([frames[KUAIRAND_LOGS[0]], frames[KUAIRAND_LOGS[1]]], ignore_index=True)
        return build_kuairand(biased, frames[KUAIRAND_LOGS[2]], val_fraction, split_seed)
    if dataset == "coat":
        train_m = np.loadtxt(root / "coat" / "train.ascii", dtype=int)
        test_m = np.loadtxt(root / "coat" / "test.ascii", dtype=int)
        tu, ti = np.where(train_m)
        su, si = np.where(test_m)
        train_target, test_target = train_m[tu, ti].astype(np.float32), test_m[su, si].astype(np.float32)
    elif dataset == "yahoo":
        # The author files are 0-based ("the data i got is from 0"); Webscope ids start at 1.
        train_m = np.loadtxt(root / "yahoo" / "ydata-ymusic-rating-study-v1_0-train.txt", dtype=int)
        test_m = np.loadtxt(root / "yahoo" / "ydata-ymusic-rating-study-v1_0-test.txt", dtype=int)
        tu, ti, train_target = train_m[:, 0] - 1, train_m[:, 1] - 1, train_m[:, 2].astype(np.float32)
        su, si, test_target = test_m[:, 0] - 1, test_m[:, 1] - 1, test_m[:, 2].astype(np.float32)
    else:
        raise ValueError(f"dataset must be one of {DATASETS}")
    num_users, num_items = int(tu.max() + 1), int(ti.max() + 1)
    target = implicit_target(train_target)
    fit_idx, val_idx = _split(len(tu), val_fraction, split_seed)
    test = {"user": su, "item": si, "target": implicit_target(test_target)}
    return {"dataset": dataset, "num_users": num_users, "num_items": num_items,
            "train": {"user": tu, "item": ti, "target": target},
            "fit_idx": np.sort(fit_idx), "val": _part(tu, ti, target, np.sort(val_idx)),
            "test": test, "items_per_test_user": ITEMS_PER_TEST_USER[dataset],
            "test_users": int(su.max() + 1)}
