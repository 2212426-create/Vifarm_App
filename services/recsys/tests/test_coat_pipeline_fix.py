"""Regression checks for warm-up selection, propensity calibration and alternating CDR."""
import contextlib
import importlib
import io
import tempfile
import unittest
import json
from pathlib import Path
from unittest.mock import patch

import numpy as np
import torch

from src.causal.idcf.ivae import train_exposure_ivae
from src.causal.cdr.cdr_model import CDRFramework
from src.causal.cdr.propensity import naive_bayes_propensity, validation_labels
from test_review_fixes import small_data


class WarmupSelectionTests(unittest.TestCase):
    def test_early_low_elbo_does_not_stop_warmup_or_win_against_mature_checkpoint(self):
        # One update/epoch; 20% * 20 = four warm-up updates, full beta at epoch 5.
        values = iter([1., 2., 3., 4., 10., 9., 10., 11.])
        with patch("src.causal.idcf.ivae.validation_elbo", side_effect=lambda *a, **k: next(values)):
            _, _, info = train_exposure_ivae(np.eye(10, 4), np.ones((10, 2)),
                latent_dim=2, hidden_dim=4, epochs=20, patience=2, batch_size=16)
        self.assertEqual((info["first_full_beta_epoch"], info["best_epoch"], info["epochs_run"]), (5, 6, 8))
        self.assertEqual(info["best_val_loss"], 9.)
        self.assertEqual(info["selected_training_beta"], 1.)

    def test_short_budget_is_explicitly_reported_instead_of_claiming_convergence(self):
        _, _, info = train_exposure_ivae(np.eye(10, 4), np.ones((10, 2)),
            latent_dim=2, hidden_dim=4, epochs=1, patience=1, batch_size=16)
        self.assertEqual(info["selection"], "budget_before_full_beta")
        self.assertIsNone(info["first_full_beta_epoch"])


class PropensityCalibrationTests(unittest.TestCase):
    def test_bayes_rule_uses_population_density_and_calibration_class_frequencies(self):
        inverse, info = naive_bayes_propensity([1, 1, 0, 0], [1, 0, 0, 0], .1)
        np.testing.assert_allclose(inverse, [5, 5, 15, 15])
        np.testing.assert_allclose(info["class_propensity"], [1/15, 1/5])

    def test_calibration_never_reads_test_and_includes_zero_positive_validation_users(self):
        class GuardedData(dict):
            def __getitem__(self, key):
                if key.startswith("test"):
                    raise AssertionError("Held-out labels accessed")
                return super().__getitem__(key)
        data = GuardedData(val_candidates={0: [0, 1], 1: [2, 3]}, val_ground_truth={0: {1}, 1: set()})
        inverse, info = naive_bayes_propensity([1, 0], validation_labels(data), .1)
        np.testing.assert_allclose(inverse, [5, 15])
        self.assertEqual(info["calibration_rows"], 4)

    def test_invalid_calibration_is_rejected_without_silent_fallback_or_clipping(self):
        for calibration, rho in (([0, 0], .1), ([.5, 1], .1), ([0, 1, 0, 0], .9)):
            with self.subTest(calibration=calibration, rho=rho), self.assertRaises(ValueError):
                naive_bayes_propensity([0, 1], calibration, rho)


class AlternatingCDRTests(unittest.TestCase):
    def test_imputation_step_observes_updated_rec_and_has_no_gradient_into_it(self):
        trainer = importlib.import_module("src.causal.cdr.train_dr_bias_cdr")
        rec_loss = CDRFramework.compute_recommendation_loss
        imp_loss = CDRFramework.compute_imputation_loss
        before, called = [], []

        def recommendation(model, *args, **kwargs):
            before.append(model.rec_model.user_embedding.weight.detach().clone())
            return rec_loss(model, *args, **kwargs)

        def imputation(model, *args, **kwargs):
            self.assertFalse(torch.equal(before[-1], model.rec_model.user_embedding.weight))
            called.append(True)
            model.rec_model.zero_grad(set_to_none=True)
            loss = imp_loss(model, *args, **kwargs)
            # Only the imputation graph should be attached to this objective.
            rec_grads = torch.autograd.grad(loss, tuple(model.rec_model.parameters()),
                                            allow_unused=True, retain_graph=True)
            self.assertTrue(all(gradient is None for gradient in rec_grads))
            return loss

        with tempfile.TemporaryDirectory() as folder, contextlib.redirect_stdout(io.StringIO()), \
                patch.object(CDRFramework, "compute_recommendation_loss", recommendation), \
                patch.object(CDRFramework, "compute_imputation_loss", imputation), \
                patch.object(trainer, "evaluate_checkpoint", side_effect=AssertionError("Test evaluated")):
            result = trainer.train_dr_bias_cdr("coat", data_dict=small_data(), epochs=1,
                batch_size=4, checkpoint_dir=folder, evaluate_test=False, device="cpu")
        self.assertEqual(len(called), 1)
        self.assertFalse(result["metadata"]["config"]["propensity_calibration"]["test_labels_used"])


class BenchmarkArtifactTests(unittest.TestCase):
    def test_repeated_run_preserves_reports_and_uses_separate_checkpoints(self):
        from experiments.workflows import run_all_benchmarks as workflow
        data = small_data()
        data["split_info"] = {}
        metrics = {"NDCG@5": .5, "Recall@5": .5, "NDCG@5_CI95_halfwidth": .01}
        with tempfile.TemporaryDirectory() as folder, contextlib.redirect_stdout(io.StringIO()), \
                patch.object(workflow, "RESULTS_DIR", folder), \
                patch.object(workflow, "load_coat_processed", return_value=data), \
                patch.object(workflow, "train_baseline_mf", return_value=metrics) as train, \
                patch.object(workflow, "paired_significance", return_value={}):
            workflow.run_all_benchmarks(dataset_filter="coat", model_filter="mf", quick_run=True)
            first = next(Path(folder).glob("*.json"))
            original = first.read_bytes()
            workflow.run_all_benchmarks(dataset_filter="coat", model_filter="mf", quick_run=True)
            self.assertEqual(first.read_bytes(), original)
            reports = list(Path(folder).glob("*.json"))
            self.assertEqual(len(reports), 2)
            self.assertEqual(len({json.loads(p.read_text("utf-8"))["protocol"]["run_id"] for p in reports}), 2)
            self.assertNotEqual(train.call_args_list[0].kwargs["checkpoint_dir"],
                                train.call_args_list[1].kwargs["checkpoint_dir"])


if __name__ == "__main__":
    unittest.main()
