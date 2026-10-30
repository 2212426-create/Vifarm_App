"""Protect independent paper-method training from accidental hybrid experiments."""
import contextlib
import importlib
import io
import tempfile
import unittest
from unittest.mock import patch

import torch

from src.causal.cdr.cdr_model import CDRFramework
from src.training.config import mf_config, cdr_config
from test_review_fixes import small_data


class PaperModelProfileTests(unittest.TestCase):
    def test_cdr_paper_backbone_matches_source_dot_product_and_factor_scores(self):
        model = CDRFramework(3, 4, embedding_dim=2, backbone="paper_dot")
        self.assertEqual(set(model.rec_model.state_dict()),
                         {"user_embedding.weight", "item_embedding.weight"})
        with torch.no_grad():
            model.rec_model.user_embedding.weight.copy_(torch.tensor([[1., 2.], [3., 4.], [5., 6.]]))
            model.rec_model.item_embedding.weight.copy_(torch.tensor([[2., 1.], [1., 3.], [4., 2.], [3., 5.]]))
        score = model(torch.tensor([0, 2]), torch.tensor([1, 3]))
        torch.testing.assert_close(score, torch.tensor([7., 45.]))
        users, items = model.get_evaluation_factors()
        self.assertEqual(float(users[2] @ items[3]), 45.)

    def test_legacy_checkpoint_without_backbone_reloads_exact_old_biased_scores(self):
        from src.utils.artifacts import make_metadata, save_checkpoint, evaluate_checkpoint
        from src.evaluation.evaluator import evaluate_unbiased_model
        data = small_data()
        model = CDRFramework(3, 4, embedding_dim=2, backbone="legacy_bias")
        with torch.no_grad():
            model.rec_model.item_bias.weight.copy_(torch.tensor([[1.], [0.], [0.], [-1.]]))
        expected = evaluate_unbiased_model(model, data["test_candidates"], data["test_ground_truth"])
        metadata = make_metadata("cdr", "coat", data, {},
                                 dict(num_users=3, num_items=4, embedding_dim=2))
        with tempfile.TemporaryDirectory() as root:
            path = root + "/old.pt"
            save_checkpoint(model, path, metadata, 1, {"NDCG@5": .5})
            actual = evaluate_checkpoint(path, data)
        self.assertEqual(actual["NDCG@5"], expected["NDCG@5"])
        self.assertEqual(actual["objective_revision"], "legacy_unversioned")

    def test_default_configs_keep_each_methods_objective_and_initialization(self):
        from src.causal.idcf.train_idcf import IDCF_CONFIG
        for dataset in ("coat", "kuairand"):
            mf, cdr = mf_config(dataset), cdr_config(dataset)
            self.assertEqual((mf["loss_name"], mf["init_scheme"], mf["scheduler_name"]),
                             ("mse", "author_uniform", "none"))
            self.assertEqual((cdr["backbone"], cdr["training_profile"], cdr["scheduler_name"]),
                             ("paper_dot", "paper", "none"))
            self.assertIsNone(cdr.get("initial_rec_checkpoint"))
            self.assertIsNone(cdr.get("max_inverse_propensity"))
            self.assertEqual(IDCF_CONFIG[dataset]["train"]["init_scheme"], "author_uniform")
            self.assertEqual(IDCF_CONFIG[dataset]["ivae"]["latent_dim"], 16 if dataset == "coat" else 32)

    def test_tuning_uses_published_cartesian_ranges_without_duplicate_baseline(self):
        from src.training.config import tuning_grids
        for dataset in ("coat", "kuairand"):
            grids = tuning_grids(dataset)
            self.assertEqual((len(grids["mf"]), len(grids["cdr"])), (10, 1120))
            configurations = {(c["lr"], c["weight_decay"], c["un_thres"], c["batch_size"])
                              for c in grids["cdr"]}
            self.assertEqual(len(configurations), 1120)
            self.assertEqual({c["lr"] for c in grids["cdr"]}, {.005, .01, .05, .1})
            self.assertEqual({c["weight_decay"] for c in grids["mf"]}, {1e-5, 1e-6})

    def test_paper_profile_rejects_hybrid_or_modified_estimator_before_reading_data(self):
        trainer = importlib.import_module("src.causal.cdr.train_dr_bias_cdr")
        for change in ({"initial_rec_checkpoint": "mf_mse.pt"}, {"ips_weighting": "author"},
                       {"filter_mode": "variance"}, {"max_inverse_propensity": 20.},
                       {"scheduler_name": "plateau"}, {"backbone": "legacy_bias"}):
            with self.subTest(change=change), self.assertRaisesRegex(ValueError, "Paper CDR"):
                trainer.train_dr_bias_cdr(**change)

    def test_cdr_seed_workflow_never_trains_mf(self):
        from experiments.workflows import coat_seed_benchmark as workflow
        data = small_data()
        with patch.object(workflow, "train_baseline_mf", side_effect=AssertionError("MF called")), \
                patch.object(workflow, "run_source", return_value={}) as train:
            workflow.run_seed("DR-BIAS + CDR", data, 43, "temporary")
        self.assertEqual(train.call_args.kwargs["seed"], 43)
        self.assertNotIn("initial_rec_checkpoint", train.call_args.kwargs)
        self.assertIn("IViDR", workflow.STANDARD_MODELS)

    def test_user_selected_six_model_benchmark_never_warms_cdr(self):
        from experiments.workflows import run_all_benchmarks as workflow
        called = []
        data = small_data()
        data["split_info"] = {}

        def mf(**kwargs):
            called.append("mf")
            return {"NDCG@5": .5, "Recall@5": .5, "NDCG@5_CI95_halfwidth": 0.}

        def causal(name, *args, **kwargs):
            called.append(name)
            return {"NDCG@5": .5, "Recall@5": .5, "NDCG@5_CI95_halfwidth": 0.}

        def cdr(*args, **kwargs):
            called.append("cdr")
            self.assertNotIn("initial_rec_checkpoint", kwargs)
            self.assertEqual(kwargs['seed'],2020)
            return {"NDCG@5": .5, "Recall@5": .5, "NDCG@5_CI95_halfwidth": 0.}

        def conalign(dataset, **kwargs):
            called.append("conalign")
            return {"NDCG@5": .5, "UNDCG@5": .5, "UAUC": .5, "AUC_global": .5, "Precision@5": .5,
                    "Recall@5_source": .5, "evaluation_scope": "conalign_source_protocol"}

        with tempfile.TemporaryDirectory() as root, contextlib.redirect_stdout(io.StringIO()), \
                patch.object(workflow, "RESULTS_DIR", root), \
                patch.object(workflow, "load_coat_processed", return_value=data), \
                patch.object(workflow, "train_baseline_mf", side_effect=mf), \
                patch.object(workflow, "run_idcf_family", side_effect=causal), \
                patch.object(workflow, "run_source", side_effect=cdr), \
                patch.object(workflow, "run_conalign", side_effect=conalign), \
                patch.object(workflow, "paired_significance", return_value={}):
            workflow.run_all_benchmarks(dataset_filter="coat", quick_run=True, epochs_coat=1)
        self.assertEqual(called, ["mf", "iDCF", "IViDR", "LCDR", "cdr", "conalign"])

    def test_yahoo_runs_six_models_and_reuses_mf_treatment(self):
        from experiments.workflows import run_all_benchmarks as workflow
        data = small_data()
        data.update(split_info={}, user_feature_info={})
        metric = {"NDCG@5": .5, "Recall@5": .5, "NDCG@5_CI95_halfwidth": 0.}
        mf_result = dict(metric, checkpoint_path="mf-treatment.pt")
        with tempfile.TemporaryDirectory() as root, contextlib.redirect_stdout(io.StringIO()), \
                patch.object(workflow, "RESULTS_DIR", root), \
                patch.object(workflow, "load_yahoo_processed", return_value=data), \
                patch.object(workflow, "train_baseline_mf", return_value=mf_result), \
                patch.object(workflow, "run_idcf_family", return_value=metric) as causal, \
                patch.object(workflow, "run_source", return_value=metric), \
                patch.object(workflow, "run_conalign", return_value={
                    **metric, "UNDCG@5": .5, "UAUC": .5, "AUC_global": .5, "Precision@5": .5,
                    "Recall@5_source": .5, "evaluation_scope": "conalign_source_protocol"}) as conalign, \
                patch.object(workflow, "paired_significance", return_value={}):
            workflow.run_all_benchmarks(dataset_filter="yahoo", quick_run=True, epochs_yahoo=1)
        self.assertEqual([c.args[0] for c in causal.call_args_list], ["iDCF", "IViDR", "LCDR"])
        self.assertIs(causal.call_args_list[1].args[3], mf_result)
        self.assertEqual(conalign.call_args.args[0], "yahoo")


if __name__ == "__main__":
    unittest.main()
