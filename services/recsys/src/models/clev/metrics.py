"""Evaluation of the CLEV-DR author scripts (utils.py: ndcg_func, recall_func, precision_func; global AUC).

Per test user, items are ranked by model.predict. Users without a positive get nDCG 1 (author convention);
recall divides by max(1, #positives), precision by K. Scores are macro averages over test users.
"""
import numpy as np
from scipy.stats import rankdata


def roc_auc(labels, scores):
    """Same value as sklearn.metrics.roc_auc_score (Mann-Whitney with average ranks for ties)."""
    labels, ranks = np.asarray(labels) > 0, rankdata(scores)
    n_pos, n_neg = labels.sum(), (~labels).sum()
    if n_pos == 0 or n_neg == 0:
        raise ValueError("AUC needs both classes")
    return float((ranks[labels].sum() - n_pos * (n_pos + 1) / 2) / (n_pos * n_neg))


def _per_user(model, x_te, y_te):
    for uid in np.unique(x_te[:, 0]):
        rows = np.arange(len(x_te))[x_te[:, 0] == uid]
        yield y_te[rows], model.predict(x_te[rows])


def ndcg_at_k(model, x_te, y_te, k):
    values = []
    discount = np.log2(1 + np.arange(1, k + 1))
    for y_u, pred_u in _per_user(model, x_te, y_te):
        top = np.argsort(-pred_u)[:k]
        dcg = y_u[top] / discount[:len(top)]
        best = y_u[np.argsort(-y_u)][:k] / discount[:min(k, len(y_u))]
        values.append(1 if np.sum(best) == 0 else np.sum(dcg) / np.sum(best))
    return float(np.mean(values))


def recall_at_k(model, x_te, y_te, k):
    return float(np.mean([np.sum(y_u[np.argsort(-p)[:k]]) / max(1, sum(y_u)) for y_u, p in _per_user(model, x_te, y_te)]))


def precision_at_k(model, x_te, y_te, k):
    return float(np.mean([np.sum(y_u[np.argsort(-p)[:k]]) / k for y_u, p in _per_user(model, x_te, y_te)]))


def evaluate(model, x_te, y_te, k):
    """Table 2 of the paper reports AUC, Recall@K, NDCG@K with K = 5 (Coat, Yahoo) and 50 (KuaiRec)."""
    return {"AUC": roc_auc(y_te, model.predict(x_te)), f"Recall@{k}": recall_at_k(model, x_te, y_te, k),
            f"NDCG@{k}": ndcg_at_k(model, x_te, y_te, k), f"Precision@{k}": precision_at_k(model, x_te, y_te, k)}
