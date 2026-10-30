"""IViDR feedback (marginal BCE, Eq. 25) with down-weighted negatives, on saved stage-1 latents.

Usage (from services/recsys): python docs/archive/2026-10-28/ividr_bce/ividr_weighted.py LATENTS NEG_WEIGHT SEED
LATENTS: ividr (v2 stage-1 checkpoints of 27/10) | idcf (iDCF latents of the same seeds)
Paper LR x WD grid, patience 20, 100 epochs; selection by validation NDCG@5; test once.
"""
import glob
import json
import sys
from pathlib import Path

import torch

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
from src.data_pipeline.coat_dataset import load_coat_processed
from src.models.idcf.train_idcf import IDCF_CONFIG, train_idcf
from src.models.ividr.train_ividr import PAPER_FEEDBACK_GRID
from src.utils.artifacts import evaluate_checkpoint, source_signature

latents, negative_weight, seed = sys.argv[1], float(sys.argv[2]), int(sys.argv[3])
torch.set_num_threads(2)
code = source_signature()
data = load_coat_processed()
if latents == 'ividr':
    report = json.loads((ROOT / f'results/ividr_opt_tied_item_lift_full_seed{seed}_20261027.json').read_text())
    stage1 = torch.load(report['stage1']['checkpoint_path'], map_location='cpu', weights_only=False)
    mean, std, source = stage1['confounder_mean'], stage1['confounder_std'], report['stage1']['checkpoint_path']
else:
    source, = glob.glob(str(ROOT / f'checkpoints/lcdr_idcf_reference/coat_idcf_full_e100_r2000_seed{seed}_v4_*.pt'))
    state = torch.load(source, map_location='cpu', weights_only=False)['model_state_dict']
    mean, std = state['c_mean'], state['c_std']
config = dict(IDCF_CONFIG['coat']['train'], patience=20)
extra = {'variant': 'ividr_reference_bce_v2', 'phi': 1., 'lambda_mf': 1., 'diagnostic': 'weighted_negative_bce'}
trials, winner = [], None
for trial, (lr, wd) in enumerate(PAPER_FEEDBACK_GRID):
    result = train_idcf(data, mean, std, 'coat', seed=seed, epochs=100, evaluate_test=False, device='cpu',
                        checkpoint_dir=str(ROOT / 'checkpoints/ividr_bce_20261028'),
                        checkpoint_tag=f'{latents}_neg{negative_weight:g}_seed{seed}_t{trial}', extra_config=extra,
                        loss_name='bce', negative_weight=negative_weight, **dict(config, lr=lr, weight_decay=wd))
    trials.append(dict(lr=lr, weight_decay=wd, best_epoch=result['best_epoch'], best_val_ndcg=result['best_val_ndcg'],
                       checkpoint_path=result['checkpoint_path']))
    if winner is None or result['best_val_ndcg'] > winner['best_val_ndcg']:
        winner = result
test = evaluate_checkpoint(winner['checkpoint_path'], data)
assert source_signature() == code
out = ROOT / f'results/ividr_bce_weighted_{latents}_neg{negative_weight:g}_seed{seed}_20261028.json'
with out.open('x', encoding='utf-8') as stream:
    json.dump(dict(latents=latents, latent_source=source, negative_weight=negative_weight, seed=seed, code_sha256=code,
                   trials=trials, val_ndcg=winner['best_val_ndcg'],
                   test={k: test[k] for k in ('NDCG@5', 'Recall@5', 'Recall@5_bounded', 'best_epoch', 'checkpoint_path')},
                   selection='validation NDCG@5 only'), stream, indent=2)
print(json.dumps(dict(latents=latents, neg=negative_weight, seed=seed, val=winner['best_val_ndcg'], test=test['NDCG@5'])))
