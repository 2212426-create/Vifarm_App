"""Record a display-only change with all original JSON values preserved."""
import json,sys,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4]
sys.path.insert(0,str(ROOT))
from src.utils.artifacts import source_signature
from experiments.workflows.run_all_benchmarks import get_benchmark_tables_data
def read(path):return json.loads((ROOT/path).read_text(encoding='utf-8'))
def write(path,data,exclusive=False):
    with (ROOT/path).open('x' if exclusive else 'w',encoding='utf-8') as f:
        json.dump(data,f,ensure_ascii=False,indent=2);f.write('\n')
code=source_signature()
path='results/benchmark_report_bounded_20261021_074350_e29d0387.json'
report=read(path);display=report.pop('display_update')
assert display['render_code_sha256']==code
assert report==read(display['input_path'])
assert hashlib.sha256((ROOT/display['input_path']).read_bytes()).hexdigest()==display['input_sha256']
headers,rows=get_benchmark_tables_data(report)
assert len(rows)==9 and 'Recall@5' not in headers and 'Recall@5 bounded' in headers
assert all('N/A' not in row for row in rows)
validation_path='results/bounded_recall_display_validation_20261021.json'
validation=read(validation_path)
assert validation['identity']['code_sha256']==code
test_log='docs/archive/2026-10-21/bounded_recall_display/model_tests.log'
b=(ROOT/test_log).read_bytes();log=b.decode('utf-16' if b.startswith(b'\xff\xfe') else 'utf-8-sig')
assert 'Ran 118 tests' in log and 'OK (skipped=1)' in log
tests=dict(total=118,passed=117,skipped=1,skip_reason='CUDA unavailable',log=test_log)
artifact='results/bounded_recall_display_verification_20261021.json'
write(artifact,dict(identity=dict(code_sha256=code),status='passed_cpu',tests=tests,
    report=path,scope='Display only: bounded recall column; all original JSON values preserved',
    original_values_unchanged=True,retrained=False,metrics_recomputed=False,
    validation_diagnostic=validation_path),True)
state=read('docs/state_snapshot.json')
state['pre_bounded_recall_display_milestone']={key:state[key] for key in ('source_sha256','scope','test_suite',
    'verification_artifact','validation_artifact','independent_cdr_validation','latest_merged_report')}
state.update(source_sha256=code,scope='Bounded-only recall display; JSON retains both metrics without recomputation',
    test_suite=tests,verification_artifact=artifact,validation_artifact=validation_path,
    independent_cdr_validation=[dict(seed=r['seed'],epoch=r['best_epoch'],val_ndcg=r['best_val_ndcg']) for r in validation['runs']])
state['latest_merged_report']=dict(state['latest_merged_report'],path=path,render_code_sha256=code)
state['displayed_recall']='Recall@5_bounded'
write('docs/state_snapshot.json',state)
print('Verified: nine bounded-only display rows; all original metrics retained')
