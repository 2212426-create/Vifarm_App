"""Yahoo! R3 ratings and observed survey proxies from the pinned CDR dataset.

Raw IDs are one-based. Shared benchmarks subtract one and split random-log
users 30/70. Survey row n belongs to raw user n; non-participants receive an
explicit missing category, never a rating-derived or random proxy.
"""
from pathlib import Path
import hashlib

import numpy as np
from scipy import sparse

from src.utils.helpers import resolve_dataset_dir

YAHOO_PREFIX = "ydata-ymusic-rating-study-v1_0-"
CDR_REPOSITORY = "CrazyDumpling/CDR_CIKM2023"
CDR_COMMIT = "6b4e6cca3df23b8d85b38fdc2e7eb5c812861ea9"
SURVEY_CARDINALITIES = (5, 5, 5, 5, 5, 5, 2)


def load_yahoo_raw(data_dir=None):
    folder = Path(resolve_dataset_dir("yahoo", data_dir))
    files = {key: folder / f"{YAHOO_PREFIX}{key}.txt"
             for key in ("train", "test", "survey-answers")}
    arrays = {key: np.loadtxt(path, dtype=np.int64, ndmin=2) for key, path in files.items()}
    for key in ("train", "test"):
        rows = arrays[key]
        if rows.shape[1] != 3 or not len(rows) or (rows[:, :2] < 1).any() or not np.isin(rows[:, 2], [1,2,3,4,5]).all():
            raise ValueError(f"Invalid Yahoo {key}: expected one-based user/item IDs and ratings 1..5")
    train, random = arrays["train"], arrays["test"]
    n_users = int(max(train[:, 0].max(), random[:, 0].max()))
    n_items = int(max(train[:, 1].max(), random[:, 1].max()))
    for key in ("train", "test"):
        ids = (arrays[key][:, 0] - 1) * n_items + arrays[key][:, 1] - 1
        if len(np.unique(ids)) != len(ids):
            raise ValueError(f"Yahoo {key} contains repeated user/item ratings")
    answers = arrays["survey-answers"]
    if answers.shape[1] != 7 or len(answers) > n_users:
        raise ValueError("Yahoo survey must have seven aligned answers per participant")
    columns = []
    for col, cardinality in enumerate(SURVEY_CARDINALITIES):
        if not np.isin(answers[:, col], np.arange(1, cardinality + 1)).all():
            raise ValueError("Invalid Yahoo survey answer code")
        codes = np.zeros(n_users, dtype=np.int64)  # 0 explicitly means missing.
        codes[:len(answers)] = answers[:, col]
        columns.append(np.eye(cardinality + 1, dtype=np.float32)[codes])
    features = np.concatenate(columns, axis=1)
    random_users = np.unique(random[:, 0])
    if random_users.max() > len(answers):
        raise ValueError("Random-log user IDs exceed aligned Yahoo survey rows")
    return dict(data_dir=str(folder), train_ratings=train, random_ratings=random,
        n_users=n_users, n_items=n_items, user_features=features,
        user_feature_info=dict(source="observed_yahoo_survey_answers", questions=7,
            encoding="one_hot_per_question_with_missing_category_0", dimensions=features.shape[1],
            surveyed_users=len(answers), missing_proxy_users=n_users-len(answers),
            proxy_sha256=hashlib.sha256(features.tobytes()).hexdigest(),
            limitation="Yahoo extension; iDCF identification assumptions not verified for missing-survey users"),
        source_signature=dict(repository=CDR_REPOSITORY, commit=CDR_COMMIT,
            files=[dict(path=str(p), size=p.stat().st_size,
                        sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in files.values()]))


def load_yahoo_processed(pos_threshold=4, data_dir=None):
    raw = load_yahoo_raw(data_dir)
    train, random = raw["train_ratings"], raw["random_ratings"]
    u, i = train[:, 0] - 1, train[:, 1] - 1
    y = (train[:, 2] >= pos_threshold).astype(np.float32)
    users = np.unique(random[:, 0] - 1)
    test_users = set(np.random.RandomState(1234).choice(users, size=len(users)*7//10, replace=False).tolist())
    pools = {"val_candidates": {}, "val_ground_truth": {}, "test_candidates": {}, "test_ground_truth": {}}
    for user in users:
        rows = random[random[:, 0] == user + 1]
        split = "test" if user in test_users else "val"
        pools[split + "_candidates"][int(user)] = rows[:, 1] - 1
        pools[split + "_ground_truth"][int(user)] = set((rows[rows[:, 2] >= pos_threshold, 1] - 1).tolist())
    n_users, n_items = raw["n_users"], raw["n_items"]
    train_ids = set((u * n_items + i).tolist())
    overlap = {split: sum(int(user*n_items+int(item) in train_ids)
        for user, items in pools[split + "_candidates"].items() for item in items) for split in ("val", "test")}
    positive_overlap = sum(int(user*n_items+int(item) in train_ids)
        for user, items in pools["test_ground_truth"].items() for item in items)
    return dict(data_dir=raw["data_dir"], cache_signature=raw["source_signature"],
        n_users=n_users, n_items=n_items, train_u=u, train_i=i, train_y=y,
        train_c=np.ones(len(y), dtype=np.float32),
        train_sparse=sparse.csr_matrix((y[y>0], (u[y>0], i[y>0])), shape=(n_users, n_items)),
        user_features=raw["user_features"], user_feature_info=raw["user_feature_info"],
        evaluation_include_zero_positive_users=False,
        split_info=dict(protocol="paper_idcf", dataset_extension="yahoo_survey_proxy", split_unit="user", seed=1234,
            positive_threshold=pos_threshold, validation_users=len(pools["val_candidates"]),
            test_users=len(pools["test_candidates"]), validation_rows=sum(map(len,pools["val_candidates"].values())),
            test_rows=sum(map(len,pools["test_candidates"].values())),
            train_random_overlap_pairs=sum(overlap.values()), validation_overlap_pairs=overlap["val"],
            test_overlap_pairs=overlap["test"], test_overlap_positive_pairs=positive_overlap), **pools)


def subset_yahoo_users(data, max_users=64, seed=42):
    """Smoke subset of random-log users; retain all item IDs and survey alignment."""
    users = np.array(sorted(set(data["val_candidates"]) | set(data["test_candidates"])))
    chosen = np.sort(np.random.RandomState(seed).choice(users, size=min(max_users,len(users)), replace=False))
    mapping = {int(user): idx for idx, user in enumerate(chosen)}
    result = dict(data)
    mask = np.isin(data["train_u"], chosen)
    result.update(n_users=len(chosen), train_u=np.array([mapping[int(x)] for x in data["train_u"][mask]]),
        train_i=data["train_i"][mask], train_y=data["train_y"][mask], train_c=data["train_c"][mask],
        user_features=data["user_features"][chosen])
    for split in ("val", "test"):
        for kind in ("candidates", "ground_truth"):
            result[split+"_"+kind] = {mapping[u]: values for u,values in data[split+"_"+kind].items() if u in mapping}
    positive=result["train_y"]>0
    result["train_sparse"] = sparse.csr_matrix((result["train_y"][positive],(result["train_u"][positive],result["train_i"][positive])),
                                                shape=(len(chosen),data["n_items"]))
    result["split_info"] = dict(data["split_info"], smoke=True, original_user_ids=chosen.tolist(),
        validation_users=len(result["val_candidates"]),test_users=len(result["test_candidates"]),
        validation_rows=sum(map(len,result["val_candidates"].values())),test_rows=sum(map(len,result["test_candidates"].values())))
    result["user_feature_info"] = dict(data["user_feature_info"], smoke=True,
        surveyed_users=len(chosen), missing_proxy_users=0,
        proxy_sha256=hashlib.sha256(result["user_features"].tobytes()).hexdigest())
    train_pairs=set(zip(result["train_u"].tolist(),result["train_i"].tolist()))
    overlap={split:sum((u,int(i)) in train_pairs for u,items in result[split+"_candidates"].items() for i in items)
             for split in ("val","test")}
    result["split_info"].update(train_random_overlap_pairs=sum(overlap.values()),validation_overlap_pairs=overlap["val"],
        test_overlap_pairs=overlap["test"],test_overlap_positive_pairs=sum((u,int(i)) in train_pairs
            for u,items in result["test_ground_truth"].items() for i in items))
    return result
