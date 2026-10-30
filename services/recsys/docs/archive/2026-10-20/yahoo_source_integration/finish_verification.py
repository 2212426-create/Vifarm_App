"""Record checked artifacts and advance documentation to this verified source."""
from pathlib import Path
import hashlib
import json
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
from src.utils.artifacts import source_signature
from src.training.config import mf_config, cdr_config, released_cdr_config, tuning_grids
from src.causal.idcf.train_idcf import IDCF_CONFIG

def read(path):
    return json.loads((ROOT/path).read_text(encoding='utf-8'))

def write(path, data, exclusive=False):
    with (ROOT/path).open('x' if exclusive else 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')

code = source_signature()
smokes = {
    'coat': 'results/benchmark_coat_all_quick_f91c57579a_20261020_222119_147e6ae1_v4.json',
    'yahoo': 'results/benchmark_yahoo_all_quick_73a6598a78_20261020_222127_b44aa7e9_v4.json',
    'kuairand': 'results/benchmark_kuairand_all_quick_907333adfb_20261020_222130_447f113a_v4.json',
    'yahoo_full_data': 'results/benchmark_yahoo_all_quick_5c628bd4b7_20261020_222302_b3d1e0bf_v4.json',
}
models = ('MF','iDCF','DR-BIAS + CDR')
for dataset, path in smokes.items():
    data = read(path)
    rows = data['yahoo' if dataset.startswith('yahoo') else dataset]
    assert data['protocol']['quick_run'] is True
    for model in models:
        assert rows[model]['metadata']['code_sha256'] == code
        assert rows[model]['checkpoint_path']
    cdr = rows['DR-BIAS + CDR']['metadata']['config']
    if dataset != 'kuairand':
        assert cdr['implementation'] == 'cdr_released'
        assert cdr['propensity_calibration']['test_labels_used'] is False

source_paths = dict(coat='results/cdr_source_coat_20261020_222318_c9e8d6e9.json',
                    yahoo='results/cdr_source_yahoo_20261020_222146_a4c6d011.json')
for path in source_paths.values():
    assert read(path)['identity']['code_sha256'] == code
    assert read(path)['test_labels_used_for_propensity'] is True
source_coat = read(source_paths['coat'])
assert abs(source_coat['metrics']['NDCG@5'] - .6566651228158734) < 1e-12
assert abs(source_coat['metrics']['Recall@5_bounded'] - .6678160988565149) < 1e-7
val_path = 'results/released_cdr_coat_validation_20261020_yahoo_integration.json'
validation = read(val_path)
assert validation['identity']['code_sha256'] == code
test_log = 'docs/archive/2026-10-20/yahoo_source_integration/model_tests.log'
log_bytes = (ROOT/test_log).read_bytes()
log = log_bytes.decode('utf-16' if log_bytes.startswith(b'\xff\xfe') else 'utf-8-sig')
assert 'Ran 109 tests' in log and 'OK (skipped=1)' in log
verification_path = 'results/yahoo_source_integration_verification_20261020.json'
verification = dict(identity=dict(code_sha256=code), status='passed_cpu',
    tests=dict(total=109, passed=108, skipped=1, reason='CUDA unavailable', log=test_log,
               upstream_parameter_parity='3 CPU epochs; rtol=atol=0'),
    shared_protocol_smokes=smokes, source_protocol=source_paths,
    source_coat_metrics=source_coat['metrics'],
    validation_only=val_path,
    yahoo_data_manifest='data/raw/yahoo/source_manifest.json',
    limitations=['No complete Yahoo quality benchmark at this milestone',
        'Source protocol uses evaluation labels for calibration; not shared held-out test',
        'Yahoo iDCF is a local dataset extension with missing survey categories',
        'CUDA unverified'])
write(verification_path, verification, exclusive=True)

snapshot = read('docs/state_snapshot.json')
snapshot['pre_yahoo_integration_milestone'] = {key:snapshot[key] for key in (
    'source_sha256','scope','test_suite','validation_artifact','independent_cdr_validation',
    'idcf_validation','limits')}
snapshot['source_sha256'] = code
snapshot['scope'] = 'Released CDR integration and Yahoo dataset extension; CPU parity, tests, smoke and validation verification'
snapshot['mf_defaults'] = {d:mf_config(d) for d in ('coat','yahoo','kuairand')}
snapshot['cdr_defaults'] = {d:released_cdr_config(d) if d!='kuairand' else cdr_config(d)
                            for d in ('coat','yahoo','kuairand')}
snapshot['cdr_implementation'] = dict(coat='released',yahoo='released',kuairand='equation')
snapshot['equation_cdr_defaults'] = {d:cdr_config(d) for d in ('coat','yahoo','kuairand')}
snapshot['idcf_pipeline_defaults'] = IDCF_CONFIG
snapshot['grid_sizes'] = {d:{k:len(v) for k,v in tuning_grids(d).items()} for d in ('coat','yahoo','kuairand')}
snapshot['grid_scope'] = 'Equation variant; Yahoo grids available in config but no Yahoo tune CLI'
snapshot['test_suite'] = dict(total=109,passed=108,skipped=1,skip_reason='CUDA unavailable',log=test_log)
snapshot['validation_artifact'] = val_path
snapshot['independent_cdr_validation'] = [dict(seed=r['seed'],epoch=r['best_epoch'],val_ndcg=r['best_val_ndcg'])
                                        for r in validation['runs']]
snapshot['idcf_validation'] = []
snapshot['validation_scope_note'] = 'Released CDR validation only; independent means no MF warm-start, not a held-out quality claim'
snapshot['verification_artifact'] = verification_path
snapshot['limits'] = verification['limitations'] + ['Eq7 tuning and API serving remain separate implementations',
                                                 'IViDR is an approximate implementation']
snapshot['post_fix_coat_benchmark']['scope'] += '; historical before released CDR integration'
write('docs/state_snapshot.json',snapshot)
print(verification_path)
