# -*- coding: utf-8 -*-
"""
Giai đoạn 1 của iDCF (Zhang et al., KDD 2023): iVAE học biến ẩn C_u từ vector exposure A_u.
Port từ github.com/BgmLover/iDCF (models/vae.py::iVAE, ivae_exposure.py, save_ae_params.ipynb):
  - Đầu vào encoder: [A_u ∈ {0,1}^n_items, W_u]; prior p(C|W) = N(0, exp(MLP(W))).
  - Decoder tái tạo A_u bằng BCE-with-logits cộng trên item; KL anneal tuyến tính tới beta_max
    trong 20% số bước đầu; phạt thêm l2_penalty * sum ||θ||.
  - Chia user 80/20 (seed 1234) để chọn mô hình theo val loss; mean/std lưu cho MỌI user.
Exposure có thể là ma trận thưa (KuaiRand); chỉ từng batch được chuyển sang dense.
Project: ViFarm (services/recsys)
"""

import copy

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from scipy import sparse
from src.utils.helpers import get_device
from src.utils.artifacts import validate_training


def mlp(input_dim, hidden_dim, output_dim, n_layers):
    layers, prev = [], input_dim
    for _ in range(n_layers - 1):
        layers += [nn.Linear(prev, hidden_dim), nn.LeakyReLU(0.2)]
        prev = hidden_dim
    layers.append(nn.Linear(prev, output_dim))
    return nn.Sequential(*layers)


class ExposureIVAE(nn.Module):
    def __init__(self, n_items, aux_dim, latent_dim=32, hidden_dim=64, n_layers=3, extra_dim=0):
        super().__init__()
        self.prior_log_var = mlp(aux_dim, hidden_dim, latent_dim, n_layers)
        # extra_dim > 0: encoder nhận thêm đặc trưng (IViDR: treatment tái tạo), decoder vẫn tái tạo A.
        self.mean_z = mlp(n_items + extra_dim + aux_dim, hidden_dim, latent_dim, n_layers)
        self.log_var_z = mlp(n_items + extra_dim + aux_dim, hidden_dim, latent_dim, n_layers)
        self.decoder = mlp(latent_dim, hidden_dim, n_items, n_layers)

    def encode(self, a, w):
        aw = torch.cat([a, w], 1)
        return self.mean_z(aw), self.log_var_z(aw)

    def forward(self, x, w, noise=None):
        """x = A (iDCF) hoặc [A, đặc trưng phụ]; mục tiêu tái tạo luôn là A."""
        prior_log_var = self.prior_log_var(w)
        mean, log_var = self.encode(x, w)
        z = mean + torch.exp(0.5 * log_var) * (torch.randn_like(mean) if noise is None else noise)
        return self.decoder(z), mean, log_var, torch.zeros_like(prior_log_var), prior_log_var


def elbo_loss(a, a_hat, mean, log_var, prior_mean, prior_log_var, anneal=1.0):
    recon = F.binary_cross_entropy_with_logits(a_hat, a, reduction="none").sum(1).mean()
    kld = -0.5 * torch.sum(1 + log_var - prior_log_var
                           - ((mean - prior_mean).pow(2) + log_var.exp()) / prior_log_var.exp(), 1).mean()
    return recon + kld * anneal


def binary_exposure(exposure):
    """Ma trận exposure 0/1 (float32), giữ dạng thưa CSR nếu đầu vào thưa."""
    if sparse.issparse(exposure):
        return (sparse.csr_matrix(exposure) > 0).astype(np.float32)
    return (np.asarray(exposure) > 0).astype(np.float32)


@torch.no_grad()
def validation_elbo(model, batches, beta=1.0, samples=8, seed=1234):
    """MC ELBO with common noise each epoch, isolated from the training RNG."""
    device = next(model.parameters()).device
    generator = torch.Generator(device=device).manual_seed(seed)
    total, count = 0.0, 0
    model.eval()
    for x, a, w in batches:
        mean, log_var = model.encode(x, w)
        prior_log_var = model.prior_log_var(w)
        for _ in range(samples):
            noise = torch.randn(mean.shape, device=device, generator=generator)
            recon = model.decoder(mean + torch.exp(0.5 * log_var) * noise)
            total += float(elbo_loss(a, recon, mean, log_var, torch.zeros_like(prior_log_var),
                                     prior_log_var, anneal=beta)) * len(a) / samples
        count += len(a)
    if count == 0:
        raise ValueError("iVAE validation split is empty")
    return total / count


def train_exposure_ivae(exposure, user_features, latent_dim=32, hidden_dim=64, n_layers=3, lr=5e-4,
                        weight_decay=1e-6, l2_penalty=0.01, batch_size=512, epochs=2000, patience=100,
                        beta_max=1.0, train_ratio=0.8, split_seed=1234, seed=42, verbose=False,
                        extra_input=None, device=None, validation_samples=8, validation_seed=1234,
                        on_progress=None):
    """Trả về (mean, std) của q(C | A, W) cho mọi user, từ mô hình có val loss tốt nhất.
    extra_input (n_users × d) được nối vào đầu vào encoder (nhánh C1 của IViDR)."""
    a_all = binary_exposure(exposure)
    validate_training(latent_dim=latent_dim, hidden_dim=hidden_dim, n_layers=n_layers,
                      lr=lr, batch_size=batch_size, epochs=epochs, patience=patience,
                      validation_samples=validation_samples)
    if (not np.isfinite(beta_max) or beta_max < 0 or not 0 < train_ratio < 1
            or not np.isfinite(weight_decay) or weight_decay < 0
            or not np.isfinite(l2_penalty) or l2_penalty < 0):
        raise ValueError("Invalid iVAE regularization or split")
    device = get_device(device)
    w_all = torch.as_tensor(np.asarray(user_features), dtype=torch.float32, device=device)
    extra = None if extra_input is None else torch.as_tensor(np.asarray(extra_input), dtype=torch.float32, device=device)
    n_users, n_items = a_all.shape
    if (not 0 < int(train_ratio * n_users) < n_users or w_all.ndim != 2
            or len(w_all) != n_users or (extra is not None and (extra.ndim != 2 or len(extra) != n_users))):
        raise ValueError("iVAE requires aligned features and nonempty train/validation users")

    def batch(users):
        rows = a_all[users]
        a = torch.as_tensor(rows.toarray() if sparse.issparse(rows) else rows, dtype=torch.float32, device=device)
        users = torch.as_tensor(users, dtype=torch.long, device=device)
        return (a if extra is None else torch.cat([a, extra[users]], 1)), a, w_all[users]

    def chunks(users):
        return [users[i:i + batch_size] for i in range(0, len(users), batch_size)]

    rng = np.random.RandomState(split_seed)
    train_users = np.sort(rng.choice(n_users, size=int(train_ratio * n_users), replace=False))
    val_users = np.setdiff1d(np.arange(n_users), train_users)

    torch.manual_seed(seed)
    np.random.seed(seed)
    model = ExposureIVAE(n_items, w_all.shape[1], latent_dim, hidden_dim, n_layers,
                         extra_dim=0 if extra is None else extra.shape[1]).to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=weight_decay)
    total_steps = epochs * ((len(train_users) + batch_size - 1) // batch_size)
    anneal_steps = max(int(0.2 * total_steps / beta_max), 1) if beta_max else 1
    best = {"val": np.inf, "state": None, "epoch": 0}
    warmup_best = {"val": np.inf, "state": None, "epoch": 0}
    first_full_beta_epoch = None
    step = 0
    for epoch in range(epochs):
        model.train()
        train_loss,train_count=0.,0
        for idx in torch.randperm(len(train_users)).split(batch_size):
            x, a, w = batch(train_users[idx.numpy()])
            anneal = min(beta_max, step / anneal_steps)
            l2 = sum(torch.norm(p) for p in model.parameters())
            loss = elbo_loss(a, *model(x, w), anneal=anneal) + l2_penalty * l2
            if not torch.isfinite(loss):
                raise FloatingPointError("Non-finite iVAE training loss")
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            train_loss += float(loss.detach()) * len(idx)
            train_count += len(idx)
            step += 1
        val = validation_elbo(model, (batch(users) for users in chunks(val_users)),
                              beta_max, validation_samples, validation_seed)
        if not np.isfinite(val):
            raise FloatingPointError("Non-finite iVAE validation loss")
        # A low full-beta validation ELBO during beta=0 training must not end
        # training or remain the selected checkpoint after the objective matures.
        # Small smoke budgets may never reach full beta; label that fallback.
        eligible = anneal >= beta_max
        selection = best if eligible else warmup_best
        if eligible and first_full_beta_epoch is None:
            first_full_beta_epoch = epoch + 1
            warmup_best["state"] = None
        should_stop=False
        if val < selection["val"]:
            selection.update(val=val, state=copy.deepcopy(model.state_dict()),
                             epoch=epoch + 1, training_beta=float(anneal))
        elif eligible and epoch + 1 - best["epoch"] >= patience:
            should_stop=True
        if on_progress is not None:
            on_progress(epoch+1,dict(train_loss=train_loss/max(train_count,1),val_loss=float(val),
                beta=float(anneal),phase='full-beta' if eligible else 'warm-up'))
        if verbose and epoch % 100 == 0:
            print(f"iVAE epoch {epoch + 1}: beta {anneal:.3f}, val loss {val:.3f} "
                  f"(best eligible {best['val']:.3f} @ {best['epoch']})", flush=True)
        if should_stop: break
    if best["state"] is None:
        best = warmup_best
    model.load_state_dict(best["state"])
    model.eval()
    parts = []
    with torch.no_grad():
        for users in chunks(np.arange(n_users)):
            x, _, w = batch(users)
            parts.append(tuple(t.cpu() for t in model.encode(x, w)))
    mean, log_var = torch.cat([m for m, _ in parts]), torch.cat([v for _, v in parts])
    return mean, torch.exp(0.5 * log_var), {"best_val_loss": best["val"], "best_epoch": best["epoch"],
                                             "epochs_run": epoch + 1,
                                             "selection": "post_warmup_full_beta" if first_full_beta_epoch else "budget_before_full_beta",
                                             "anneal_steps": anneal_steps,
                                             "first_full_beta_epoch": first_full_beta_epoch,
                                             "selected_training_beta": best["training_beta"],
                                             "last_training_beta": float(anneal),
                                             "config": dict(latent_dim=latent_dim, hidden_dim=hidden_dim,
                                                 n_layers=n_layers, lr=lr, weight_decay=weight_decay,
                                                 l2_penalty=l2_penalty, batch_size=batch_size, epochs=epochs,
                                                 patience=patience, beta_max=beta_max, train_ratio=train_ratio,
                                                 split_seed=split_seed, seed=seed, device=str(device),
                                                 validation_samples=validation_samples,
                                                 validation_seed=validation_seed,
                                                 validation_metric="mc_elbo_common_noise_v1")}
