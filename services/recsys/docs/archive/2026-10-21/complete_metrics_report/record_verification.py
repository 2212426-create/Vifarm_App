"""Verify a checkpoint-only refresh and record the current metric milestone."""
import sys,json,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4]
sys.path.insert(0,str(ROOT))
from src.utils.artifacts import source_signature
from experiments.workflows.run_all_benchmarks import get_benchmark_tables_data
def read(path):return json.loads((ROOT/path).read_text(encoding='utf-8'))
def write(path,value,exclusive=False):
    with (ROOT/path).open('x' if exclusive else 'w',encoding='utf-8') as f:
        json.dump(value,f,ensure_ascii=False,indent=2);f.write('\n')
code=source_signature()
report='results/benchmark_report_20261021_072543_c37b107c.json'
data=read(report)
refresh=data['report_refresh']
assert refresh['evaluation_code_sha256']==code and refresh['retrained'] is False
original_path=Path(refresh['input_path'])
assert hashlib.sha256(original_path.read_bytes()).hexdigest()==refresh['input_sha256']
original=json.loads(original_path.read_text(encoding='utf-8'))
for dataset in ('coat','yahoo','kuairand'):
    for model in ('MF','iDCF'):
        assert data[dataset][model]==original[dataset][model]
    before=original[dataset]['DR-BIAS + CDR'];after=data[dataset]['DR-BIAS + CDR']
    assert before['metadata']==after['metadata']
    assert before['checkpoint_path']==after['checkpoint_path']
    assert all(after['metrics'][key]==value for key,value in before['metrics'].items())
headers,rows=get_benchmark_tables_data(data)
assert len(rows)==9 and all('N/A' not in row for row in rows)
test_log='docs/archive/2026-10-21/complete_metrics_report/model_tests.log'
b=(ROOT/test_log).read_bytes();text=b.decode('utf-16' if b.startswith(b'\xff\xfe') else 'utf-8-sig')
assert 'Ran 118 tests' in text and 'OK (skipped=1)' in text
validation_path='results/complete_metrics_report_validation_20261021.json'
validation=read(validation_path)
assert validation['identity']['code_sha256']==code
tests=dict(total=118,passed=117,skipped=1,skip_reason='CUDA unavailable',log=test_log)
path='results/complete_metrics_report_verification_20261021.json'
write(path,dict(identity=dict(code_sha256=code),status='passed_cpu',tests=tests,
    report=report,input_report=str(original_path),retrained=False,
    original_file_unchanged=True,original_primary_metrics_unchanged=True,
    mf_idcf_rows_and_training_metadata_unchanged=True,
    unified_rows=len(rows),undefined_metrics_in_this_report=0,
    cdr_metrics={d:data[d]['DR-BIAS + CDR']['metrics'] for d in ('coat','yahoo','kuairand')},
    validation_diagnostic=validation_path,
    metric_policy='Both Recalls on source-eligible users; source empty-positive Recall=1, Precision/HitRate=0',
    limit='Merged display preserves distinct protocols and AUC types; no cross-protocol significance tests'),True)
state=read('docs/state_snapshot.json')
state['pre_complete_metric_report_milestone']={key:state[key] for key in ('source_sha256','scope','test_suite',
    'verification_artifact','validation_artifact','independent_cdr_validation')}
state.update(reviewed_on='2026-10-21',source_sha256=code,
    scope='Source auxiliary metrics and unified protocol-labeled display; latest nine-model report refreshed from checkpoints, no retraining',
    test_suite=tests,verification_artifact=path,validation_artifact=validation_path,
    independent_cdr_validation=[dict(seed=r['seed'],epoch=r['best_epoch'],val_ndcg=r['best_val_ndcg']) for r in validation['runs']])
state['latest_merged_report']=dict(path=report,training_code_sha256='134b536cc623a5b925adc8b2e4b8fcb2d8880ff54ccfd0b4002b294b5c532154',
    evaluation_code_sha256=code,retrained=False)
write('docs/state_snapshot.json',state)
print(path)
print('9 complete rows; original metrics and input file unchanged')
