"""IViDR options: Eq. (10) v3 lift, Table 4 ablations, prior mean; default v2 lift + prior 0 + w-=.1."""
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import torch

from src.models.ividr import train_ividr
from src.models.ividr.ividr_reference import PaperExposureIVAE
from src.models.ividr.train_ividr import (DEFAULT_EQ10_BRIDGE, DEFAULT_NEGATIVE_WEIGHT, DEFAULT_PRIOR_MEAN,
                                         train_dual_ivae)


def inputs():
    rng = np.random.default_rng(4)
    a = (rng.random((12, 7)) > .5).astype('float32')
    a[0] = 0
    return a, rng.normal(size=(12, 3)).astype('float32'), rng.normal(size=(7, 5)).astype('float32')


class IViDRV3Tests(unittest.TestCase):
    def model(self, **options):
        a, w, t = inputs()
        torch.manual_seed(0)
        return PaperExposureIVAE(7, 3, 2, 8, 2, t, a, w, 4, **options), torch.tensor(a), torch.tensor(w)

    def test_rownorm_lift_matches_each_user_exposure_norm(self):
        model, a, _ = self.model(eq10_bridge='tied_item_lift_rownorm')
        lift = model.reconstructed_input(a) - a
        torch.testing.assert_close(lift.norm(dim=1), a.norm(dim=1), atol=1e-5, rtol=1e-5)
        self.assertEqual(float(lift[0].detach().abs().sum()), 0.)

    def test_rownorm_lift_does_not_vanish_when_gates_shrink(self):
        model, a, _ = self.model(eq10_bridge='tied_item_lift_rownorm')
        before = model.reconstructed_input(a)
        with torch.no_grad():
            for gate in (model.iv.alpha_fitted, model.iv.alpha_residual):
                gate[-1].weight.mul_(1e-3)
                gate[-1].bias.mul_(1e-3)
        after = model.reconstructed_input(a)
        torch.testing.assert_close((after - a).norm(dim=1), (before - a).norm(dim=1), atol=1e-4, rtol=1e-4)

    def test_v2_default_of_model_is_unchanged(self):
        model, a, _ = self.model()
        t, fitted, residual, g1, g2 = model.iv.components()
        expected = a + (a @ (g1 * fitted + g2 * residual)) @ t.T / 2
        torch.testing.assert_close(model.reconstructed_input(a), expected)

    def test_table4_ablations_use_requested_component(self):
        for reconstruction in ('treatment', 'fitted', 'residual'):
            model, a, _ = self.model(reconstruction=reconstruction)
            t, fitted, residual, g1, g2 = model.iv.components()
            part = {'treatment': t, 'fitted': g1 * fitted, 'residual': g2 * residual}[reconstruction]
            torch.testing.assert_close(model.reconstructed_input(a), a + (a @ part) @ t.T / 2)

    def test_zero_prior_mean_matches_idcf_prior_and_leaves_mean_head_unused(self):
        model, a, w = self.model(prior_mean='zero')
        generator = torch.Generator().manual_seed(3)
        loss = model.dual_elbo(a, w, generator=generator)
        loss.backward()
        self.assertTrue(all(p.grad is None for p in model.prior_mean.parameters()))
        self.assertGreater(model.prior_log_var[0].weight.grad.abs().sum(), 0)
        learned, _, _ = self.model()
        self.assertEqual(learned.prior_mean_mode, 'learned')

    def test_rejects_unknown_options(self):
        a, w, t = inputs()
        with self.assertRaises(ValueError):
            PaperExposureIVAE(7, 3, 2, 8, 2, t, a, w, 4, eq10_bridge='free_linear')
        with self.assertRaises(ValueError):
            PaperExposureIVAE(7, 3, 2, 8, 2, t, a, w, 4, reconstruction='both')

    def test_stage1_records_v3_architecture_and_reloads(self):
        a, w, t = inputs()
        with tempfile.TemporaryDirectory() as folder:
            mean, std, info = train_dual_ivae(dict(exposure=a, proxy=w, instrument=w), t, epochs=3, batch_size=6,
                                              hidden_dim=8, latent_dim=2, treatment_dim=4, validation_samples=1,
                                              checkpoint_path=folder + '/stage1.pt', implementation='reference_v2',
                                              eq10_bridge='tied_item_lift_rownorm')
            saved = torch.load(folder + '/stage1.pt', weights_only=True)
            model = PaperExposureIVAE(**saved['model_config'], item_embeddings=t, exposure=a, instruments=w).eval()
            model.load_state_dict(saved['model_state_dict'])
            again = model.confounders(torch.tensor(a), torch.tensor(w))
        self.assertEqual(saved['architecture'], 'paper_ivae_learned_instruments_v3_rownorm')
        self.assertEqual(info['eq10_bridge'], 'tied_item_lift_rownorm')
        torch.testing.assert_close(again[0], mean, atol=1e-6, rtol=1e-6)
        torch.testing.assert_close(again[1], std, atol=1e-6, rtol=1e-6)

    def test_pipeline_keeps_v2_default_and_v3_selectable(self):
        captured = []

        def fake_stage1(*args, **kwargs):
            captured.append((kwargs['eq10_bridge'], kwargs['reconstruction'], kwargs['prior_mean']))
            raise RuntimeError('stop after stage1 arguments')

        data = dict(n_users=2, n_items=2)
        with patch.object(train_ividr, 'train_dual_ivae', side_effect=fake_stage1), \
                patch('src.models.idcf.train_idcf.DATASET_INPUTS', {'coat': lambda d: {}}):
            for overrides in (None, dict(eq10_bridge='tied_item_lift_rownorm'), dict(prior_mean='learned')):
                with tempfile.TemporaryDirectory() as folder, self.assertRaises(RuntimeError):
                    train_ividr.fit_ividr_pipeline(data, 'coat', item_emb=np.zeros((2, 2)), checkpoint_dir=folder,
                                                   ivae_overrides=overrides)
        self.assertEqual((DEFAULT_EQ10_BRIDGE, DEFAULT_PRIOR_MEAN, DEFAULT_NEGATIVE_WEIGHT), ('tied_item_lift', 'zero', .1))
        self.assertEqual(captured, [('tied_item_lift', 'full', 'zero'), ('tied_item_lift_rownorm', 'full', 'zero'),
                                    ('tied_item_lift', 'full', 'learned')])


if __name__ == '__main__':
    unittest.main()
