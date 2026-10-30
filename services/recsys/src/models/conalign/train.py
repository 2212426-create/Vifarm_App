# -*- coding: utf-8 -*-
"""
Huấn luyện ConAlign hai giai đoạn, port từ third_party/conalign/mymodel.py::train_and_eval:
  1. Pretrain tháp biased trên dữ liệu biased: lặp block user × item (Block), BCE tổng +
     weight_decay_1 * L2 embedding của user/item trong block, SGD lr_1; early stop theo
     AUC validation biased (patience 60).
  2. Chép tháp biased sang tháp unbiased, đóng băng tháp biased. Mỗi epoch xáo trộn
     biased train + unbiased train: BCE chỉ trên mẫu unbiased; alignment chỉ cho mẫu có
     BCE tháp unbiased > BCE tháp biased (cổng rời rạc), trọng số alignment_weight;
     cộng weight_decay_2 * L2 embedding unbiased; SGD lr_2; early stop theo AUC val unbiased.
Test: cả hai tháp trên test unbiased (random) và test biased, metric theo source.
Thứ tự tiêu thụ RNG (DataLoader, randperm) giữ như source để cùng seed cho cùng kết quả.
Project: ViFarm (services/recsys)
"""

import copy
import hashlib
import json
import os
import random
import time

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, Dataset

from src.models.conalign.metrics import test_metrics, train_metrics
from src.models.conalign.model import DualTowerMF
from src.utils.artifacts import source_signature
from src.utils.helpers import CHECKPOINT_DIR, get_device

# mymodel.py::para; `adaptive_alignment` luôn bật trong source nên không có khóa tắt.
CONALIGN_CONFIG = {
    'yahoo': dict(batch_size=1024, train_batch_size=1024, pretrain_epochs=500, finetune_epochs=500,
                  patience=60, block_batch=[6000, 500], dim=10, learning_rate_1=0.001,
                  learning_rate_2=0.01, weight_decay_1=1e-6, weight_decay_2=1e-1, alignment_weight=0.18),
    'coat': dict(batch_size=128, train_batch_size=128, pretrain_epochs=500, finetune_epochs=500,
                 patience=60, block_batch=[64, 64], dim=10, learning_rate_1=0.01,
                 learning_rate_2=0.001, weight_decay_1=0.01, weight_decay_2=0.01, alignment_weight=0.2),
    'kuairand': dict(batch_size=1024, train_batch_size=1024, pretrain_epochs=500, finetune_epochs=500,
                     patience=60, block_batch=[500, 10000], dim=10, learning_rate_1=0.01,
                     learning_rate_2=0.01, weight_decay_1=0.001, weight_decay_2=0.001, alignment_weight=0.2),
}


def setup_seed(seed):
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed(seed)
    np.random.seed(seed)
    random.seed(seed)


class LoaderList(Dataset):
    def __init__(self, lst):
        self.lst = lst

    def __getitem__(self, index):
        return self.lst[index]

    def __len__(self):
        return len(self.lst)


class Block:
    """Block user × item của utils/data_loader.py; trả các tương tác nằm trong block."""

    def __init__(self, mat, u_batch_size, i_batch_size, device):
        self.mat = mat
        self.n_users, self.n_items = mat.shape
        self.device = device
        self.User_loader = DataLoader(LoaderList(torch.arange(self.n_users).to(device)),
                                      batch_size=u_batch_size, shuffle=True, num_workers=0)
        self.Item_loader = DataLoader(LoaderList(torch.arange(self.n_items).to(device)),
                                      batch_size=i_batch_size, shuffle=True, num_workers=0)

    def get_batch(self, batch_user, batch_item):
        index_row = np.isin(self.mat._indices()[0].cpu().numpy(), batch_user.cpu().numpy())
        index_col = np.isin(self.mat._indices()[1].cpu().numpy(), batch_item.cpu().numpy())
        index = torch.tensor(np.where(index_row * index_col)[0]).to(self.device)
        return self.mat._indices()[0][index], self.mat._indices()[1][index], self.mat._values()[index]


class Interactions(Dataset):
    def __init__(self, mat):
        self.mat = mat

    def __getitem__(self, index):
        return self.mat._indices()[0][index], self.mat._indices()[1][index], self.mat._values()[index]

    def __len__(self):
        return self.mat._nnz()


class EarlyStopping:
    """utils/early_stop.py với một biến AUC và Best.RANKED."""

    def __init__(self, model, patience):
        self.model = model
        self.best_val = -np.inf
        self.remembered_val = -np.inf
        self.max_patience = self.patience = patience
        self.best_epoch = None
        self.best_state = None

    def check(self, value, epoch):
        if value >= self.best_val:
            self.best_val = value
            self.patience = self.max_patience
            if value >= self.remembered_val and self.remembered_val != value:
                self.best_epoch = epoch
                self.remembered_val = value
                self.best_state = {key: tensor.cpu() for key, tensor in self.model.state_dict().items()}
        else:
            self.patience -= 1
        return self.patience == 0


def predict(model, loader, device):
    biased, unbiased, trues, users, items = [], [], [], [], []
    with torch.no_grad():
        for u, i, r in loader:
            b, ub, _ = model(u.to(device), i.to(device))
            biased.append(b)
            unbiased.append(ub)
            trues.append(r.to(device).float())
            users.append(u.to(device))
            items.append(i.to(device))
    return (torch.cat(biased), torch.cat(unbiased), torch.cat(trues), torch.cat(users), torch.cat(items))


def l2_on(embedding_user, embedding_item, users, items):
    return (torch.sum(embedding_user(torch.unique(users)) ** 2)
            + torch.sum(embedding_item(torch.unique(items)) ** 2)) / 2


def train_conalign(data, dataset, seed=0, device=None, overrides=None, checkpoint_dir=None, verbose=True):
    """Huấn luyện + test như source. Gọi setup_seed trước khi nạp dữ liệu để giữ thứ tự RNG."""
    config = copy.deepcopy(CONALIGN_CONFIG[dataset])
    unknown = set(overrides or {}) - set(config)
    if unknown:
        raise ValueError(f'Unknown ConAlign override: {sorted(unknown)}')
    config.update(overrides or {})
    device = get_device(device)
    train_data, unif_train = data['train_biased'], data['train_unbiased']
    users_unif, items_unif = unif_train._indices()[0], unif_train._indices()[1]
    y_unif = unif_train._values().float()
    train_loader = Block(train_data, config['block_batch'][0], config['block_batch'][1], device)
    loaders = {name: DataLoader(Interactions(data[name]), batch_size=config['batch_size'])
               for name in ('val_biased', 'val_unbiased', 'test_unbiased', 'test_biased')}
    n_user, n_item = train_data.shape
    model = DualTowerMF(n_user, n_item, dim=config['dim'], alignment_weight=config['alignment_weight']).to(device)
    optimizer = torch.optim.SGD(model.parameters(), lr=config['learning_rate_1'], weight_decay=0)
    criterion = nn.BCELoss(reduction='none')
    history = {'stage1': [], 'stage2': []}
    started = time.time()

    stopper = EarlyStopping(model, config['patience'])
    for epoch in range(config['pretrain_epochs']):
        model.train()
        preds, trues = [], []
        for u_batch in train_loader.User_loader:
            for i_batch in train_loader.Item_loader:
                users, items, y = train_loader.get_batch(u_batch, i_batch)
                y = y.float()
                optimizer.zero_grad()
                biased_probs, _, _ = model(users, items)
                loss = criterion(biased_probs, y).sum() + config['weight_decay_1'] * l2_on(
                    model.user_latent_biased, model.item_latent_biased, users, items)
                loss.backward()
                optimizer.step()
                preds.append(biased_probs.detach())
                trues.append(y.detach())
        train_res = train_metrics(torch.cat(preds), torch.cat(trues))
        model.eval()
        b, _, r, _, _ = predict(model, loaders['val_biased'], device)
        val_res = train_metrics(b, r)
        history['stage1'].append(dict(epoch=epoch, train_bce=train_res['BCE'], train_auc=train_res['AUC'],
                                      val_bce=val_res['BCE'], val_auc=val_res['AUC']))
        if verbose:
            print(f"[ConAlign][{dataset}][Stage 1] Epoch {epoch:3d} | Train BCE {train_res['BCE']:.4f} "
                  f"AUC {train_res['AUC']:.4f} | Val BCE {val_res['BCE']:.4f} AUC {val_res['AUC']:.4f}", flush=True)
        if stopper.check(val_res['AUC'], epoch):
            break
    model.load_state_dict(stopper.best_state)
    stage1 = dict(best_epoch=stopper.best_epoch, best_val_auc=float(stopper.remembered_val),
                  epochs_run=epoch + 1)

    model.copy_biased_to_unbiased()
    for parameter in model.biased_parameters():
        parameter.requires_grad = False
    optimizer = torch.optim.SGD(filter(lambda p: p.requires_grad, model.parameters()),
                                lr=config['learning_rate_2'], weight_decay=0)
    stopper = EarlyStopping(model, config['patience'])
    users_bias, items_bias = train_data._indices()[0], train_data._indices()[1]
    y_bias = train_data._values().float()
    users_all = torch.cat([users_bias, users_unif])
    items_all = torch.cat([items_bias, items_unif])
    y_all = torch.cat([y_bias, y_unif])
    is_unbiased_all = torch.cat([torch.zeros(len(users_bias), dtype=torch.bool),
                                 torch.ones(len(users_unif), dtype=torch.bool)])
    batch_size = config['train_batch_size']
    for epoch in range(config['finetune_epochs']):
        model.train()
        preds, trues = [], []
        align_total, align_batches, batches = 0.0, 0, 0
        order = torch.randperm(len(users_all))
        users_shuffled, items_shuffled = users_all[order], items_all[order]
        y_shuffled, unbiased_shuffled = y_all[order], is_unbiased_all[order]
        for start in range(0, len(users_all), batch_size):
            users = users_shuffled[start:start + batch_size].to(device)
            items = items_shuffled[start:start + batch_size].to(device)
            y = y_shuffled[start:start + batch_size].to(device)
            unbiased_mask = unbiased_shuffled[start:start + batch_size].to(device)
            optimizer.zero_grad()
            biased_probs, unbiased_probs, align = model(users, items)
            total = torch.tensor(0.0, device=device)
            with torch.no_grad():
                use_align = criterion(unbiased_probs, y) > criterion(biased_probs, y)
            if int(unbiased_mask.sum().item()) > 0:
                total += criterion(unbiased_probs[unbiased_mask], y[unbiased_mask]).sum()
                preds.append(unbiased_probs[unbiased_mask].detach())
                trues.append(y[unbiased_mask].detach())
            if int(use_align.sum().item()) > 0:
                selected = align[use_align].sum()
                total += model.alignment_weight * selected
                align_total += selected.item()
                align_batches += 1
            total += config['weight_decay_2'] * l2_on(model.user_latent_unbiased, model.item_latent_unbiased,
                                                      users, items)
            total.backward()
            optimizer.step()
            batches += 1
        train_res = train_metrics(torch.cat(preds), torch.cat(trues)) if preds else {'BCE': 0.0, 'AUC': 0.5}
        model.eval()
        _, ub, r, _, _ = predict(model, loaders['val_unbiased'], device)
        val_res = train_metrics(ub, r)
        history['stage2'].append(dict(epoch=epoch, train_bce=train_res['BCE'], train_auc=train_res['AUC'],
                                      val_bce=val_res['BCE'], val_auc=val_res['AUC'],
                                      alignment_batch_ratio=align_batches / max(batches, 1),
                                      mean_alignment=align_total / align_batches if align_batches else 0.0))
        if verbose:
            print(f"[ConAlign][{dataset}][Stage 2] Epoch {epoch:3d} | Train BCE {train_res['BCE']:.4f} "
                  f"AUC {train_res['AUC']:.4f} | Val BCE {val_res['BCE']:.4f} AUC {val_res['AUC']:.4f}", flush=True)
        if stopper.check(val_res['AUC'], epoch):
            break
    model.load_state_dict(stopper.best_state)
    stage2 = dict(best_epoch=stopper.best_epoch, best_val_auc=float(stopper.remembered_val),
                  epochs_run=epoch + 1)
    model.eval()
    results = {}
    for name in ('test_unbiased', 'test_biased'):
        b, ub, r, users, items = predict(model, loaders[name], device)
        results[name] = {'biased_tower': test_metrics(b, r, users, items),
                         'unbiased_tower': test_metrics(ub, r, users, items)}
    identity = dict(model='conalign', dataset=dataset, seed=seed, config=config, data=data['info'],
                    code_sha256=source_signature(), source_commit='f6171bb5871025be2a77a37c4c9ab151cbaaab6f',
                    device=str(device), torch=str(torch.__version__))
    digest = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()[:16]
    directory = checkpoint_dir or os.path.join(CHECKPOINT_DIR, 'conalign')
    os.makedirs(directory, exist_ok=True)
    path = os.path.join(directory, f'{dataset}_seed{seed}_{digest}.pt')
    torch.save({'identity': identity, 'model_state_dict': model.state_dict(),
                'stage1': stage1, 'stage2': stage2}, path)
    return dict(identity=identity, stage1=stage1, stage2=stage2, history=history,
                source_metrics=results, checkpoint_path=path, seconds=time.time() - started)
