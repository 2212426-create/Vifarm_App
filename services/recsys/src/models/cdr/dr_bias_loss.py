"""CDR Eq. (7), plus explicitly named historical estimators for comparison."""
import math

import torch
import torch.nn.functional as F

PAPER_OBJECTIVE_REVISION = "cdr_eq7_bce_v1"


def imputed_bce(logits, pseudo_labels):
    """BCE(sigmoid(logits), pseudo_labels), stable and differentiable in either argument.

    Rec updates detach pseudo_labels; imp updates detach logits. Both updates
    therefore optimize exactly the same error instead of reversing BCE arguments.
    """
    return F.softplus(logits) - pseudo_labels * logits


def dr_bias_closed_form_imputation_loss(e_loss, e_hat_loss, inv_prop):
    weight = inv_prop ** 3 * (1.0 - 1.0 / inv_prop.clamp(min=1.0)) ** 2
    return ((e_loss - e_hat_loss).square() * weight).mean()


def imputation_keep(mean, variance, threshold, mode="cv"):
    if mode not in ("cv", "variance"):
        raise ValueError("filter_mode must be cv or variance")
    if not math.isfinite(threshold) or threshold < 0:
        raise ValueError("Imputation threshold must be finite and nonnegative")
    uncertainty = variance.detach().clamp(min=0)
    if mode == "cv":
        uncertainty = uncertainty.sqrt() / mean.detach().clamp(min=1e-8)
    return (uncertainty < threshold).to(mean.dtype)


def cdr_recommendation_loss(pred_obs, y_obs, inv_prop_obs, imp_loss_obs, imp_unc_obs,
                            pred_unobs, imp_loss_unobs, imp_unc_unobs,
                            un_thres=0.1, counterfactual_scale=1.0,
                            filter_mode="cv", ips_weighting="paper",
                            observed_fraction=None, counterfactual_pool="all",
                            observed_error=None, return_diagnostics=False):
    """Sampled Eq. (7), normalized by population proportions rather than batch sizes.

    rho = unique observed pairs / (num_users * num_items).
    all: rho * mean_O[w*(e-gamma*h)] + mean_D[gamma*h].
    unobserved: rho * mean_O[w*e-(w-1)*gamma*h]
                + (1-rho) * mean_(D\\O)[gamma*h].

    author/dr preserve the historical sum/M objectives, for explicit ablations
    only. They do not claim to implement Eq. (7) with a full-catalog direct pool.
    """
    if ips_weighting not in ("paper", "author", "dr"):
        raise ValueError("ips_weighting must be paper, author or dr")
    if counterfactual_pool not in ("all", "unobserved"):
        raise ValueError("counterfactual_pool must be all or unobserved")
    if not len(pred_obs):
        raise ValueError("Observed batch is empty")
    keep_obs = imputation_keep(imp_loss_obs, imp_unc_obs, un_thres, filter_mode)
    keep_direct = imputation_keep(imp_loss_unobs, imp_unc_unobs, un_thres, filter_mode)
    error = (F.binary_cross_entropy(pred_obs, y_obs, reduction="none")
             if observed_error is None else observed_error)
    retained_obs = imp_loss_obs * keep_obs
    retained_direct = imp_loss_unobs * keep_direct

    if ips_weighting == "paper":
        if observed_fraction is None or not math.isfinite(observed_fraction) or not 0 < observed_fraction <= 1:
            raise ValueError("Eq. (7) requires observed_fraction in (0, 1]")
        if counterfactual_scale != 1.0:
            raise ValueError("Eq. (7) already normalizes the population; counterfactual_scale must be 1")
        rho = observed_fraction
        correction = inv_prop_obs if counterfactual_pool == "all" else inv_prop_obs - 1.0
        observed = rho * (inv_prop_obs * error - correction * retained_obs).mean()
        direct_fraction = 1.0 if counterfactual_pool == "all" else 1.0 - rho
        if not len(retained_direct) and direct_fraction > 0:
            raise ValueError("Direct batch is empty for a nonempty candidate pool")
        direct = retained_direct.mean() * direct_fraction if len(retained_direct) else observed.new_zeros(())
        loss = observed + direct
    else:
        correction = (inv_prop_obs - 1.0).clamp(min=0) if ips_weighting == "dr" else torch.ones_like(inv_prop_obs)
        loss = ((inv_prop_obs * error - correction * retained_obs).sum()
                + retained_direct.sum() * counterfactual_scale) / max(len(pred_unobs), 1)

    stats = {"observed_count": len(keep_obs), "direct_count": len(keep_direct),
             "filtered_observed": int((1 - keep_obs).sum().item()),
             "filtered_direct": int((1 - keep_direct).sum().item())}
    fraction = (stats["filtered_observed"] + stats["filtered_direct"]) / max(
        stats["observed_count"] + stats["direct_count"], 1)
    return (loss, fraction, stats) if return_diagnostics else (loss, fraction)
