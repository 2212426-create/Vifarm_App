"""Metrics of Hu et al. (utils/metrics.py), which follow Guo et al. (MRDR-DL real-world/metric.py).

Coat and Yahoo test sets have a fixed number of items per user (16, 10) and are reshaped; users without a
positive are skipped; DCG@K is not normalised and Recall@K counts hits (it can exceed 1). KuaiRand goes through
the per-user branch of the author code, whose Recall@K divides by the user's positives; Tables V-VI of the paper
report values above 1 for KuaiRand, so the hit count is also reported (`recall_count`).

NDCG@5, Recall@5 and Recall@5_bounded are added with the project definitions (src/evaluation/protocol.py) so the
model can be read at the K used elsewhere in the thesis. They are not in the paper and stay on this protocol.
"""
import numpy as np

from src.models.clev.metrics import roc_auc

KS = (2, 4, 6)


def _ranked_rows(label, score, user_num, items_per_user, user_ids):
    """Yield each user's labels sorted by descending score, skipping users without a positive."""
    label, score = np.asarray(label, dtype=float), np.asarray(score, dtype=float)
    if user_ids is None:
        label, score = label.reshape([user_num, items_per_user]), score.reshape([user_num, items_per_user])
        for row_label, row_score in zip(label, score):
            if row_label.sum() > 0:
                yield row_label[np.argsort(-row_score)]
        return
    user_ids = np.asarray(user_ids)
    order = np.argsort(user_ids, kind="stable")
    bounds = np.flatnonzero(np.diff(user_ids[order])) + 1
    for rows in np.split(order, bounds):
        if label[rows].sum() > 0:
            yield label[rows][np.argsort(-score[rows])]


def dcg_at_k(label, score, user_num, items_per_user, ks=KS, user_ids=None):
    values = {k: [] for k in ks}
    for ranked in _ranked_rows(label, score, user_num, items_per_user, user_ids):
        for k in ks:
            if k <= len(ranked):
                values[k].append(np.sum(ranked[:k] / np.log2(np.arange(k) + 2)))
    return np.array([np.mean(values[k]) if values[k] else 0.0 for k in ks])


def recall_at_k(label, score, user_num, items_per_user, ks=KS, user_ids=None, normalise=None):
    """Hit count for the reshaped datasets; fraction of positives for the per-user branch (author code)."""
    normalise = user_ids is not None if normalise is None else normalise
    values = {k: [] for k in ks}
    for ranked in _ranked_rows(label, score, user_num, items_per_user, user_ids):
        for k in ks:
            if k <= len(ranked):
                values[k].append(ranked[:k].sum() / (ranked.sum() if normalise else 1.0))
    return np.array([np.mean(values[k]) if values[k] else 0.0 for k in ks])


def project_topk(label, score, user_num, items_per_user, k=5, user_ids=None):
    """Project NDCG@K (IDCG over min(K, positives)), Recall@K = hits / positives, bounded = hits / min(K, positives).

    Macro average over users with at least one positive, the same users the Hu metrics keep."""
    ndcg, recall, bounded = [], [], []
    discounts = 1.0 / np.log2(np.arange(k) + 2)
    for ranked in _ranked_rows(label, score, user_num, items_per_user, user_ids):
        positives = ranked.sum()
        hits = ranked[:k]
        ideal = discounts[:int(min(k, positives))].sum()
        ndcg.append(float(np.sum(hits * discounts[:len(hits)]) / ideal))
        recall.append(float(hits.sum() / positives))
        bounded.append(float(hits.sum() / min(k, positives)))
    mean = lambda values: float(np.mean(values)) if values else 0.0  # noqa: E731
    return {f"NDCG@{k}": mean(ndcg), f"Recall@{k}": mean(recall), f"Recall@{k}_bounded": mean(bounded)}


def user_auc(label, score, user_num, items_per_user, user_ids=None):
    """calculate_auc: mean AUC over users that have both classes."""
    label, score = np.asarray(label), np.asarray(score)
    if user_ids is None:
        groups = zip(label.reshape([user_num, items_per_user]), score.reshape([user_num, items_per_user]))
    else:
        order = np.argsort(user_ids, kind="stable")
        bounds = np.flatnonzero(np.diff(np.asarray(user_ids)[order])) + 1
        groups = ((label[rows], score[rows]) for rows in np.split(order, bounds))
    aucs = [roc_auc(lab, sco) for lab, sco in groups if len(np.unique(lab)) > 1]
    return float(np.mean(aucs)) if aucs else 0.0


def evaluate(label, score, user_num, items_per_user, user_ids=None):
    dcg = dcg_at_k(label, score, user_num, items_per_user, user_ids=user_ids)
    recall = recall_at_k(label, score, user_num, items_per_user, user_ids=user_ids)
    out = {"AUC": roc_auc(label, score), "UAUC": user_auc(label, score, user_num, items_per_user, user_ids)}
    out.update({f"DCG@{k}": float(v) for k, v in zip(KS, dcg)})
    out.update({f"Recall@{k}": float(v) for k, v in zip(KS, recall)})
    out.update(project_topk(label, score, user_num, items_per_user, user_ids=user_ids))
    if user_ids is not None:
        counts = recall_at_k(label, score, user_num, items_per_user, user_ids=user_ids, normalise=False)
        out.update({f"Recall@{k}_count": float(v) for k, v in zip(KS, counts)})
    return out
