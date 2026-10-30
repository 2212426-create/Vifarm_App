"""Regression coverage for tuning dispatch, warm starts and causal training."""
import contextlib
import importlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import torch

from src.causal.cdr.sampling import CounterfactualSampler
from src.causal.idcf.ivae import ExposureIVAE, validation_elbo, train_exposure_ivae
from src.models.matrix_factorization import MatrixFactorization
from src.training.config import mf_config, cdr_config, tuning_grids
from src.utils.artifacts import make_metadata, save_checkpoint, load_checkpoint


def small_data():
    return dict(n_users=3, n_items=4, train_u=np.array([0, 0, 1, 2]),
                train_i=np.array([0, 1, 2, 0]), train_y=np.array([1, 0, 1, 0], dtype=np.float32),
                train_c=np.ones(4, dtype=np.float32),
                val_candidates={0: [2, 3]}, val_ground_truth={0: {2}},
                test_candidates={1: [0, 3]}, test_ground_truth={1: {3}})


class TuningConfigTests(unittest.TestCase):
    def test_legacy_grid_entrypoint_also_uses_current_mf_objective(self):
        from src.training import train_pipeline as workflow
        captured = []

        def trial(**kwargs):
            captured.append(kwargs)
            return {"validation": {"NDCG@5": kwargs["lr"], "Recall@5": 0.5},
                    "checkpoint": "selected.pt", "metadata": {}}

        with contextlib.redirect_stdout(io.StringIO()), \
                patch.object(workflow, "train_single_run", side_effect=trial), \
                patch("src.utils.artifacts.evaluate_checkpoint", return_value={"NDCG@5": 0.5}):
            workflow.run_grid_search(small_data(), lr_candidates=[0.001], weight_decay_candidates=[1e-6])
        self.assertEqual((captured[0]["loss_name"], captured[0]["decay_scope"],
                          captured[0]["scheduler_name"], captured[0]["train_global_bias"]),
                         ("mse", "all", "none", False))
        self.assertFalse(captured[0]["evaluate_test"])

    def test_grid_contains_current_baseline_and_dispatches_explicit_objective(self):
        for dataset, module in (("coat", "tune_coat_models"), ("kuairand", "tune_kuairand_models")):
            workflow = importlib.import_module("experiments.workflows." + module)
            data = small_data()
            base = mf_config(dataset)
            for key in ("epochs", "patience"):
                base.pop(key)
            self.assertEqual(tuning_grids(dataset)["mf"][0], base)
            with patch.object(workflow, "train_baseline_mf") as train:
                workflow.train_model("mf", base, 12, False, "regression", data_dict=data, patience=3)
            kwargs = train.call_args.kwargs
            self.assertEqual((kwargs["loss_name"], kwargs["decay_scope"], kwargs["scheduler_name"]),
                             ("mse", "all", "none"))
            self.assertIs(kwargs["data_dict"], data)
            self.assertEqual((kwargs["patience"], kwargs["evaluate_test"]), (3, False))

    def test_coat_cli_trains_cdr_independently_and_honors_patience(self):
        from experiments.workflows import tune_coat_models as workflow
        data, events = small_data(), []
        grids = {"cdr": [{"embedding_dim": 4, "lr": 0.001}, {"embedding_dim": 4, "lr": 0.002}]}

        def trial(**kwargs):
            events.append("trial")
            self.assertIs(kwargs["data_dict"], data)
            self.assertEqual((kwargs["patience"], kwargs["epochs"]), (13, 2))
            self.assertNotIn("initial_rec_checkpoint", kwargs)
            self.assertEqual(kwargs['selection'],'source_train_loss_last')
            self.assertEqual(kwargs['calibration_fraction'],.05)
            self.assertEqual(kwargs['un_thres'],10.)
            self.assertFalse(kwargs["evaluate_test"])
            return dict(best_val_ndcg=kwargs["lr"], best_epoch=1,
                        checkpoint_path="cdr.pt", metadata={})

        def evaluate(*args, **kwargs):
            self.assertEqual(events, ["trial", "trial"])
            return {"NDCG@5": 0.5, "Recall@5": 0.5}

        with tempfile.TemporaryDirectory() as root, contextlib.redirect_stdout(io.StringIO()), \
                patch.object(workflow, "RESULTS_DIR", root), patch.object(workflow, "GRIDS", grids), \
                patch.object(workflow, "load_coat_processed", return_value=data), \
                patch.object(workflow, "train_baseline_mf", return_value={
                    "checkpoint_path": "warm.pt", "best_val_ndcg": 0.6}) as warm, \
                patch.object(workflow, "train_released_cdr", side_effect=trial), \
                patch.object(workflow, "evaluate_checkpoint", side_effect=evaluate):
            workflow.main(["--model", "cdr", "--epochs", "2", "--patience", "13"])
            warm.assert_not_called()
            report = json.loads(next(Path(root).glob("*.json")).read_text(encoding="utf-8"))
            self.assertEqual(report["identity"]["patience"], {"cdr": 13})


class CDRCheckpointTests(unittest.TestCase):
    def test_degrading_fine_tune_retains_exact_epoch_zero_weights(self):
        trainer = importlib.import_module("src.causal.cdr.train_dr_bias_cdr")
        data = small_data()
        matrix = np.zeros((3, 4), dtype=np.float32)
        matrix[data["train_u"], data["train_i"]] = 1
        raw = dict(train_matrix=matrix, test_matrix=matrix, propensities=np.ones_like(matrix) * 0.5)
        model = MatrixFactorization(3, 4, embedding_dim=4, train_global_bias=False)
        metadata = make_metadata("mf", "coat", data, {"seed": 42},
                                 dict(num_users=3, num_items=4, embedding_dim=4, train_global_bias=False))
        score = lambda value: {"NDCG@5": value, "Recall@5": value, "HitRate@5": value}
        with tempfile.TemporaryDirectory() as root, contextlib.redirect_stdout(io.StringIO()):
            warm = str(Path(root) / "warm.pt")
            save_checkpoint(model, warm, metadata, 1, score(0.9))
            with patch.object(trainer, "load_coat_raw_features", return_value=raw), \
                    patch.object(trainer, "evaluate_unbiased_model", side_effect=[score(0.9), score(0.1)]), \
                    patch.object(trainer, "evaluate_checkpoint", side_effect=AssertionError("test accessed")):
                result = trainer.train_dr_bias_cdr("coat", data_dict=data, embedding_dim=4,
                    epochs=1, batch_size=4, initial_rec_checkpoint=warm,
                    training_profile="experimental", backbone="legacy_bias",
                    evaluate_test=False, checkpoint_dir=root)
            self.assertEqual((result["best_epoch"], result["selection_origin"]), (0, "warm_start"))
            checkpoint = load_checkpoint(result["checkpoint_path"])
            for key, tensor in model.state_dict().items():
                torch.testing.assert_close(checkpoint["model_state_dict"]["rec_model." + key], tensor)
            self.assertEqual(result["metadata"]["config"]["counterfactuals"], "all_catalog_pairs")


class CounterfactualSamplingTests(unittest.TestCase):
    def test_uniform_complement_excludes_all_observed_pairs_including_negatives(self):
        torch.manual_seed(42)
        sampler = CounterfactualSampler(2, 3, [0, 0, 1, 1], [0, 0, 0, 2], "unobserved")
        users, items = sampler.sample(1000)
        pairs = set(zip(users.tolist(), items.tolist()))
        self.assertEqual(pairs, {(0, 1), (0, 2), (1, 1)})
        self.assertEqual(sampler.size, 3)

    def test_dense_observation_with_one_missing_pair_and_empty_pool(self):
        sampler = CounterfactualSampler(2, 2, [0, 0, 1], [0, 1, 0], "unobserved")
        users, items = sampler.sample(20)
        self.assertEqual(set(zip(users.tolist(), items.tolist())), {(1, 1)})
        with self.assertRaisesRegex(ValueError, "empty"):
            CounterfactualSampler(1, 1, [0], [0], "unobserved")
        # Full-catalog sampling remains valid even when every pair was observed.
        users, items = CounterfactualSampler(1, 1, [0], [0], "all").sample(3)
        self.assertEqual((users.tolist(), items.tolist()), ([0] * 3, [0] * 3))


class CausalTrainingTests(unittest.TestCase):
    def test_pipeline_passes_stage_overrides_without_mutating_defaults(self):
        trainer = importlib.import_module("src.causal.idcf.train_idcf")
        mean, std = torch.zeros(3, 2), torch.ones(3, 2)
        data = small_data()
        defaults = dict(trainer.IDCF_CONFIG["coat"]["train"])
        with patch.dict(trainer.DATASET_INPUTS, {"coat": lambda data: {}}), \
                patch.object(trainer, "idcf_confounders", return_value=(mean, std, {"config": {}})) as stage1, \
                patch.object(trainer, "train_idcf", return_value={}) as stage2:
            trainer.fit_idcf_pipeline(data, "coat", epochs=3, ivae_epochs=2, device="cpu",
                train_overrides={"embedding_dim": 7, "lr": 0.003, "batch_size": 9},
                ivae_overrides={"latent_dim": 2, "batch_size": 4})
        self.assertEqual(stage1.call_args.kwargs["latent_dim"], 2)
        self.assertEqual(stage1.call_args.kwargs["batch_size"], 4)
        cfg = stage2.call_args.kwargs
        self.assertEqual((cfg["embedding_dim"], cfg["lr"], cfg["batch_size"], str(cfg["device"])),
                         (7, 0.003, 9, "cpu"))
        self.assertEqual(trainer.IDCF_CONFIG["coat"]["train"], defaults)

    def test_benchmark_forwards_overrides_to_causal_pipeline(self):
        from experiments.workflows import run_all_benchmarks as workflow
        with patch.object(workflow, "fit_idcf_pipeline", return_value={}) as fit:
            workflow.run_idcf_family("iDCF", "coat", small_data(), None, {}, "test", 2, 3,
                train_overrides={"embedding_dim": 7}, ivae_overrides={"latent_dim": 2}, device="cpu")
        self.assertEqual(fit.call_args.kwargs["train_overrides"], {"embedding_dim": 7})
        self.assertEqual(fit.call_args.kwargs["ivae_overrides"], {"latent_dim": 2})

    def test_validation_noise_is_repeatable_and_does_not_advance_training_rng(self):
        model = ExposureIVAE(4, 2, latent_dim=3, hidden_dim=4)
        x, w = torch.zeros(5, 4), torch.ones(5, 2)
        before = torch.random.get_rng_state().clone()
        first = validation_elbo(model, [(x, x, w)], samples=4)
        self.assertTrue(torch.equal(before, torch.random.get_rng_state()))
        torch.randn(100)
        second = validation_elbo(model, [(x, x, w)], samples=4)
        self.assertEqual(first, second)

    @unittest.skipUnless(torch.cuda.is_available(), "CUDA unavailable")
    def test_both_causal_stages_train_on_cuda_and_checkpoint_loads_on_cpu(self):
        from src.causal.idcf.train_idcf import train_idcf
        exposure = np.eye(3, 4, dtype=np.float32)
        mean, std, info = train_exposure_ivae(exposure, np.eye(3), latent_dim=2,
            hidden_dim=4, epochs=1, batch_size=2, validation_samples=2, device="cuda")
        self.assertEqual(mean.device.type, "cpu")
        self.assertEqual(info["config"]["device"], "cuda")
        with tempfile.TemporaryDirectory() as root:
            result = train_idcf(small_data(), mean, std, "coat", epochs=1,
                embedding_dim=4, batch_size=4, device="cuda", checkpoint_dir=root, evaluate_test=False)
            self.assertEqual(result["metadata"]["config"]["device"], "cuda")
            self.assertEqual(load_checkpoint(result["checkpoint_path"])["model_state_dict"]["c_mean"].device.type, "cpu")

    def test_author_initialization_includes_bias_and_is_recorded_in_checkpoint(self):
        from src.baselines.train_mf import train_baseline_mf
        model = MatrixFactorization(20, 30, embedding_dim=4, init_scheme="author_uniform")
        for weights in (model.user_embedding.weight, model.item_embedding.weight,
                        model.user_bias.weight, model.item_bias.weight):
            self.assertTrue((weights.abs() <= 0.01).all())
            self.assertGreater(weights.abs().sum().item(), 0)
        with tempfile.TemporaryDirectory() as root, contextlib.redirect_stdout(io.StringIO()):
            result = train_baseline_mf("coat", data_dict=small_data(), epochs=1,
                embedding_dim=4, init_scheme="author_uniform", checkpoint_dir=root, evaluate_test=False)
            self.assertEqual(result["metadata"]["model_kwargs"]["init_scheme"], "author_uniform")


if __name__ == "__main__":
    unittest.main()
