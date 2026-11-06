"""Data of the CLEV-DR author scripts (dataset.py, coat_test.py, yahoo_main.py) and KuaiRand-Pure for the thesis.

Coat: train.ascii / test.ascii rating matrices, ratings >= 3 positive. Yahoo! R3: Webscope train/test files with
the original 1-based ids, ratings >= 3 positive, training rows shuffled once with the seeded global numpy RNG.
KuaiRand-Pure replaces the KuaiRec data of the paper (the thesis uses KuaiRand-Pure for every model): both
standard logs are the biased training log, the random log is the test set, target is_click, users and videos
mapped jointly over the three logs. Repeated (user, video) rows are merged (clicked if any row is a click),
because the author code builds dense matrices that would sum duplicates. Labels follow the code, not the paper.
"""
from pathlib import Path

import numpy as np
import pandas as pd

from src.models.conalign.data import KUAIRAND_LOGS
from src.utils.helpers import RAW_DATA_DIR

DATASETS = ("coat", "yahoo", "kuairand")


def binarize(y, thres=3):
    """utils.binarize: y < thres -> 0, otherwise 1 (on a copy)."""
    y = np.array(y, dtype=float, copy=True)
    y[y < thres] = 0
    y[y >= thres] = 1
    return y


def rating_mat_to_sample(mat):
    row, col = np.nonzero(mat)
    return np.concatenate([row.reshape(-1, 1), col.reshape(-1, 1)], axis=1), mat[row, col]


def kuairand_frames_to_samples(biased, random_log):
    users = np.unique(np.concatenate([biased.user_id.to_numpy(), random_log.user_id.to_numpy()]))
    videos = np.unique(np.concatenate([biased.video_id.to_numpy(), random_log.video_id.to_numpy()]))

    def encode(frame):
        merged = frame.groupby(["user_id", "video_id"], as_index=False, sort=True)["is_click"].max()
        x = np.stack([np.searchsorted(users, merged.user_id.to_numpy()),
                      np.searchsorted(videos, merged.video_id.to_numpy())], axis=1)
        return x.astype(np.int64), merged.is_click.to_numpy().astype(float)

    x_train, y_train = encode(biased)
    x_test, y_test = encode(random_log)
    return x_train, y_train, x_test, y_test, len(users), len(videos)


def load(dataset, data_dir=None):
    """Return x_train, y_train, x_test, y_test, num_user, num_item.

    Yahoo shuffles its training rows with np.random, so call this after seeding, as yahoo_main.py does.
    """
    root = Path(data_dir or RAW_DATA_DIR)
    if dataset == "coat":
        train = np.loadtxt(root / "coat" / "train.ascii", dtype=int)
        test = np.loadtxt(root / "coat" / "test.ascii", dtype=int)
        x_train, y_train = rating_mat_to_sample(train)
        x_test, y_test = rating_mat_to_sample(test)
        return x_train, binarize(y_train), x_test, binarize(y_test), train.shape[0], train.shape[1]
    if dataset == "yahoo":
        train = np.loadtxt(root / "yahoo" / "ydata-ymusic-rating-study-v1_0-train.txt", dtype=int)
        test = np.loadtxt(root / "yahoo" / "ydata-ymusic-rating-study-v1_0-test.txt", dtype=int)
        x_train, y_train = train[:, :-1], train[:, -1]
        idxs = np.arange(x_train.shape[0])
        np.random.shuffle(idxs)
        x_train, y_train = x_train[idxs], y_train[idxs]
        return (x_train, binarize(y_train), test[:, :-1], binarize(test[:, -1]),
                int(x_train[:, 0].max() + 1), int(x_train[:, 1].max() + 1))
    if dataset == "kuairand":
        frames = {name: pd.read_csv(next((root / "kuairand_pure").rglob(name)),
                                    usecols=["user_id", "video_id", "is_click"]) for name in KUAIRAND_LOGS}
        biased = pd.concat([frames[KUAIRAND_LOGS[0]], frames[KUAIRAND_LOGS[1]]], ignore_index=True)
        return kuairand_frames_to_samples(biased, frames[KUAIRAND_LOGS[2]])
    raise ValueError(f"dataset must be one of {DATASETS}")
