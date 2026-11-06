"""CLEV-DR (Zhang et al., KDD 2025, "Ours-DR") checked against the formulas of the author code."""
import unittest

import numpy as np
import torch

import pandas as pd

from src.models.clev.data import binarize, kuairand_frames_to_samples, rating_mat_to_sample
from src.models.clev.metrics import ndcg_at_k, precision_at_k, recall_at_k, roc_auc
from src.models.clev.model import CLEVDR, CLEVDRLarge, NCFBase, all_pairs
from src.models.clev.metrics import evaluate
from src.models.clev.train import ALPHA_SWEEP, CLEV_CONFIG, run_seed, setup_seed


class _Fixed:
    def __init__(self, scores):
        self.scores = scores

    def predict(self, x):
        return self.scores[x[:, 0], x[:, 1]]


class CLEVModelTests(unittest.TestCase):
    def test_ncf_tower_is_2k_k_k_1(self):
        model = NCFBase(5, 7, embedding_k=4)
        self.assertEqual([layer.out_features for layer in (model.linear_1, model.linear_2, model.linear_3)], [4, 4, 1])
        self.assertEqual(model.linear_1.in_features, 8)
        out = model.forward(np.array([[0, 1], [4, 6]]))
        self.assertEqual(tuple(out.shape), (2,))

    def test_four_towers_and_bounded_rho(self):
        model = CLEVDR(4, 3, batch_size=2, embedding_k=2, monte_sample_num=3)
        names = {name.split(".")[0] for name, _ in model.named_parameters()}
        self.assertEqual(names, {"prediction_model", "propensity_model", "propensity_model_2", "imputation_model",
                                 "rho_v"})
        with torch.no_grad():
            model.rho_v.fill_(3.0)
        self.assertLess(float(model.rho()), 1.0)
        self.assertGreater(float(model.rho()), 0.99)

    def test_all_pairs_is_row_major(self):
        np.testing.assert_array_equal(all_pairs(2, 3), [[0, 0], [0, 1], [0, 2], [1, 0], [1, 1], [1, 2]])

    def test_predict_is_sigmoid_of_prediction_tower(self):
        model = CLEVDR(3, 3, batch_size=2, embedding_k=2)
        x = np.array([[0, 1], [2, 2]])
        expected = torch.sigmoid(model.prediction_model.forward(x)).detach().numpy()
        np.testing.assert_allclose(model.predict(x), expected, rtol=1e-6)

    def test_short_fit_runs_and_changes_weights(self):
        torch.manual_seed(0)
        np.random.seed(0)
        model = CLEVDR(6, 5, batch_size=4, embedding_k=8, monte_sample_num=4, batch_size_prop=10)
        x = np.array([[u, i] for u in range(6) for i in range(5) if (u + i) % 2 == 0])
        y = (np.arange(len(x)) % 2).astype(np.float32)
        before = [p.detach().clone() for p in model.prediction_model.parameters()]
        model.compute_ips(x, num_epoch=2, lr=.01, lamb=0, tol=1e-5)
        model.fit(x, y, num_epoch=2, lr=.01, lamb=0, tol=1e-5, alpha=.5, G=2)
        self.assertTrue(any(not torch.equal(a, b) for a, b in zip(before, model.prediction_model.parameters())))
        self.assertTrue(np.isfinite(model.predict(x)).all())


class CLEVLargeTests(unittest.TestCase):
    """CLEVDRLarge drops the |U| x |I| arrays (needed for KuaiRand-Pure) but must reproduce CLEVDR exactly."""

    def fit_both(self, chunk):
        rng = np.random.default_rng(4)
        x = np.array(sorted({(int(u), int(i)) for u, i in zip(rng.integers(0, 9, 40), rng.integers(0, 7, 40))}))
        x = x[rng.permutation(len(x))]
        y = rng.integers(0, 2, len(x)).astype(np.float32)
        out = []
        for cls, extra in ((CLEVDR, {}), (CLEVDRLarge, {"epsilon_chunk": chunk})):
            torch.manual_seed(0)
            np.random.seed(0)
            model = cls(9, 7, batch_size=6, embedding_k=8, monte_sample_num=5, batch_size_prop=16, **extra)
            model.compute_ips(x, num_epoch=3, lr=.01, lamb=0, tol=1e-5)
            model.fit(x, y, num_epoch=3, lr=.01, lamb=0, tol=1e-5, alpha=.5, G=2)
            out.append((model.predict(x), float(model.rho().detach())))
        return out

    def test_large_mode_matches_the_author_layout_exactly(self):
        for chunk in (5, 64):
            (full, rho_full), (large, rho_large) = self.fit_both(chunk)
            np.testing.assert_array_equal(full, large)
            self.assertEqual(rho_full, rho_large)

    def test_chunked_noise_equals_one_draw(self):
        for users, items, m, chunk in ((9, 7, 5, 5), (9, 7, 5, 16), (17, 1, 3, 16), (40, 41, 1, 100), (3, 6, 7, 13)):
            model = CLEVDRLarge(users, items, batch_size=2, embedding_k=2, monte_sample_num=m, epsilon_chunk=chunk)
            codes = np.arange(0, users * items, 2)
            torch.manual_seed(1)
            chunked = model._observed_epsilon(codes)
            torch.manual_seed(1)
            full = model.normal.sample((users * items, m)).squeeze(-1)[torch.as_tensor(codes)]
            self.assertTrue(torch.equal(chunked, full), (users, items, m, chunk))

    def test_large_mode_never_builds_all_pairs(self):
        model = CLEVDRLarge(1000, 1000, batch_size=4, embedding_k=2)
        self.assertIsNone(model.x_all)

    def test_int32_shuffle_parity_across_seeds(self):
        for seed in (0, 1, 2, 42, 2026):
            np.random.seed(seed)
            a64 = np.arange(5000, dtype=np.int64)
            np.random.shuffle(a64)
            np.random.seed(seed)
            a32 = np.arange(5000, dtype=np.int32)
            np.random.shuffle(a32)
            np.testing.assert_array_equal(a64, a32)

    def test_large_mode_pair_indices_dtype_is_int32(self):
        model = CLEVDRLarge(10, 10, batch_size=2, embedding_k=2)
        idxs = model._pair_indices()
        self.assertEqual(idxs.dtype, np.int32)
        self.assertEqual(len(idxs), 100)

    def test_large_mode_rejects_duplicate_pairs(self):
        model = CLEVDRLarge(3, 3, batch_size=2, embedding_k=2)
        with self.assertRaises(ValueError):
            model.fit(np.array([[0, 1], [0, 1]]), np.array([1., 0.]), num_epoch=1)


class CLEVDataTests(unittest.TestCase):
    def test_binarize_is_greater_or_equal_threshold(self):
        np.testing.assert_array_equal(binarize(np.array([1., 2., 3., 5.])), [0, 0, 1, 1])
        np.testing.assert_array_equal(binarize(np.array([1.9, 2., 4.]), 2), [0, 1, 1])

    def test_rating_matrix_to_samples_keeps_nonzero_cells(self):
        x, y = rating_mat_to_sample(np.array([[0, 4], [2, 0]]))
        np.testing.assert_array_equal(x, [[0, 1], [1, 0]])
        np.testing.assert_array_equal(y, [4, 2])

    def test_kuairand_maps_ids_jointly_and_keeps_one_row_per_pair(self):
        biased = pd.DataFrame({"user_id": [7, 7, 7, 9], "video_id": [3, 3, 5, 3], "is_click": [0, 1, 0, 1]})
        random_log = pd.DataFrame({"user_id": [9, 11, 11], "video_id": [8, 3, 3], "is_click": [0, 0, 1]})
        x_train, y_train, x_test, y_test, n_users, n_items = kuairand_frames_to_samples(biased, random_log)
        self.assertEqual((n_users, n_items), (3, 3))
        self.assertEqual(sorted(map(tuple, x_train.tolist())), [(0, 0), (0, 1), (1, 0)])
        self.assertEqual(dict(zip(map(tuple, x_train.tolist()), y_train.tolist()))[(0, 0)], 1.0)  # clicked once
        self.assertEqual(sorted(zip(map(tuple, x_test.tolist()), y_test.tolist())), [((1, 2), 0.0), ((2, 0), 1.0)])


class CLEVMetricTests(unittest.TestCase):
    def setUp(self):
        self.model = _Fixed(np.array([[.9, .1, .5], [.2, .8, .3]]))
        self.x = np.array([[0, 0], [0, 1], [0, 2], [1, 0], [1, 1], [1, 2]])
        self.y = np.array([0., 1., 1., 0., 0., 0.])

    def test_ndcg_counts_users_without_positives_as_one(self):
        # user 0 ranks items 0, 2, 1: hits at positions 2 and 3; user 1 has no positive -> 1.
        dcg = 1 / np.log2(3) + 1 / np.log2(4)
        idcg = 1 / np.log2(2) + 1 / np.log2(3)
        self.assertAlmostEqual(ndcg_at_k(self.model, self.x, self.y, 3), np.mean([dcg / idcg, 1.0]))

    def test_recall_divides_by_max_one_positive_count(self):
        self.assertAlmostEqual(recall_at_k(self.model, self.x, self.y, 2), np.mean([1 / 2, 0.0]))

    def test_auc_matches_pairwise_definition_with_ties(self):
        labels, scores = np.array([1, 0, 1, 0, 0]), np.array([.9, .9, .3, .1, .3])
        pairs = [(1.0 if p > n else .5 if p == n else 0.0) for p in scores[labels == 1] for n in scores[labels == 0]]
        self.assertAlmostEqual(roc_auc(labels, scores), np.mean(pairs))

    def test_precision_divides_by_k(self):
        self.assertAlmostEqual(precision_at_k(self.model, self.x, self.y, 2), np.mean([1 / 2, 0.0]))


class CLEVSharedIPSTests(unittest.TestCase):
    def test_one_ips_per_seed_gives_the_same_runs_as_separate_runs(self):
        rng = np.random.default_rng(2)
        x = np.array(sorted({(int(u), int(i)) for u, i in zip(rng.integers(0, 20, 40), rng.integers(0, 15, 40))}))
        y = rng.integers(0, 2, len(x)).astype(np.float32)
        data = (x, y, x[:12], y[:12], 20, 15)
        overrides = dict(emb_dim=4, batch_size=4, monte_sample_num=4, batch_size_prop=8, k=3)
        shared = run_seed("coat", (.3, .7), seed=1, data=data, num_epoch=2, overrides=overrides)
        config = dict(CLEV_CONFIG["coat"], **overrides)
        for result, alpha in zip(shared, (.3, .7)):  # the author scripts: one fresh process per alpha
            setup_seed(1)
            setup_seed(1)
            model = CLEVDR(20, 15, batch_size=4, embedding_k=4, batch_size_prop=8, monte_sample_num=4)
            model.compute_ips(x, num_epoch=2, lr=config["lr_prop"], lamb=config["weight_decay_prop"], tol=config["tol_prop"])
            model.fit(x, y, num_epoch=2, lr=config["lr"], lamb=config["weight_decay"], tol=config["tol"], alpha=alpha,
                      G=config["G"])
            self.assertEqual(result["AUC"], evaluate(model, x[:12], y[:12], 3)["AUC"])
            self.assertEqual(result["NDCG@3"], evaluate(model, x[:12], y[:12], 3)["NDCG@3"])


class CLEVConfigTests(unittest.TestCase):
    def test_author_script_hyperparameters(self):
        self.assertEqual({k: CLEV_CONFIG["yahoo"][k] for k in ("emb_dim", "lr", "weight_decay", "batch_size",
                                                                "monte_sample_num", "G", "batch_size_prop")},
                         dict(emb_dim=64, lr=.05, weight_decay=1e-5, batch_size=8192, monte_sample_num=44, G=4,
                              batch_size_prop=204800))
        self.assertEqual(ALPHA_SWEEP, {"coat": (.4, .6, .8), "yahoo": (.4, .6, .8), "kuairand": (.2, .4, .6, .8)})
        self.assertTrue(CLEV_CONFIG["kuairand"]["large"])


if __name__ == "__main__":
    unittest.main()
