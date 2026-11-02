# -*- coding: utf-8 -*-
"""
Giai đoạn 2 của iDCF: điểm(u, i) = MF(u, i) + <e_i, C_u>, C_u ~ N(mean_u, std_u) cố định từ iVAE.
Port từ iDCF.py::MFMF: khi huấn luyện lấy trung bình 10 mẫu C, khi suy luận dùng C = mean.
mean/std là buffer nên nằm trong checkpoint; dựng lại mô hình chỉ cần shape.
Project: ViFarm (services/recsys)
"""

import numpy as np
import torch
import torch.nn as nn

from src.models.mf.matrix_factorization import MatrixFactorization


class IDCFModel(nn.Module):
    def __init__(self, num_users, num_items, latent_dim, embedding_dim=64, sample_size=10,
                 init_scheme="normal"):
        super().__init__()
        self.mf = MatrixFactorization(num_users, num_items, embedding_dim=embedding_dim, use_bias=True,
                                      train_global_bias=False, init_scheme=init_scheme)
        self.register_buffer("c_mean", torch.zeros(num_users, latent_dim))
        self.register_buffer("c_std", torch.zeros(num_users, latent_dim))
        self.item_c = nn.Embedding(num_items, latent_dim)
        nn.init.uniform_(self.item_c.weight, -0.01, 0.01)
        self.sample_size = sample_size

    def set_confounders(self, mean, std):
        self.c_mean.copy_(torch.as_tensor(mean, dtype=torch.float32))
        self.c_std.copy_(torch.as_tensor(std, dtype=torch.float32))
        return self

    def forward(self, users, items, sample=False):
        e = self.item_c(items)
        mean = self.c_mean[users]
        if sample:
            z = mean + self.c_std[users] * torch.randn((self.sample_size, *mean.shape), device=mean.device)
            latent = (e * z).sum(-1).mean(0)
        else:
            latent = (e * mean).sum(-1)
        return self.mf(users, items) + latent

    def get_evaluation_factors(self):
        with torch.no_grad():
            u_mf, i_mf = self.mf.get_evaluation_factors()
            return (np.hstack([u_mf, self.c_mean.cpu().numpy()]),
                    np.hstack([i_mf, self.item_c.weight.detach().cpu().numpy()]))
