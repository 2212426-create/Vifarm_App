"""Fresh three-seed CDR validation after adding NDCG@5/Recall@5 to MRDR-CAL (08/11/2026)."""
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
previous = json.loads((ROOT / 'docs/state_snapshot.json').read_text(encoding='utf-8'))['independent_cdr_validation']
data = load_coat_processed(pos_threshold=3)
runs = []
for old in previous:
    seed = old['seed']
    result = train_released_cdr('coat', data, seed=seed, evaluate_test=False, device='cpu',
        selection='source_train_loss_last', calibration_fraction=.05,
        checkpoint_dir=ROOT / 'checkpoints/mrdr_topk_validation_20261108',
        checkpoint_tag=f'seed{seed}')
    assert (result['best_epoch'], result['best_val_ndcg']) == (old['epoch'], old['val_ndcg'])
    runs.append(dict(seed=seed, best_epoch=result['best_epoch'], best_val_ndcg=result['best_val_ndcg'],
                     epochs_run=result['epochs_run'], checkpoint_path=str(result['checkpoint_path'])))
assert source_signature() == code
with (ROOT / 'results/mrdr_topk_validation_20261108.json').open('w', encoding='utf-8') as stream:
    json.dump(dict(identity=dict(code_sha256=code), runs=runs,
        evaluation='validation_only_no_held_out_test',
        regression='Exact CDR validation scores and selected epochs after adding project top-5 metrics to MRDR-CAL (CDR code unchanged)'),
        stream, indent=2)
print(json.dumps([dict(seed=r['seed'], epoch=r['best_epoch'], val=r['best_val_ndcg']) for r in runs]))
