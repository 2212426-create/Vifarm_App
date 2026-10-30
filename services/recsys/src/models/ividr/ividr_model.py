"""IViDR equations (6)-(15), (40)-(44); explicit local dimension bridge.

Instrument columns come only from users exposed to each item in biased train.
The fixed feature embedding, mean pooling and registered exposure bridge resolve
dimensions unspecified in the preprint. This is not an author-code reproduction.
"""
import numpy as np
import torch
from torch import nn
from scipy import sparse

from src.models.idcf.ivae import ExposureIVAE, binary_exposure, mlp


def instrument_bases(exposure, features, treatment_dim, seed=1234):
    """Thin orthonormal Q_j implements Z_j Z_j^dagger without dense d*d caches."""
    a = sparse.csc_matrix(binary_exposure(exposure))
    w = np.asarray(features, dtype=np.float64)
    if (w.ndim != 2 or len(w) != a.shape[0] or not np.isfinite(w).all()
            or not w.shape[1] or treatment_dim < 1):
        raise ValueError("IV instruments require finite, aligned user features")
    transform = np.random.default_rng(seed).normal(size=(w.shape[1], treatment_dim)) / np.sqrt(w.shape[1])
    width = min(w.shape[1], treatment_dim)
    basis = np.zeros((a.shape[1], treatment_dim, width), dtype=np.float32)
    summaries = np.zeros((a.shape[1], treatment_dim), dtype=np.float32)
    ranks = []
    for item in range(a.shape[1]):
        users = a.indices[a.indptr[item]:a.indptr[item+1]]
        if not len(users):
            ranks.append(0)
            continue
        # First reduce in raw feature space; important when d=128 and histories are long.
        raw = w[users].T
        u, s, _ = np.linalg.svd(raw, full_matrices=False)
        rank = int(np.count_nonzero(s > (s[0] * 1e-8 if len(s) else 0)))
        mapped = transform.T @ u[:, :rank]
        q, singular, _ = np.linalg.svd(mapped, full_matrices=False)
        rank = int(np.count_nonzero(singular > (singular[0]*1e-8 if len(singular) else 0)))
        basis[item, :, :rank] = q[:, :rank]
        summaries[item] = w[users].mean(0) @ transform
        ranks.append(rank)
    return torch.from_numpy(basis), torch.from_numpy(summaries), {
        "construction": "biased-exposure user columns per item; thin SVD basis",
        "feature_embedding": "fixed seeded linear map; no rating/random-log labels",
        "feature_embedding_seed": seed, "mean_rank": float(np.mean(ranks)),
        "empty_items": int(np.count_nonzero(np.asarray(ranks) == 0)),
        "basis_bytes": int(basis.nbytes),
    }


class IVTreatment(nn.Module):
    """Learn MLP0 and both Eq.(9) gates; no fixed residual coefficient."""
    def __init__(self, item_embeddings, bases, summaries, hidden_dim=64):
        super().__init__()
        t = torch.as_tensor(item_embeddings, dtype=torch.float32)
        q = torch.as_tensor(bases, dtype=torch.float32)
        z = torch.as_tensor(summaries, dtype=torch.float32)
        if (t.ndim != 2 or q.ndim != 3 or z.ndim != 2
                or len(t) != len(q) or z.shape != q.shape[:2]
                or not all(torch.isfinite(v).all() for v in (t, q, z))):
            raise ValueError("Invalid treatment/instrument dimensions or values")
        self.register_buffer("treatment", t.clone())
        self.register_buffer("instrument_basis", q.clone())
        self.register_buffer("instrument_summary", z.clone())
        d = z.shape[1]
        self.phi = mlp(t.shape[1], hidden_dim, d, 3)
        self.alpha_fitted = mlp(2*d, hidden_dim, 1, 3)
        self.alpha_residual = mlp(2*d, hidden_dim, 1, 3)

    def components(self):
        t = self.phi(self.treatment)
        q = self.instrument_basis
        fitted = torch.bmm(q, torch.bmm(q.transpose(1, 2), t.unsqueeze(-1))).squeeze(-1)
        residual = t - fitted
        gates = torch.cat((t, self.instrument_summary), dim=1)
        return fitted, residual, self.alpha_fitted(gates), self.alpha_residual(gates)

    def forward(self):
        fitted, residual, a, b = self.components()
        return a*fitted + b*residual


class DualExposureIVAE(ExposureIVAE):
    """Shared encoder/prior on original and IV-reconstructed input; two ELBOs."""
    def __init__(self, n_items, aux_dim, latent_dim, hidden_dim, n_layers,
                 item_embeddings, bases, summaries):
        super().__init__(n_items, aux_dim, latent_dim, hidden_dim, n_layers)
        self.prior_mean = mlp(aux_dim, hidden_dim, latent_dim, n_layers)
        self.iv = IVTreatment(item_embeddings, bases, summaries, hidden_dim)
        self.exposure_bridge = nn.Linear(summaries.shape[1], n_items, bias=False)

    def posteriors(self, a, w):
        reconstructed = self.iv()
        history = (a @ reconstructed) / a.sum(1, keepdim=True).clamp_min(1)
        x_re = a + self.exposure_bridge(history)
        m1, l1 = self.encode(x_re, w)
        m2, l2 = self.encode(a, w)
        return m1, l1, m2, l2

    def dual_elbo(self, a, w, beta=1., generator=None):
        from src.models.idcf.ivae import elbo_loss
        m1, l1, m2, l2 = self.posteriors(a, w)
        pm, pl = self.prior_mean(w), self.prior_log_var(w)
        losses = []
        for mean, logvar in ((m1, l1), (m2, l2)):
            noise = torch.randn(mean.shape, device=mean.device, generator=generator)
            z = mean + torch.exp(.5*logvar)*noise
            losses.append(elbo_loss(a, self.decoder(z), mean, logvar, pm, pl, beta))
        return (losses[0]+losses[1])*.5

    def confounders(self, a, w, rho=.9, tau=.9):
        m1, l1, m2, l2 = self.posteriors(a, w)
        # Independent draws from the two posteriors; Eq.(15) then has this variance.
        return rho*m1+tau*m2, torch.sqrt(rho*rho*l1.exp()+tau*tau*l2.exp())
