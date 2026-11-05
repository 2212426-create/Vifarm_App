"""NCF (GMF, MLP, NeuMF) behaviour checked against the author's Keras code (He et al., WWW 2017)."""
import contextlib
import io
import tempfile
import unittest

import numpy as np
import torch

from src.models.ncf.ncf_model import NCF
from src.models.ncf.train_ncf import NCF_CONFIG, sample_training_instances, train_ncf
from src.utils.artifacts import evaluate_checkpoint


def ranking_data(n_users=12, n_items=8, seed=0):
    rng = np.random.default_rng(seed)
    pairs = [(u, i) for u in range(n_users) for i in range(n_items) if rng.random() < .5]
    u, i = (np.array(column) for column in zip(*pairs))
    y = rng.integers(0, 2, len(u)).astype(np.float32)
    y[:n_users] = 1.0
    return dict(n_users=n_users, n_items=n_items, train_u=u, train_i=i, train_y=y,
                val_candidates={0: [1, 2, 3], 1: [0, 4]}, val_ground_truth={0: {2}, 1: {4}},
                test_candidates={2: [0, 5], 3: [1, 2]}, test_ground_truth={2: {5}, 3: {1}},
                evaluation_include_zero_positive_users=False)


class NCFArchitectureTests(unittest.TestCase):
    def test_author_defaults(self):
        # NeuMF.py parse_args: num_factors 8, layers [64,32,16,8], num_neg 4, lr .001, batch 256, Adam, 100 epochs.
        for config in NCF_CONFIG.values():
            self.assertEqual((config["embedding_dim"], tuple(config["layers"]), config["num_negatives"],
                              config["lr"], config["batch_size"], config["optimizer"], config["epochs"]),
                             (8, (64, 32, 16, 8), 4, 1e-3, 256, "adam", 100))

    def test_mlp_tower_follows_layers_argument(self):
        model = NCF(10, 6, variant="mlp", embedding_dim=8, layers=(64, 32, 16, 8))
        self.assertEqual(model.mlp_user.embedding_dim, 32)
        self.assertEqual([layer.out_features for layer in model.mlp_layers], [32, 16, 8])
        self.assertEqual(model.prediction.in_features, 8)

    def test_prediction_input_per_variant(self):
        sizes = {variant: NCF(5, 4, variant=variant, embedding_dim=8, layers=(64, 32, 16, 8)).prediction.in_features
                 for variant in ("gmf", "mlp", "neumf")}
        self.assertEqual(sizes, {"gmf": 8, "mlp": 8, "neumf": 16})

    def test_initialisation_matches_author_code(self):
        torch.manual_seed(0)
        model = NCF(4000, 3000, variant="neumf", embedding_dim=8, layers=(64, 32, 16, 8))
        self.assertAlmostEqual(float(model.gmf_user.weight.detach().std()), .01, places=3)
        self.assertAlmostEqual(float(model.mlp_item.weight.detach().std()), .01, places=3)
        bound = np.sqrt(3 / model.prediction.in_features)  # Keras lecun_uniform
        self.assertLessEqual(float(model.prediction.weight.detach().abs().max()), bound)
        self.assertEqual(float(model.prediction.bias.detach().abs().sum()), 0.0)
        self.assertTrue(all(float(layer.bias.detach().abs().sum()) == 0.0 for layer in model.mlp_layers))

    def test_predict_matches_forward(self):
        model = NCF(5, 7, variant="neumf", embedding_dim=4, layers=(8, 4))
        items = np.array([0, 3, 6])
        expected = model(torch.full((3,), 2), torch.as_tensor(items)).detach().numpy()
        np.testing.assert_allclose(model.predict(2, items), expected, rtol=1e-6)

    def test_pretrained_neumf_averages_gmf_and_mlp(self):
        # load_pretrain_model: prediction = [0.5 h_gmf, 0.5 h_mlp], bias 0.5 (b_gmf + b_mlp).
        torch.manual_seed(1)
        gmf = NCF(6, 5, variant="gmf", embedding_dim=4, layers=(8, 4))
        mlp = NCF(6, 5, variant="mlp", embedding_dim=4, layers=(8, 4))
        for module in (gmf.prediction, mlp.prediction):
            torch.nn.init.normal_(module.bias)
        neumf = NCF(6, 5, variant="neumf", embedding_dim=4, layers=(8, 4))
        neumf.load_pretrained(gmf, mlp, alpha=.5)
        u, i = torch.tensor([0, 3, 5]), torch.tensor([4, 1, 0])
        expected = .5 * gmf(u, i) + .5 * mlp(u, i)
        torch.testing.assert_close(neumf(u, i), expected)


class NCFSamplingTests(unittest.TestCase):
    def test_four_negatives_per_positive_never_hit_positives(self):
        rng = np.random.default_rng(3)
        pos_u = np.array([0, 0, 1, 2, 2, 2])
        pos_i = np.array([0, 1, 2, 0, 3, 4])
        users, items, labels = sample_training_instances(pos_u, pos_i, n_items=6, num_negatives=4, rng=rng)
        self.assertEqual(len(labels), len(pos_u) * 5)
        self.assertEqual(int(labels.sum()), len(pos_u))
        positives = set(zip(pos_u.tolist(), pos_i.tolist()))
        negatives = set(zip(users[labels == 0].tolist(), items[labels == 0].tolist()))
        self.assertFalse(positives & negatives)
        np.testing.assert_array_equal(np.bincount(users[labels == 0], minlength=3), [8, 4, 12])

    def test_user_with_every_item_positive_is_rejected(self):
        with self.assertRaises(ValueError):
            sample_training_instances(np.array([0, 0]), np.array([0, 1]), n_items=2, num_negatives=1,
                                      rng=np.random.default_rng(0))


class NCFTrainingTests(unittest.TestCase):
    def run_variant(self, folder, variant, **kwargs):
        with contextlib.redirect_stdout(io.StringIO()):
            return train_ncf(ranking_data(), "coat", variant=variant, seed=1, checkpoint_dir=folder,
                             checkpoint_tag=variant, epochs=2, embedding_dim=4, layers=(8, 4), batch_size=16,
                             **kwargs)

    def test_checkpoint_reloads_with_identical_test_scores(self):
        with tempfile.TemporaryDirectory() as folder:
            result = self.run_variant(folder, "neumf")
            reloaded = evaluate_checkpoint(result["checkpoint_path"], ranking_data())
            self.assertEqual(result["metadata"]["model"], "ncf")
            self.assertEqual(result["metadata"]["config"]["variant"], "neumf")
            self.assertIn(result["best_epoch"], (0, 1, 2))
            self.assertAlmostEqual(result["NDCG@5"], reloaded["NDCG@5"], places=12)

    def test_pretrained_neumf_records_its_sources(self):
        with tempfile.TemporaryDirectory() as folder:
            gmf, mlp = self.run_variant(folder, "gmf"), self.run_variant(folder, "mlp")
            result = self.run_variant(folder, "neumf", pretrain=(gmf["checkpoint_path"], mlp["checkpoint_path"]))
            config = result["metadata"]["config"]
            self.assertEqual(config["pretrain"]["alpha"], .5)
            self.assertEqual(config["pretrain"]["gmf"], gmf["checkpoint_path"])

    def test_pretrain_requires_neumf(self):
        with tempfile.TemporaryDirectory() as folder, self.assertRaises(ValueError):
            self.run_variant(folder, "gmf", pretrain=("a.pt", "b.pt"))


if __name__ == "__main__":
    unittest.main()
