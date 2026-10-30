"""Released CDR algorithm with project validation/test separation."""
import hashlib
import os

import numpy as np
import torch

from src.models.cdr.released import ReleasedCDR, fit_released, released_inverse_propensity, UPSTREAM_COMMIT, UPSTREAM_URL
from src.models.cdr.propensity import validation_labels, propensity_diagnostics
from src.evaluation.evaluator import evaluate_unbiased_model
from src.training.config import released_cdr_config
from src.utils.artifacts import make_metadata, checkpoint_path, save_checkpoint, evaluate_checkpoint, validate_training
from src.utils.helpers import set_seed, get_device, CHECKPOINT_DIR
from src.utils import training_log


def train_released_cdr(dataset_name, data_dict, *, epochs=None, patience=5,
                       embedding_dim=None, lr=None, batch_size=None, weight_decay=None,
                       un_thres=None, dropout_rate=None, evaluate_test=True, seed=42,
                       device=None, checkpoint_dir=None, checkpoint_tag="manual",
                       selection="validation_ndcg",calibration_fraction=1.,G=None):
    cfg = released_cdr_config(dataset_name, epochs=epochs, embedding_dim=embedding_dim,
        lr=lr,batch_size=batch_size,weight_decay=weight_decay,un_thres=un_thres,dropout_rate=dropout_rate,G=G)
    validate_training(epochs=cfg["epochs"],batch_size=cfg["batch_size"],lr=cfg["lr"],patience=patience,
                      embedding_dim=cfg["embedding_dim"])
    data = data_dict
    set_seed(seed)
    device = get_device(device)
    kwargs = dict(num_users=data["n_users"],num_items=data["n_items"],embedding_dim=cfg["embedding_dim"],
                  un_thres=cfg["un_thres"],dropout_rate=cfg["dropout_rate"])
    model = ReleasedCDR(**kwargs).to(device)
    x = np.stack([data["train_u"],data["train_i"]],1)
    y = data["train_y"]
    labels=validation_labels(data)
    if not 0 < calibration_fraction <= 1: raise ValueError('Invalid calibration fraction')
    if calibration_fraction<1:
        order=np.random.permutation(len(labels));labels=labels[order[:max(1,int(len(labels)*calibration_fraction))]]
    inverse, calibration = released_inverse_propensity(x,y,labels,
        population_size=None if selection=='source_train_loss_last' else data["n_users"]*data["n_items"])
    calibration.update(source="random_validation_only",test_labels_used=False)
    sampler='replacement' if data['n_users']*data['n_items']>20_000_000 else 'permutation'
    config = dict(cfg, seed=seed,device=str(device),patience=patience,
        catalog_sampler=sampler,
        loss="bce",implementation="cdr_released",method_reference=UPSTREAM_URL,upstream_commit=UPSTREAM_COMMIT,
        paper_reproduction=False,initialization="independent_source_xavier_rec_default_normal_imp",
        filter_mode="variance",output_probability_dropout=True,imputation_bce="BCE(imp,detached_rec)",
        propensity="naive_bayes_validation",propensity_calibration=calibration,
        propensity_diagnostics=propensity_diagnostics(inverse.numpy()),
        propensity_sha256=hashlib.sha256(inverse.numpy().tobytes()).hexdigest(),
        selection=selection,source_adaptations=["project labels/split/evaluator", "validation-only propensity calibration", selection])
    metadata = make_metadata("cdr_released",dataset_name,data,config,kwargs)
    path = checkpoint_path(checkpoint_dir or os.path.join(CHECKPOINT_DIR,"cdr_released"),
                           f"{dataset_name}_cdr_released_{checkpoint_tag}",metadata)
    best = dict(ndcg=-1.,epoch=0)
    training_log.header('CDR',dataset_name,{'Thiết bị':str(device),'Dim':cfg['embedding_dim'],
        'LR':cfg['lr'],'Batch':cfg['batch_size'],'Optimizer':'adam','Loss':'bce','Seed':seed},
        f"Validation calibration | selection: {selection}")

    def on_epoch(epoch,stats):
        model.eval()
        val = evaluate_unbiased_model(model,data["val_candidates"],data["val_ground_truth"],
            include_zero_positive_users=data.get("evaluation_include_zero_positive_users",False))
        stats["validation_ndcg"] = val["NDCG@5"]
        if val["NDCG@5"] > best["ndcg"]:
            best.update(ndcg=val["NDCG@5"],epoch=epoch)
            save_checkpoint(model,path,metadata,epoch,dict(val,cdr_training=dict(stats)))
        if selection=='validation_ndcg':
            training_log.progress('CDR',dataset_name,epoch,cfg['epochs'],{
                'Train Rec Loss':stats['rec_loss'],'Train Imp Loss':stats['imp_loss'],
                'Val NDCG@5':val['NDCG@5'],'Val Recall@5':val['Recall@5'],
                'Filtered':f"{stats['filtered_fraction']:.1%}"})
        else:
            training_log.result('CDR',dataset_name,val,'VALIDATION')
        model.train()
        return epoch-best["epoch"] >= patience

    if selection not in ('validation_ndcg','source_train_loss_last'): raise ValueError('Unknown CDR selection')
    def report_training(epoch,stats):
        training_log.progress('CDR',dataset_name,epoch,cfg['epochs'],{
            'Train Rec Loss':stats['rec_loss'],'Train Imp Loss':stats['imp_loss'],
            'Filtered':f"{stats['filtered_fraction']:.1%}"})
    history = fit_released(model,x,y,inverse,epochs=cfg["epochs"],batch_size=cfg["batch_size"],
        lr=cfg["lr"],weight_decay=cfg["weight_decay"],G=cfg["G"],samples=10,
        stop=patience,
        on_epoch=on_epoch if selection=='validation_ndcg' else None,catalog_sampler=sampler,
        on_progress=report_training if selection=='source_train_loss_last' else None)
    if selection=='source_train_loss_last':
        on_epoch(len(history),history[-1])
    training_log.finish('CDR',dataset_name,len(history),cfg['epochs'],selected_epoch=best['epoch'],
        best_label='Val NDCG@5',best=best['ndcg'])
    if not evaluate_test:
        return dict(best_val_ndcg=best["ndcg"],best_epoch=best["epoch"],epochs_run=len(history),
                    metadata=metadata,checkpoint_path=path,training_history=history)
    metrics=evaluate_checkpoint(path,data,device)
    training_log.result('CDR',dataset_name,metrics,'TEST',path)
    return dict(metrics,epochs_run=len(history),training_history=history)
