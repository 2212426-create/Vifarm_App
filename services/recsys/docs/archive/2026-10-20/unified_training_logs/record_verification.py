"""Freeze the verified logging-only milestone without rewriting old artifacts."""
import json,sys
from pathlib import Path
import torch
ROOT=Path(__file__).resolve().parents[4]
sys.path.insert(0,str(ROOT))
from src.utils.artifacts import source_signature
def read(path):return json.loads((ROOT/path).read_text(encoding='utf-8'))
def write(path,value,exclusive=False):
    with (ROOT/path).open('x' if exclusive else 'w',encoding='utf-8') as f:
        json.dump(value,f,ensure_ascii=False,indent=2);f.write('\n')
def log(path):
    b=(ROOT/path).read_bytes()
    return b.decode('utf-16' if b.startswith(b'\xff\xfe') else 'utf-8-sig')
code=source_signature()
test_log='docs/archive/2026-10-20/unified_training_logs/model_tests.log'
assert 'Ran 115 tests' in log(test_log) and 'OK (skipped=1)' in log(test_log)
smoke='results/benchmark_coat_all_quick_7e3c020ae1_20261020_231221_e4861999_v4.json'
full='results/benchmark_coat_cdr_dd41848bc6_20261020_231233_64456c33_v4.json'
for path in (smoke,full):
    for r in read(path)['coat'].values():
        if 'metadata' in r:assert r['metadata']['code_sha256']==code
for tag in ('[MF][COAT] Epoch','[iDCF/iVAE][COAT] Epoch','[iDCF/feedback][COAT] Epoch',
            '[CDR][COAT] Epoch','[CDR][COAT] SOURCE EVAL'):
    assert tag in log('docs/archive/2026-10-20/unified_training_logs/coat_smoke.log')
current=read(full)['coat']['DR-BIAS + CDR']
previous=read(read('results/cdr_source_default_verification_20261020.json')['full_source_runs']['coat'])
assert current['metrics']==previous['metrics']
old=torch.load(previous['checkpoint_path'],map_location='cpu',weights_only=True)['model_state_dict']
new=torch.load(current['checkpoint_path'],map_location='cpu',weights_only=True)['model_state_dict']
assert all(torch.equal(old[k],new[k]) for k in old)
val_path='results/unified_training_logs_validation_20261020.json'
validation=read(val_path)
assert validation['identity']['code_sha256']==code
artifact='results/unified_training_logs_verification_20261020.json'
tests=dict(total=115,passed=114,skipped=1,skip_reason='CUDA unavailable',log=test_log)
write(artifact,dict(identity=dict(code_sha256=code),status='passed_cpu',tests=tests,
    scope='Console logging only; objectives, RNG, optimization, stopping and evaluation unchanged',
    smoke=smoke,full_coat_source=full,cdr_metrics=current['metrics'],
    full_coat_parameters='All tensors bitwise equal to preceding source-default checkpoint',
    callback_tests='CDR parameters/history/stopping and iVAE latent/selection identical with and without progress',
    validation_diagnostic=val_path,validation_regression=validation['regression']),True)
state=read('docs/state_snapshot.json')
state['pre_logging_milestone']={key:state[key] for key in ('source_sha256','scope','test_suite',
    'verification_artifact','validation_artifact','independent_cdr_validation')}
state.update(source_sha256=code,scope='Unified console training logs; full Coat source parameters and validation diagnostics unchanged',
    test_suite=tests,verification_artifact=artifact,validation_artifact=val_path,
    independent_cdr_validation=[dict(seed=r['seed'],epoch=r['best_epoch'],val_ndcg=r['best_val_ndcg']) for r in validation['runs']])
state['source_protocol_benchmarks']['coat']=full
state['source_protocol_benchmark_sources']=dict(coat=code,yahoo=previous['identity']['code_sha256'])
write('docs/state_snapshot.json',state)
print(artifact)
print('Full Coat source parameter parity: exact')
