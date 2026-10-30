# -*- coding: utf-8 -*-
"""
Huấn luyện iDCF hai giai đoạn theo mã tác giả (github.com/BgmLover/iDCF):
  1. ExposureIVAE trên exposure train và đặc trưng user (proxy W) -> mean/std C.
  2. IDCFModel với MSE trên điểm thô; chọn epoch bằng validation NDCG@5, lưu checkpoint,
     chấm test một lần qua evaluate_checkpoint.
Đầu vào theo dataset:
  - Coat: exposure = train.ascii > 0; W = Z = user_features.ascii (14 cột one-hot).
  - KuaiRand: exposure = mọi cặp (user, video) trong standard log đã lọc (cả click lẫn không);
    W = đặc trưng user one-hot như notebook tác giả; Z = tỷ lệ exposure theo tab.
Project: ViFarm (services/recsys)
"""

import hashlib
import os

import numpy as np
import torch
import torch.nn.functional as F
from scipy import sparse

from src.models.idcf.idcf_model import IDCFModel
from src.models.ividr.ividr_reference import IViDRMarginalMF
from src.models.idcf.ivae import train_exposure_ivae
from src.models.ividr.ividr_staged import DEFAULT_ALPHA_RESIDUAL
from src.data_pipeline.coat_dataset import load_coat_processed, load_coat_raw_features
from src.data_pipeline.yahoo_dataset import load_yahoo_processed
from src.data_pipeline.kuairand_dataset import load_kuairand_author_proxy, load_kuairand_tab_instruments
from src.evaluation.evaluator import evaluate_unbiased_model
from src.evaluation.protocol import TOP_K
from src.utils.artifacts import (checkpoint_path, evaluate_checkpoint, make_metadata, save_checkpoint,
                                 validate_training)
from src.utils.helpers import CHECKPOINT_DIR, set_seed, get_device
from src.utils import training_log


def coat_inputs(data):
    raw = load_coat_raw_features(data.get("data_dir"))
    return {"exposure": raw["train_matrix"] > 0, "proxy": raw["user_features"],
            "instrument": raw["user_features"]}


def kuairand_inputs(data):
    n = len(data["train_u"])
    exposure = sparse.csr_matrix((np.ones(n, dtype=np.float32), (data["train_u"], data["train_i"])),
                                 shape=(data["n_users"], data["n_items"]))
    instrument, _ = load_kuairand_tab_instruments(data["user_mapping"], data["video_mapping"], data.get("data_dir"))
    return {"exposure": exposure, "proxy": load_kuairand_author_proxy(data["user_mapping"], data.get("data_dir")),
            "instrument": instrument}


def yahoo_inputs(data):
    exposure = sparse.csr_matrix((np.ones(len(data["train_u"]),dtype=np.float32),
        (data["train_u"],data["train_i"])),shape=(data["n_users"],data["n_items"]))
    return dict(exposure=exposure,proxy=data["user_features"],instrument=data["user_features"])


DATASET_INPUTS = {"coat": coat_inputs, "kuairand": kuairand_inputs, "yahoo": yahoo_inputs}

# Giai đoạn 2 theo iDCF.py: lr 5e-4, wd 1e-6, dim 64, ≤ 100 epoch; KuaiRand lr 1e-4 (nhánh chạy nhiều seed
# của tác giả), batch 2048 và patience 5 (argparser.py). Coat stage-1 dimensions
# follow the released tuned checkpoint, not the unrelated runnable sample_config.
# Its optimizer settings are local defaults; the checkpoint does not encode them.
IDCF_CONFIG = {
    # Yahoo is a dataset extension with observed survey proxies, not a published
    # iDCF Yahoo reproduction. Missing survey users have explicit missing codes.
    "yahoo": {"ivae":dict(latent_dim=16,hidden_dim=32,n_layers=3,batch_size=512,patience=100),
              "train":dict(lr=5e-4,weight_decay=1e-6,embedding_dim=64,batch_size=2048,
                           patience=5,init_scheme="author_uniform")},
    "coat": {"ivae": dict(latent_dim=16, hidden_dim=32, n_layers=3, batch_size=512, patience=100),
             "train": dict(lr=5e-4, weight_decay=1e-6, embedding_dim=64, batch_size=512, patience=5, init_scheme="author_uniform")},
    "kuairand": {"ivae": dict(latent_dim=32, hidden_dim=64, n_layers=2, batch_size=2048, patience=5),
                 "train": dict(lr=1e-4, weight_decay=1e-6, embedding_dim=64, batch_size=2048, patience=5, init_scheme="author_uniform")},
}


def idcf_confounders(inputs, seed=42, latent_dim=16, **ivae_kwargs):
    """Giai đoạn 1: C ~ q(C | A, W) từ iVAE trên exposure."""
    return train_exposure_ivae(inputs["exposure"], inputs["proxy"], latent_dim=latent_dim, seed=seed, **ivae_kwargs)


def train_idcf(data, confounder_mean, confounder_std, dataset_name="coat", seed=42, lr=5e-4, weight_decay=1e-6,
               embedding_dim=64, batch_size=512, epochs=100, patience=5, evaluate_test=True,
               checkpoint_dir=None, checkpoint_tag="manual", extra_config=None, device=None,
               init_scheme="author_uniform", loss_name="mse", negative_weight=1.0):
    validate_training(lr=lr, embedding_dim=embedding_dim, batch_size=batch_size, epochs=epochs, patience=patience)
    if loss_name not in ('mse', 'bce'):
        raise ValueError('Feedback loss must be mse or bce')
    if not 0 < negative_weight <= 1 or (negative_weight != 1 and loss_name != 'bce'):
        raise ValueError('negative_weight must be in (0, 1] and is only defined for BCE feedback')
    variant = (extra_config or {}).get('variant')
    if loss_name == 'bce' and variant not in ('ividr_equations_bce','ividr_reference_bce_v2'):
        raise ValueError('BCE feedback is reserved for the explicit IViDR equations implementation')
    if variant=='ividr_reference_bce_v2' and loss_name!='bce':
        raise ValueError('IViDR reference objective is BCE')
    if variant=='lcdr' and loss_name!='mse':
        raise ValueError('LCDR keeps the iDCF squared-error feedback model')
    feedback_model = ('ividr_reference' if variant=='ividr_reference_bce_v2' else
                      'ividr_bce' if loss_name == 'bce' else 'lcdr' if variant=='lcdr' else 'idcf')
    mean = torch.as_tensor(confounder_mean, dtype=torch.float32).detach().cpu()
    std = torch.as_tensor(confounder_std, dtype=torch.float32).detach().cpu()
    if (mean.ndim != 2 or mean.shape != std.shape or mean.shape[0] != data["n_users"]
            or not torch.isfinite(mean).all() or not torch.isfinite(std).all() or (std < 0).any()):
        raise ValueError("Confounders must be finite, equally shaped, with nonnegative std")
    if len(data["train_y"]) == 0:
        raise ValueError("Training data is empty")
    device = get_device(device)
    set_seed(seed)
    model_class = IViDRMarginalMF if feedback_model=='ividr_reference' else IDCFModel
    model = model_class(data["n_users"], data["n_items"], mean.shape[1], embedding_dim=embedding_dim,
                      init_scheme=init_scheme).to(device)
    model.set_confounders(mean, std)
    optimizer = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=weight_decay)
    confounders = hashlib.sha256(mean.numpy().tobytes() + std.numpy().tobytes()).hexdigest()[:16]
    metadata = make_metadata(
        feedback_model, dataset_name, data,
        dict(lr=lr, weight_decay=weight_decay, batch_size=batch_size, epochs=epochs, patience=patience,
             seed=seed, loss=loss_name, device=str(device), confounders_sha256=confounders,
             **({'negative_weight': negative_weight} if negative_weight != 1 else {}),
             paper_reproduction=False, **dict({'method_reference':'iDCF_KDD2023_MFMF'}, **(extra_config or {}))),
        dict(num_users=data["n_users"], num_items=data["n_items"], latent_dim=mean.shape[1],
             embedding_dim=embedding_dim, init_scheme=init_scheme))
    save_path = checkpoint_path(checkpoint_dir or os.path.join(CHECKPOINT_DIR, "idcf"),
                                f"{dataset_name}_{feedback_model}_{checkpoint_tag}", metadata)
    u = torch.as_tensor(data["train_u"], dtype=torch.long, device=device)
    i = torch.as_tensor(data["train_i"], dtype=torch.long, device=device)
    y = torch.as_tensor(data["train_y"], dtype=torch.float32, device=device)
    include = data.get("evaluation_include_zero_positive_users", True)
    best = {"ndcg": -1.0, "epoch": 0}
    label=('IViDR' if loss_name=='bce' else
           'IViDR-approx' if (extra_config or {}).get('variant')=='ividr_staged' else
           'LCDR' if variant=='lcdr' else 'iDCF')
    feedback_loss=F.binary_cross_entropy_with_logits if loss_name=='bce' else F.mse_loss
    if loss_name=='bce' and (not torch.isfinite(y).all() or not ((y==0)|(y==1)).all()):
        raise ValueError('IViDR BCE requires binary training labels')
    training_log.header(label,dataset_name,{'Thiết bị':str(device),'Dim':embedding_dim,
        'LR':lr,'Batch':batch_size,'Optimizer':'adam','Loss':loss_name,'Seed':seed},
        'Held-out | chọn checkpoint bằng Val NDCG@5',stage='Giai đoạn 2/2: feedback')
    for epoch in range(1, epochs + 1):
        model.train()
        total_loss, count = 0., 0
        for idx in torch.randperm(len(y), device=device).split(batch_size):
            if negative_weight == 1:
                loss = feedback_loss(model(u[idx], i[idx], sample=True), y[idx])
            else:
                # Weighted BCE: rated-but-disliked exposures count negative_weight.
                weights = torch.where(y[idx] > 0, 1., negative_weight)
                loss = (F.binary_cross_entropy_with_logits(model(u[idx], i[idx], sample=True), y[idx],
                                                           reduction='none') * weights).mean()
            if not torch.isfinite(loss):
                raise FloatingPointError("Non-finite iDCF training loss")
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            total_loss += float(loss.detach()) * len(idx)
            count += len(idx)
        model.eval()
        val = evaluate_unbiased_model(model, data["val_candidates"], data["val_ground_truth"], k=TOP_K,
                                      include_zero_positive_users=include)
        training_log.progress(label,dataset_name,epoch,epochs,{'Train Loss':total_loss/max(count,1),
            'Val NDCG@5':val['NDCG@5'],'Val Recall@5':val['Recall@5'],
            'Val HR@5':val['HitRate@5']},stage='feedback')
        if val["NDCG@5"] > best["ndcg"]:
            best.update(ndcg=val["NDCG@5"], epoch=epoch)
            save_checkpoint(model, save_path, metadata, epoch, val)
        elif epoch - best["epoch"] >= patience:
            break
    training_log.finish(label,dataset_name,epoch,epochs,selected_epoch=best['epoch'],
        best_label='Best Val NDCG@5',best=best['ndcg'],stage='feedback')
    if not evaluate_test:
        return {"best_val_ndcg": best["ndcg"], "best_epoch": best["epoch"], "epochs_run": epoch,
                "checkpoint_path": save_path, "metadata": metadata}
    metrics=evaluate_checkpoint(save_path,data,device)
    training_log.result(label,dataset_name,metrics,'TEST',save_path)
    return {**metrics, "epochs_run": epoch}


def fit_idcf_pipeline(data, dataset_name, seed=42, item_emb=None, alpha_residual=DEFAULT_ALPHA_RESIDUAL,
                      checkpoint_dir=None, checkpoint_tag="manual", evaluate_test=True, epochs=100,
                      ivae_epochs=2000, train_overrides=None, ivae_overrides=None, device=None):
    """iDCF for no treatment; otherwise learned-IV/BCE IViDR (legacy MSE weights remain readable)."""
    if item_emb is not None:
        from src.models.ividr.train_ividr import fit_ividr_pipeline
        return fit_ividr_pipeline(data,dataset_name,seed=seed,item_emb=item_emb,
            checkpoint_dir=checkpoint_dir,checkpoint_tag=checkpoint_tag,evaluate_test=evaluate_test,
            epochs=epochs,ivae_epochs=ivae_epochs,train_overrides=train_overrides,
            ivae_overrides=ivae_overrides,device=device)
    config = {stage: dict(values) for stage, values in IDCF_CONFIG[dataset_name].items()}
    train_overrides, ivae_overrides = train_overrides or {}, ivae_overrides or {}
    if set(train_overrides) - set(config["train"]):
        raise ValueError("Unknown stage 2 override")
    allowed_ivae = {"latent_dim", "hidden_dim", "n_layers", "lr", "weight_decay", "l2_penalty",
                    "batch_size", "patience", "beta_max", "train_ratio", "split_seed",
                    "validation_samples", "validation_seed", "verbose"}
    if set(ivae_overrides) - allowed_ivae:
        raise ValueError("Unknown stage 1 override")
    config["train"].update(train_overrides)
    config["ivae"].update(ivae_overrides)
    device = get_device(device)
    inputs = DATASET_INPUTS[dataset_name](data)
    label='iDCF'
    training_log.header(label,dataset_name,{'Thiết bị':str(device),
        'Latent dim':config['ivae']['latent_dim'],'Hidden dim':config['ivae']['hidden_dim'],
        'Layers':config['ivae']['n_layers'],'LR':config['ivae'].get('lr',5e-4),
        'Batch':config['ivae']['batch_size'],'Seed':seed},
        'Exposure-user validation | chọn ELBO sau full-beta warm-up',stage='Giai đoạn 1/2: iVAE')
    def ivae_progress(epoch,stats):
        training_log.progress(label,dataset_name,epoch,ivae_epochs,{
            'Train ELBO+L2':stats['train_loss'],'Val ELBO':stats['val_loss'],
            'Beta':stats['beta'],'Phase':stats['phase']},stage='iVAE')
    config['ivae']['on_progress']=ivae_progress
    mean, std, info = idcf_confounders(inputs, seed=seed, epochs=ivae_epochs, device=device, **config["ivae"])
    extra = {"variant": "idcf"}
    config['ivae'].pop('on_progress')
    ivae_info=info.get('base',info)
    if 'epochs_run' in ivae_info:
        training_log.finish(label,dataset_name,ivae_info['epochs_run'],ivae_epochs,
            selected_epoch=ivae_info['best_epoch'],best_label='Best Val ELBO',
            best=ivae_info['best_val_loss'],stage='iVAE')
    extra["confounder_training"] = info
    if dataset_name == "yahoo":
        extra["proxy_features"] = data["user_feature_info"]
        extra["dataset_extension"] = "Yahoo survey proxies; no original iDCF Yahoo result claimed"
    result = train_idcf(data, mean, std, dataset_name, seed=seed, epochs=epochs, evaluate_test=evaluate_test,
                        checkpoint_dir=checkpoint_dir, checkpoint_tag=checkpoint_tag, extra_config=extra,
                        device=device, **config["train"])
    return {**result, "confounder_info": info}


if __name__ == "__main__":
    r = fit_idcf_pipeline(load_coat_processed(), "coat")
    print({k: r[k] for k in ("NDCG@5", "Recall@5", "best_epoch", "checkpoint_path")})
