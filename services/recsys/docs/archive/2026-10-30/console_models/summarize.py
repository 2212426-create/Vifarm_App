"""Summaries of the 28-30/10 studies: ConAlign KuaiRand window, LCDR constraint variants and LR x WD grid.

Usage (from services/recsys): python docs/archive/2026-10-30/console_models/summarize.py
Reads the per-run JSON reports only; writes results/lcdr_conalign_studies_summary_20261030.json.
"""
import json
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[4]
RESULTS = ROOT / 'results'


def stats(values):
    return dict(mean=float(np.mean(values)), std=float(np.std(values, ddof=1)) if len(values) > 1 else None,
                n=len(values), values=[float(v) for v in values])


windows = {}
for window, files in (('source', ['conalign_kuairand_20261028_081519_b614253e.json',
                                  'conalign_kuairand_window_source_seed1_20261028.json',
                                  'conalign_kuairand_window_source_seed2_20261028.json']),
                      ('intended', [f'conalign_kuairand_window_intended_seed{s}_20261028.json' for s in (0, 1)]),
                      ('paper', [f'conalign_kuairand_window_paper_seed{s}_20261028.json' for s in (0, 1, 2)])):
    towers = [json.loads((RESULTS / f).read_text(encoding='utf-8'))['source_metrics']['test_unbiased']['unbiased_tower']
              for f in files]
    windows[window] = dict(files=files, **{k: stats([t[k] for t in towers]) for k in ('UAUC', 'NDCG', 'UNDCG', 'AUC')})

baseline = json.loads((RESULTS / 'lcdr_coat_20261027_220934_6395e1a8.json').read_text(encoding='utf-8'))
variants = dict(default=dict(files=['lcdr_coat_20261027_220934_6395e1a8.json'],
                             val=stats([r['best_val_ndcg'] for r in baseline['lcdr']]),
                             test=stats([r['NDCG@5'] for r in baseline['lcdr']])),
                idcf=dict(files=['lcdr_coat_20261027_220934_6395e1a8.json'],
                          val=stats([r['best_val_ndcg'] for r in baseline['idcf']]),
                          test=stats([r['NDCG@5'] for r in baseline['idcf']])))
for variant in ('shared', 'squared', 'lambda10'):
    files = [f'lcdr_constraint_{variant}_seed{s}_20261028.json' for s in (42, 43, 44)]
    runs = [json.loads((RESULTS / f).read_text(encoding='utf-8')) for f in files]
    variants[variant] = dict(files=files, val=stats([r['test']['best_val_ndcg'] for r in runs]),
                             test=stats([r['test']['NDCG@5'] for r in runs]),
                             constraint=stats([r['representation']['best_val_parts']['constraint'] for r in runs]))
grid = {}
for model in ('lcdr', 'idcf'):
    files = [f'lcdr_grid_{model}_seed{s}_20261028.json' for s in (42, 43, 44)]
    runs = [json.loads((RESULTS / f).read_text(encoding='utf-8')) for f in files]
    grid[model] = dict(files=files, chosen=[r['chosen'] for r in runs], val=stats([r['chosen']['val'] for r in runs]),
                       test=stats([r['chosen']['test'] for r in runs]))
summary = dict(selection='validation only; test reported once', conalign_kuairand_window=windows,
               lcdr_coat_constraint=variants, lcdr_coat_lr_wd_grid=grid)
out = RESULTS / 'lcdr_conalign_studies_summary_20261030.json'
with out.open('x', encoding='utf-8') as stream:
    json.dump(summary, stream, indent=2)
for window, row in windows.items():
    print(window, {k: round(row[k]['mean'], 4) for k in ('UAUC', 'NDCG', 'UNDCG')},
          {k: round(row[k]['std'], 4) for k in ('UAUC', 'NDCG')})
for name, row in {**variants, **{f'grid_{m}': r for m, r in grid.items()}}.items():
    print(name, round(row['val']['mean'], 4), round(row['test']['mean'], 4), round(row['test']['std'], 4))
