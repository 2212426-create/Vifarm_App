"""MRDR-CAL (Hu et al., TKDE 2025): NeuMF propensity + Platt scaling (author code) + MRDR (Guo et al. code)."""
import unittest

import numpy as np
import pandas as pd
import torch
import torch.nn.functional as F

from src.models.mrdr_cal.data import build_kuairand, implicit_target, sample_unobserved
from src.models.mrdr_cal.metrics import dcg_at_k, project_topk, recall_at_k
from src.models.mrdr_cal.model import NeuMF, Platt
from src.models.mrdr_cal.train import MRDR_CAL_CONFIG, dr_loss, mrdr_imputation_loss


class MRDRCalModelTests(unittest.TestCase):
    def test_neumf_matches_author_layout(self):
        model = NeuMF(5, 4, 64, 64, [64, 32, 16], dropout=.2, output_logits=True)
        self.assertEqual(model.predict_layer.in_features, 64 + 16)
        self.assertEqual(tuple(model(torch.tensor([0, 4]), torch.tensor([1, 3])).shape), (2,))

    def test_platt_is_affine_on_logits(self):
        platt = Platt()
        self.assertAlmostEqual(float(platt.a), .6, places=6)  # utils/platt.py initial values
        self.assertEqual(float(platt.b), 0.0)
        logits = torch.tensor([-1.0, 0.5, 2.0])
        torch.testing.assert_close(platt(logits), .6 * logits)

    def test_platt_fit_reduces_nll(self):
        torch.manual_seed(0)
        logits = torch.randn(400) * 3
        labels = (torch.rand(400) < torch.sigmoid(logits / 3)).float()
        platt = Platt()
        before = float(F.binary_cross_entropy_with_logits(platt(logits), labels))
        platt.fit(logits, labels)
        self.assertLess(float(F.binary_cross_entropy_with_logits(platt(logits), labels)), before)


class MRDRLossTests(unittest.TestCase):
    def test_imputation_loss_weights_by_one_minus_p_over_p_squared(self):
        logits, y, p = torch.tensor([.3, -1.0]), torch.tensor([1.0, 0.0]), torch.tensor([.5, .25])
        ce = F.binary_cross_entropy_with_logits(logits, y, reduction="none")
        expected = torch.mean(ce / p * (1 - p) / p)
        torch.testing.assert_close(mrdr_imputation_loss(logits, y, p), expected)

    def test_dr_loss_is_imputed_error_plus_ipw_correction(self):
        pred, imp = torch.tensor([.2, -.4, 1.0]), torch.tensor([.0, .5, -.3])
        y, o, p = torch.tensor([1.0, 0.0, 0.0]), torch.tensor([1.0, 1.0, 0.0]), torch.tensor([.5, .8, 1.0])
        e = F.binary_cross_entropy_with_logits(pred, y, reduction="none")
        e_il = F.binary_cross_entropy_with_logits(pred, torch.sigmoid(imp), reduction="none")
        torch.testing.assert_close(dr_loss(pred, imp, y, o, p), torch.mean((e - e_il) * o / p + e_il))

    def test_dr_loss_does_not_train_the_imputation_model(self):
        pred, imp = torch.zeros(2, requires_grad=True), torch.zeros(2, requires_grad=True)
        dr_loss(pred, imp, torch.ones(2), torch.ones(2), torch.ones(2)).backward()
        self.assertIsNone(imp.grad)


class MRDRDataTests(unittest.TestCase):
    def test_implicit_target_is_rating_above_three(self):
        np.testing.assert_array_equal(implicit_target(np.array([1., 3., 4., 5.])), [0, 0, 1, 1])

    def test_sampled_negatives_are_unobserved(self):
        rng = np.random.default_rng(0)
        users, items = sample_unobserved(np.array([0, 0, 1]), np.array([0, 1, 1]), 2, 3, 3, rng)
        observed = {(0, 0), (0, 1), (1, 1)}
        self.assertEqual(len(users), 3)
        self.assertFalse(observed & set(zip(users.tolist(), items.tolist())))

    def test_kuairand_builder_maps_ids_jointly_and_splits_random_log(self):
        biased = pd.DataFrame({"user_id": [7, 7, 9], "video_id": [3, 5, 3], "is_click": [1, 0, 1]})
        random_log = pd.DataFrame({"user_id": [9, 11, 7, 11], "video_id": [8, 3, 5, 5], "is_click": [0, 1, 1, 0]})
        data = build_kuairand(biased, random_log, val_fraction=.25, seed=0)
        self.assertEqual((data["num_users"], data["num_items"]), (3, 3))
        self.assertEqual(len(data["train"]["user"]), 3)
        self.assertEqual(len(data["val"]["user"]) + len(data["test"]["user"]), 4)
        self.assertEqual(len(data["val"]["user"]), 1)


class MRDRMetricTests(unittest.TestCase):
    def test_reshaped_dcg_and_count_recall_skip_users_without_positives(self):
        label = np.array([0, 1, 1, 0, 0, 0])  # 2 users x 3 items; user 1 has no positive
        score = np.array([.9, .8, .1, .5, .4, .3])
        dcg = dcg_at_k(label, score, 2, 3, ks=(2,))
        self.assertAlmostEqual(dcg[0], 1 / np.log2(3))
        self.assertAlmostEqual(recall_at_k(label, score, 2, 3, ks=(2,))[0], 1.0)  # hits, not a fraction

    def test_kuairand_recall_is_normalised_per_user(self):
        label = np.array([1, 1, 0, 0])
        score = np.array([.9, .1, .8, .2])
        users = np.array([0, 0, 0, 1])
        self.assertAlmostEqual(recall_at_k(label, score, 2, None, ks=(2,), user_ids=users)[0], .5)


class MRDRConfigTests(unittest.TestCase):
    def test_project_topk_matches_project_definitions(self):
        # user 0: positives ranked 1st and 3rd of 6, two positives; user 1: no positive (skipped)
        label = np.array([1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        score = np.array([.9, .8, .7, .1, .2, .3, .9, .8, .7, .6, .5, .4])
        out = project_topk(label, score, 2, 6, k=5)
        idcg = 1 + 1 / np.log2(3)
        self.assertAlmostEqual(out["NDCG@5"], (1 + 1 / np.log2(4)) / idcg)
        self.assertAlmostEqual(out["Recall@5"], 1.0)
        self.assertAlmostEqual(out["Recall@5_bounded"], 1.0)
        # seven positives, three in the top 5: recall 3/7, bounded 3/5
        label = np.array([1, 0, 1, 0, 1, 1, 1, 1, 1])
        score = np.arange(9)[::-1].astype(float)
        out = project_topk(label, score, 1, 9, k=5)
        self.assertAlmostEqual(out["Recall@5"], 3 / 7)
        self.assertAlmostEqual(out["Recall@5_bounded"], 3 / 5)

    def test_paper_appendix_backbone(self):
        for config in MRDR_CAL_CONFIG.values():
            self.assertEqual((config["embedding_size"], config["mlp_layers"], config["batch_size"], config["lr"],
                              config["dropout"]), (64, [64, 32, 16], 1024, 1e-3, .2))


if __name__ == "__main__":
    unittest.main()
