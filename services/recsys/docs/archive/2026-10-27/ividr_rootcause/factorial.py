"""Coat root-cause factorial: swap stage-1 latents and feedback heads between iDCF and IViDR.

Usage (from services/recsys): python docs/archive/2026-10-27/ividr_rootcause/factorial.py CELL SEED
CELL:
  idcf_lat+bce     iDCF latents, IViDR feedback (marginal BCE, paper grid, patience 20)
  ividr_lat+mse    IViDR v2 latents, iDCF feedback (MSE MFMF, iDCF Coat config)
  ividr_mean+bce   IViDR latents with the mean of the two posteriors ((C1+C2)/2) instead of .9C1+.9C2
  ividr_center+bce IViDR latents centred per dimension (removes the large shared offset), IViDR feedback
Latents are read from the saved seed checkpoints; only the feedback stage is trained.
Feedback selection is validation NDCG@5; test is evaluated once for reporting.
"""
import glob
import json
import sys
import time
from pathlib import Path

import torch

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
from src.data_pipeline.coat_dataset import load_coat_processed
from src.models.idcf.train_idcf import IDCF_CONFIG, train_idcf
from src.models.ividr.train_ividr import PAPER_FEEDBACK_GRID
from src.utils.artifacts import evaluate_checkpoint, source_signature

cell, seed = sys.argv[1], int(sys.argv[2])
torch.set_num_threads(2)
started, code = time.time(), source_signature()
data = load_coat_processed()
out_dir = ROOT / 'checkpoints/ividr_rootcause_20261027'
ividr_report = json.loads((ROOT / f'results/ividr_opt_tied_item_lift_full_seed{seed}_20261027.json').read_text())
stage1 = torch.load(ividr_report['stage1']['checkpoint_path'], map_location='cpu', weights_only=False)
idcf_path, = glob.glob(str(ROOT / f'checkpoints/lcdr_idcf_reference/coat_idcf_full_e100_r2000_seed{seed}_v4_*.pt'))
idcf_state = torch.load(idcf_path, map_location='cpu', weights_only=False)['model_state_dict']

if cell == 'idcf_lat+bce':
    mean, std, head = idcf_state['c_mean'], idcf_state['c_std'], 'bce'
elif cell in ('ividr_lat+mse', 'ividr_mean+bce', 'ividr_center+bce'):
    mean, std = stage1['confounder_mean'], stage1['confounder_std']
    head = 'mse' if cell == 'ividr_lat+mse' else 'bce'
    if cell == 'ividr_mean+bce':
        # .9C1+.9C2 -> (C1+C2)/2; std sqrt(.81v1+.81v2) -> sqrt(.25v1+.25v2) (same ratio).
        mean, std = mean / 1.8, std * (.5 / .9)
    if cell == 'ividr_center+bce':
        mean = mean - mean.mean(0, keepdim=True)
else:
    raise SystemExit(f'Unknown cell {cell}')

config = dict(IDCF_CONFIG['coat']['train'])
if head == 'mse':
    grid, extra, loss = [(config['lr'], config['weight_decay'])], {'variant': 'idcf', 'rootcause_cell': cell}, 'mse'
else:
    config['patience'] = 20
    grid, loss = PAPER_FEEDBACK_GRID, 'bce'
    extra = {'variant': 'ividr_reference_bce_v2', 'rootcause_cell': cell, 'phi': 1., 'lambda_mf': 1.}
trials, winner = [], None
for trial, (lr, wd) in enumerate(grid):
    result = train_idcf(data, mean, std, 'coat', seed=seed, epochs=100, evaluate_test=False, checkpoint_dir=str(out_dir),
                        checkpoint_tag=f'{cell.replace("+", "_")}_seed{seed}_t{trial}', device='cpu', extra_config=extra,
                        loss_name=loss, **dict(config, lr=lr, weight_decay=wd))
    trials.append(dict(lr=lr, weight_decay=wd, best_epoch=result['best_epoch'], best_val_ndcg=result['best_val_ndcg']))
    if winner is None or result['best_val_ndcg'] > winner['best_val_ndcg']:
        winner = result
test = evaluate_checkpoint(winner['checkpoint_path'], data)
assert source_signature() == code
latent = dict(mean_abs=float(mean.abs().mean()), std_mean=float(std.mean()),
              snr=float((mean.abs() / std).mean()))
report = dict(cell=cell, seed=seed, code_sha256=code, latent=latent, trials=trials,
              val_ndcg=winner['best_val_ndcg'], test={k: test[k] for k in ('NDCG@5', 'Recall@5', 'Recall@5_bounded', 'best_epoch')},
              ividr_stage1=ividr_report['stage1']['checkpoint_path'], idcf_reference=idcf_path,
              seconds=time.time() - started, selection='validation NDCG@5 only')
path = ROOT / f'results/ividr_rootcause_{cell.replace("+", "_")}_seed{seed}_20261027.json'
with path.open('x', encoding='utf-8') as stream:
    json.dump(report, stream, indent=2)
print(json.dumps(dict(cell=cell, seed=seed, val=report['val_ndcg'], test=report['test']['NDCG@5'], **latent)))
