"""Hypothesis test: logistic (BCE) MF on Coat needs stronger regularization than the paper grid.

Pure MF through the IViDR marginal-BCE head with latents disabled (zeros), so this is exactly the
feedback model of Eq. (23)-(25) without C. Adam, LR 1e-3, up to 300 epochs, patience 20.
Only embedding dimension and weight decay vary. Selection: validation NDCG@5; test once.
Usage (from services/recsys): python docs/archive/2026-10-28/ividr_bce/mf_bce.py DIM WD SEED
"""
import json
import sys
from pathlib import Path

import torch

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
from src.data_pipeline.coat_dataset import load_coat_processed
from src.models.idcf.train_idcf import IDCF_CONFIG, train_idcf
from src.utils.artifacts import evaluate_checkpoint, source_signature

dim, wd, seed = int(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3])
torch.set_num_threads(2)
code = source_signature()
data = load_coat_processed()
zeros = torch.zeros(data['n_users'], 16)
config = dict(IDCF_CONFIG['coat']['train'], patience=20, lr=1e-3, weight_decay=wd, embedding_dim=dim)
extra = {'variant': 'ividr_reference_bce_v2', 'rootcause_cell': 'mf_bce_regularization', 'phi': 1., 'lambda_mf': 1.}
result = train_idcf(data, zeros, zeros, 'coat', seed=seed, epochs=300, evaluate_test=False, device='cpu',
                    checkpoint_dir=str(ROOT / 'checkpoints/ividr_bce_20261028'),
                    checkpoint_tag=f'mf_bce_d{dim}_wd{wd:g}_seed{seed}', extra_config=extra, loss_name='bce', **config)
test = evaluate_checkpoint(result['checkpoint_path'], data)
assert source_signature() == code
report = dict(model='MF+BCE (IViDR head, C disabled)', dim=dim, weight_decay=wd, lr=1e-3, seed=seed, code_sha256=code,
              val_ndcg=result['best_val_ndcg'], best_epoch=result['best_epoch'], epochs_run=result['epochs_run'],
              test={k: test[k] for k in ('NDCG@5', 'Recall@5', 'Recall@5_bounded')})
out = ROOT / f'results/ividr_bce_mf_d{dim}_wd{wd:g}_seed{seed}_20261028.json'
with out.open('x', encoding='utf-8') as stream:
    json.dump(report, stream, indent=2)
print(json.dumps(dict(dim=dim, wd=wd, seed=seed, val=report['val_ndcg'], test=test['NDCG@5'], epoch=report['best_epoch'])))
