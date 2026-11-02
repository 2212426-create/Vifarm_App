"""LCDR on Coat: choices the paper leaves open in the Eq. (6) constraint lambda * ||Z_lc - Z||.

Usage (from services/recsys): python docs/archive/2026-10-28/lcdr_constraint/run.py VARIANT SEED
VARIANT:
  squared   lambda * ||Z_lc - Z||_2^2 (project default: not squared)
  shared    gradient of the constraint also reaches the iVAE (project default: Z detached)
  lambda10  lambda = 10 instead of the paper's .9, same norm and detach as the project
Baseline (project default) for seeds 42/43/44 is in results/lcdr_coat_20261027_220934_6395e1a8.json;
seed 42 reproduced exactly on 28/10 (results/lcdr_coat_20261028_081517_b71fff26.json).
Everything else is fit_lcdr_pipeline. Selection is validation NDCG@5 inside the pipeline; test is
reported once and must not be used to choose a variant.
"""
import inspect
import json
import sys
import textwrap
import time
from pathlib import Path

import torch

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
from src.data_pipeline.coat_dataset import load_coat_processed
from src.models.lcdr import lcvae as lcvae_module
from src.models.lcdr import train_lcdr
from src.utils.artifacts import source_signature

variant, seed = sys.argv[1], int(sys.argv[2])
if variant not in ('squared', 'shared', 'lambda10'):
    raise SystemExit(f'Unknown variant {variant}')
torch.set_num_threads(2)
started, code = time.time(), source_signature()
overrides = {}
if variant == 'squared':
    def squared_loss(a, a_hat, mean, log_var, z_lc, z, constraint_weight, anneal=1.0):
        recon = torch.nn.functional.binary_cross_entropy_with_logits(a_hat, a, reduction="none").sum(1).mean()
        kld = -0.5 * torch.sum(1 + log_var - mean.pow(2) - log_var.exp(), 1).mean()
        constraint = (z_lc - z).pow(2).sum(1).mean()
        return recon + kld * anneal + constraint_weight * constraint, constraint
    lcvae_module.lcvae_loss = squared_loss
if variant == 'shared':
    source = textwrap.dedent(inspect.getsource(lcvae_module.train_lcdr_representations))
    for old, new in (('torch.randn_like(mean_i)).detach()', 'torch.randn_like(mean_i))'),
                     ('z_gradient="detached"', 'z_gradient="shared"')):
        assert source.count(old) == 1, old
        source = source.replace(old, new)
    exec(compile(source, lcvae_module.__file__, 'exec'), lcvae_module.__dict__)
    train_lcdr.train_lcdr_representations = lcvae_module.train_lcdr_representations
if variant == 'lambda10':
    overrides = dict(constraint_weight=10.)
result = train_lcdr.fit_lcdr_pipeline(load_coat_processed(), 'coat', seed=seed, representation_overrides=overrides,
                                      checkpoint_dir=str(ROOT / 'checkpoints/lcdr_constraint_20261028'),
                                      checkpoint_tag=f'{variant}_seed{seed}', device='cpu')
assert source_signature() == code
info = result['representation_info']
keep = ('NDCG@5', 'Recall@5', 'Recall@5_bounded', 'Precision@5', 'HitRate@5', 'AUC', 'best_epoch', 'best_val_ndcg',
        'checkpoint_path')
report = dict(variant=variant, seed=seed, code_sha256=code, test={k: result[k] for k in keep if k in result},
              representation={k: info[k] for k in ('best_val_loss', 'best_val_parts', 'best_epoch', 'epochs_run')},
              seconds=time.time() - started, selection='validation NDCG@5 only; test reported once')
out = ROOT / f'results/lcdr_constraint_{variant}_seed{seed}_20261028.json'
with out.open('x', encoding='utf-8') as stream:
    json.dump(report, stream, indent=2)
print(json.dumps(dict(variant=variant, seed=seed, val=result['best_val_ndcg'], test=result['NDCG@5'],
                      constraint=info['best_val_parts']['constraint'])))
