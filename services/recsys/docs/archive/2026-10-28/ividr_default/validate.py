"""Fresh three-seed CDR validation after the IViDR default change of 28/10/2026."""
import json
from pathlib import Path
import sys
import torch

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
from src.utils.artifacts import source_signature
from src.models.cdr.train_released_cdr import train_released_cdr
from src.data_pipeline.coat_dataset import load_coat_processed

torch.set_num_threads(2)
code = source_signature()
previous = json.loads((ROOT / 'results/ividr_zero_prior_validation_20261028.json').read_text())
data = load_coat_processed(pos_threshold=3)
runs = []
for old in previous['runs']:
    seed = old['seed']
    result = train_released_cdr('coat', data, seed=seed, evaluate_test=False, device='cpu',
        selection='source_train_loss_last', calibration_fraction=.05,
        checkpoint_dir=ROOT / 'checkpoints/ividr_default_validation_20261028',
        checkpoint_tag=f'seed{seed}')
    assert (result['best_epoch'], result['best_val_ndcg']) == (old['best_epoch'], old['best_val_ndcg'])
    runs.append(dict(seed=seed, **result))
assert source_signature() == code
with (ROOT / 'results/ividr_default_validation_20261028.json').open('x', encoding='utf-8') as stream:
    json.dump(dict(identity=dict(code_sha256=code), runs=runs,
        evaluation='validation_only_no_held_out_test',
        previous_validation='results/ividr_zero_prior_validation_20261028.json',
        regression='Exact validation scores and selected epochs after the IViDR default change'), stream, indent=2)
