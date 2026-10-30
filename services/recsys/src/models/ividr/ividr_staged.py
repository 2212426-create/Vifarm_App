# -*- coding: utf-8 -*-
"""
IViDR theo giai đoạn (Algorithm 1, Appendix B của bài báo) dựng trên iDCF hai giai đoạn.
Đây là pipeline lịch sử với các lựa chọn địa phương, không chứng nhận tái lập paper:
  0. Treatment T = embedding item của MF-MSE (cấu hình tác giả iDCF) huấn luyện trên biased train.
  1. 2SLS: IV của item j là IV trung bình Z̄_j của các user đã thấy j; hồi quy bình phương
     tối thiểu (có intercept) T ~ Z̄ trên mọi item -> phần fitted T̂ = Z̄B, residual T̃ = T - T̂;
     T^re = T̂ + alpha_residual * T̃. Bài báo học α1, α2 bằng MLP (Eq. 8); ở đây cố định α1 = 1.
     alpha_residual = 1 cho T^re = T (2SLS không có tác dụng); 0 là biến thể IViDR-F.
  2. C2 = iVAE trên A (giống iDCF); C1 = iVAE trên [A, X^re_u] với X^re_u = trung bình T^re
     của các item user đã thấy; C = rho*C1 + tau*C2 (rho = tau = 0.9), std ghép giả định độc lập.
  3. Mô hình gợi ý = IDCFModel(MF + <e_i, C_u>), MSE.
Project: ViFarm (services/recsys)
"""

import numpy as np
import torch

from src.models.idcf.ivae import binary_exposure, train_exposure_ivae
from src.utils.artifacts import load_checkpoint

# Chọn bằng validation Coat (ablation 3 seed); xem docs/benchmarks/root_cause_analysis.md.
DEFAULT_ALPHA_RESIDUAL = 0.0


def iv_reconstruct(item_emb, exposure, instruments, alpha_residual=DEFAULT_ALPHA_RESIDUAL):
    """2SLS theo item: trả về T^re (n_items × d) và R² của bước hồi quy thứ nhất."""
    exposure = binary_exposure(exposure)
    counts = np.asarray(exposure.sum(0), dtype=np.float64).reshape(-1, 1)
    z_bar = np.asarray(exposure.T @ np.asarray(instruments, dtype=np.float64)) / np.maximum(counts, 1.0)
    design = np.hstack([np.ones((len(z_bar), 1)), z_bar])
    coef, *_ = np.linalg.lstsq(design, item_emb, rcond=None)
    fitted = design @ coef
    residual = item_emb - fitted
    r2 = 1.0 - (residual ** 2).sum() / ((item_emb - item_emb.mean(0)) ** 2).sum()
    return fitted + alpha_residual * residual, float(r2)


def mf_item_embeddings(mf_checkpoint):
    state = load_checkpoint(mf_checkpoint, torch.device("cpu"))["model_state_dict"]
    return state["item_embedding.weight"].numpy().astype(np.float64)


def ividr_confounders(inputs, item_emb, seed=42, latent_dim=16, rho=0.9, tau=0.9,
                      alpha_residual=DEFAULT_ALPHA_RESIDUAL,
                      **ivae_kwargs):
    """inputs như train_idcf.DATASET_INPUTS; item_emb = treatment T (n_items × d)."""
    exposure = binary_exposure(inputs["exposure"])
    t_re, r2 = iv_reconstruct(item_emb, exposure, inputs["instrument"], alpha_residual)
    x_re = exposure @ t_re / np.maximum(np.asarray(exposure.sum(1)).reshape(-1, 1), 1.0)
    m2, s2, info2 = train_exposure_ivae(exposure, inputs["proxy"], latent_dim=latent_dim, seed=seed, **ivae_kwargs)
    m1, s1, info1 = train_exposure_ivae(exposure, inputs["proxy"], latent_dim=latent_dim, seed=seed + 1000,
                                        extra_input=x_re, **ivae_kwargs)
    mean = rho * m1 + tau * m2
    std = torch.sqrt((rho * s1) ** 2 + (tau * s2) ** 2)
    return mean, std, {"first_stage_r2": r2, "alpha_residual": alpha_residual, "ivae_C1": info1, "ivae_C2": info2}
