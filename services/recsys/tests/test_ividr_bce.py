"""Equation checks, real gradient flow and complete IViDR checkpoint reload."""
import contextlib
import io
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import torch
from scipy.sparse import csr_matrix

from src.causal.idcf.ividr_model import IVTreatment, DualExposureIVAE, instrument_bases
from src.causal.idcf.train_ividr import train_dual_ivae, fit_ividr_pipeline
from src.causal.idcf.train_idcf import train_idcf
from src.utils.artifacts import evaluate_checkpoint, load_checkpoint
from test_review_fixes import small_data


class LearnedIVTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        torch.set_num_threads(2)

    def test_projection_equals_pseudoinverse_for_actual_item_user_columns(self):
        a=np.array([[1,0,1],[1,1,0],[0,1,1],[0,0,0]],dtype=float)
        w=np.array([[1,0,0],[0,1,0],[0,0,1],[100,100,100]],dtype=float)
        q,z,info=instrument_bases(a,w,4,seed=7)
        transform=np.random.default_rng(7).normal(size=(3,4))/np.sqrt(3)
        for j in range(3):
            columns=(w[a[:,j]>0]@transform).T
            expected=columns@np.linalg.pinv(columns)
            np.testing.assert_allclose(q[j].numpy()@q[j].numpy().T,expected,atol=2e-6)
            np.testing.assert_allclose(z[j],columns.mean(1),atol=2e-6)
        sparse_q,_,_=instrument_bases(csr_matrix(a),w,4,seed=7)
        torch.testing.assert_close(q,sparse_q)

    def test_both_gates_and_phi_receive_gradients_and_residual_is_orthogonal(self):
        torch.manual_seed(8)
        q=torch.zeros(3,4,1);q[:,0,0]=1
        iv=IVTreatment(torch.randn(3,5),q,torch.randn(3,4),8)
        fitted,residual,_,_=iv.components()
        torch.testing.assert_close((fitted*residual).sum(1),torch.zeros(3),atol=1e-6,rtol=0)
        iv().square().sum().backward()
        for group in (iv.phi,iv.alpha_fitted,iv.alpha_residual):
            self.assertGreater(sum(p.grad.abs().sum().item() for p in group.parameters()),0)

    def test_eval_is_deterministic_and_projection_has_optimizer_and_checkpoint_state(self):
        rng=np.random.default_rng(1)
        a=(rng.random((10,6))>.5).astype('float32');w=rng.normal(size=(10,3)).astype('float32')
        q,z,_=instrument_bases(a,w,4)
        m=DualExposureIVAE(6,3,2,8,2,rng.normal(size=(6,5)),q,z).eval()
        x,features=torch.tensor(a),torch.tensor(w)
        before=set(m.state_dict())
        a1=m.confounders(x,features);a2=m.confounders(x,features)
        for x1,x2 in zip(a1,a2):torch.testing.assert_close(x1,x2,atol=0,rtol=0)
        optimizer=torch.optim.Adam(m.parameters())
        known={id(p) for g in optimizer.param_groups for p in g['params']}
        self.assertIn(id(m.exposure_bridge.weight),known)
        m.dual_elbo(x,features).backward()
        self.assertGreater(m.exposure_bridge.weight.grad.abs().sum(),0)
        self.assertEqual(before,set(m.state_dict()))
        copy_model=DualExposureIVAE(6,3,2,8,2,np.zeros((6,5)),q,z)
        copy_model.load_state_dict(m.state_dict());copy_model.eval()
        for x1,x2 in zip(a1,copy_model.confounders(x,features)):
            torch.testing.assert_close(x1,x2,atol=0,rtol=0)

    def test_dual_training_exports_registered_reconstruction_and_finite_latents(self):
        rng=np.random.default_rng(9)
        a=(rng.random((12,8))>.5).astype('float32');w=rng.normal(size=(12,3)).astype('float32')
        with tempfile.TemporaryDirectory() as tmp:
            mean,std,info=train_dual_ivae(dict(exposure=csr_matrix(a),proxy=w,instrument=w),
                rng.normal(size=(8,5)),epochs=3,batch_size=6,hidden_dim=8,latent_dim=2,
                treatment_dim=4,checkpoint_path=tmp+'/stage1.pt',validation_samples=2)
            saved=torch.load(tmp+'/stage1.pt',weights_only=True)
        self.assertEqual(tuple(mean.shape),(12,2))
        self.assertTrue(torch.isfinite(mean).all() and (std>0).all())
        self.assertIn('exposure_bridge.weight',saved['model_state_dict'])
        self.assertTrue(info['learned_reconstruction'])

    def test_bce_is_explicit_and_old_idcf_keeps_mse(self):
        data=small_data()
        mean=torch.zeros(data['n_users'],2);std=torch.zeros_like(mean)
        with tempfile.TemporaryDirectory() as tmp,contextlib.redirect_stdout(io.StringIO()):
            result=train_idcf(data,mean,std,'coat',epochs=1,embedding_dim=4,
                checkpoint_dir=tmp,extra_config={'variant':'ividr_equations_bce'},loss_name='bce')
            again=evaluate_checkpoint(result['checkpoint_path'],data,'cpu')
            checkpoint=load_checkpoint(result['checkpoint_path'])
            original=train_idcf(data,mean,std,'coat',epochs=1,embedding_dim=4,checkpoint_dir=tmp)
        self.assertEqual(result['metadata']['model'],'ividr_bce')
        self.assertEqual(result['metadata']['config']['loss'],'bce')
        self.assertEqual(result['NDCG@5'],again['NDCG@5'])
        self.assertIn('c_mean',checkpoint['model_state_dict'])
        self.assertEqual(original['metadata']['config']['loss'],'mse')
        with self.assertRaises(ValueError):train_idcf(data,mean,std,loss_name='bce')

    def test_full_pipeline_does_not_read_held_out_test_until_final_selection(self):
        data=small_data();n,m=data['n_users'],data['n_items']
        rng=np.random.default_rng(3)
        inputs=dict(exposure=np.ones((n,m)),proxy=rng.normal(size=(n,3)),instrument=rng.normal(size=(n,3)))
        def forbidden(*args,**kwargs):raise AssertionError('Held-out evaluation called')
        from src.causal.idcf import train_idcf as trainer
        with tempfile.TemporaryDirectory() as tmp,contextlib.redirect_stdout(io.StringIO()), \
                patch.dict(trainer.DATASET_INPUTS,{'coat':lambda d:inputs}), \
                patch('src.utils.artifacts.evaluate_checkpoint',side_effect=forbidden):
            result=fit_ividr_pipeline(data,'coat',item_emb=rng.normal(size=(m,4)),
                epochs=1,ivae_epochs=2,evaluate_test=False,checkpoint_dir=tmp,
                ivae_overrides={'hidden_dim':8,'latent_dim':2,'validation_samples':1})
        self.assertFalse(result['validation_search']['test_used_for_selection'])
        self.assertEqual(len(result['validation_search']['trials']),1)

    def test_published_grid_selects_by_validation_and_reads_test_only_for_winner(self):
        data=small_data();n,m=data['n_users'],data['n_items']
        from src.causal.idcf import train_idcf as trainer
        def trial(*args,**kwargs):
            self.assertFalse(kwargs['evaluate_test'])
            self.assertEqual(kwargs['loss_name'],'bce')
            return dict(best_epoch=1,best_val_ndcg=1. if kwargs['lr']==5e-4 else 0.,
                checkpoint_path=str(kwargs['lr'])+'_'+str(kwargs['weight_decay']))
        with tempfile.TemporaryDirectory() as tmp,contextlib.redirect_stdout(io.StringIO()), \
                patch.dict(trainer.DATASET_INPUTS,{'coat':lambda d:{}}), \
                patch('src.causal.idcf.train_ividr.train_dual_ivae',return_value=(torch.zeros(n,2),torch.ones(n,2),{})), \
                patch.object(trainer,'train_idcf',side_effect=trial) as fit, \
                patch('src.utils.artifacts.evaluate_checkpoint',return_value={}) as test:
            result=fit_ividr_pipeline(data,'coat',item_emb=np.zeros((m,4)),epochs=20,checkpoint_dir=tmp)
        self.assertEqual(fit.call_count,10)
        self.assertEqual(test.call_count,1)
        self.assertEqual(test.call_args.args[0],'0.0005_1e-05')
        self.assertEqual(len(result['validation_search']['trials']),10)


if __name__=='__main__':unittest.main()
