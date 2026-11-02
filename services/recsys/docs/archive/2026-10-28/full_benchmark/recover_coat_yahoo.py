"""Recover IViDR Coat/Yahoo test scores from the interrupted benchmark run 20261028_214102_cf42b911.

The run finished Coat and Yahoo, then the machine rebooted during KuaiRand stage 1, so the final
report was never written. Each finished dataset left its 10 LR x WD feedback checkpoints. This
picks the winner the way fit_ividr_pipeline does (first trial with the highest validation NDCG@5,
read from the checkpoint) and evaluates only that checkpoint on test with evaluate_checkpoint.
Usage (from services/recsys): python docs/archive/2026-10-28/full_benchmark/recover_coat_yahoo.py
"""
import glob
import json
import re
import sys
from pathlib import Path

import torch

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
from src.data_pipeline.coat_dataset import load_coat_processed
from src.data_pipeline.yahoo_dataset import load_yahoo_processed
from src.utils.artifacts import evaluate_checkpoint, source_signature

RUN = ROOT / 'checkpoints/benchmark_runs/20261028_214102_cf42b911'
report = dict(run=RUN.name, code_sha256=source_signature(), selection='max_validation_NDCG@5, first trial on ties',
              test_used_for_selection=False, datasets={})
for dataset, load in (('coat', load_coat_processed), ('yahoo', load_yahoo_processed)):
    paths = sorted(glob.glob(str(RUN / f'**/{dataset}_ividr_reference_*_bce_trial*.pt'), recursive=True),
                   key=lambda p: int(re.search(r'_trial(\d+)_', p).group(1)))
    assert len(paths) == 10, (dataset, len(paths))
    trials = []
    for path in paths:
        state = torch.load(path, map_location='cpu', weights_only=True)
        config = state['metadata']['config']
        trials.append(dict(path=path, lr=config['lr'], weight_decay=config['weight_decay'], epoch=state['epoch'],
                           val=state['validation']['NDCG@5'], code_sha256=state['metadata'].get('code_sha256')))
    winner = trials[0]
    for trial in trials[1:]:
        if trial['val'] > winner['val']:
            winner = trial
    test = evaluate_checkpoint(winner['path'], load())
    keep = ('NDCG@5', 'Recall@5', 'Recall@5_bounded', 'Precision@5', 'HitRate@5', 'AUC')
    report['datasets'][dataset] = dict(winner={k: v for k, v in winner.items()}, test={k: test[k] for k in keep},
                                       trials=[{k: t[k] for k in ('lr', 'weight_decay', 'epoch', 'val')} for t in trials])
    print(json.dumps(dict(dataset=dataset, lr=winner['lr'], wd=winner['weight_decay'], val=winner['val'],
                          **{k: test[k] for k in keep})))
out = ROOT / 'results/ividr_benchmark_recovered_coat_yahoo_20261029.json'
with out.open('x', encoding='utf-8') as stream:
    json.dump(report, stream, indent=2)
print(out)
