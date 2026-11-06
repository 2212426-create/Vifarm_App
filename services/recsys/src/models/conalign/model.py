# -*- coding: utf-8 -*-
"""
ConAlign (Zhang et al., RecSys 2026): MF hai tháp, tháp biased và tháp unbiased.
Port từ third_party/conalign/mymodel.py::DualTowerMF (commit f6171bb):
  - Mỗi tháp có embedding user/item rộng `dim` và bias user/item, khởi tạo kaiming_normal.
  - Xác suất = sigmoid(<p_u, q_i> + b_u + b_i) cho từng tháp.
  - Alignment loss theo từng mẫu = (mean|p_u^ub - p_u^b| + mean|q_i^ub - q_i^b|
    + |b_u^ub - b_u^b| + |b_i^ub - b_i^b|) / 2; tháp biased bị detach.
Thứ tự tạo tham số giữ nguyên source để cùng seed cho cùng trọng số.
Project: ViFarm (services/recsys)
"""

import torch
import torch.nn as nn


class DualTowerMF(nn.Module):
    def __init__(self, n_user, n_item, dim=32, dropout=0.0, alignment_weight=0.1):
        super().__init__()
        self.dim = dim
        self.alignment_weight = alignment_weight
        self.user_latent_biased = nn.Embedding(n_user, dim)
        self.item_latent_biased = nn.Embedding(n_item, dim)
        self.user_bias_biased = nn.Embedding(n_user, 1)
        self.item_bias_biased = nn.Embedding(n_item, 1)
        for embedding in (self.user_latent_biased, self.item_latent_biased,
                          self.user_bias_biased, self.item_bias_biased):
            nn.init.kaiming_normal_(embedding.weight, mode='fan_out', a=0)
        self.user_latent_unbiased = nn.Embedding(n_user, dim)
        self.item_latent_unbiased = nn.Embedding(n_item, dim)
        self.user_bias_unbiased = nn.Embedding(n_user, 1)
        self.item_bias_unbiased = nn.Embedding(n_item, 1)
        for embedding in (self.user_latent_unbiased, self.item_latent_unbiased,
                          self.user_bias_unbiased, self.item_bias_unbiased):
            nn.init.kaiming_normal_(embedding.weight, mode='fan_out', a=0)
        self.dropout = nn.Dropout(p=dropout)

    def forward(self, users, items):
        u_biased = self.dropout(self.user_latent_biased(users))
        i_biased = self.dropout(self.item_latent_biased(items))
        bu_biased = self.user_bias_biased(users)
        bi_biased = self.item_bias_biased(items)
        biased_logits = torch.sum(u_biased * i_biased, dim=1) + bu_biased.squeeze() + bi_biased.squeeze()
        u_unbiased = self.dropout(self.user_latent_unbiased(users))
        i_unbiased = self.dropout(self.item_latent_unbiased(items))
        bu_unbiased = self.user_bias_unbiased(users)
        bi_unbiased = self.item_bias_unbiased(items)
        unbiased_logits = (torch.sum(u_unbiased * i_unbiased, dim=1) + bu_unbiased.squeeze()
                           + bi_unbiased.squeeze())
        # Gradient chỉ chảy vào tháp unbiased (detach tháp biased) như source.
        align = (torch.mean(torch.abs(u_unbiased - u_biased.detach()), dim=1)
                 + torch.mean(torch.abs(i_unbiased - i_biased.detach()), dim=1)
                 + torch.abs(bu_unbiased.squeeze() - bu_biased.squeeze().detach())
                 + torch.abs(bi_unbiased.squeeze() - bi_biased.squeeze().detach())) / 2
        return torch.sigmoid(biased_logits), torch.sigmoid(unbiased_logits), align

    def biased_parameters(self):
        return [self.user_latent_biased.weight, self.item_latent_biased.weight,
                self.user_bias_biased.weight, self.item_bias_biased.weight]

    def copy_biased_to_unbiased(self):
        with torch.no_grad():
            self.user_latent_unbiased.weight.copy_(self.user_latent_biased.weight)
            self.item_latent_unbiased.weight.copy_(self.item_latent_biased.weight)
            self.user_bias_unbiased.weight.copy_(self.user_bias_biased.weight)
            self.item_bias_unbiased.weight.copy_(self.item_bias_biased.weight)

    def predict_user_all(self, user_indices: torch.Tensor, tower: str = "unbiased") -> torch.Tensor:
        """
        Dự đoán logits của một nhóm users trên TOÀN BỘ items bằng nhân ma trận:
        Mặc định sử dụng tháp unbiased đã được căn chỉnh để suy luận không thiên lệch.
        user_indices: Tensor (B,) hoặc int
        Trả về: Tensor logits (B, n_item)
        """
        user_indices = torch.as_tensor(user_indices, device=self.user_latent_unbiased.weight.device).view(-1)
        if tower == "biased":
            p_u = self.user_latent_biased(user_indices)
            q_all = self.item_latent_biased.weight
            b_u = self.user_bias_biased(user_indices)
            b_all = self.item_bias_biased.weight.squeeze(-1)
        else:
            p_u = self.user_latent_unbiased(user_indices)
            q_all = self.item_latent_unbiased.weight
            b_u = self.user_bias_unbiased(user_indices)
            b_all = self.item_bias_unbiased.weight.squeeze(-1)
        return torch.matmul(p_u, q_all.t()) + b_u + b_all.unsqueeze(0)
