"""TopPop and ItemKNN-CF, re-implemented from the formulas of Dacrema et al., RecSys 2019.

Reference framework: github.com/MaurizioFD/RecSys2019_DeepLearning_Evaluation @ 0fb6b7f, files
Base/NonPersonalizedRecommender.py (TopPop), KNN/ItemKNNCFRecommender.py and
Base/Similarity/Compute_Similarity_Python.py. No code is copied; the behaviour follows those files:
TopPop scores an item by its number of interactions in the training URM; ItemKNN keeps, for every target item,
the top-K cosine neighbours with denominator ||x_i|| ||x_j|| + shrink + 1e-6 and a zero diagonal, and scores
URM[u] @ W. The training URM holds the H30 positives (train_y > 0).
"""
from itertools import product

import numpy as np
from scipy import sparse

from src.evaluation.evaluator import evaluate_unbiased_model
from src.evaluation.protocol import TOP_K

# Dacrema et al. search topK in [5, 1000] and shrink in [0, 1000]; this is a fixed grid over the same ranges.
ITEM_KNN_GRID = [dict(top_k=k, shrink=s) for k, s in product((5, 10, 20, 50, 100, 200, 500, 1000),
                                                              (0, 10, 50, 100, 200, 500, 1000))]
ITEM_KNN_DEFAULT = dict(top_k=50, shrink=100)  # ItemKNNCFRecommender.fit defaults


def positive_matrix(data):
    positive = np.asarray(data["train_y"]) > 0
    users, items = np.asarray(data["train_u"])[positive], np.asarray(data["train_i"])[positive]
    urm = sparse.csr_matrix((np.ones(len(users), dtype=np.float32), (users, items)),
                            shape=(data["n_users"], data["n_items"]))
    urm.data[:] = 1.0  # duplicate positives collapse to one implicit interaction
    return urm


class TopPop:
    def __init__(self, urm):
        self.item_pop = np.diff(sparse.csc_matrix(urm).indptr).astype(np.float32)

    def eval(self):
        return self

    def predict(self, user, items, device=None):
        return self.item_pop[np.asarray(items)]


def cosine_gram(urm):
    """Item-item dot products and column norms, computed once and shared by every grid point."""
    urm = sparse.csc_matrix(urm, dtype=np.float32)
    gram = (urm.T @ urm).toarray().astype(np.float32)
    norms = np.sqrt(np.asarray(urm.power(2).sum(axis=0)).ravel()).astype(np.float32)
    return gram, norms


def similarity_matrix(gram, norms, top_k, shrink):
    weights = gram / (np.outer(norms, norms) + shrink + 1e-6)
    np.fill_diagonal(weights, 0.0)
    n_items = len(norms)
    top_k = min(int(top_k), n_items)
    # For each target item (column), keep the top_k largest non-zero weights.
    keep = np.argpartition(-weights, top_k - 1, axis=0)[:top_k]
    columns = np.broadcast_to(np.arange(n_items), keep.shape)
    values = weights[keep, columns]
    nonzero = values != 0.0
    return sparse.csr_matrix((values[nonzero], (keep[nonzero], columns[nonzero])), shape=(n_items, n_items))


class ItemKNNCF:
    def __init__(self, urm, top_k=50, shrink=100, gram=None):
        if top_k < 1 or shrink < 0:
            raise ValueError("top_k must be positive and shrink nonnegative")
        self.urm = sparse.csr_matrix(urm, dtype=np.float32)
        gram, norms = gram if gram is not None else cosine_gram(self.urm)
        self.top_k, self.shrink = int(top_k), float(shrink)
        self.similarity = similarity_matrix(gram, norms, top_k, shrink)

    def eval(self):
        return self

    def predict(self, user, items, device=None):
        return (self.urm[int(user)] @ self.similarity).toarray().ravel()[np.asarray(items)]


def evaluate(model, data, split, **kwargs):
    return evaluate_unbiased_model(model, data[f"{split}_candidates"], data[f"{split}_ground_truth"], k=TOP_K,
                                   include_zero_positive_users=data.get("evaluation_include_zero_positive_users",
                                                                        True), **kwargs)


def select_item_knn(data, grid=None):
    """Pick (top_k, shrink) by validation NDCG@5; the first config wins ties, test is not read."""
    urm = positive_matrix(data)
    gram = cosine_gram(urm)
    rows, best = [], None
    for config in grid or ITEM_KNN_GRID:
        model = ItemKNNCF(urm, gram=gram, **config)
        validation = evaluate(model, data, "val")
        rows.append(dict(config=dict(config), val_ndcg=validation["NDCG@5"]))
        if best is None or validation["NDCG@5"] > best[1]["NDCG@5"]:
            best = (dict(config), validation)
    return {"config": best[0], "validation": best[1], "grid": rows}


def evaluate_test(model, data, return_user_ndcg=False):
    return evaluate(model, data, "test", compute_user_auc=True, return_user_ndcg=return_user_ndcg)
