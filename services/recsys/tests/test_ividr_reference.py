"""Independent formula, probability integration and checkpoint regressions."""
import contextlib
import io
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import torch
from scipy.integrate import quad
from scipy.special import expit
from torch.nn import functional as F

from src.causal.idcf.ividr_reference import LearnedInstruments, PaperExposureIVAE, IViDRMarginalMF
from src.causal.idcf.train_ividr import train_dual_ivae
from src.causal.idcf.train_idcf import train_idcf
from src.utils.artifacts import evaluate_checkpoint,load_checkpoint
from src.evaluation.evaluator import evaluate_unbiased_model
from test_review_fixes import small_data


class IViDRReferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):torch.set_num_threads(2)

    def inputs(self):
        rng=np.random.default_rng(4)
        a=(rng.random((12,7))>.5).astype('float32')
        a[:,-1]=0
        return a,rng.normal(size=(12,3)).astype('float32'),rng.normal(size=(7,5)).astype('float32')

    def test_learned_projection_matches_full_instrument_pseudoinverse_after_update(self):
        a,w,t=self.inputs();iv=LearnedInstruments(t,a,w,4,8)
        with torch.no_grad():iv.feature_embedding.weight.mul_(1.2)
        base,fitted,residual,_,_=iv.components()
        embedded=iv.feature_embedding(torch.tensor(w))
        for j in range(a.shape[1]):
            z=embedded[torch.tensor(a[:,j]>0)].T
            expected=z @ torch.linalg.pinv(z) @ base[j]
            torch.testing.assert_close(fitted[j],expected,atol=2e-6,rtol=2e-5)
        torch.testing.assert_close(fitted+residual,base)
        torch.testing.assert_close((fitted*residual).sum(1),torch.zeros(len(t)),atol=2e-6,rtol=0)
        iv().square().sum().backward()
        for group in (iv.feature_embedding,iv.phi,iv.alpha_fitted,iv.alpha_residual):
            self.assertGreater(sum(p.grad.abs().sum().item() for p in group.parameters()),0)
        self.assertGreater(iv.gate_columns.grad.abs().sum(),0)

    def test_eq10_coordinate_lift_is_tied_and_has_no_free_bridge(self):
        a,w,t=self.inputs()
        m=PaperExposureIVAE(7,3,2,8,2,t,a,w,4)
        original,fitted,residual,g1,g2=m.iv.components()
        expected=torch.tensor(a)+(torch.tensor(a)@(g1*fitted+g2*residual))@original.T/2
        torch.testing.assert_close(m.reconstructed_input(torch.tensor(a)),expected)
        self.assertFalse(hasattr(m,'exposure_bridge'))
        self.assertEqual(tuple(m.reconstructed_input(torch.tensor(a)).shape),a.shape)
        # The generative decoder still predicts binary exposure, Eq. (44).
        m.dual_elbo(torch.tensor(a),torch.tensor(w)).backward()
        self.assertGreater(m.iv.feature_embedding.weight.grad.abs().sum(),0)

    def test_marginal_bce_integrates_probabilities_before_log_loss(self):
        m=IViDRMarginalMF(1,1,1,embedding_dim=2,sample_size=2)
        with torch.no_grad():
            for p in m.mf.parameters():p.zero_()
            m.item_c.weight.fill_(1)
        m.set_confounders(torch.ones(1,1),torch.full((1,1),2.))
        with patch('torch.randn',return_value=torch.tensor([[[-1.]],[[1.]]])):
            logit=m(torch.tensor([0]),torch.tensor([0]),sample=True)
        probability=torch.sigmoid(torch.tensor([-1.,3.])).mean()
        torch.testing.assert_close(torch.sigmoid(logit),probability[None])
        torch.testing.assert_close(F.binary_cross_entropy_with_logits(logit,torch.ones(1)),-probability.log())
        self.assertGreater(abs(float(probability)-float(torch.sigmoid(torch.tensor(1.)))),.05)

    def test_inference_quadrature_matches_numeric_integral_and_preserves_rng(self):
        m=IViDRMarginalMF(1,1,1,embedding_dim=2,quadrature_points=64)
        with torch.no_grad():
            for p in m.mf.parameters():p.zero_()
            m.item_c.weight.fill_(1)
        m.set_confounders(torch.tensor([[1.]]),torch.tensor([[1.5]]))
        state=torch.get_rng_state().clone()
        probability=float(torch.sigmoid(m(torch.tensor([0]),torch.tensor([0]))).detach())
        target=quad(lambda z:expit(1+1.5*z)*np.exp(-z*z/2)/np.sqrt(2*np.pi),-10,10)[0]
        self.assertAlmostEqual(probability,target,places=6)
        torch.testing.assert_close(state,torch.get_rng_state())
        self.assertFalse(hasattr(m,'get_evaluation_factors'))

    def test_reference_feedback_uses_nonlinear_evaluator_and_reloads_exactly(self):
        data=small_data();mean=torch.ones(data['n_users'],2);std=mean*2
        with tempfile.TemporaryDirectory() as tmp,contextlib.redirect_stdout(io.StringIO()):
            r=train_idcf(data,mean,std,'coat',epochs=2,embedding_dim=4,checkpoint_dir=tmp,
                extra_config={'variant':'ividr_reference_bce_v2'},loss_name='bce')
            saved=load_checkpoint(r['checkpoint_path']);m=IViDRMarginalMF(**saved['metadata']['model_kwargs'])
            m.load_state_dict(saved['model_state_dict'])
            expected=evaluate_unbiased_model(m,data['test_candidates'],data['test_ground_truth'],compute_user_auc=True)
            again=evaluate_checkpoint(r['checkpoint_path'],data,'cpu')
        self.assertEqual(r['metadata']['model'],'ividr_reference')
        self.assertEqual(r['metadata']['architecture_version'],'ividr_reference_bce_v2')
        for key in ('NDCG@5','Recall@5_bounded','AUC'):
            self.assertEqual(r[key],expected[key]);self.assertEqual(r[key],again[key])

    def test_stage1_saves_learned_features_and_reproduces_latents(self):
        a,w,t=self.inputs()
        with tempfile.TemporaryDirectory() as tmp:
            mean,std,info=train_dual_ivae(dict(exposure=a,proxy=w,instrument=w),t,
                epochs=3,batch_size=6,hidden_dim=8,latent_dim=2,treatment_dim=4,
                validation_samples=1,checkpoint_path=tmp+'/stage1.pt',implementation='reference_v2')
            cp=torch.load(tmp+'/stage1.pt',weights_only=True)
            config=cp['model_config']
            m=PaperExposureIVAE(**config,item_embeddings=t,exposure=a,instruments=w).eval()
            m.load_state_dict(cp['model_state_dict'])
            again=m.confounders(torch.tensor(a),torch.tensor(w))
        self.assertEqual(cp['architecture'],'paper_ivae_learned_instruments_v2')
        torch.testing.assert_close(again[0],mean,atol=1e-6,rtol=1e-6)
        torch.testing.assert_close(again[1],std,atol=1e-6,rtol=1e-6)
        self.assertTrue(info['eq10_completion_is_local'])


if __name__=='__main__':unittest.main()
