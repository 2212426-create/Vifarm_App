# -*- coding: utf-8 -*-
"""
Giai đoạn 1 của LCDR (Deng et al., arXiv 2505.16708v1): học Z_lc có ràng buộc nhân quả.
Theo Algorithm 1 và Eq. (6) của paper (không có mã tác giả công khai):
  - iVAE q(Z | A, W), prior p(Z | W) — dùng ExposureIVAE và ELBO của iDCF trong project.
  - LCVAE q(Z_lc | A) = N(mu(A), sigma^2(A)), prior N(0, I), decoder Bernoulli trên A.
  - Mỗi batch: lấy mẫu Z và Z_lc bằng reparameterization; loss LCVAE =
    BCE tái tạo + KL + lambda * ||Z_lc - Z||_2 (chuẩn L2 không bình phương, theo từng user).
  - Hai nhánh chạy song song trong cùng vòng lặp (phần độ phức tạp của paper).
Lựa chọn địa phương (paper không ghi): iVAE vẫn tối ưu ELBO của chính nó; Z bị detach trong
ràng buộc để LCVAE không kéo iVAE (paper: iVAE là tín hiệu dẫn hướng); kiến trúc, KL anneal,
L2 penalty, chia user 80/20 và chọn mô hình theo ELBO validation giống iDCF.
Project: ViFarm (services/recsys)
"""

import copy

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from scipy import sparse

from src.models.idcf.ivae import ExposureIVAE, binary_exposure, elbo_loss, mlp
from src.utils.artifacts import validate_training
from src.utils.helpers import get_device


class LatentConstrainedVAE(nn.Module):
    """VAE chuẩn trên exposure A; số chiều latent bằng iVAE để so ||Z_lc - Z||."""

    def __init__(self, n_items, latent_dim=32, hidden_dim=64, n_layers=3):
        super().__init__()
        self.mean_z = mlp(n_items, hidden_dim, latent_dim, n_layers)
        self.log_var_z = mlp(n_items, hidden_dim, latent_dim, n_layers)
        self.decoder = mlp(latent_dim, hidden_dim, n_items, n_layers)

    def encode(self, a):
        return self.mean_z(a), self.log_var_z(a)

    def forward(self, a, noise=None):
        mean, log_var = self.encode(a)
        z = mean + torch.exp(0.5 * log_var) * (torch.randn_like(mean) if noise is None else noise)
        return self.decoder(z), mean, log_var, z


def lcvae_loss(a, a_hat, mean, log_var, z_lc, z, constraint_weight, anneal=1.0):
    """-ELBO của Eq. (6): tái tạo Bernoulli + KL tới N(0, I) + lambda * ||Z_lc - Z||_2."""
    recon = F.binary_cross_entropy_with_logits(a_hat, a, reduction="none").sum(1).mean()
    kld = -0.5 * torch.sum(1 + log_var - mean.pow(2) - log_var.exp(), 1).mean()
    constraint = torch.linalg.vector_norm(z_lc - z, ord=2, dim=1).mean()
    return recon + kld * anneal + constraint_weight * constraint, constraint


@torch.no_grad()
def validation_loss(ivae, lcvae, batches, constraint_weight, beta, samples, seed):
    """MC loss hai nhánh với nhiễu chung mỗi epoch, tách khỏi RNG huấn luyện."""
    device = next(lcvae.parameters()).device
    generator = torch.Generator(device=device).manual_seed(seed)
    totals, count = np.zeros(3), 0
    ivae.eval()
    lcvae.eval()
    for a, w in batches:
        mean_i, log_var_i = ivae.encode(a, w)
        prior_log_var = ivae.prior_log_var(w)
        mean_lc, log_var_lc = lcvae.encode(a)
        for _ in range(samples):
            noise_i = torch.randn(mean_i.shape, device=device, generator=generator)
            noise_lc = torch.randn(mean_lc.shape, device=device, generator=generator)
            z = mean_i + torch.exp(0.5 * log_var_i) * noise_i
            z_lc = mean_lc + torch.exp(0.5 * log_var_lc) * noise_lc
            ivae_part = elbo_loss(a, ivae.decoder(z), mean_i, log_var_i, torch.zeros_like(prior_log_var),
                                  prior_log_var, anneal=beta)
            lc_part, constraint = lcvae_loss(a, lcvae.decoder(z_lc), mean_lc, log_var_lc, z_lc, z,
                                             constraint_weight, anneal=beta)
            totals += np.array([float(ivae_part), float(lc_part), float(constraint)]) * len(a) / samples
        count += len(a)
    if count == 0:
        raise ValueError("LCDR validation split is empty")
    return totals / count


def train_lcdr_representations(exposure, user_features, constraint_weight, latent_dim=32, hidden_dim=64,
                               n_layers=3, lr=5e-4, weight_decay=1e-6, l2_penalty=0.01, batch_size=512,
                               epochs=2000, patience=100, beta_max=1.0, train_ratio=0.8, split_seed=1234,
                               seed=42, device=None, validation_samples=8, validation_seed=1234,
                               on_progress=None, verbose=False):
    """Trả về (mean, std) của q(Z_lc | A) cho mọi user và thông tin huấn luyện."""
    validate_training(latent_dim=latent_dim, hidden_dim=hidden_dim, n_layers=n_layers, lr=lr,
                      batch_size=batch_size, epochs=epochs, patience=patience,
                      validation_samples=validation_samples)
    if (not np.isfinite(constraint_weight) or constraint_weight < 0 or not np.isfinite(beta_max)
            or beta_max < 0 or not 0 < train_ratio < 1 or weight_decay < 0 or l2_penalty < 0):
        raise ValueError("Invalid LCDR constraint, regularization or split")
    a_all = binary_exposure(exposure)
    device = get_device(device)
    w_all = torch.as_tensor(np.asarray(user_features), dtype=torch.float32, device=device)
    n_users, n_items = a_all.shape
    if w_all.ndim != 2 or len(w_all) != n_users or not 0 < int(train_ratio * n_users) < n_users:
        raise ValueError("LCDR requires aligned proxies and nonempty train/validation users")

    def batch(users):
        rows = a_all[users]
        a = torch.as_tensor(rows.toarray() if sparse.issparse(rows) else rows, dtype=torch.float32, device=device)
        return a, w_all[torch.as_tensor(users, dtype=torch.long, device=device)]

    def chunks(users):
        return [users[i:i + batch_size] for i in range(0, len(users), batch_size)]

    rng = np.random.RandomState(split_seed)
    train_users = np.sort(rng.choice(n_users, size=int(train_ratio * n_users), replace=False))
    val_users = np.setdiff1d(np.arange(n_users), train_users)
    torch.manual_seed(seed)
    np.random.seed(seed)
    ivae = ExposureIVAE(n_items, w_all.shape[1], latent_dim, hidden_dim, n_layers).to(device)
    lcvae = LatentConstrainedVAE(n_items, latent_dim, hidden_dim, n_layers).to(device)
    parameters = list(ivae.parameters()) + list(lcvae.parameters())
    optimizer = torch.optim.Adam(parameters, lr=lr, weight_decay=weight_decay)
    total_steps = epochs * ((len(train_users) + batch_size - 1) // batch_size)
    anneal_steps = max(int(0.2 * total_steps / beta_max), 1) if beta_max else 1
    best = {"val": np.inf, "state": None, "epoch": 0}
    warmup_best = {"val": np.inf, "state": None, "epoch": 0}
    first_full_beta_epoch, step = None, 0
    for epoch in range(epochs):
        ivae.train()
        lcvae.train()
        train_loss, train_count = 0., 0
        for idx in torch.randperm(len(train_users)).split(batch_size):
            a, w = batch(train_users[idx.numpy()])
            anneal = min(beta_max, step / anneal_steps)
            a_hat_i, mean_i, log_var_i, prior_mean, prior_log_var = ivae(a, w)
            ivae_part = elbo_loss(a, a_hat_i, mean_i, log_var_i, prior_mean, prior_log_var, anneal=anneal)
            z = (mean_i + torch.exp(0.5 * log_var_i) * torch.randn_like(mean_i)).detach()
            a_hat_lc, mean_lc, log_var_lc, z_lc = lcvae(a)
            lc_part, _ = lcvae_loss(a, a_hat_lc, mean_lc, log_var_lc, z_lc, z, constraint_weight, anneal=anneal)
            loss = ivae_part + lc_part + l2_penalty * sum(torch.norm(p) for p in parameters)
            if not torch.isfinite(loss):
                raise FloatingPointError("Non-finite LCDR training loss")
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            train_loss += float(loss.detach()) * len(idx)
            train_count += len(idx)
            step += 1
        ivae_val, lc_val, constraint_val = validation_loss(
            ivae, lcvae, (batch(users) for users in chunks(val_users)), constraint_weight,
            beta_max, validation_samples, validation_seed)
        val = ivae_val + lc_val
        if not np.isfinite(val):
            raise FloatingPointError("Non-finite LCDR validation loss")
        eligible = anneal >= beta_max
        selection = best if eligible else warmup_best
        if eligible and first_full_beta_epoch is None:
            first_full_beta_epoch = epoch + 1
            warmup_best["state"] = None
        stop = False
        if val < selection["val"]:
            selection.update(val=val, epoch=epoch + 1, training_beta=float(anneal),
                             parts=dict(ivae=float(ivae_val), lcvae=float(lc_val), constraint=float(constraint_val)),
                             state=(copy.deepcopy(ivae.state_dict()), copy.deepcopy(lcvae.state_dict())))
        elif eligible and epoch + 1 - best["epoch"] >= patience:
            stop = True
        if on_progress is not None:
            on_progress(epoch + 1, dict(train_loss=train_loss / max(train_count, 1), val_loss=float(val),
                                        val_constraint=float(constraint_val), beta=float(anneal),
                                        phase="full-beta" if eligible else "warm-up"))
        if verbose and epoch % 100 == 0:
            print(f"LCDR epoch {epoch + 1}: beta {anneal:.3f}, val {val:.3f} (best {best['val']:.3f})", flush=True)
        if stop:
            break
    if best["state"] is None:
        best = warmup_best
    ivae.load_state_dict(best["state"][0])
    lcvae.load_state_dict(best["state"][1])
    lcvae.eval()
    parts = []
    with torch.no_grad():
        for users in chunks(np.arange(n_users)):
            a, _ = batch(users)
            parts.append(tuple(t.cpu() for t in lcvae.encode(a)))
    mean = torch.cat([m for m, _ in parts])
    log_var = torch.cat([v for _, v in parts])
    return mean, torch.exp(0.5 * log_var), {
        "best_val_loss": float(best["val"]), "best_val_parts": best["parts"], "best_epoch": best["epoch"],
        "epochs_run": epoch + 1,
        "selection": "post_warmup_full_beta" if first_full_beta_epoch else "budget_before_full_beta",
        "anneal_steps": anneal_steps, "first_full_beta_epoch": first_full_beta_epoch,
        "selected_training_beta": best["training_beta"], "last_training_beta": float(anneal),
        "config": dict(constraint_weight=constraint_weight, latent_dim=latent_dim, hidden_dim=hidden_dim,
                       n_layers=n_layers, lr=lr, weight_decay=weight_decay, l2_penalty=l2_penalty,
                       batch_size=batch_size, epochs=epochs, patience=patience, beta_max=beta_max,
                       train_ratio=train_ratio, split_seed=split_seed, seed=seed, device=str(device),
                       validation_samples=validation_samples, validation_seed=validation_seed,
                       constraint_norm="l2_not_squared_per_user_mean", z_gradient="detached",
                       validation_metric="mc_ivae_plus_lcvae_common_noise_v1")}
