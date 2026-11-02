"""LCDR objective, gradient routing and pipeline wiring."""
import contextlib
import io
import tempfile
import unittest

import numpy as np
import torch

from src.models.lcdr.lcvae import LatentConstrainedVAE, lcvae_loss, train_lcdr_representations
from src.models.lcdr.train_lcdr import LCDR_CONFIG, PAPER_LAMBDA, fit_lcdr_pipeline
from src.utils.artifacts import evaluate_checkpoint


def ranking_data(n_users=12, n_items=6, seed=0):
    rng = np.random.default_rng(seed)
    pairs = [(u, i) for u in range(n_users) for i in range(n_items) if rng.random() < .5]
    u, i = (np.array(column) for column in zip(*pairs))
    return dict(n_users=n_users, n_items=n_items, train_u=u, train_i=i,
                train_y=rng.integers(0, 2, len(u)).astype(np.float32),
                val_candidates={0: [1, 2, 3], 1: [0, 4]}, val_ground_truth={0: {2}, 1: {4}},
                test_candidates={2: [0, 5], 3: [1, 2]}, test_ground_truth={2: {5}, 3: {1}},
                evaluation_include_zero_positive_users=False)


class LCDRObjectiveTests(unittest.TestCase):
    def test_constraint_is_mean_non_squared_l2_norm(self):
        a = torch.zeros(2, 3)
        z_lc, z = torch.tensor([[3., 4.], [0., 0.]]), torch.zeros(2, 2)
        zero = torch.zeros(2, 2)
        loss, constraint = lcvae_loss(a, torch.full((2, 3), -50.), zero, zero, z_lc, z, constraint_weight=.5)
        self.assertAlmostEqual(float(constraint), 2.5, places=6)
        self.assertAlmostEqual(float(loss), .5 * 2.5, places=4)

    def test_kl_matches_standard_normal_prior(self):
        mean, log_var = torch.tensor([[1., -2.]]), torch.tensor([[.5, -1.]])
        loss, _ = lcvae_loss(torch.zeros(1, 1), torch.full((1, 1), -50.), mean, log_var,
                             torch.zeros(1, 2), torch.zeros(1, 2), constraint_weight=0.)
        expected = -.5 * torch.sum(1 + log_var - mean ** 2 - log_var.exp())
        self.assertAlmostEqual(float(loss), float(expected), places=4)

    def test_paper_lambda_and_idcf_sizes(self):
        self.assertEqual(PAPER_LAMBDA, {"coat": .9, "yahoo": .1, "kuairand": .9})
        for dataset, config in LCDR_CONFIG.items():
            self.assertEqual(config["representation"]["constraint_weight"], PAPER_LAMBDA[dataset])

    def test_encoder_sees_exposure_only(self):
        model = LatentConstrainedVAE(n_items=5, latent_dim=2, hidden_dim=4, n_layers=2)
        a_hat, mean, _, z = model(torch.zeros(3, 5))
        self.assertEqual((tuple(a_hat.shape), tuple(mean.shape), tuple(z.shape)), ((3, 5), (3, 2), (3, 2)))


class LCDRTrainingTests(unittest.TestCase):
    def test_representations_cover_every_user(self):
        rng = np.random.default_rng(0)
        a = (rng.random((20, 8)) < .3).astype(np.float32)
        w = np.eye(4, dtype=np.float32)[rng.integers(0, 4, 20)]
        mean, std, info = train_lcdr_representations(a, w, constraint_weight=.9, latent_dim=3, hidden_dim=8,
                                                     epochs=4, patience=4, batch_size=8)
        self.assertEqual(tuple(mean.shape), (20, 3))
        self.assertTrue(torch.all(std > 0))
        self.assertEqual(info["config"]["z_gradient"], "detached")
        self.assertEqual(set(info["best_val_parts"]), {"ivae", "lcvae", "constraint"})

    def test_pipeline_saves_reloadable_lcdr_checkpoint(self):
        data = ranking_data()
        from src.models.idcf import train_idcf as idcf_module
        rng = np.random.default_rng(1)
        original = idcf_module.DATASET_INPUTS["coat"]
        idcf_module.DATASET_INPUTS["coat"] = lambda d: {
            "exposure": (rng.random((d["n_users"], d["n_items"])) < .5).astype(np.float32),
            "proxy": np.eye(3, dtype=np.float32)[np.arange(d["n_users"]) % 3]}
        try:
            with tempfile.TemporaryDirectory() as folder, contextlib.redirect_stdout(io.StringIO()):
                result = fit_lcdr_pipeline(data, "coat", seed=1, checkpoint_dir=folder, epochs=2,
                                           representation_epochs=2, evaluate_test=True,
                                           representation_overrides=dict(latent_dim=2, hidden_dim=4, batch_size=4),
                                           train_overrides=dict(embedding_dim=4, batch_size=8))
                self.assertEqual(result["metadata"]["model"], "lcdr")
                self.assertEqual(result["metadata"]["config"]["variant"], "lcdr")
                reloaded = evaluate_checkpoint(result["checkpoint_path"], data)
                self.assertEqual(reloaded["NDCG@5"], result["NDCG@5"])
        finally:
            idcf_module.DATASET_INPUTS["coat"] = original


if __name__ == "__main__":
    unittest.main()
