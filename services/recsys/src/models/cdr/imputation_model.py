# -*- coding: utf-8 -*-
"""
Mô hình Gán Nhãn Imputation Model tích hợp Monte Carlo Dropout trong DR-BIAS + CDR
Biến thể địa phương tham khảo CDR CIKM 2023 (Song et al.)
Project: ViFarm (services/recsys)
"""

import torch
import torch.nn as nn
import torch.nn.functional as F
from src.models.cdr.dr_bias_loss import imputed_bce


class ImputationModel(nn.Module):
    """
    Mô hình Imputation Model g_Psi(u, i) dự đoán sai số / nhãn giả mạo:
      - Ma trận nhúng người dùng và vật phẩm
      - Monte Carlo Dropout để ước tính kỳ vọng sai số và độ bất định (variance)
    """
    def __init__(self, num_users, num_items, embedding_dim=4, dropout_rate=0.5,
                 init_scheme="xavier_normal", dropout_scheme="inverted"):
        super().__init__()
        self.num_users = num_users
        self.num_items = num_items
        self.embedding_dim = embedding_dim
        self.dropout_rate = dropout_rate
        if init_scheme not in ("xavier_normal", "embedding_default") or dropout_scheme not in ("inverted", "mask"):
            raise ValueError("Unknown imputation initialization/dropout scheme")
        self.init_scheme = init_scheme
        self.dropout_scheme = dropout_scheme

        self.user_embedding = nn.Embedding(num_users, embedding_dim)
        self.item_embedding = nn.Embedding(num_items, embedding_dim)
        self.dropout = nn.Dropout(p=dropout_rate)

        self.reset_parameters()

    def reset_parameters(self):
        # MF_McdropoutModel in the released code leaves nn.Embedding initialization intact.
        if self.init_scheme == "xavier_normal":
            nn.init.xavier_normal_(self.user_embedding.weight)
            nn.init.xavier_normal_(self.item_embedding.weight)

    def forward(self, user_idx, item_idx):
        """Dự đoán logits điểm số của Imputation Model"""
        u_emb = self.user_embedding(user_idx)
        i_emb = self.item_embedding(item_idx)
        return torch.sum(u_emb * i_emb, dim=-1)

    def sample_predict(self, user_idx, item_idx, num_samples=10):
        """
        Lấy N mẫu xác suất m_hat qua Monte Carlo Dropout.
        Sử dụng F.dropout với training=True để MC Dropout hoạt động nhất quán cả khi eval.
        Trả về: Tensor có kích thước (num_samples, batch_size)
        """
        preds = []
        with torch.no_grad():
            u_base = self.user_embedding(user_idx)
            i_base = self.item_embedding(item_idx)
            for _ in range(num_samples):
                if self.dropout_scheme == "mask":
                    u_emb = u_base * (torch.rand_like(u_base) > self.dropout_rate)
                    i_emb = i_base * (torch.rand_like(i_base) > self.dropout_rate)
                else:
                    u_emb = F.dropout(u_base, p=self.dropout_rate, training=True)
                    i_emb = F.dropout(i_base, p=self.dropout_rate, training=True)
                p = torch.sigmoid(torch.sum(u_emb * i_emb, dim=-1))
                preds.append(p)
            return torch.stack(preds, dim=0)

    def sample_bce(self, pred, imp_samples, from_logits=False):
        """
        Tính kỳ vọng tổn thất BCE và độ bất định phương sai của sai số e_hat theo Eq. 8 CDR:
          e_hat^{(s)} = BCE(pred, m^{(s)})
          sigma^2 = Var(e_hat^{(s)})
        """
        if imp_samples.shape[0] < 1:
            raise ValueError("At least one Monte Carlo sample is required")
        # Targets are fixed for the recommendation update; predictions retain gradients.
        samples = imp_samples.detach()
        prediction = pred.unsqueeze(0).expand_as(samples)
        bce_samples = (imputed_bce(prediction, samples) if from_logits else
                       F.binary_cross_entropy(prediction, samples, reduction="none"))
        return bce_samples.mean(0), bce_samples.detach().var(0, unbiased=False)
