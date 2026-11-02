"""Unified data, metrics, training and experiment regression suite."""
import os
import tempfile
import unittest
from unittest.mock import patch
import numpy as np
import pandas as pd
import torch
from src.data_pipeline.kuairand_dataset import (compute_click_scores, load_kuairand_processed,
                                                load_kuairand_tab_instruments)
from src.data_pipeline.coat_dataset import load_coat_processed, load_coat_raw_features
from src.evaluation.evaluator import evaluate_unbiased_model
from src.training.train_pipeline import train_single_run
from src.baselines.train_mf import train_baseline_mf
import copy
from pathlib import Path
import torch.nn.functional as F
from src.causal.cdr.cdr_model import CDRFramework
from src.causal.cdr.dr_bias_loss import cdr_recommendation_loss
from src.evaluation.diagnostics import candidate_pool_diagnostics
from src.evaluation.vectorized_evaluator import GPUVectorizedEvaluator
from src.utils.artifacts import data_signature, digest, load_checkpoint, evaluate_checkpoint
from experiments.workflows.run_all_benchmarks import run_all_benchmarks
from src.models.matrix_factorization import MatrixFactorization
from src.utils.artifacts import load_checkpoint
from src.utils.helpers import set_seed
from experiments.workflows import compare_mf_optimizers as comparison
from src.evaluation.protocol import protocol_metadata, summarize_seeds, validate_paper_split
from experiments import run as entrypoint


class FixedScores:
    def eval(self):
        return self

    def get_evaluation_factors(self):
        return np.ones((3, 1), dtype=np.float32), np.array([[2.0], [1.0], [0.0]], dtype=np.float32)


class BenchmarkProtocolTests(unittest.TestCase):
    def test_coat_paper_split_keeps_random_users_disjoint(self):
        data = load_coat_processed()
        raw = load_coat_raw_features()
        self.assertEqual(len(data["train_y"]), 6960)
        self.assertEqual(data["split_info"]["validation_users"], 87)
        self.assertEqual(data["split_info"]["test_users"], 203)
        self.assertEqual(data["split_info"]["validation_rows"], 1392)
        self.assertEqual(data["split_info"]["test_rows"], 3248)
        self.assertEqual(data["split_info"]["train_random_overlap_pairs"], 366)
        self.assertEqual(data["split_info"]["test_overlap_pairs"], 247)
        expected_test_users = set(np.random.RandomState(1234).choice(np.arange(290), 203, replace=False))
        self.assertEqual(set(data["test_candidates"]), expected_test_users)
        self.assertFalse(set(data["val_candidates"]) & set(data["test_candidates"]))
        self.assertFalse(data["evaluation_include_zero_positive_users"])
        for split in ("val", "test"):
            for user, items in data[f"{split}_candidates"].items():
                expected = set(items[raw["test_matrix"][user, items] >= 4])
                self.assertEqual(data[f"{split}_ground_truth"][user], expected)

    def test_click_label_is_required_and_binary(self):
        with self.assertRaisesRegex(ValueError, "is_click"):
            compute_click_scores(pd.DataFrame({"other_signal": [1]}))
        with self.assertRaisesRegex(ValueError, "only 0 or 1"):
            compute_click_scores(pd.DataFrame({"is_click": [2]}))

    def test_zero_positive_user_contributes_zero_to_macro_metrics(self):
        result = evaluate_unbiased_model(
            FixedScores(), {0: [0, 1], 1: [0, 1]}, {0: {0}, 1: set()}, k=1,
        )
        self.assertEqual(result["eval_users"], 2)
        self.assertEqual(result["zero_positive_users"], 1)
        self.assertEqual(result["NDCG@1"], 0.5)
        self.assertEqual(result["HitRate@1"], 0.5)
        paper = evaluate_unbiased_model(
            FixedScores(), {0: [0, 1], 1: [0, 1]}, {0: {0}, 1: set()},
            k=1, include_zero_positive_users=False,
        )
        self.assertEqual(paper["eval_users"], 1)
        self.assertEqual(paper["zero_positive_users"], 1)
        self.assertEqual(paper["NDCG@1"], 1.0)

    def test_paper_idcf_uses_click_two_train_logs_and_user_split(self):
        with tempfile.TemporaryDirectory() as root:
            first = pd.DataFrame({"user_id": np.repeat(np.arange(4), 10),
                                  "video_id": np.tile(np.arange(2), 20),
                                  "is_click": np.tile([0, 1], 20)})
            second = pd.DataFrame({"user_id": np.arange(4), "video_id": [0] * 4,
                                   "is_click": [1] * 4})
            random_log = pd.DataFrame({"user_id": np.repeat(np.arange(4), 2),
                                       "video_id": np.tile(np.arange(2), 4),
                                       "is_click": np.tile([1, 0], 4)})
            first.to_csv(os.path.join(root, "log_standard_4_08_to_4_21_pure.csv"), index=False)
            second.to_csv(os.path.join(root, "log_standard_4_22_to_5_08_pure.csv"), index=False)
            random_log.to_csv(os.path.join(root, "log_random_4_22_to_5_08_pure.csv"), index=False)
            data = load_kuairand_processed(data_dir=root, cache_dir=os.path.join(root, "cache"))
            self.assertEqual(data["split_info"]["train_rows"], 44)
            self.assertEqual(data["train_y"].sum(), 24)
            self.assertEqual(data["split_info"]["label"], "is_click")
            self.assertFalse(data["evaluation_include_zero_positive_users"])
            self.assertFalse(set(data["val_candidates"]) & set(data["test_candidates"]))
            self.assertTrue(np.all(data["train_c"] == 1.0))
            weighted = load_kuairand_processed(alpha=2.0, data_dir=root,
                                                cache_dir=os.path.join(root, "cache"))
            self.assertEqual(weighted["train_c"].max(), 3.0)
            self.assertEqual(weighted["train_c"].min(), 1.0)

    def test_grid_trial_never_evaluates_test(self):
        data = {
            "num_users": 2, "num_items": 6,
            "train_u": np.array([0, 0, 1, 1]),
            "train_i": np.array([0, 1, 0, 1]),
            "train_y": np.array([1., 0., 0., 1.], dtype=np.float32),
            "train_c": np.array([2., 1., 1., 2.], dtype=np.float32),
            "train_user_pos_map": {0: {0}, 1: {1}},
            "val_candidates": {0: [2, 3]}, "val_ground_truth": {0: {2}},
            "test_candidates": {1: [4, 5]}, "test_ground_truth": {1: {4}},
        }
        fake_metrics = {"NDCG@5": 0.5, "Recall@5": 0.5,
                        "Precision@5": 0.2, "HitRate@5": 1.0, "elapsed_seconds": 0.0}
        with tempfile.TemporaryDirectory() as root, patch(
            "src.baselines.train_mf.evaluate_unbiased_model", return_value=fake_metrics
        ) as evaluator:
            result = train_single_run(data, embedding_dim=4, epochs=1, batch_size=4,
                                      checkpoint_dir=root, evaluate_test=False)
            self.assertEqual(evaluator.call_count, 1)
            self.assertIs(evaluator.call_args.args[1], data["val_candidates"])
            self.assertNotIn("test", result)

    def test_coat_mf_validation_trial_does_not_evaluate_test(self):
        fake_metrics = {"NDCG@5": 0.5, "Recall@5": 0.5, "HitRate@5": 0.5}
        with tempfile.TemporaryDirectory() as root, patch(
            "src.baselines.train_mf.CHECKPOINT_DIR", root
        ), patch("src.baselines.train_mf.evaluate_unbiased_model", return_value=fake_metrics) as evaluator:
            result = train_baseline_mf(dataset_name="coat", epochs=1, evaluate_test=False)
            self.assertEqual(result["best_val_ndcg"], 0.5)
            self.assertEqual(evaluator.call_count, 1)


def tiny_data():
    return dict(n_users=3, num_users=3, n_items=6, num_items=6,
                train_u=np.array([0, 0, 1, 1, 2, 2]), train_i=np.array([0, 1, 1, 2, 0, 2]),
                train_y=np.array([1, 0, 0, 1, 0, 1], dtype=np.float32),
                train_c=np.ones(6, dtype=np.float32),
                val_candidates={0: [2, 3]}, val_ground_truth={0: {2}},
                test_candidates={1: [4, 5]}, test_ground_truth={1: {4}})


class RegressionTests(unittest.TestCase):
    def test_cdr_counterfactual_sampling_weight_scales_direct_term(self):
        terms = dict(pred_obs=torch.tensor([0.5]), y_obs=torch.tensor([1.0]),
                     inv_prop_obs=torch.tensor([1.0]),
                     imp_loss_obs=torch.tensor([0.0]), imp_unc_obs=torch.tensor([0.0]),
                     pred_unobs=torch.tensor([0.5]),
                     imp_loss_unobs=torch.tensor([2.0]),
                     imp_unc_unobs=torch.tensor([0.0]), un_thres=1.0, ips_weighting="author")
        base, _ = cdr_recommendation_loss(**terms, counterfactual_scale=1.0)
        scaled, _ = cdr_recommendation_loss(**terms, counterfactual_scale=3.0)
        torch.testing.assert_close(scaled - base, torch.tensor(4.0))

    def test_cdr_gradient_isolation_and_ips_fallback(self):
        torch.manual_seed(42)
        for threshold in (0.0, 1e6):
            model = CDRFramework(4, 6, embedding_dim=4, un_thres=threshold)
            reference = copy.deepcopy(model.rec_model)
            u, i = torch.tensor([0, 1, 2]), torch.tensor([0, 1, 2])
            y, inv = torch.tensor([1., 0., 1.]), torch.tensor([2., 3., 2.])
            ru, ri = torch.tensor([3, 3]), torch.tensor([4, 5])
            rec, imp, _ = model.compute_cdr_losses(u, i, y, inv, ru, ri, mc_samples=1, observed_fraction=3/24)
            self.assertTrue(torch.isfinite(rec))
            rec.backward()
            self.assertTrue(all(p.grad is None for p in model.imp_model.parameters()))
            ips = (F.binary_cross_entropy_with_logits(reference(u, i), y, reduction="none") * inv).mean() * (3/24)
            ips.backward()
            delta = max((a.grad - b.grad).abs().max().item()
                        for a, b in zip(model.rec_model.parameters(), reference.parameters()))
            if threshold:
                self.assertGreater(delta, 1e-6)
                self.assertGreater(model.rec_model.item_embedding.weight.grad[4:].abs().sum().item(), 0)
            else:
                self.assertLess(delta, 1e-6)
            model.zero_grad(set_to_none=True)
            imp.backward()
            self.assertTrue(all(p.grad is None for p in model.rec_model.parameters()))
            self.assertGreater(sum(p.grad.abs().sum().item() for p in model.imp_model.parameters()), 0)

    def test_mf_entrypoints_match_and_selected_checkpoint_is_not_retrained(self):
        data = tiny_data()
        with tempfile.TemporaryDirectory() as root:
            normal = train_baseline_mf("kuairand", data_dict=data, embedding_dim=4,
                                      epochs=2, lr=.001, batch_size=3, patience=7,
                                      checkpoint_dir=root, evaluate_test=False)
            grid = train_single_run(data, embedding_dim=4, epochs=2, lr=.001,
                                    batch_size=3, patience=7, checkpoint_dir=root, evaluate_test=False)
            first = load_checkpoint(normal["checkpoint_path"])
            second = load_checkpoint(grid["checkpoint"])
            for key, value in first["model_state_dict"].items():
                torch.testing.assert_close(value, second["model_state_dict"][key], atol=0, rtol=0)
            with patch("torch.optim.Adam.step", side_effect=AssertionError("Must not train")):
                result = evaluate_checkpoint(grid["checkpoint"], data)
            self.assertEqual(result["best_epoch"], first["epoch"])
            old = Path(root) / "old.pt"
            torch.save({"model_state_dict": first["model_state_dict"]}, old)
            with self.assertRaisesRegex(ValueError, "incompatible"):
                load_checkpoint(old)
            changed = copy.deepcopy(data)
            changed["train_y"][0] = 0
            self.assertNotEqual(digest(data_signature(data)), digest(data_signature(changed)))
            with self.assertRaisesRegex(ValueError, "does not match"):
                evaluate_checkpoint(grid["checkpoint"], changed)

    def test_empty_pools_small_catalog_and_masked_truth(self):
        data = tiny_data()
        data["test_candidates"], data["test_ground_truth"] = {}, {}
        diagnostics = candidate_pool_diagnostics(data)
        self.assertEqual(diagnostics["candidate_size_p10_p50_p90"], [0, 0, 0])
        self.assertEqual(diagnostics["random_expected"]["NDCG@5"], 0)
        class Scores(torch.nn.Module):
            def predict_user_all(self, users):
                return torch.tensor([[3., 2., 1.]]).expand(len(users), -1).clone()
            def get_evaluation_factors(self):
                return np.ones((1, 1)), np.array([[3.], [2.], [1.]])
        model = Scores()
        full = GPUVectorizedEvaluator(3, {0: {0, 1}}, {0: {0}}, k=5, device=torch.device("cpu"))
        result = full.evaluate(model)
        self.assertEqual(result["Recall@5"], 1)
        self.assertEqual(result["NDCG@5"], 1)
        self.assertEqual(evaluate_unbiased_model(model, {}, {}, k=2)["NDCG@2"], 0)
        logged = evaluate_unbiased_model(model, {0: [1, 2]}, {0: {1}}, k=5)
        self.assertEqual(logged["NDCG@5"], result["NDCG@5"])

    def test_invalid_cli_is_rejected_before_loading_data(self):
        with patch("experiments.workflows.run_all_benchmarks.load_kuairand_processed", side_effect=AssertionError("Loaded data")):
            for kwargs in (dict(epochs_kr=0), dict(lr=-1), dict(grid_search=True, dataset_filter="coat"),
                           dict(grid_search=True, dataset_filter="kuairand", model_filter="cdr")):
                with self.assertRaises(ValueError):
                    run_all_benchmarks(**kwargs)

    def test_explicit_feature_root_does_not_fallback(self):
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaises(FileNotFoundError):
                load_kuairand_tab_instruments({1: 0}, {1: 0}, data_dir=root)

    def test_tuning_evaluates_only_selected_checkpoint(self):
        from experiments.workflows import tune_coat_models as tune
        calls = []
        def trial(name, config, epochs, evaluate_test, tag, **kwargs):
            self.assertFalse(evaluate_test)
            calls.append(config["lr"])
            return dict(best_val_ndcg=config["lr"], best_epoch=1,
                        checkpoint_path=f"trial_{config['lr']}.pt", metadata={})
        with tempfile.TemporaryDirectory() as root, patch.object(tune, "GRIDS", {"mf": [{"lr": .01}, {"lr": .02}]}), \
                patch.object(tune, "RESULTS_DIR", root), \
                patch.object(tune, "load_coat_processed", return_value=tiny_data()), \
                patch.object(tune, "train_model", side_effect=trial), \
                patch.object(tune, "evaluate_checkpoint", return_value={"NDCG@5": .5, "Recall@5": .5}) as evaluate, \
                patch("sys.argv", ["tune_coat_models.py", "--model", "mf", "--epochs", "1"]):
            tune.main()
            self.assertEqual(calls, [.01, .02])
            evaluate.assert_called_once()
            self.assertEqual(evaluate.call_args.args[0], "trial_0.02.pt")

class OptimizerTests(unittest.TestCase):
    def test_sgd_one_step_matches_objective_gradient_for_both_losses(self):
        data = tiny_data()
        data["train_c"] = np.array([2, 1, 1, 2, 1, 2], dtype=np.float32)
        for loss_name in ("bce", "mse"):
            for scope in ("embeddings", "all"):
                set_seed(42)
                model = MatrixFactorization(3, 6, embedding_dim=4)
                initial = {name: p.detach().clone() for name, p in model.named_parameters()}
                scores = model(torch.tensor(data["train_u"]), torch.tensor(data["train_i"]))
                labels = torch.tensor(data["train_y"])
                losses = (torch.nn.functional.binary_cross_entropy_with_logits(scores, labels, reduction="none")
                          if loss_name == "bce" else (scores - labels).square())
                objective = (losses * torch.tensor(data["train_c"])).mean()
                objective += .02 / 2 * sum(p.square().sum() for name, p in model.named_parameters()
                                           if scope == "all" or "embedding" in name)
                objective.backward()
                expected = {name: initial[name] - .1 * p.grad for name, p in model.named_parameters()}
                with tempfile.TemporaryDirectory() as root:
                    result = train_baseline_mf(
                        "kuairand", data_dict=data, epochs=1, embedding_dim=4, batch_size=6,
                        lr=.1, weight_decay=.02, optimizer_name="sgd", loss_name=loss_name,
                        train_global_bias=True, init_scheme="normal",
                        decay_scope=scope, scheduler_name="none", checkpoint_dir=root, evaluate_test=False)
                    state = load_checkpoint(result["checkpoint_path"])
                for name, value in expected.items():
                    torch.testing.assert_close(state["model_state_dict"][name], value, atol=1e-7, rtol=1e-5)

    def test_comparison_selects_on_validation_before_any_test(self):
        events = []
        def train(dataset, **kwargs):
            self.assertFalse(kwargs["evaluate_test"])
            events.append("train")
            return dict(best_val_ndcg=kwargs["lr"], checkpoint_path=str(kwargs["lr"]),
                        validation={}, metadata={}, best_epoch=1)
        def evaluate(path, *args):
            events.append("test")
            return {"NDCG@5": .1, "Recall@5": .2}
        with tempfile.TemporaryDirectory() as root, \
                patch.object(comparison, "RESULTS_DIR", root), \
                patch.object(comparison, "train_baseline_mf", side_effect=train), \
                patch.object(comparison, "evaluate_checkpoint", side_effect=evaluate) as evaluator:
            result = comparison.compare(tiny_data(), "coat", epochs=1, seeds=[42],
                                        adam_lrs=[.01, .02], sgd_lrs=[.1, .2], weight_decays=[0])
        self.assertEqual(events, ["train"] * 4 + ["test"] * 2)
        self.assertEqual([c.args[0] for c in evaluator.call_args_list], ["0.02", "0.2"])
        self.assertEqual(result["recommended_by_validation"], "sgd")

    def test_entrypoint_accepts_canonical_shape_keys_and_rejects_als(self):
        data = tiny_data()
        del data["num_users"], data["num_items"]
        with tempfile.TemporaryDirectory() as root:
            result = train_single_run(data, epochs=1, checkpoint_dir=root, evaluate_test=False,
                                      optimizer_name="sgd", loss_name="mse")
        self.assertEqual(result["metadata"]["config"]["optimizer"], "sgd")
        with self.assertRaisesRegex(ValueError, "ALS"):
            train_baseline_mf(data_dict=data, optimizer_name="als")

class PaperMetricTests(unittest.TestCase):
    def test_ndcg_recall_match_hand_computed_idcf_binary_definition(self):
        # User 0: two hits at ranks 1 and 3, seven positives (> k).
        # User 1: one hit at rank 2, only two candidates (< k).
        # User 2: zero positives, excluded from the paper macro average.
        class Scores:
            def get_evaluation_factors(self):
                return np.ones((3, 1)), np.arange(10, 0, -1, dtype=float)[:, None]
        result = evaluate_unbiased_model(
            Scores(), {0: list(range(10)), 1: [2, 3], 2: [0, 1]},
            {0: {0, 2, 5, 6, 7, 8, 9}, 1: {3}, 2: set()}, k=5,
            include_zero_positive_users=False)
        expected_ndcg = ((1 + .5) / sum(1 / np.log2(r + 1) for r in range(1, 6))
                         + 1 / np.log2(3)) / 2
        self.assertAlmostEqual(result['NDCG@5'], expected_ndcg)
        self.assertAlmostEqual(result['Recall@5'], (2 / 7 + 1) / 2)
        self.assertNotEqual(result['Recall@5'], result['Recall@5_bounded'])
        self.assertEqual(result['eval_users'], 2)
        self.assertEqual(result['candidate_users'], 3)
        self.assertEqual(result['zero_positive_users'], 1)

    def test_reference_dense_ranking_agrees_without_duplicates_or_ties(self):
        # Independent dense ranking oracle for the released iDCF metric convention.
        rng = np.random.default_rng(71)
        predictions = rng.normal(size=(4, 12))
        labels = rng.integers(0, 2, size=(4, 12))
        labels[0] = 0
        class Scores:
            def predict(self, user, items, device=None):
                return predictions[user, items]
        candidates = {u: list(range(12)) for u in range(4)}
        truth = {u: set(np.flatnonzero(labels[u])) for u in range(4)}
        result = evaluate_unbiased_model(Scores(), candidates, truth, include_zero_positive_users=False)
        ndcgs, recalls = [], []
        for u in (1, 2, 3):
            ranking = sorted(range(12), key=lambda i: predictions[u, i], reverse=True)[:5]
            gains = [int(labels[u, item]) for item in ranking]
            dcg = sum(gain / np.log2(rank + 2) for rank, gain in enumerate(gains))
            idcg = sum(1 / np.log2(rank + 2) for rank in range(min(5, int(labels[u].sum()))))
            ndcgs.append(dcg / idcg)
            recalls.append(sum(gains) / labels[u].sum())
        self.assertAlmostEqual(result['NDCG@5'], np.mean(ndcgs))
        self.assertAlmostEqual(result['Recall@5'], np.mean(recalls))

    def test_candidate_validation_and_deterministic_ties(self):
        class Scores:
            def get_evaluation_factors(self):
                return np.ones((1, 1)), np.ones((4, 1))
        for pool in ([3, 0, 2, 1], [1, 2, 0, 3]):
            score = evaluate_unbiased_model(Scores(), {0: pool}, {0: {0}}, k=1)
            self.assertEqual(score['NDCG@1'], 1)
        for candidates, truth in (({0: [0, 0]}, {0: {0}}),
                                  ({0: [0, 1]}, {0: {2}}), ({}, {0: {0}})):
            with self.assertRaises(ValueError):
                evaluate_unbiased_model(Scores(), candidates, truth)
        class Nonfinite:
            def predict(self, user, items, device=None):
                return np.full(len(items), np.nan)
        with self.assertRaisesRegex(ValueError, 'scores'):
            evaluate_unbiased_model(Nonfinite(), {0: [0]}, {0: {0}})

    def test_seed_std_auc_and_split_are_explicit(self):
        summary = summarize_seeds([{'NDCG@5': .2, 'Recall@5': .4},
                                   {'NDCG@5': .4, 'Recall@5': .6}])
        self.assertAlmostEqual(summary['NDCG@5']['std'], np.sqrt(.02))
        self.assertIsNone(summarize_seeds([{'NDCG@5': .2, 'Recall@5': .4}])['NDCG@5']['std'])
        score = evaluate_unbiased_model(FixedScores(), {0: [0]}, {0: {0}}, compute_user_auc=True)
        self.assertIsNone(score['AUC'])
        self.assertEqual(score['auc_users'], 0)
        data = tiny_data()
        data['split_info'] = {'protocol': 'paper_idcf'}
        data['evaluation_include_zero_positive_users'] = False
        validate_paper_split(data)
        data['test_candidates'] = data['val_candidates']
        with self.assertRaisesRegex(ValueError, 'disjoint'):
            validate_paper_split(data)
        self.assertEqual(protocol_metadata()['recall_denominator'], 'all_positive_items_in_candidate_pool')

    def test_old_metric_protocol_cannot_silently_mix_with_new_evaluation(self):
        with tempfile.TemporaryDirectory() as root:
            result = train_baseline_mf('kuairand', data_dict=tiny_data(), epochs=1,
                                      embedding_dim=4, checkpoint_dir=root, evaluate_test=False)
            state = load_checkpoint(result['checkpoint_path'])
            del state['metadata']['protocol']['metric_revision']
            torch.save(state, result['checkpoint_path'])
            with self.assertRaisesRegex(ValueError, 'older evaluation protocol'):
                evaluate_checkpoint(result['checkpoint_path'], tiny_data())


class EntrypointTests(unittest.TestCase):
    def test_single_mf_uses_shared_entrypoint(self):
        with patch('src.baselines.train_mf.main') as train:
            self.assertEqual(entrypoint.main(['mf', '--dataset', 'coat']), 0)
            train.assert_called_once_with(['--dataset', 'coat'])

    def test_workflows_receive_only_their_arguments(self):
        for command, module_name in entrypoint.WORKFLOWS.items():
            with patch(f'experiments.workflows.{module_name}.main') as workflow:
                self.assertEqual(entrypoint.main([command, '--help']), 0)
                workflow.assert_called_once_with(['--help'])

    def test_smoke_keeps_subset_out_of_full_benchmarks(self):
        with patch('experiments.workflows.run_all_benchmarks.run_all_benchmarks') as benchmark:
            entrypoint.main(['smoke'])
            self.assertEqual(benchmark.call_count, 3)
            coat, yahoo, kuairand = [call.kwargs for call in benchmark.call_args_list]
            self.assertEqual(coat['dataset_filter'], 'coat')
            self.assertIsNone(coat['smoke_users'])
            self.assertEqual(yahoo['dataset_filter'], 'yahoo')
            self.assertEqual(yahoo['smoke_users'], 64)
            self.assertEqual(kuairand['smoke_users'], 64)
            self.assertTrue(all(call.kwargs['quick_run'] for call in benchmark.call_args_list))

    def test_test_command_propagates_failure_exit_status(self):
        with patch.object(entrypoint.unittest.defaultTestLoader, 'discover'), \
                patch.object(entrypoint.unittest, 'TextTestRunner') as runner:
            runner.return_value.run.return_value.wasSuccessful.return_value = False
            self.assertEqual(entrypoint.main(['test']), 1)

class ExperimentInfraTests(unittest.TestCase):
    def test_experiment_lock_excludes_second_writer_and_releases_after_failure(self):
        from src.utils.experiment_lock import experiment_lock
        with tempfile.TemporaryDirectory() as root:
            lock = Path(root) / 'experiment.lock'
            with self.assertRaisesRegex(ValueError, 'interrupted'):
                with experiment_lock(lock):
                    with self.assertRaisesRegex(RuntimeError, 'already running'):
                        with experiment_lock(lock):
                            self.fail('Concurrent writer acquired lock')
                    raise ValueError('interrupted')
            with experiment_lock(lock):
                pass

    def test_paper_mf_global_intercept_remains_zero(self):
        with tempfile.TemporaryDirectory() as root:
            result = train_baseline_mf('kuairand', data_dict=tiny_data(), epochs=2,
                                      checkpoint_dir=root, evaluate_test=False, train_global_bias=False)
            state = load_checkpoint(result['checkpoint_path'])
            self.assertEqual(state['model_state_dict']['global_bias'].item(), 0)
            self.assertFalse(state['metadata']['model_kwargs']['train_global_bias'])
            self.assertEqual(result['epochs_run'], 2)

class FusedAdamTests(unittest.TestCase):
    def test_fused_adam_matches_standard_steps_with_l2(self):
        torch.manual_seed(17)
        for decay in (1e-5, 1e-6):
            original = torch.nn.Parameter(torch.randn(50, 32))
            fused = torch.nn.Parameter(original.detach().clone())
            first = torch.optim.Adam([original], lr=1e-3, weight_decay=decay)
            second = torch.optim.Adam([fused], lr=1e-3, weight_decay=decay, fused=True)
            for _ in range(10):
                grad = torch.randn_like(original)
                original.grad = grad.clone()
                fused.grad = grad.clone()
                first.step()
                second.step()
            torch.testing.assert_close(original, fused, atol=1e-6, rtol=1e-6)


class CheckpointCorrectionTests(unittest.TestCase):
    def test_atomic_replace_retries_transient_permission_and_preserves_old_file(self):
        from src.utils.artifacts import replace_with_retry
        with tempfile.TemporaryDirectory() as root, patch('src.utils.artifacts.time.sleep'):
            source, target = Path(root) / 'new.tmp', Path(root) / 'best.pt'
            source.write_text('new')
            target.write_text('old')
            actual = Path.replace
            calls = []
            def transient(path, destination):
                calls.append(1)
                if len(calls) < 3:
                    raise PermissionError('file temporarily locked')
                return actual(path, destination)
            with patch.object(Path, 'replace', transient):
                replace_with_retry(source, target)
            self.assertEqual(target.read_text(), 'new')
            self.assertEqual(len(calls), 3)
            source.write_text('another')
            with patch.object(Path, 'replace', side_effect=PermissionError('locked')):
                with self.assertRaises(PermissionError):
                    replace_with_retry(source, target)
            self.assertEqual(target.read_text(), 'new')

    def test_idcf_checkpoint_roundtrip_and_old_architecture_rejected(self):
        from src.causal.idcf.train_idcf import train_idcf
        data = tiny_data()
        mean, std = torch.randn(3, 2), torch.rand(3, 2)
        with tempfile.TemporaryDirectory() as root:
            result = train_idcf(data, mean, std, "kuairand", embedding_dim=4, epochs=2, batch_size=4,
                                checkpoint_dir=root, evaluate_test=False)
            metrics = evaluate_checkpoint(result['checkpoint_path'], data)
            self.assertTrue(np.isfinite(metrics['NDCG@5']))
            state = load_checkpoint(result['checkpoint_path'])
            self.assertEqual(state['metadata']['architecture_version'], 'idcf_v1')
            torch.testing.assert_close(state['model_state_dict']['c_mean'], mean)
            self.assertEqual(state['model_state_dict']['mf.global_bias'].item(), 0)
            state['metadata']['architecture_version'] = 'idcf_v0'
            torch.save(state, result['checkpoint_path'])
            with self.assertRaisesRegex(ValueError, 'Incompatible architecture'):
                evaluate_checkpoint(result['checkpoint_path'], data)

    def test_invalid_candidate_ids_cannot_silently_use_numpy_negative_index(self):
        for candidates in ({-1: [0]}, {0: [-1]}, {0: [1.5]}, {0: [3]}, {3: [0]}):
            with self.assertRaises(ValueError):
                evaluate_unbiased_model(FixedScores(), candidates, {})

    def test_empty_validation_does_not_create_a_selected_checkpoint(self):
        data = tiny_data()
        data['val_ground_truth'] = {0: set()}
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaisesRegex(ValueError, 'Validation must contain'):
                train_baseline_mf('kuairand', data_dict=data, epochs=1, checkpoint_dir=root)
            self.assertFalse(list(Path(root).glob('*.pt')))
