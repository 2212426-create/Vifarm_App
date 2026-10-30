"""Validation-only diagnostic of the source estimator; not its default protocol."""
from pathlib import Path
import sys,json
import torch
ROOT=Path(__file__).resolve().parents[4]
sys.path.insert(0,str(ROOT))
from src.utils.artifacts import source_signature
from src.data_pipeline.coat_dataset import load_coat_processed
from src.causal.cdr.train_released_cdr import train_released_cdr
torch.set_num_threads(2)
code=source_signature()
data=load_coat_processed(pos_threshold=3)
runs=[]
for seed in (2020,2021,2022):
    r=train_released_cdr('coat',data,seed=seed,evaluate_test=False,device='cpu',
        selection='source_train_loss_last',calibration_fraction=.05,
        checkpoint_dir=ROOT/'checkpoints/cdr_source_default_validation',checkpoint_tag=f'seed{seed}')
    runs.append(dict(seed=seed,**r))
assert source_signature()==code
with (ROOT/'results/cdr_source_estimator_validation_20261020.json').open('x',encoding='utf-8') as f:
    json.dump(dict(identity=dict(code_sha256=code),runs=runs,evaluation='validation_only_no_held_out_test',
        scope='Released estimator validation diagnostic; split and metrics differ from default source protocol'),f,indent=2)
