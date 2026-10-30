"""Finite-population, gradient and checkpoint checks for CDR Eq. (7)."""
import contextlib
import importlib
import io
import itertools
import tempfile
import unittest

import numpy as np
import torch
import torch.nn.functional as F

from src.causal.cdr.cdr_model import CDRFramework
from src.causal.cdr.dr_bias_loss import (PAPER_OBJECTIVE_REVISION, cdr_recommendation_loss,
                                        dr_bias_closed_form_imputation_loss, imputed_bce, imputation_keep)
from src.causal.cdr.observations import aggregate_observed_pairs
from src.utils.artifacts import evaluate_checkpoint, load_checkpoint


def loss_on_population(errors, imputed, observed, propensities, pool="all", **kwargs):
    errors, imputed = torch.as_tensor(errors), torch.as_tensor(imputed)
    observed = torch.as_tensor(observed, dtype=torch.long)
    direct = list(range(len(errors))) if pool == "all" else [i for i in range(len(errors)) if i not in observed.tolist()]
    return cdr_recommendation_loss(
        pred_obs=(-errors[observed]).exp(), y_obs=torch.ones(len(observed)),
        inv_prop_obs=1 / torch.as_tensor(propensities)[observed],
        imp_loss_obs=imputed[observed], imp_unc_obs=torch.zeros(len(observed)),
        pred_unobs=torch.ones(len(direct)) * 0.5, imp_loss_unobs=imputed[direct],
        imp_unc_unobs=torch.zeros(len(direct)), observed_fraction=len(observed) / len(errors),
        counterfactual_pool=pool, un_thres=1.0, **kwargs)[0]


class PaperEstimatorTests(unittest.TestCase):
    def test_perfect_imputation_recovers_population_risk_with_wrong_propensities(self):
        errors = torch.tensor([0.2, 0.8, 0.3, 0.7])
        # Diagnostic that failed under the historical author estimator (1.15).
        loss = loss_on_population(errors, errors, [0, 1], [.5, .25, .9, .9])
        torch.testing.assert_close(loss, errors.mean())

    def test_correct_propensity_recovers_risk_in_expectation_with_wrong_imputation(self):
        errors = torch.tensor([0.2, 0.7, 1.2])
        imputed = torch.tensor([0.9, 0.1, 0.5])
        propensity = [1.0, 0.2, 0.7]  # One pair is always observed: no empty observed sets.
        expected = 0.0
        for mask in itertools.product((False, True), repeat=2):
            observed = [0] + [i + 1 for i, included in enumerate(mask) if included]
            probability = np.prod([propensity[i+1] if included else 1-propensity[i+1]
                                   for i, included in enumerate(mask)])
            expected += probability * loss_on_population(errors, imputed, observed, propensity)
        torch.testing.assert_close(expected, errors.mean())

    def test_full_and_complement_estimators_agree_on_exact_populations(self):
        args = ([.2, .7, 1.2, .4], [.9, .1, .5, .3], [0, 2], [.5, .8, .3, .1])
        torch.testing.assert_close(loss_on_population(*args), loss_on_population(*args, pool="unobserved"))

    def test_batch_ratio_changes_neither_loss_nor_gradient(self):
        imputed = torch.tensor([.2, .6, .3, .9], requires_grad=True)
        base = loss_on_population([.4, .3, .5, .7], imputed, [0, 1], [.3, .7, 1, 1])
        base_grad = torch.autograd.grad(base, imputed)[0]
        repeated = cdr_recommendation_loss(
            pred_obs=torch.exp(-torch.tensor([.4, .3])).repeat(3), y_obs=torch.ones(6),
            inv_prop_obs=torch.tensor([1/.3, 1/.7]).repeat(3),
            imp_loss_obs=imputed[:2].repeat(3), imp_unc_obs=torch.zeros(6),
            pred_unobs=torch.ones(20)*.5, imp_loss_unobs=imputed.repeat(5),
            imp_unc_unobs=torch.zeros(20), observed_fraction=.5, un_thres=1.0)[0]
        torch.testing.assert_close(base, repeated)
        torch.testing.assert_close(base_grad, torch.autograd.grad(repeated, imputed)[0])

    def test_filtering_everything_yields_population_normalized_ips(self):
        e, w = torch.tensor([.2, .8]), torch.tensor([2., 4.])
        result, fraction = cdr_recommendation_loss(
            pred_obs=(-e).exp(), y_obs=torch.ones(2), inv_prop_obs=w,
            imp_loss_obs=torch.ones(2), imp_unc_obs=torch.zeros(2),
            pred_unobs=torch.ones(7)*.5, imp_loss_unobs=torch.ones(7), imp_unc_unobs=torch.zeros(7),
            observed_fraction=.08, un_thres=0)
        torch.testing.assert_close(result, .08 * (e*w).mean())
        self.assertEqual(fraction, 1.0)

    def test_requires_population_density_and_rejects_legacy_scaling(self):
        args = dict(pred_obs=torch.tensor([.5]), y_obs=torch.ones(1), inv_prop_obs=torch.ones(1),
            imp_loss_obs=torch.ones(1), imp_unc_obs=torch.zeros(1), pred_unobs=torch.tensor([.5]),
            imp_loss_unobs=torch.ones(1), imp_unc_unobs=torch.zeros(1))
        for rho in (None, 0, 1.1, float("nan")):
            with self.assertRaises(ValueError):
                cdr_recommendation_loss(**args, observed_fraction=rho)
        with self.assertRaises(ValueError):
            cdr_recommendation_loss(**args, observed_fraction=.5, counterfactual_scale=3.125)


class ImputedErrorTests(unittest.TestCase):
    def test_training_imputation_fits_the_error_used_for_recommendation(self):
        logits = torch.tensor([np.log(4.)], dtype=torch.float32)  # p=0.8; true label=1.
        pseudo = torch.tensor([.6], requires_grad=True)
        error = F.binary_cross_entropy_with_logits(logits, torch.ones(1), reduction="none")
        loss = dr_bias_closed_form_imputation_loss(error, imputed_bce(logits, pseudo), torch.tensor([2.]))
        loss.backward()
        self.assertLess(pseudo.grad.item(), 0)  # Gradient descent increases q toward the true label.
        torch.testing.assert_close(imputed_bce(logits, torch.ones(1)), error)

    def test_extreme_logits_keep_loss_and_both_gradients_finite(self):
        logits = torch.tensor([-1000., 1000.], requires_grad=True)
        targets = torch.tensor([.2, .8], requires_grad=True)
        loss = imputed_bce(logits, targets).mean()
        loss.backward()
        self.assertTrue(torch.isfinite(loss))
        self.assertTrue(torch.isfinite(logits.grad).all())
        self.assertTrue(torch.isfinite(targets.grad).all())

    def test_cv_filter_compares_std_to_mean_and_zero_variance_is_zero_cv(self):
        kept = imputation_keep(torch.tensor([.2, 1., 1.]), torch.tensor([.04, .01, 0.]), .5)
        torch.testing.assert_close(kept, torch.tensor([0., 1., 1.]))


class PaperTrainingTests(unittest.TestCase):
    def test_pair_aggregation_retains_negatives_and_averages_repeated_labels(self):
        u, i, y = aggregate_observed_pairs([0, 0, 0, 1], [1, 1, 2, 0], [1, 0, 0, 1], 3)
        np.testing.assert_array_equal(u, [0, 0, 1])
        np.testing.assert_array_equal(i, [1, 2, 0])
        np.testing.assert_array_equal(y, [.5, 0, 1])

    def test_trainer_records_density_filter_counts_revision_and_reloads_checkpoint(self):
        trainer = importlib.import_module("src.causal.cdr.train_dr_bias_cdr")
        data = dict(n_users=3, n_items=4, train_u=np.array([0, 0, 0, 1, 2]),
            train_i=np.array([0, 0, 1, 2, 0]), train_y=np.array([1, 0, 0, 1, 0], dtype=np.float32),
            train_item_exposure_counts=np.array([3, 1, 1, 0]),
            val_candidates={0: [2, 3]}, val_ground_truth={0: {2}},
            test_candidates={1: [0, 3]}, test_ground_truth={1: {3}})
        with tempfile.TemporaryDirectory() as root, contextlib.redirect_stdout(io.StringIO()):
            result = trainer.train_dr_bias_cdr("kuairand", data_dict=data, embedding_dim=4,
                epochs=1, batch_size=3, checkpoint_dir=root, evaluate_test=False, device="cpu")
            cfg = result["metadata"]["config"]
            self.assertEqual(cfg["objective_revision"], PAPER_OBJECTIVE_REVISION)
            self.assertEqual((cfg["observed_pairs"], cfg["raw_training_rows"], cfg["observed_fraction"]), (4, 5, 1/3))
            history = result["training_history"][0]
            self.assertEqual((history["observed_count"], history["direct_count"]), (4, 4))
            evaluated = evaluate_checkpoint(result["checkpoint_path"], data)
            self.assertEqual(evaluated["objective_revision"], PAPER_OBJECTIVE_REVISION)
            self.assertEqual(evaluated["cdr_training"], result["cdr_training"])
            # Old checkpoints remain inference-compatible, explicitly marked as legacy.
            state = load_checkpoint(result["checkpoint_path"])
            del state["metadata"]["config"]["objective_revision"]
            for key in ("filter_mode", "ips_weighting"):
                del state["metadata"]["model_kwargs"][key]
            torch.save(state, result["checkpoint_path"])
            legacy = evaluate_checkpoint(result["checkpoint_path"], data)
            self.assertEqual(legacy["objective_revision"], "legacy_unversioned")
            self.assertEqual(legacy["NDCG@5"], evaluated["NDCG@5"])


if __name__ == "__main__":
    unittest.main()
