"""iDCF hai giai đoạn và bộ lọc CDR theo mã tác giả."""
import unittest

import numpy as np
import torch

from src.causal.cdr.dr_bias_loss import cdr_recommendation_loss
from src.causal.idcf.idcf_model import IDCFModel
from src.causal.idcf.ivae import ExposureIVAE, train_exposure_ivae


class ExposureIVAETests(unittest.TestCase):
    def test_returns_confounders_for_every_user(self):
        rng = np.random.default_rng(0)
        a = (rng.random((20, 8)) < 0.3).astype(np.float32)
        w = np.eye(4, dtype=np.float32)[rng.integers(0, 4, 20)]
        mean, std, info = train_exposure_ivae(a, w, latent_dim=3, hidden_dim=8, epochs=5, patience=5, batch_size=8)
        self.assertEqual(tuple(mean.shape), (20, 3))
        self.assertTrue(torch.all(std > 0))
        self.assertGreaterEqual(info["best_epoch"], 1)

    def test_decoder_reconstructs_exposure(self):
        model = ExposureIVAE(n_items=6, aux_dim=2, latent_dim=3, hidden_dim=4)
        a_hat, *_ = model(torch.zeros(2, 6), torch.zeros(2, 2))
        self.assertEqual(tuple(a_hat.shape), (2, 6))


class IDCFModelTests(unittest.TestCase):
    def test_score_is_mf_plus_confounder_term_and_factors_agree(self):
        torch.manual_seed(0)
        mean, std = torch.randn(3, 2), torch.ones(3, 2)
        model = IDCFModel(3, 4, 2, embedding_dim=5).set_confounders(mean, std).eval()
        u, i = torch.tensor([0, 1, 2]), torch.tensor([3, 0, 1])
        expected = model.mf(u, i) + (model.item_c(i) * mean[u]).sum(-1)
        torch.testing.assert_close(model(u, i), expected)
        uf, itf = model.get_evaluation_factors()
        np.testing.assert_allclose((uf[u.numpy()] * itf[i.numpy()]).sum(1), expected.detach().numpy(), atol=1e-5)

    def test_sampling_averages_around_mean(self):
        model = IDCFModel(1, 1, 2, embedding_dim=2).set_confounders(torch.ones(1, 2), torch.zeros(1, 2))
        u = i = torch.tensor([0])
        torch.testing.assert_close(model(u, i, sample=True), model(u, i))


class CDRAuthorModeTests(unittest.TestCase):
    def _terms(self, unc):
        return dict(pred_obs=torch.tensor([0.5]), y_obs=torch.tensor([1.0]), inv_prop_obs=torch.tensor([3.0]),
                    imp_loss_obs=torch.tensor([0.2]), imp_unc_obs=torch.tensor([unc]),
                    pred_unobs=torch.tensor([0.5]), imp_loss_unobs=torch.tensor([0.2]),
                    imp_unc_unobs=torch.tensor([unc]))

    def test_variance_filter_keeps_what_cv_filter_drops(self):
        # std/mean = 0.1/0.2 = 0.5 > 0.01 -> CV bỏ; phương sai 0.01 < 10 -> author giữ.
        _, dropped = cdr_recommendation_loss(**self._terms(0.01), un_thres=0.01, filter_mode="cv", ips_weighting="author")
        _, kept = cdr_recommendation_loss(**self._terms(0.01), un_thres=10.0, filter_mode="variance", ips_weighting="author")
        self.assertEqual((dropped, kept), (1.0, 0.0))

    def test_author_ips_subtracts_unweighted_imputation(self):
        dr, _ = cdr_recommendation_loss(**self._terms(0.0), un_thres=10.0, filter_mode="variance",
                                        ips_weighting="dr")
        author, _ = cdr_recommendation_loss(**self._terms(0.0), un_thres=10.0, filter_mode="variance",
                                            ips_weighting="author")
        torch.testing.assert_close(author - dr, torch.tensor((3.0 - 1.0 - 1.0) * 0.2))

    def test_rejects_unknown_modes(self):
        with self.assertRaises(ValueError):
            cdr_recommendation_loss(**self._terms(0.0), filter_mode="median")


if __name__ == "__main__":
    unittest.main()
