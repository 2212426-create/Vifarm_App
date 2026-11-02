# -*- coding: utf-8 -*-
"""
Kiến trúc mô hình tổng thể DR-BIAS + CDR
Bao gồm Recommendation Model f_Theta và Imputation Model g_Psi
Biến thể địa phương tham khảo CDR CIKM 2023 (Song et al.)
Project: ViFarm (services/recsys)
"""

import torch
import torch.nn as nn
import torch.nn.functional as F

from src.models.mf.matrix_factorization import MatrixFactorization
from src.models.cdr.imputation_model import ImputationModel
from src.models.cdr.dr_bias_loss import (
    dr_bias_closed_form_imputation_loss,
    cdr_recommendation_loss, imputed_bce
)


class CDRFramework(nn.Module):
    """
    Khung làm việc Conservative Doubly Robust (CDR):
      - f_Theta: Mô hình gợi ý chính Matrix Factorization
      - g_Psi: Mô hình gán nhãn sai số Imputation Model với Monte Carlo Dropout
    """
    def __init__(self, num_users, num_items, embedding_dim=4, un_thres=0.1, dropout_rate=0.5,
                 filter_mode="cv", ips_weighting="paper", backbone="paper_dot"):
        super().__init__()
        if ips_weighting not in ("paper", "author", "dr") or filter_mode not in ("cv", "variance"):
            raise ValueError("Unknown CDR estimator or filter")
        self.num_users = num_users
        self.num_items = num_items
        self.embedding_dim = embedding_dim
        self.un_thres = un_thres
        self.filter_mode = filter_mode
        self.ips_weighting = ips_weighting
        self.last_filter_stats = {}
        if backbone not in ("paper_dot", "legacy_bias"):
            raise ValueError("Unknown CDR backbone")
        self.backbone = backbone

        # 1. Recommendation Model f_Theta
        # The checkpoint loader supplies legacy_bias for historical metadata.
        self.rec_model = MatrixFactorization(
            num_users, num_items, embedding_dim=embedding_dim, use_bias=backbone == "legacy_bias",
            init_scheme="xavier_normal" if backbone == "paper_dot" else "normal")

        # 2. Imputation Model g_Psi
        self.imp_model = ImputationModel(
            num_users, num_items, embedding_dim=embedding_dim, dropout_rate=dropout_rate,
            init_scheme="embedding_default" if backbone == "paper_dot" else "xavier_normal",
            dropout_scheme="mask" if backbone == "paper_dot" else "inverted")

    def forward(self, user_idx, item_idx):
        """Dự đoán logits của mô hình gợi ý chính"""
        return self.rec_model(user_idx, item_idx)

    def compute_cdr_losses(self, u_obs, i_obs, r_obs, inv_p_obs,
                           u_unobs, i_unobs, mc_samples=10,
                           counterfactual_scale=1.0, observed_fraction=None, counterfactual_pool="all"):
        """Compatibility helper; the trainer alternates the two updates explicitly."""
        rec, filtered = self.compute_recommendation_loss(
            u_obs, i_obs, r_obs, inv_p_obs, u_unobs, i_unobs, mc_samples,
            counterfactual_scale, observed_fraction, counterfactual_pool)
        return rec, self.compute_imputation_loss(u_obs, i_obs, r_obs, inv_p_obs), filtered

    def compute_recommendation_loss(self, u_obs, i_obs, r_obs, inv_p_obs,
                                    u_unobs, i_unobs, mc_samples=10,
                                    counterfactual_scale=1.0, observed_fraction=None,
                                    counterfactual_pool="all"):
        # --- BƯỚC 1: TÍNH CDR LOSS CHO RECOMMENDATION MODEL ---
        # Dự đoán trên tập quan sát
        logits_obs = self.rec_model(u_obs, i_obs)
        pred_obs = torch.sigmoid(logits_obs)
        imp_samples_obs = self.imp_model.sample_predict(u_obs, i_obs, num_samples=mc_samples)
        imp_loss_obs, imp_unc_obs = self.imp_model.sample_bce(
            logits_obs if self.ips_weighting == "paper" else pred_obs, imp_samples_obs,
            from_logits=self.ips_weighting == "paper")

        # Dự đoán trên tập unobserved/counterfactuals
        logits_unobs = self.rec_model(u_unobs, i_unobs)
        pred_unobs = torch.sigmoid(logits_unobs)
        imp_samples_unobs = self.imp_model.sample_predict(u_unobs, i_unobs, num_samples=mc_samples)
        imp_loss_unobs, imp_unc_unobs = self.imp_model.sample_bce(
            logits_unobs if self.ips_weighting == "paper" else pred_unobs, imp_samples_unobs,
            from_logits=self.ips_weighting == "paper")

        loss_rec, filtered_ratio, self.last_filter_stats = cdr_recommendation_loss(
            pred_obs=pred_obs,
            y_obs=r_obs,
            inv_prop_obs=inv_p_obs,
            imp_loss_obs=imp_loss_obs,
            imp_unc_obs=imp_unc_obs,
            pred_unobs=pred_unobs,
            imp_loss_unobs=imp_loss_unobs,
            imp_unc_unobs=imp_unc_unobs,
            un_thres=self.un_thres,
            counterfactual_scale=counterfactual_scale,
            filter_mode=self.filter_mode,
            ips_weighting=self.ips_weighting,
            observed_fraction=observed_fraction, counterfactual_pool=counterfactual_pool,
            observed_error=F.binary_cross_entropy_with_logits(logits_obs, r_obs, reduction="none"),
            return_diagnostics=True,
        )

        return loss_rec, filtered_ratio

    def compute_imputation_loss(self, u_obs, i_obs, r_obs, inv_p_obs):
        """Fit imputed error against the current, detached recommendation model."""
        # --- BƯỚC 2: TÍNH DR-BIAS LOSS CHO IMPUTATION MODEL ---
        # Imputation model g_psi dự đoán nhãn giả mạo sao cho e_hat mô phỏng sai số của rec model
        # Fit the same imputed error as used in the recommendation loss.
        with torch.no_grad():
            logits_fixed = self.rec_model(u_obs, i_obs)
        pred_rec_fixed = torch.sigmoid(logits_fixed)
        pred_imp = torch.sigmoid(self.imp_model(u_obs, i_obs))

        e_loss = F.binary_cross_entropy_with_logits(logits_fixed, r_obs, reduction="none")
        e_hat_loss = (imputed_bce(logits_fixed, pred_imp) if self.ips_weighting == "paper"
                      else F.binary_cross_entropy(pred_imp, pred_rec_fixed, reduction="none"))
        loss_imp = dr_bias_closed_form_imputation_loss(e_loss, e_hat_loss, inv_p_obs)

        return loss_imp


    def get_evaluation_factors(self):
        """Trích xuất factors của Recommendation Model phục vụ Unbiased Re-ranking."""
        return self.rec_model.get_evaluation_factors()
