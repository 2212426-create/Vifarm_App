"""Audit frozen-source artifacts, reload source checkpoints, then advance state."""
from pathlib import Path
import sys,json
import torch
ROOT=Path(__file__).resolve().parents[4]
sys.path.insert(0,str(ROOT))
from src.utils.artifacts import source_signature,evaluate_checkpoint
from src.causal.cdr.source_protocol import evaluate_source_checkpoint
from src.training.config import released_cdr_config,released_tuning_grids

def read(path): return json.loads((ROOT/path).read_text(encoding='utf-8'))
def write(path,value,exclusive=False):
    with (ROOT/path).open('x' if exclusive else 'w',encoding='utf-8') as f:
        json.dump(value,f,ensure_ascii=False,indent=2);f.write('\n')

torch.set_num_threads(2)
code=source_signature()
source_runs={d:[] for d in ('coat','yahoo','kuairand')}
benchmarks=[];seed_reports=[];tuning=[];smokes={}
for p in sorted((ROOT/'results').glob('*.json')):
    r=read(p.relative_to(ROOT))
    relative=p.relative_to(ROOT).as_posix()
    if r.get('identity',{}).get('code_sha256')==code:
        if r.get('evaluation_scope')=='cdr_source_protocol':
            source_runs[r['identity']['dataset']].append(relative)
        elif p.name.startswith('coat_seeds_'): seed_reports.append(relative)
        elif p.name.startswith('tuning_'): tuning.append(relative)
    if p.name.startswith('benchmark_'):
        for dataset in source_runs:
            row=r.get(dataset,{}).get('DR-BIAS + CDR',{})
            if row.get('metadata',{}).get('code_sha256')==code:
                assert row['evaluation_scope']=='cdr_source_protocol'
                benchmarks.append(relative)
                if r['protocol']['quick_run']:
                    assert all(r[dataset][m]['metadata']['code_sha256']==code for m in ('MF','iDCF','DR-BIAS + CDR'))
                    smokes[dataset]=relative
assert set(smokes)==set(source_runs)
assert seed_reports and tuning
full={}
reloads={}
for dataset,paths in source_runs.items():
    for relative in paths:
        r=read(relative)
        if r['config']['epochs']==1000:
            full[dataset]=relative
            actual=evaluate_source_checkpoint(r['checkpoint_path'])
            assert actual['NDCG@5']==r['metrics']['NDCG@5']
            assert actual['AUC_global']==r['metrics']['AUC_global']
            # Public evaluation adapter must retain source metrics/protocol.
            assert evaluate_checkpoint(r['checkpoint_path'],{})['evaluation_scope']=='cdr_source_protocol'
            reloads[dataset]=dict(path=relative,metrics=actual['NDCG@5'])
assert {'coat','yahoo'}<=set(full)
coat=read(full['coat'])
assert abs(coat['metrics']['NDCG@5']-.6566651228158734)<1e-12
assert abs(coat['metrics']['Recall@5_bounded']-.667816091954023)<1e-12
seed=read(seed_reports[0])['runs']['DR-BIAS + CDR'][0]
assert seed['recall_metric']=='Recall@5_bounded'
assert seed['NDCG@5']==coat['metrics']['NDCG@5']
test_log='docs/archive/2026-10-20/cdr_source_default/model_tests.log'
b=(ROOT/test_log).read_bytes();log=b.decode('utf-16' if b.startswith(b'\xff\xfe') else 'utf-8-sig')
assert 'Ran 113 tests' in log and 'OK (skipped=1)' in log
validation_path='results/cdr_source_estimator_validation_20261020.json'
validation=read(validation_path)
assert validation['identity']['code_sha256']==code
path='results/cdr_source_default_verification_20261020.json'
verification=dict(identity=dict(code_sha256=code),status='passed_cpu',
    tests=dict(total=113,passed=112,skipped=1,skip_reason='CUDA unavailable',log=test_log),
    full_source_runs=full,source_coat_metrics=coat['metrics'],source_yahoo_metrics=read(full['yahoo'])['metrics'],
    source_checkpoint_reload=reloads,benchmark_reports=benchmarks,smoke_reports=smokes,
    seed_reports=seed_reports,tuning_smokes=tuning,validation_diagnostic=validation_path,
    serving='ReleasedCDR asserted by API tests; item-frequency propensity/replacement sampling recorded',
    limits=['Source Coat/Yahoo uses evaluation labels for calibration; not independent held-out test',
            'KuaiRand uses local preprocessing and array/bounded-memory sampling adaptations',
            'Tuning uses validation calibration/selection; separate from default source protocol',
            'API lacks randomized log; serving adaptation', 'CUDA unverified'])
write(path,verification,True)
state=read('docs/state_snapshot.json')
state['pre_source_protocol_default_milestone']={key:state[key] for key in (
    'source_sha256','scope','test_suite','verification_artifact','validation_artifact','independent_cdr_validation')}
state.update(source_sha256=code,scope='CDR source-protocol default; Coat/Yahoo full fits, three-dataset smoke, seed/tuning/API tests and checkpoint reload',
    cdr_defaults={d:released_cdr_config(d) for d in source_runs},
    cdr_implementation={d:'released_source_protocol' for d in source_runs},
    grid_sizes={d:{k:len(v) for k,v in released_tuning_grids(d).items()} for d in source_runs},
    grid_scope='Released estimator; validation adaptation, not default source-protocol scoring',
    test_suite=verification['tests'],verification_artifact=path,validation_artifact=validation_path,
    independent_cdr_validation=[dict(seed=r['seed'],epoch=r['best_epoch'],val_ndcg=r['best_val_ndcg']) for r in validation['runs']],
    validation_scope_note='Validation-only source estimator diagnostic; not the default source-protocol benchmark',
    evaluation=dict(mf_idcf='logged_binary_v1 / >=4 / random-user 30/70',
                    cdr='cdr_source_v1 / >=3 Coat/Yahoo / full random log / 5% calibration / train-loss last',
                    cross_protocol_paired_tests=False),limits=verification['limits'])
state['source_protocol_benchmarks']=full
write('docs/state_snapshot.json',state)
assert source_signature()==code
print(path)
print(json.dumps(verification['source_yahoo_metrics']))
