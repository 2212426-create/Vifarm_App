"""ConAlign KuaiRand-Pure: training time window as released, as intended by the source, and as in the paper.

Usage (from services/recsys): python docs/archive/2026-10-28/conalign_paper_window/run.py WINDOW SEED
WINDOW: source | intended | paper
  source:   utils/load_kuairand.py as released. Train dates are built as 20220408 + i for i < 28, so they
            run 20220408..20220430 then 20220431..20220435 (not real dates): 01-05/05 never enter train.
  intended: the 28 calendar days the source docstring states, train 08/04-05/05.
  paper:    Sec. 4.1 "logs from April 22 to May 8, covering 17 consecutive days ... first two weeks are
            used for training ... Day 15 validation ... last two days test": train 22/04-05/05.
            Rows before 22/04 are dropped before ID mapping.
Validation (06/05) and test (07-08/05) are the same in every window; only training data differs.
Everything else (model, para(), early stopping, metrics) is the ported source.
"""
import json
import sys
import time
from datetime import date, timedelta
from pathlib import Path

import pandas as pd
import torch

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
from src.models.conalign import data as conalign_data
from src.models.conalign.train import setup_seed, train_conalign
from src.utils.artifacts import source_signature

PAPER_FIRST_DATE = 20220422


def calendar_days(first, count):
    return [int((first + timedelta(days=i)).strftime('%Y%m%d')) for i in range(count)]


window, seed = sys.argv[1], int(sys.argv[2])
if window not in ('source', 'intended', 'paper'):
    raise SystemExit(f'Unknown window {window}')
torch.set_num_threads(4)
started, code = time.time(), source_signature()
if window == 'intended':
    conalign_data.KUAIRAND_TRAIN_DATES = calendar_days(date(2022, 4, 8), 28)
    assert conalign_data.KUAIRAND_TRAIN_DATES[-1] == 20220505
if window == 'paper':
    read_csv = pd.read_csv
    conalign_data.KUAIRAND_TRAIN_DATES = calendar_days(date(2022, 4, 22), 14)
    assert conalign_data.KUAIRAND_TRAIN_DATES[-1] == 20220505
    conalign_data.pd.read_csv = lambda *a, **k: (lambda f: f[f['date'] >= PAPER_FIRST_DATE].reset_index(drop=True))(
        read_csv(*a, **k))
setup_seed(seed)
data = conalign_data.load_conalign_data('kuairand', seed=seed)
data['info']['window'] = window
result = train_conalign(data, 'kuairand', seed=seed, verbose=False)
assert source_signature() == code
result.update(window=window, code_sha256=code, seconds_total=time.time() - started,
              protocol=f'ConAlign source code; KuaiRand {window} time window')
out = ROOT / f'results/conalign_kuairand_window_{window}_seed{seed}_20261028.json'
with out.open('x', encoding='utf-8') as stream:
    json.dump(result, stream, indent=2, ensure_ascii=False)
tower = result['source_metrics']['test_unbiased']['unbiased_tower']
print(json.dumps(dict(window=window, seed=seed, n_users=data['n_users'], n_items=data['n_items'],
                      counts=data['info']['counts'], UAUC=tower['UAUC'], NDCG=tower['NDCG'], UNDCG=tower['UNDCG'])))
