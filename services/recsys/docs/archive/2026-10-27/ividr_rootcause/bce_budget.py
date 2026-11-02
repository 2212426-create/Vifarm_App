"""Hypothesis test: is the marginal-BCE feedback head under-trained by the paper's LR grid?

Only the feedback optimizer budget changes: LR above the paper grid (max 1e-3) and up to 300
epochs, patience 20, weight decay 1e-6. Latents are fixed from saved checkpoints.
Usage: python docs/archive/2026-10-27/ividr_rootcause/bce_budget.py LATENTS LR SEED
LATENTS: idcf | ividr | zero (pure MF + BCE head, latent term disabled)
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
from src.utils.artifacts import evaluate_checkpoint, source_signature

latents, lr, seed = sys.argv[1], float(sys.argv[2]), int(sys.argv[3])
torch.set_num_threads(2)
code = source_signature()
data = load_coat_processed()
if latents == 'idcf':
    path, = glob.glob(str(ROOT / f'checkpoints/lcdr_idcf_reference/coat_idcf_full_e100_r2000_seed{seed}_v4_*.pt'))
    state = torch.load(path, map_location='cpu', weights_only=False)['model_state_dict']
    mean, std = state['c_mean'], state['c_std']
elif latents == 'ividr':
    report = json.loads((ROOT / f'results/ividr_opt_tied_item_lift_full_seed{seed}_20261027.json').read_text())
    stage1 = torch.load(report['stage1']['checkpoint_path'], map_location='cpu', weights_only=False)
    mean, std = stage1['confounder_mean'], stage1['confounder_std']
else:
    mean = std = torch.zeros(data['n_users'], 16)
config = dict(IDCF_CONFIG['coat']['train'], patience=20, lr=lr, weight_decay=1e-6)
extra = {'variant': 'ividr_reference_bce_v2', 'rootcause_cell': f'bce_budget_{latents}', 'phi': 1., 'lambda_mf': 1.}
result = train_idcf(data, mean, std, 'coat', seed=seed, epochs=300, evaluate_test=False, device='cpu',
                    checkpoint_dir=str(ROOT / 'checkpoints/ividr_rootcause_20261027'),
                    checkpoint_tag=f'bce_budget_{latents}_lr{lr:g}_seed{seed}', extra_config=extra, loss_name='bce', **config)
test = evaluate_checkpoint(result['checkpoint_path'], data)
assert source_signature() == code
report = dict(latents=latents, lr=lr, weight_decay=1e-6, max_epochs=300, seed=seed, code_sha256=code,
              val_ndcg=result['best_val_ndcg'], best_epoch=result['best_epoch'], epochs_run=result['epochs_run'],
              test={k: test[k] for k in ('NDCG@5', 'Recall@5', 'Recall@5_bounded')})
out = ROOT / f'results/ividr_rootcause_bce_budget_{latents}_lr{lr:g}_seed{seed}_20261027.json'
with out.open('x', encoding='utf-8') as stream:
    json.dump(report, stream, indent=2)
print(json.dumps(dict(latents=latents, lr=lr, seed=seed, val=report['val_ndcg'], test=test['NDCG@5'],
                      epoch=report['best_epoch'])))
