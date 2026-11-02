"""Hypothesis test: does marginal (variance-integrated) BCE inference distort the ranking?

Reloads the validation-selected BCE checkpoints of the factorial and IViDR v2 runs, then scores
validation/test twice: as trained (logit E[sigmoid], GH32 over c_std) and with c_std = 0 at
inference only (rank by MF + <e_i, mean_u>). No training; weights are unchanged.
Usage (from services/recsys): python docs/archive/2026-10-27/ividr_rootcause/marginal_inference.py
"""
import glob
import json
import sys
from pathlib import Path

import torch

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
from src.data_pipeline.coat_dataset import load_coat_processed
from src.evaluation.evaluator import evaluate_unbiased_model
from src.models.ividr.ividr_reference import IViDRMarginalMF
from src.utils.artifacts import load_checkpoint

torch.set_num_threads(4)
data = load_coat_processed()


def winner_paths():
    for report in sorted(glob.glob(str(ROOT / 'results/ividr_rootcause_*_20261027.json'))):
        r = json.loads(Path(report).read_text())
        if not r['cell'].endswith('+bce'):
            continue
        trial = max(range(len(r['trials'])), key=lambda t: r['trials'][t]['best_val_ndcg'])
        path, = glob.glob(str(ROOT / f"checkpoints/ividr_rootcause_20261027/coat_ividr_reference_"
                                     f"{r['cell'].replace('+', '_')}_seed{r['seed']}_t{trial}_v4_*.pt"))
        yield r['cell'], r['seed'], path
    for report in sorted(glob.glob(str(ROOT / 'results/ividr_opt_tied_item_lift_full_seed*_20261027.json'))):
        r = json.loads(Path(report).read_text())
        yield 'ividr_v2+bce', r['seed'], r['test']['checkpoint_path']


def score(model, split):
    return evaluate_unbiased_model(model, data[f'{split}_candidates'], data[f'{split}_ground_truth'], k=5,
                                   include_zero_positive_users=False)


rows = []
for cell, seed, path in winner_paths():
    state = load_checkpoint(path)
    model = IViDRMarginalMF(**state['metadata']['model_kwargs'])
    model.load_state_dict(state['model_state_dict'])
    model.eval()
    row = dict(cell=cell, seed=seed, checkpoint=path)
    for mode in ('marginal', 'mean_only'):
        if mode == 'mean_only':
            model.c_std.zero_()
        for split in ('val', 'test'):
            metrics = score(model, split)
            row[f'{mode}_{split}_ndcg'] = metrics['NDCG@5']
            row[f'{mode}_{split}_recall'] = metrics['Recall@5']
    rows.append(row)
    print(json.dumps({k: (round(v, 4) if isinstance(v, float) else v) for k, v in row.items() if k != 'checkpoint'}))
out = ROOT / 'results/ividr_rootcause_marginal_inference_20261027.json'
with out.open('x', encoding='utf-8') as stream:
    json.dump(dict(rows=rows, note='Inference-only change; checkpoints selected earlier by validation NDCG@5'), stream, indent=2)
