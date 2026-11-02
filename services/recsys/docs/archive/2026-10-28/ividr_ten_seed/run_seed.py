"""Ten-seed Coat comparison on one source hash: iDCF, IViDR default, IViDR zero prior + negative weight .1.

Usage (from services/recsys): python docs/archive/2026-10-28/ividr_ten_seed/run_seed.py MODEL SEED
MODEL: idcf | ividr_default | ividr_zero_neg0.1
IViDR trains its MF treatment with the same seed. Selection is validation NDCG@5 inside each
pipeline (IViDR: paper LR x WD grid); test is evaluated once for reporting.
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
from src.models.ividr.ividr_staged import mf_item_embeddings
from src.models.ividr.train_ividr import fit_ividr_pipeline
from src.models.mf.train_mf import train_baseline_mf
from src.training.config import mf_config
from src.utils.artifacts import source_signature

model, seed = sys.argv[1], int(sys.argv[2])
torch.set_num_threads(2)
started, code = time.time(), source_signature()
checkpoints = ROOT / 'checkpoints/ividr_ten_seed_20261028'
data = load_coat_processed()
if model == 'idcf':
    result = fit_idcf_pipeline(data, 'coat', seed=seed, checkpoint_dir=str(checkpoints), checkpoint_tag=f'idcf_seed{seed}')
elif model in ('ividr_default', 'ividr_zero_neg0.1'):
    mf = train_baseline_mf(dataset_name='coat', data_dict=data, seed=seed, checkpoint_dir=str(checkpoints),
                           evaluate_test=False, checkpoint_tag=f'treatment_seed{seed}', **mf_config('coat'))
    options = (dict(ivae_overrides=dict(prior_mean='zero'), negative_weight=.1) if model == 'ividr_zero_neg0.1' else {})
    result = fit_ividr_pipeline(data, 'coat', seed=seed, item_emb=mf_item_embeddings(mf['checkpoint_path']),
                                checkpoint_dir=str(checkpoints), checkpoint_tag=f'{model}_seed{seed}', device='cpu',
                                **options)
else:
    raise SystemExit(f'Unknown model {model}')
assert source_signature() == code
keep = ('NDCG@5', 'Recall@5', 'Recall@5_bounded', 'Precision@5', 'HitRate@5', 'AUC', 'best_epoch', 'best_val_ndcg',
        'checkpoint_path')
report = dict(model=model, seed=seed, code_sha256=code, test={k: result[k] for k in keep if k in result},
              validation_search=result.get('validation_search'), seconds=time.time() - started,
              selection='validation NDCG@5 only; test reported once')
out = ROOT / f'results/ividr_ten_seed_{model}_seed{seed}_20261028.json'
with out.open('x', encoding='utf-8') as stream:
    json.dump(report, stream, indent=2)
print(json.dumps(dict(model=model, seed=seed, val=result['best_val_ndcg'], test=result['NDCG@5'])))
