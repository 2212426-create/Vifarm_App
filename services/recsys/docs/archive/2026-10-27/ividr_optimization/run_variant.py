"""Coat IViDR variant run: MF treatment, IViDR stage1/feedback, Eq. (10) diagnostics.

Usage (from services/recsys): python docs/archive/2026-10-27/ividr_optimization/run_variant.py VARIANT SEED
VARIANT = BRIDGE:RECONSTRUCTION, e.g. tied_item_lift:full (v2) or tied_item_lift_rownorm:fitted.
Checkpoint selection is validation-only inside fit_ividr_pipeline; test is computed once
for reporting and never used to pick a variant.
"""
import json
import sys
import time
from pathlib import Path

import numpy as np
import torch

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
from src.data_pipeline.coat_dataset import load_coat_processed
from src.models.idcf.ivae import binary_exposure
from src.models.idcf.train_idcf import DATASET_INPUTS
from src.models.ividr.ividr_reference import PaperExposureIVAE
from src.models.ividr.ividr_staged import mf_item_embeddings
from src.models.ividr.train_ividr import fit_ividr_pipeline
from src.models.mf.train_mf import train_baseline_mf
from src.training.config import mf_config
from src.utils.artifacts import source_signature

bridge, reconstruction = sys.argv[1].split(':')
seed = int(sys.argv[2])
torch.set_num_threads(2)
started = time.time()
code = source_signature()
checkpoints = ROOT / 'checkpoints/ividr_optimization_20261027'
data = load_coat_processed()
mf = train_baseline_mf(dataset_name='coat', data_dict=data, seed=seed, checkpoint_dir=str(checkpoints),
                       evaluate_test=False, checkpoint_tag=f'treatment_seed{seed}', **mf_config('coat'))
item_emb = mf_item_embeddings(mf['checkpoint_path'])
result = fit_ividr_pipeline(data, 'coat', seed=seed, item_emb=item_emb, checkpoint_dir=str(checkpoints),
                            checkpoint_tag=f'{bridge}_{reconstruction}_seed{seed}', device='cpu',
                            ivae_overrides=dict(eq10_bridge=bridge, reconstruction=reconstruction))

info = result['confounder_info']
state = torch.load(info['checkpoint_path'], map_location='cpu', weights_only=False)
inputs = DATASET_INPUTS['coat'](data)
config = state['model_config']
model = PaperExposureIVAE(config['n_items'], config['aux_dim'], config['latent_dim'], config['hidden_dim'],
                          config['n_layers'], item_emb, inputs['exposure'], inputs['instrument'],
                          config['treatment_dim'], config['eq10_bridge'], config['reconstruction'])
model.load_state_dict(state['model_state_dict'])
model.eval()
a = torch.as_tensor(np.asarray(binary_exposure(inputs['exposure'])), dtype=torch.float32)
w = torch.as_tensor(np.asarray(inputs['proxy']), dtype=torch.float32)
with torch.no_grad():
    x_re = model.reconstructed_input(a)
    m1, _, m2, _ = model.posteriors(a, w)
    _, _, _, alpha, beta = model.iv.components()
diagnostics = dict(
    perturbation_ratio=float((x_re - a).norm() / a.norm()),
    posterior_mean_cosine=float(torch.nn.functional.cosine_similarity(m1.flatten(), m2.flatten(), dim=0)),
    posterior_mean_relative_difference=float((m1 - m2).norm() / m2.norm()),
    gate_fitted=dict(mean=float(alpha.mean()), min=float(alpha.min()), max=float(alpha.max())),
    gate_residual=dict(mean=float(beta.mean()), min=float(beta.min()), max=float(beta.max())),
    exposure='biased training exposure only')
assert source_signature() == code
keep = ('NDCG@5', 'Recall@5', 'Recall@5_bounded', 'Precision@5', 'HitRate@5', 'AUC', 'best_epoch', 'best_val_ndcg',
        'checkpoint_path')
report = dict(dataset='coat', seed=seed, eq10_bridge=bridge, reconstruction=reconstruction, code_sha256=code,
              mf_treatment_checkpoint=mf['checkpoint_path'], test={k: result[k] for k in keep if k in result},
              validation_search=result['validation_search'],
              stage1=dict(best_epoch=info['best_epoch'], epochs_run=info['epochs_run'],
                          best_val_loss=info['best_val_loss'], checkpoint_path=info['checkpoint_path']),
              diagnostics=diagnostics, seconds=time.time() - started,
              selection='validation NDCG@5 only; test reported once')
out = ROOT / f'results/ividr_opt_{bridge}_{reconstruction}_seed{seed}_20261027.json'
with out.open('x', encoding='utf-8') as stream:
    json.dump(report, stream, indent=2)
print(json.dumps(dict(out=str(out), val=result['best_val_ndcg'], test=result['NDCG@5'],
                      **{k: diagnostics[k] for k in ('perturbation_ratio', 'posterior_mean_cosine')}), indent=2))
