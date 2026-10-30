"""Frozen-source validation evidence; never evaluates held-out test."""
import json
from pathlib import Path
import sys
import platform
import torch

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
from src.data_pipeline.coat_dataset import load_coat_processed
from src.causal.cdr.train_released_cdr import train_released_cdr
from src.utils.artifacts import source_signature, data_signature

torch.set_num_threads(2)
identity = dict(code_sha256=source_signature(), data=data_signature(load_coat_processed()),
                python=platform.python_version(), torch=torch.__version__)
runs = []
for seed in (42, 43, 44):
    r = train_released_cdr('coat', load_coat_processed(), seed=seed, device='cpu', evaluate_test=False,
        checkpoint_dir=ROOT/'checkpoints/yahoo_source_integration_validation', checkpoint_tag=f'seed{seed}')
    runs.append(dict(seed=seed, **r))
assert source_signature() == identity['code_sha256']
result = dict(identity=identity, evaluation='validation_only_no_held_out_test', runs=runs,
              implementation='cdr_released', hyperparameter_search=False,
              limitation='Three validation seeds verify operation, not independent test performance')
path = ROOT/'results/released_cdr_coat_validation_20261020_yahoo_integration.json'
with path.open('x', encoding='utf-8') as f:
    json.dump(result, f, ensure_ascii=False, indent=2, default=str)
print(path)
