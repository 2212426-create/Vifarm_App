"""Coat: stage-2 LR x weight-decay grid from the LCDR paper (Sec. 5.1), for LCDR and for iDCF alike.

Usage (from services/recsys): python docs/archive/2026-10-28/lcdr_constraint/grid.py MODEL SEED
MODEL: lcdr | idcf. Stage 1 is the project default (LCDR: lambda .9, L2 not squared, Z detached).
Grid lr {1e-3, 5e-4, 1e-4, 5e-5, 1e-5} x wd {1e-5, 1e-6}; the project default is lr 5e-4, wd 1e-6.
The configuration is chosen by validation NDCG@5 only. Test is stored for every cell for the record,
but only the validation-selected cell is the reported result.
"""
import json
import sys
import time
from pathlib import Path

import torch

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
from src.data_pipeline.coat_dataset import load_coat_processed
from src.models.idcf.train_idcf import fit_idcf_pipeline
from src.models.lcdr.train_lcdr import fit_lcdr_pipeline
from src.utils.artifacts import source_signature

LRS, WDS = (1e-3, 5e-4, 1e-4, 5e-5, 1e-5), (1e-5, 1e-6)
model, seed = sys.argv[1], int(sys.argv[2])
fit = {'lcdr': fit_lcdr_pipeline, 'idcf': fit_idcf_pipeline}[model]
torch.set_num_threads(2)
started, code, data = time.time(), source_signature(), load_coat_processed()
cells = []
for lr in LRS:
    for wd in WDS:
        result = fit(data, 'coat', seed=seed, train_overrides=dict(lr=lr, weight_decay=wd), device='cpu',
                     checkpoint_dir=str(ROOT / 'checkpoints/lcdr_grid_20261028'),
                     checkpoint_tag=f'{model}_lr{lr:g}_wd{wd:g}_seed{seed}')
        cells.append(dict(lr=lr, weight_decay=wd, val=result['best_val_ndcg'], test=result['NDCG@5'],
                          recall=result['Recall@5'], best_epoch=result['best_epoch']))
        print(json.dumps(cells[-1]), flush=True)
assert source_signature() == code
chosen = max(cells, key=lambda cell: cell['val'])
report = dict(model=model, seed=seed, code_sha256=code, chosen=chosen, cells=cells, seconds=time.time() - started,
              selection='validation NDCG@5 only; test reported once for the chosen cell')
out = ROOT / f'results/lcdr_grid_{model}_seed{seed}_20261028.json'
with out.open('x', encoding='utf-8') as stream:
    json.dump(report, stream, indent=2)
print(json.dumps(dict(model=model, seed=seed, chosen=chosen)))
