"""Run the published CDR script conditions, separately from held-out benchmarks.

This explicitly uses 5% of the random evaluation labels for Naive Bayes, as the
published script does. Results must not be substituted for shared test scores.
"""
import argparse
import hashlib
from datetime import datetime
import json
from pathlib import Path
from uuid import uuid4

import numpy as np
import torch
from scipy.stats import rankdata

from src.models.cdr.released import ReleasedCDR,fit_released,released_inverse_propensity,UPSTREAM_COMMIT,UPSTREAM_URL
from src.data_pipeline.coat_dataset import load_coat_raw_features
from src.data_pipeline.yahoo_dataset import load_yahoo_raw
from src.data_pipeline.kuairand_dataset import load_kuairand_processed, subset_kuairand_users
from src.training.config import released_cdr_config
from src.utils.helpers import set_seed,RESULTS_DIR,CHECKPOINT_DIR
from src.utils.artifacts import source_signature
from src.utils import training_log


def source_metrics(model,x,y,k=5,include_empty=True,bounded=True):
    device=next(model.parameters()).device
    with torch.no_grad():
        pred=model(torch.as_tensor(x[:,0],device=device).long(),torch.as_tensor(x[:,1],device=device).long()).sigmoid().cpu().numpy()
    ndcg,recall,recall_all,recall_bounded,precision,hitrate=[],[],[],[],[],[]
    for user in np.unique(x[:,0]):
        mask=x[:,0]==user
        labels,scores=y[mask],pred[mask]
        if not include_empty and not labels.sum(): continue
        top=np.argsort(-scores)[:k]
        discount=1/np.log2(np.arange(2,len(top)+2))
        ideal=np.sort(labels)[::-1][:k]
        denominator=float((ideal*discount).sum())
        ndcg.append(float((labels[top]*discount).sum()/denominator) if denominator else 1.)
        recall_denom=ideal.sum() if bounded else labels.sum()
        recall.append(float(labels[top].sum()/recall_denom) if recall_denom else 1.)
        hits=labels[top].sum()
        # Auxiliary metrics use the same eligible users and ranking as source.
        # Preserve its empty-user Recall=1 convention; precision/hit-rate are 0.
        recall_all.append(float(hits/labels.sum()) if labels.sum() else 1.)
        recall_bounded.append(float(hits/ideal.sum()) if ideal.sum() else 1.)
        precision.append(float(hits/k))
        hitrate.append(float(hits>0))
    positive = np.asarray(y) > 0
    n_positive, n_negative = int(positive.sum()), int((~positive).sum())
    auc = ((rankdata(pred)[positive].sum() - n_positive * (n_positive + 1) / 2)
           / (n_positive * n_negative)) if n_positive and n_negative else None
    metrics={"NDCG@5":float(np.mean(ndcg)),
            "Recall@5":float(np.mean(recall_all)),"Recall@5_bounded":float(np.mean(recall_bounded)),
            "Precision@5":float(np.mean(precision)),"HitRate@5":float(np.mean(hitrate)),
            "AUC_global":None if auc is None else float(auc),"users":len(ndcg)}
    metrics['Recall@5_bounded' if bounded else 'Recall@5']=float(np.mean(recall))
    return metrics


def source_data(dataset, data_dir=None, smoke_users=None):
    """Canonical data before training RNG/shuffle; evaluation can reload identically."""
    adaptations=[]
    if dataset=="coat":
        raw=load_coat_raw_features(data_dir)
        u,i=np.nonzero(raw["train_matrix"]);x=np.stack([u,i],1);y=raw["train_matrix"][u,i].astype(int)
        u,i=np.nonzero(raw["test_matrix"]);xt=np.stack([u,i],1);yt=raw["test_matrix"][u,i].astype(int)
        n_users,n_items=raw["train_matrix"].shape
        calibration=yt
    elif dataset=="yahoo":
        raw=load_yahoo_raw(data_dir)
        x,y=raw["train_ratings"][:,:2],raw["train_ratings"][:,2].copy()
        xt,yt=raw["random_ratings"][:,:2],raw["random_ratings"][:,2].copy()
        # Preserve source one-based IDs and its dummy zero row/column.
        n_users,n_items=int(x[:,0].max()+1),int(x[:,1].max()+1)
        calibration=yt
    elif dataset=="kuairand":
        data=load_kuairand_processed(data_dir=data_dir)
        if smoke_users is not None: data=subset_kuairand_users(data,smoke_users)
        x=np.stack([data['train_u'],data['train_i']],1);y=data['train_y'].astype(int)
        def rows(split):
            pairs=[(u,int(i)) for u,items in data[split+'_candidates'].items() for i in items]
            labels=[int(i in data[split+'_ground_truth'].get(u,set())) for u,i in pairs]
            return np.asarray(pairs,dtype=int),np.asarray(labels,dtype=int)
        xt,yt=rows('test');_,calibration=rows('val')
        n_users,n_items=data['n_users'],data['n_items']
        adaptations=['local KuaiRand preprocessing/user split; original processed CSVs unavailable',
            'array trainer sampling instead of source Torch DataLoader',
            'zero-based local user IDs, including user 0 in evaluation',
            'global AUC half-credit ties instead of source arbitrary tie ranks']
    else: raise ValueError('Unsupported CDR source dataset')
    if dataset!='kuairand':
        y,yt,calibration=(y>=3).astype(int),(yt>=3).astype(int),(calibration>=3).astype(int)
    h=hashlib.sha256()
    for a in (x,y,xt,yt,calibration):
        a=np.ascontiguousarray(a);h.update(str((a.shape,a.dtype.str)).encode());h.update(a.tobytes())
    return dict(x=x,y=y,xt=xt,yt=yt,calibration=calibration,n_users=n_users,n_items=n_items,
                sha256=h.hexdigest(),adaptations=adaptations)


def run_source(dataset,epochs=1000,seed=2020,threads=2,output_dir=None,*,data_dir=None,
               smoke_users=None,embedding_dim=None,lr=None,batch_size=None,weight_decay=None,
               un_thres=None,dropout_rate=None,checkpoint_dir=None,device=None):
    if epochs<1 or threads<1: raise ValueError("Invalid source run options")
    torch.set_num_threads(threads)
    set_seed(seed)
    data=source_data(dataset,data_dir,smoke_users)
    x,y,xt,yt=(data[k] for k in ('x','y','xt','yt'))
    n_users,n_items=data['n_users'],data['n_items']
    if dataset=='yahoo':
        order=np.arange(len(x));np.random.shuffle(order);x,y=x[order],y[order]
    cfg=released_cdr_config(dataset,epochs=epochs,embedding_dim=embedding_dim,lr=lr,batch_size=batch_size,
        weight_decay=weight_decay,un_thres=un_thres,dropout_rate=dropout_rate)
    cfg.update(tol=1e-5,stop=5,mc_samples=10)
    if smoke_users is not None: cfg['batch_size']=min(cfg['batch_size'],len(x))
    model=ReleasedCDR(n_users,n_items,cfg["embedding_dim"],cfg["un_thres"],cfg["dropout_rate"])
    # Model creation must precede the source calibration RNG draw.
    labels=data['calibration'];order=np.arange(len(labels));np.random.shuffle(order);selected=order[:int(.05*len(order))]
    if len(selected)<1: raise ValueError('Source calibration needs at least 20 random ratings')
    if dataset=='kuairand' and smoke_users is not None and len(np.unique(labels[selected]))<2:
        selected=order
        data['adaptations'].append('smoke-only calibration expanded to all validation rows to retain both classes')
    inverse,calibration=released_inverse_propensity(x,y,labels[selected])
    from src.utils.helpers import get_device
    model=model.to(get_device(device or 'cpu'))
    sampler='permutation'
    adaptations=list(data['adaptations'])
    if n_users*n_items>20_000_000:
        sampler='replacement';adaptations.append('bounded-memory catalog sampling with replacement')
    training_log.header('CDR',dataset,{'Thiết bị':str(next(model.parameters()).device),
        'Dim':cfg['embedding_dim'],'LR':cfg['lr'],'Batch':cfg['batch_size'],
        'Optimizer':'adam','Loss':'bce','Seed':seed,'Dropout':cfg['dropout_rate'],
        'Variance threshold':cfg['un_thres']},
        'Source protocol | calibration 5% validation' if dataset=='kuairand' else
        'Source protocol | rating >=3 | calibration 5% random | chấm toàn random log')
    def report_epoch(epoch,stats):
        training_log.progress('CDR',dataset,epoch,epochs,{'Train Rec Loss':stats['rec_loss'],
            'Train Imp Loss':stats['imp_loss'],'Filtered':f"{stats['filtered_fraction']:.1%}"})
    history=fit_released(model,x,y,inverse,epochs=epochs,batch_size=cfg["batch_size"],lr=cfg["lr"],
                         weight_decay=cfg["weight_decay"],G=cfg["G"],catalog_sampler=sampler,
                         on_progress=report_epoch)
    training_log.finish('CDR',dataset,len(history),epochs,selected_epoch=len(history))
    metrics=source_metrics(model,xt,yt,include_empty=dataset!='kuairand',bounded=dataset!='kuairand')
    run_id=datetime.now().strftime("%Y%m%d_%H%M%S")+"_"+uuid4().hex[:8]
    cp=Path(checkpoint_dir or Path(CHECKPOINT_DIR)/"cdr_source")/run_id
    cp.mkdir(parents=True,exist_ok=False)
    checkpoint=cp/f"{dataset}.pt"
    metadata=dict(model='cdr_source',architecture_version='cdr_released_v1',dataset=dataset,
        code_sha256=source_signature(),config=dict(cfg,seed=seed,selection='source_train_loss_last',
        implementation='cdr_released',catalog_sampler=sampler),data=dict(sha256=data['sha256']),
        model_kwargs=dict(num_users=n_users,num_items=n_items,embedding_dim=cfg['embedding_dim'],
                          un_thres=cfg['un_thres'],dropout_rate=cfg['dropout_rate']),
        protocol=dict(metric_revision='cdr_source_v1',scope='cdr_source_protocol',
            recall_denominator='all_positive' if dataset=='kuairand' else 'min(k,n_positive)',
            calibration='validation_5_percent' if dataset=='kuairand' else 'evaluation_5_percent',
            supplementary_metrics=['Recall@5_bounded' if dataset=='kuairand' else 'Recall@5','Precision@5','HitRate@5'],
            auxiliary_aggregation='same source-eligible users; empty users: Recall=1, precision/hit-rate=0',
            paper_scores_directly_comparable=False),adaptations=adaptations,
        data_dir=str(data_dir) if data_dir else None,smoke_users=smoke_users)
    torch.save(dict(model_state_dict=model.state_dict(),metadata=metadata,epochs_run=len(history)),checkpoint)
    result=dict(identity=dict(code_sha256=source_signature(),upstream=UPSTREAM_URL,seed=seed,dataset=dataset),
        scope="published_script_conditions_not_project_held_out",config=cfg,source_calibration=calibration,
        test_labels_used_for_propensity=dataset!='kuairand',calibration_rows=len(selected),positive_threshold=1 if dataset=='kuairand' else 3,
        evaluation_pool="local_held_out_random_log" if dataset=='kuairand' else "entire_random_log",
        zero_positive_score=None if dataset=='kuairand' else 1,recall_denominator=metadata['protocol']['recall_denominator'],
        raw_id_convention="source_unchanged",checkpoint_path=str(checkpoint),training_history=history,
        metrics=metrics,quick_run=epochs<1000,metadata=metadata,evaluation_scope='cdr_source_protocol',
        best_epoch=len(history),best_val_ndcg=None,selection_origin='source_train_loss_last',epochs_run=len(history),
        limitation="Paper prose and released script differ; these source-protocol scores are not shared benchmark results")
    result.update(metrics)
    folder=Path(output_dir or RESULTS_DIR);folder.mkdir(parents=True,exist_ok=True)
    path=folder/f"cdr_source_{dataset}_{run_id}.json"
    with path.open("x",encoding="utf-8") as stream: json.dump(result,stream,ensure_ascii=False,indent=2)
    md=path.with_suffix(".md")
    with md.open("x",encoding="utf-8") as stream:
        stream.write(f"# CDR released script: {dataset}\n\nDiagnostic under published script conditions; NOT project held-out evaluation.\n\n"
                     f"Protocol: {metadata['protocol']}. Adaptations: {adaptations}.\n\n"
                     f"Metrics: {metrics}.\n\n"
                     f"Seed {seed}; epochs run {len(history)}; source {UPSTREAM_COMMIT}.\n")
    training_log.result('CDR',dataset,metrics,'SOURCE EVAL',checkpoint)
    print(f"[CDR][{dataset.upper()}] Báo cáo: {path}",flush=True)
    return result


def evaluate_source_checkpoint(path,device='cpu'):
    state=torch.load(path,map_location=device,weights_only=True)
    meta=state['metadata']
    data=source_data(meta['dataset'],meta.get('data_dir'),meta.get('smoke_users'))
    if data['sha256']!=meta['data']['sha256']: raise ValueError('Source checkpoint data differs')
    model=ReleasedCDR(**meta['model_kwargs']).to(device)
    model.load_state_dict(state['model_state_dict'])
    return dict(source_metrics(model,data['xt'],data['yt'],include_empty=meta['dataset']!='kuairand',
                bounded=meta['dataset']!='kuairand'),metadata=meta,evaluation_scope='cdr_source_protocol')

