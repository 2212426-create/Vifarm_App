"""TopPop and ItemKNN-CF checked against the formulas of Dacrema et al. (RecSys 2019) framework."""
import unittest

import numpy as np
from scipy import sparse

from src.models.neighborhood.recommenders import ItemKNNCF, TopPop, positive_matrix, select_item_knn


def toy_urm():
    rows = [0, 0, 1, 1, 1, 2, 3]
    cols = [0, 1, 0, 1, 2, 2, 3]
    return sparse.csr_matrix((np.ones(len(rows), dtype=np.float32), (rows, cols)), shape=(4, 4))


class NeighborhoodTests(unittest.TestCase):
    def test_positive_matrix_keeps_only_positive_labels(self):
        data = dict(n_users=2, n_items=3, train_u=np.array([0, 0, 1, 1]), train_i=np.array([0, 1, 1, 1]),
                    train_y=np.array([1., 0., 1., 1.], dtype=np.float32))
        urm = positive_matrix(data)
        np.testing.assert_array_equal(urm.toarray(), [[1, 0, 0], [0, 1, 0]])

    def test_top_pop_counts_positive_users_per_item(self):
        model = TopPop(toy_urm())
        np.testing.assert_array_equal(model.item_pop, [2, 2, 2, 1])
        np.testing.assert_array_equal(model.predict(0, np.array([3, 0])), [1, 2])

    def test_cosine_with_shrink_and_zero_diagonal(self):
        urm = toy_urm()
        model = ItemKNNCF(urm, top_k=4, shrink=10)
        dense = urm.toarray()
        norms = np.sqrt((dense ** 2).sum(axis=0))
        expected = dense.T @ dense / (np.outer(norms, norms) + 10 + 1e-6)
        np.fill_diagonal(expected, 0.0)
        np.testing.assert_allclose(model.similarity.toarray(), expected, rtol=1e-5)

    def test_top_k_keeps_k_neighbours_per_target_item(self):
        model = ItemKNNCF(toy_urm(), top_k=1, shrink=0)
        self.assertTrue(np.all(np.diff(model.similarity.tocsc().indptr) <= 1))
        self.assertEqual(model.similarity[1, 0], model.similarity.toarray()[:, 0].max())

    def test_score_is_user_profile_times_similarity(self):
        urm = toy_urm()
        model = ItemKNNCF(urm, top_k=4, shrink=0)
        expected = (urm[2] @ model.similarity).toarray().ravel()[[0, 1, 3]]
        np.testing.assert_allclose(model.predict(2, np.array([0, 1, 3])), expected, rtol=1e-6)

    def test_selection_uses_validation_only(self):
        data = dict(n_users=4, n_items=4, train_u=np.array([0, 0, 1, 1, 1, 2, 3]),
                    train_i=np.array([0, 1, 0, 1, 2, 2, 3]), train_y=np.ones(7, dtype=np.float32),
                    val_candidates={2: [0, 1, 3]}, val_ground_truth={2: {1}},
                    test_candidates={3: [0, 1]}, test_ground_truth={3: set()},
                    evaluation_include_zero_positive_users=False)
        selected = select_item_knn(data, grid=[dict(top_k=1, shrink=0), dict(top_k=4, shrink=0)])
        self.assertEqual(len(selected["grid"]), 2)
        self.assertIn(selected["config"], [row["config"] for row in selected["grid"]])
        self.assertEqual(selected["validation"]["NDCG@5"], max(row["val_ndcg"] for row in selected["grid"]))


if __name__ == "__main__":
    unittest.main()
