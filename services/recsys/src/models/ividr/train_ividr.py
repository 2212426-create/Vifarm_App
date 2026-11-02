"""Train learned IV reconstruction/iVAE, then validation-selected BCE feedback."""
import copy
import hashlib
import os
from pathlib import Path

import numpy as np
import torch

from src.models.idcf.ivae import binary_exposure
from src.models.ividr.ividr_model import DualExposureIVAE, instrument_bases
from src.models.ividr.ividr_reference import PaperExposureIVAE
from src.utils.artifacts import source_signature
from src.utils.helpers import get_device, set_seed, CHECKPOINT_DIR
from src.utils import training_log

PAPER_URL = "https://arxiv.org/html/2410.12451"
PAPER_FEEDBACK_GRID = tuple((lr, wd) for lr in (1e-3, 5e-4, 1e-4, 5e-5, 1e-5) for wd in (1e-5, 1e-6))
# v3 option (27/10/2026): v2 gates shrink Eq. (10)'s added term to ~0.3% of A. v3 keeps it at
# ||A_u|| per user, but on Coat seeds 42-44 the encoder still ignored it (posterior cosine
# ~0.999) and validation NDCG did not improve, so v2 stays the default.
DEFAULT_EQ10_BRIDGE = 'tied_item_lift'
IVIDR_VERSIONS = {'tied_item_lift': 'reference_v2', 'tied_item_lift_rownorm': 'reference_v3_rownorm'}
# Default since 28/10/2026 (user decision after the root-cause study): stage-1 prior mean 0 as in
# the iDCF code (Eq. 42 learns it) and BCE with negatives weighted .1 (Eq. 25 is unweighted).
# Coat 10 seeds: test NDCG@5 .5657 vs .5325 for the paper-literal setting. Paper-literal run:
# ivae_overrides=dict(prior_mean='learned'), negative_weight=1.
DEFAULT_PRIOR_MEAN = 'zero'
DEFAULT_NEGATIVE_WEIGHT = .1


def train_dual_ivae(inputs, item_emb, *, epochs=2000, latent_dim=16, hidden_dim=32,
                    n_layers=3, batch_size=512, lr=5e-4, weight_decay=1e-6,
                    l2_penalty=0., patience=100, beta_max=1., train_ratio=.8,
                    split_seed=1234, validation_samples=8, validation_seed=1234,
                    seed=42, treatment_dim=32, device=None, verbose=False,
                    on_progress=None, checkpoint_path=None, implementation='legacy_v1',
                    eq10_bridge='tied_item_lift', reconstruction='full', prior_mean='learned'):
    if (epochs < 1 or batch_size < 1 or patience < 1 or lr <= 0 or weight_decay < 0
            or l2_penalty < 0 or beta_max < 0 or validation_samples < 1):
        raise ValueError("Invalid IViDR training configuration")
    a = binary_exposure(inputs['exposure'])
    w = torch.as_tensor(np.asarray(inputs['proxy']), dtype=torch.float32)
    n, items = a.shape
    if not 0 < int(n*train_ratio) < n or len(w) != n or not torch.isfinite(w).all():
        raise ValueError("IViDR requires aligned features and nonempty exposure-user splits")
    if implementation not in ('legacy_v1', 'reference_v2'):
        raise ValueError('Unknown IViDR stage1 implementation')
    device = get_device(device)
    set_seed(seed)
    if implementation == 'reference_v2':
        model = PaperExposureIVAE(items, w.shape[1], latent_dim, hidden_dim, n_layers,
            item_emb, a, inputs['instrument'], treatment_dim, eq10_bridge, reconstruction, prior_mean).to(device)
        info = dict(feature_embedding='trainable linear user-feature embedding',
            gate_inputs='full per-item Z with factorized learned column weights; no fixed mean',
            projection='QR(E U_j); exact Z_j Z_j^dagger while embedding retains rank',
            dimension_bridge=('tied_item_lift: A + (A T_re) T_0^T / sqrt(d)' if eq10_bridge=='tied_item_lift'
                else 'tied_item_lift_rownorm: A + P ||A_u|| / ||P_u||, P = (A T_re) T_0^T / sqrt(d)'),
            eq10_bridge=eq10_bridge, reconstruction=reconstruction, prior_mean=prior_mean,
            eq10_completion_is_local=True)
    else:
        q, summary, info = instrument_bases(a, inputs['instrument'], treatment_dim, split_seed)
        model = DualExposureIVAE(items, w.shape[1], latent_dim, hidden_dim, n_layers,
                                  item_emb, q, summary).to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=weight_decay)
    rng = np.random.RandomState(split_seed)
    train_users = np.sort(rng.choice(n, int(n*train_ratio), replace=False))
    val_users = np.setdiff1d(np.arange(n), train_users)
    w = w.to(device)

    def batch(users):
        rows = a[users]
        x = torch.as_tensor(rows.toarray() if hasattr(rows, 'toarray') else rows,
                            dtype=torch.float32, device=device)
        return x, w[torch.as_tensor(users, dtype=torch.long, device=device)]

    def validation():
        generator = torch.Generator(device=device).manual_seed(validation_seed)
        model.eval()
        total = 0.
        with torch.no_grad():
            for users in np.array_split(val_users, max(1, int(np.ceil(len(val_users)/batch_size)))):
                x, features = batch(users)
                v = sum(float(model.dual_elbo(x, features, beta_max, generator))
                        for _ in range(validation_samples))/validation_samples
                total += v*len(users)
        return total/len(val_users)

    steps_per_epoch = int(np.ceil(len(train_users)/batch_size))
    anneal_steps = max(int(.2*epochs*steps_per_epoch/max(beta_max, 1e-12)), 1)
    best = dict(value=float('inf'), state=None, epoch=0)
    warmup = dict(value=float('inf'), state=None, epoch=0)
    steps, stale = 0, 0
    history = []
    for epoch in range(1, epochs+1):
        model.train()
        total = 0.
        for positions in torch.randperm(len(train_users)).split(batch_size):
            users = train_users[positions.numpy()]
            x, features = batch(users)
            beta = min(beta_max, steps/anneal_steps)
            loss = model.dual_elbo(x, features, beta)
            if l2_penalty:
                loss = loss + l2_penalty*sum(torch.norm(p) for p in model.parameters())
            if not torch.isfinite(loss):
                raise FloatingPointError("Non-finite IViDR dual ELBO")
            optimizer.zero_grad(); loss.backward(); optimizer.step()
            total += float(loss.detach())*len(users)
            steps += 1
        value = validation()
        if not np.isfinite(value):
            raise FloatingPointError("Non-finite IViDR validation ELBO")
        eligible = beta >= beta_max
        selected = best if eligible else warmup
        if value < selected['value']:
            selected.update(value=value, state=copy.deepcopy(model.state_dict()), epoch=epoch)
            if eligible: stale = 0
        elif eligible:
            stale += 1
        stats = dict(train_loss=total/len(train_users), val_loss=value, beta=beta,
                      phase='full-beta' if eligible else 'warm-up')
        history.append(stats)
        if on_progress: on_progress(epoch, stats)
        if stale >= patience: break
    selected = best if best['state'] is not None else warmup
    model.load_state_dict(selected['state']); model.eval()
    means, stds = [], []
    with torch.no_grad():
        for users in np.array_split(np.arange(n), max(1, int(np.ceil(n/batch_size)))):
            mean, std = model.confounders(*batch(users))
            means.append(mean.cpu()); stds.append(std.cpu())
    mean, std = torch.cat(means), torch.cat(stds)
    info.update(best_epoch=selected['epoch'], best_val_loss=selected['value'], epochs_run=epoch,
        full_beta_selection=best['state'] is not None, rho=.9, tau=.9,
        shared_encoder=True, learned_prior_mean=prior_mean=='learned', learned_reconstruction=True)
    if implementation == 'legacy_v1':
        info['dimension_bridge']='mean of biased item histories -> registered Linear -> additive exposure'
    if checkpoint_path:
        Path(checkpoint_path).parent.mkdir(parents=True, exist_ok=True)
        torch.save(dict(model_state_dict=selected['state'], confounder_mean=mean, confounder_std=std,
            info=info, code_sha256=source_signature(),
            model_config=dict(n_items=items,aux_dim=w.shape[1],latent_dim=latent_dim,
                hidden_dim=hidden_dim,n_layers=n_layers,treatment_dim=treatment_dim,
                eq10_bridge=eq10_bridge,reconstruction=reconstruction,prior_mean=prior_mean),
            architecture=(('paper_ivae_learned_instruments_v3_rownorm' if eq10_bridge=='tied_item_lift_rownorm'
                           else 'paper_ivae_learned_instruments_v2') if implementation=='reference_v2'
                          else 'dual_ivae_learned_iv_v1')), checkpoint_path)
        info['checkpoint_path'] = str(checkpoint_path)
        info['checkpoint_sha256'] = hashlib.sha256(Path(checkpoint_path).read_bytes()).hexdigest()
    return mean, std, info


def fit_ividr_pipeline(data, dataset_name, seed=42, item_emb=None, checkpoint_dir=None,
                       checkpoint_tag='manual', evaluate_test=True, epochs=100,
                       ivae_epochs=2000, train_overrides=None, ivae_overrides=None, device=None,
                       negative_weight=DEFAULT_NEGATIVE_WEIGHT):
    from src.models.idcf.train_idcf import IDCF_CONFIG, DATASET_INPUTS, train_idcf
    from src.utils.artifacts import evaluate_checkpoint
    if item_emb is None:
        raise ValueError('IViDR requires item treatments trained only on biased training data')
    config = copy.deepcopy(IDCF_CONFIG[dataset_name])
    config['train']['patience'] = 20
    train_overrides, ivae_overrides = train_overrides or {}, ivae_overrides or {}
    if set(train_overrides)-set(config['train']): raise ValueError('Unknown IViDR feedback override')
    allowed = {'latent_dim','hidden_dim','n_layers','batch_size','lr','weight_decay','l2_penalty',
        'patience','beta_max','train_ratio','split_seed','validation_samples','validation_seed','verbose',
        'eq10_bridge','reconstruction','prior_mean'}
    if set(ivae_overrides)-allowed: raise ValueError('Unknown IViDR exposure override')
    config['ivae'].update(eq10_bridge=DEFAULT_EQ10_BRIDGE, reconstruction='full', prior_mean=DEFAULT_PRIOR_MEAN)
    config['train'].update(train_overrides); config['ivae'].update(ivae_overrides)
    version = (IVIDR_VERSIONS[config['ivae']['eq10_bridge']]
               + ('_prior0' if config['ivae']['prior_mean'] == 'zero' else '')
               + (f'_neg{negative_weight:g}' if negative_weight != 1 else ''))
    label = 'IViDR'  # One display name; the exact setting is in ividr_version/metadata.
    directory = Path(checkpoint_dir or os.path.join(CHECKPOINT_DIR,'ividr'))
    directory.mkdir(parents=True, exist_ok=True)
    # Tags alone are not unique across repeated manual calls; use run identity.
    from uuid import uuid4
    stage1_path = directory/f'{dataset_name}_{checkpoint_tag}_exposure_{uuid4().hex[:8]}.pt'
    def progress(epoch, stats):
        training_log.progress(label,dataset_name,epoch,ivae_epochs,
            {'Train ELBO':stats['train_loss'],'Val ELBO':stats['val_loss'],'Beta':stats['beta']},stage='learned IV+iVAE')
    training_log.header(label,dataset_name,{'Seed':seed,'Feedback loss':'BCEWithLogits',
        'IV':'learned MLP0/MLP1/MLP2'},'Biased-exposure user split; full-beta ELBO selection',stage='Giai đoạn 1/2')
    mean, std, info = train_dual_ivae(DATASET_INPUTS[dataset_name](data),item_emb,
        seed=seed,epochs=ivae_epochs,device=device,treatment_dim={'coat':32,'yahoo':96,'kuairand':128}[dataset_name],
        on_progress=progress,checkpoint_path=stage1_path,implementation='reference_v2',**config['ivae'])
    extra = dict(variant='ividr_reference_bce_v2',display_name=label,ividr_version=version,
        eq10_bridge=config['ivae']['eq10_bridge'],reconstruction=config['ivae']['reconstruction'],
        prior_mean=config['ivae']['prior_mean'],
        implementation_status='arxiv_reference_with_explicit_eq10_completion',
        feedback_expectation='E[sigmoid(MF + latent score)]; MC10 train, deterministic GH32 inference',
        phi=1.,lambda_mf=1.,rho=.9,tau=.9,
        method_reference=PAPER_URL,confounder_training=info,
        treatment_sha256=hashlib.sha256(np.ascontiguousarray(item_emb).tobytes()).hexdigest(),
        source_limitations=['arXiv v1 reference; not an author-code or final-publication reproduction',
            'Eq. (10) dimension mapping unspecified: explicit tied-item coordinate lift'
            + (', rescaled per user to ||A_u|| (v3)' if version.startswith('reference_v3_rownorm') else ''),
            *(['stage-1 prior mean fixed to 0 as in the iDCF code; Eq. (42) learns it']
              if config['ivae']['prior_mean']=='zero' else []),
            *([f'BCE negatives weighted {negative_weight:g}; Eq. (25) is unweighted']
              if negative_weight != 1 else []),
            'factorized first gate layer; shared encoder/prior/decoder is a parameterization choice',
            'project dataset preprocessing and split retained'])
    if dataset_name=='yahoo': extra['proxy_features']=data['user_feature_info']
    cfg=config['train']
    search=epochs>=20 and not any(k in train_overrides for k in ('lr','weight_decay'))
    grid=PAPER_FEEDBACK_GRID if search else ((cfg['lr'],cfg['weight_decay']),)
    trials=[]; winner=None
    for trial,(lr,wd) in enumerate(grid):
        options=dict(cfg,lr=lr,weight_decay=wd)
        result=train_idcf(data,mean,std,dataset_name,seed=seed,epochs=epochs,evaluate_test=False,
            checkpoint_dir=directory,checkpoint_tag=f'{checkpoint_tag}_bce_trial{trial}',device=device,
            extra_config=extra,loss_name='bce',negative_weight=negative_weight,**options)
        trials.append(dict(lr=lr,weight_decay=wd,best_epoch=result['best_epoch'],
            best_val_ndcg=result['best_val_ndcg'],checkpoint_path=result['checkpoint_path']))
        if winner is None or result['best_val_ndcg']>winner['best_val_ndcg']: winner=result
    if evaluate_test: winner=evaluate_checkpoint(winner['checkpoint_path'],data,get_device(device))
    winner['confounder_info']=info
    winner['validation_search']=dict(trials=trials,selection='max_validation_NDCG@5',test_used_for_selection=False)
    return winner
