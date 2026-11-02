"""IViDR with an iDCF-style zero prior mean in stage 1, then marginal BCE with weighted negatives.

Deviates from Eq. (42) (learned prior mean) at the user's request on 28/10/2026.
Usage (from services/recsys): python docs/archive/2026-10-28/ividr_bce/ividr_zero_prior.py NEG_WEIGHT SEED
Stage 1 is retrained (v2 Eq. 10 bridge, prior mean 0); feedback uses the paper LR x WD grid,
selection by validation NDCG@5; test once.
"""
import json
import sys
import time
from pathlib import Path

import torch

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
from src.data_pipeline.coat_dataset import load_coat_processed
from src.models.ividr.ividr_staged import mf_item_embeddings
from src.models.ividr.train_ividr import fit_ividr_pipeline
from src.models.mf.train_mf import train_baseline_mf
from src.training.config import mf_config
from src.utils.artifacts import source_signature

negative_weight, seed = float(sys.argv[1]), int(sys.argv[2])
torch.set_num_threads(2)
started, code = time.time(), source_signature()
checkpoints = ROOT / 'checkpoints/ividr_bce_20261028'
data = load_coat_processed()
mf = train_baseline_mf(dataset_name='coat', data_dict=data, seed=seed, checkpoint_dir=str(checkpoints),
                       evaluate_test=False, checkpoint_tag=f'treatment_seed{seed}', **mf_config('coat'))
result = fit_ividr_pipeline(data, 'coat', seed=seed, item_emb=mf_item_embeddings(mf['checkpoint_path']),
                            checkpoint_dir=str(checkpoints), checkpoint_tag=f'zero_prior_neg{negative_weight:g}_seed{seed}',
                            device='cpu', ivae_overrides=dict(prior_mean='zero'), negative_weight=negative_weight)
info = result['confounder_info']
stage1 = torch.load(info['checkpoint_path'], map_location='cpu', weights_only=False)
mean, std = stage1['confounder_mean'], stage1['confounder_std']
assert source_signature() == code
keep = ('NDCG@5', 'Recall@5', 'Recall@5_bounded', 'best_epoch', 'best_val_ndcg', 'checkpoint_path')
report = dict(prior_mean='zero', negative_weight=negative_weight, seed=seed, code_sha256=code,
              test={k: result[k] for k in keep}, validation_search=result['validation_search'],
              stage1=dict(best_epoch=info['best_epoch'], epochs_run=info['epochs_run'], checkpoint_path=info['checkpoint_path']),
              latent=dict(mean_abs=float(mean.abs().mean()), std_mean=float(std.mean())),
              seconds=time.time() - started, selection='validation NDCG@5 only')
out = ROOT / f'results/ividr_bce_zero_prior_neg{negative_weight:g}_seed{seed}_20261028.json'
with out.open('x', encoding='utf-8') as stream:
    json.dump(report, stream, indent=2)
print(json.dumps(dict(neg=negative_weight, seed=seed, val=result['best_val_ndcg'], test=result['NDCG@5'], **report['latent'])))
