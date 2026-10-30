"""Verify real Coat results, complete stage1 reload and unchanged other models."""
import json
from pathlib import Path
import sys

import numpy as np
import torch

ROOT=Path(__file__).resolve().parents[4]
sys.path.insert(0,str(ROOT))
from src.utils.artifacts import source_signature,evaluate_checkpoint
from src.causal.idcf.train_idcf import DATASET_INPUTS
from src.causal.idcf.ividr_reference import PaperExposureIVAE
from src.data_pipeline.coat_dataset import load_coat_processed

torch.set_num_threads(2)
read=lambda p:json.loads(p.read_text(encoding='utf-8'))
report=max(ROOT.glob('results/benchmark_coat_all_*20261022*_v4.json'),
           key=lambda p:p.stat().st_mtime)
assert '_quick_' not in report.name
r=read(report);old=read(ROOT/'results/benchmark_coat_all_b384ff80db_20261021_115348_e8c7d044_v4.json')
iv=r['coat']['IViDR'];meta=iv['metadata']
assert meta['model']=='ividr_reference'
assert meta['code_sha256']==source_signature()
assert meta['config']['variant']=='ividr_reference_bce_v2'
assert meta['config']['paper_reproduction'] is False
fields=('NDCG@5','Recall@5','Recall@5_bounded','Precision@5','HitRate@5','AUC')
unchanged=[]
for name in ('MF','iDCF','DR-BIAS + CDR'):
    current,previous=r['coat'][name],old['coat'][name]
    comparison_fields=fields[:-1]+(('AUC_global',) if name=='DR-BIAS + CDR' else ('AUC',))
    assert all(current[k]==previous[k] for k in comparison_fields)
    a=torch.load(current['checkpoint_path'],map_location='cpu',weights_only=True)['model_state_dict']
    b=torch.load(previous['checkpoint_path'],map_location='cpu',weights_only=True)['model_state_dict']
    assert set(a)==set(b) and all(torch.equal(a[k],b[k]) for k in a)
    unchanged.append(dict(model=name,metrics_exact=True,all_tensors_exact=True))

data=load_coat_processed();again=evaluate_checkpoint(iv['checkpoint_path'],data,'cpu')
assert all(iv[k]==again[k] for k in fields)
stage1=torch.load(iv['confounder_info']['checkpoint_path'],map_location='cpu',weights_only=True)
assert stage1['architecture']=='paper_ivae_learned_instruments_v2'
assert stage1['code_sha256']==source_signature()
inputs=DATASET_INPUTS['coat'](data)
torch.manual_seed(42)
m=PaperExposureIVAE(**stage1['model_config'],item_embeddings=stage1['model_state_dict']['iv.treatment'].numpy(),
                    exposure=inputs['exposure'],instruments=inputs['instrument'])
initial=m.iv.feature_embedding.weight.detach().clone()
m.load_state_dict(stage1['model_state_dict']);m.eval()
feature_update=float((m.iv.feature_embedding.weight-initial).norm().detach())
assert feature_update>0
with torch.no_grad():
    mean,std=m.confounders(torch.tensor(inputs['exposure'],dtype=torch.float32),
                          torch.tensor(inputs['proxy'],dtype=torch.float32))
assert torch.equal(mean,stage1['confounder_mean']) and torch.equal(std,stage1['confounder_std'])
log=Path(__file__).with_name('tests.log').read_text(encoding='utf-8')
assert 'Ran 132 tests' in log and 'OK (skipped=1)' in log
smoke=[]
for dataset in ('coat','yahoo','kuairand'):
    p=max(ROOT.glob(f'results/benchmark_{dataset}_all_quick_*20261022*_v4.json'),key=lambda p:p.stat().st_mtime)
    sr=read(p)[dataset]
    assert all(name in sr for name in ('MF','iDCF','IViDR','DR-BIAS + CDR'))
    assert sr['IViDR']['metadata']['model']=='ividr_reference'
    assert sr['IViDR']['metadata']['code_sha256']==source_signature()
    smoke.append(dict(dataset=dataset,report=p.relative_to(ROOT).as_posix(),purpose='smoke_not_quality'))
proof=dict(identity=dict(code_sha256=source_signature()),
    full_coat_report=report.relative_to(ROOT).as_posix(),
    test_suite=dict(total=132,passed=131,skipped=1,log='docs/archive/2026-10-22/ividr_reference/tests.log'),
    metrics={k:iv[k] for k in fields},implementation='ividr_reference_bce_v2',
    validation_artifact='results/ividr_reference_validation_20261022.json',
    feedback_reload_metrics_exact=True,stage1_reload_latents_exact=True,
    feature_embedding_update_norm=feature_update,unchanged_models_regression=unchanged,smoke=smoke,
    paper_reproduction=False,eq10_coordinate_completion_is_local=True,
    limitations=meta['config']['source_limitations'])
with (ROOT/'results/ividr_reference_verification_20261022.json').open('x',encoding='utf-8') as f:
    json.dump(proof,f,indent=2)
print(json.dumps(dict(report=proof['full_coat_report'],metrics=proof['metrics'],
                     unchanged_models_exact=True,stage1_reload_exact=True,feature_update_norm=feature_update),indent=2))
