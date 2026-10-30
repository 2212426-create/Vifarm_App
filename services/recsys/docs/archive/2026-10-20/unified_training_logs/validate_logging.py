"""Check the logging milestone against the preceding validation diagnostics."""
import json,sys
from pathlib import Path
import torch
ROOT=Path(__file__).resolve().parents[4]
sys.path.insert(0,str(ROOT))
from src.utils.artifacts import source_signature
from src.causal.cdr.train_released_cdr import train_released_cdr
from src.data_pipeline.coat_dataset import load_coat_processed
torch.set_num_threads(2)
code=source_signature()
previous=json.loads((ROOT/'results/cdr_source_estimator_validation_20261020.json').read_text(encoding='utf-8'))
data=load_coat_processed(pos_threshold=3)
runs=[]
for old in previous['runs']:
    seed=old['seed']
    r=train_released_cdr('coat',data,seed=seed,evaluate_test=False,device='cpu',
        selection='source_train_loss_last',calibration_fraction=.05,
        checkpoint_dir=ROOT/'checkpoints/unified_training_logs_validation',checkpoint_tag=f'seed{seed}')
    assert (r['best_epoch'],r['best_val_ndcg'])==(old['best_epoch'],old['best_val_ndcg'])
    runs.append(dict(seed=seed,**r))
assert source_signature()==code
with (ROOT/'results/unified_training_logs_validation_20261020.json').open('x',encoding='utf-8') as f:
    json.dump(dict(identity=dict(code_sha256=code),runs=runs,evaluation='validation_only_no_held_out_test',
        previous_validation='results/cdr_source_estimator_validation_20261020.json',
        regression='All three selected epochs and validation scores exactly match before logging edits'),f,indent=2)
