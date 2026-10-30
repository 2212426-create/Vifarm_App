"""Run the declared full Coat default suite into a fresh directory; retain all old artifacts."""
from datetime import datetime, timezone
import importlib
import json
from pathlib import Path
import platform
import sys
import time

RUN_DIR = Path(__file__).resolve().parent
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
import numpy as np
import pandas as pd
import torch
from src.utils.artifacts import source_signature
from experiments.workflows import run_all_benchmarks as workflow

torch.set_num_threads(2)
source_before = source_signature()
checkpoint_root = ROOT / 'checkpoints' / RUN_DIR.name
for name in ('src.baselines.train_mf', 'src.causal.idcf.train_idcf', 'src.causal.cdr.train_dr_bias_cdr'):
    importlib.import_module(name).CHECKPOINT_DIR = str(checkpoint_root)
workflow.RESULTS_DIR = str(RUN_DIR)
request = {
    'started_at_utc': datetime.now(timezone.utc).isoformat(), 'dataset': 'coat',
    'models': list(workflow.STANDARD_MODELS), 'seed': 42, 'device': 'cpu',
    'quick_run': False, 'hyperparameter_tuning': False, 'default_configuration': True,
    'feedback_epoch_cap': 100, 'ivae_epoch_cap': 2000,
    'checkpoint_selection': 'validation_ndcg', 'source_sha256': source_before,
    'checkpoint_root': str(checkpoint_root), 'torch_num_threads': torch.get_num_threads(),
    'environment': {'python': platform.python_version(), 'numpy': np.__version__,
                    'pandas': pd.__version__, 'torch': str(torch.__version__),
                    'cuda_available': torch.cuda.is_available()},
    'entrypoint_equivalent': 'python experiments/run.py benchmark --dataset coat --model all --device cpu',
    'runtime_wrapper_changes': 'unique report/checkpoint directories and CPU thread count only',
}
with (RUN_DIR / 'request.json').open('x', encoding='utf-8') as stream:
    json.dump(request, stream, ensure_ascii=False, indent=2)
print('RUN_DIRECTORY', RUN_DIR, flush=True)
print('SOURCE_SHA256', source_before, flush=True)
started = time.monotonic()
try:
    results = workflow.run_all_benchmarks(dataset_filter='coat', model_filter='all', device='cpu')
    assert all(name in results['coat'] for name in workflow.STANDARD_MODELS)
    assert source_signature() == source_before, 'Source changed during experiment'
    summary = {}
    for name in workflow.STANDARD_MODELS:
        result = results['coat'][name]
        summary[name] = {key: result.get(key) for key in (
            'NDCG@5', 'Recall@5', 'Precision@5', 'HitRate@5', 'AUC',
            'best_epoch', 'best_val_ndcg', 'checkpoint_path', 'selection_origin')}
    completion = {'status': 'success', 'completed_at_utc': datetime.now(timezone.utc).isoformat(),
                  'elapsed_seconds': round(time.monotonic() - started, 3),
                  'source_sha256': source_before, 'scope': 'full_Coat_default_config_single_seed_42',
                  'paper_reproduction': False, 'models': summary,
                  'significance': results['significance'].get('coat', {})}
except Exception as exc:
    completion = {'status': 'failed', 'error': repr(exc), 'source_sha256': source_before,
                  'elapsed_seconds': round(time.monotonic() - started, 3)}
    with (RUN_DIR / 'completion.json').open('x', encoding='utf-8') as stream:
        json.dump(completion, stream, ensure_ascii=False, indent=2, allow_nan=False)
    raise
with (RUN_DIR / 'completion.json').open('x', encoding='utf-8') as stream:
    json.dump(completion, stream, ensure_ascii=False, indent=2, allow_nan=False)
print('RUN_COMPLETED', json.dumps(completion, ensure_ascii=False), flush=True)
