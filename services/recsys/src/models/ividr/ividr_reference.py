"""IViDR arXiv 2410.12451: learned instruments and marginal BCE prediction.

Equations (6)-(9) use the entire per-item instrument matrix. Its first gate
layer is factorized over user columns, so no padded user*embedding tensor is
needed. The paper leaves Eq. (10)'s coordinate conversion unspecified: this
implementation explicitly ties that conversion to the item treatment vectors.
It is a documented reference implementation, not a claim of author-code parity.
"""
import math

import numpy as np
import torch
from scipy import sparse
from torch import nn
from torch.nn import functional as F

from src.models.idcf.ivae import ExposureIVAE, binary_exposure, elbo_loss, mlp
from src.models.mf.matrix_factorization import MatrixFactorization


class LearnedInstruments(nn.Module):
    """Linear feature embeddings; exact column-space projection for each item.

Cache orthonormal bases in RAW feature space, never embedded feature space.
Then QR(E U_j) spans precisely the columns of Z_j = E W_j throughout training.
Both Eq. (9) gates receive a learned linear function of all columns of Z_j.
"""
    def __init__(self, item_embeddings, exposure, features, dimension, hidden_dim):
        super().__init__()
        a = sparse.csr_matrix(binary_exposure(exposure))
        w = np.asarray(features, dtype=np.float32)
        t = np.asarray(item_embeddings, dtype=np.float32)
        if (w.ndim != 2 or t.ndim != 2 or len(w) != a.shape[0]
                or len(t) != a.shape[1] or not w.shape[1] or dimension < 1
                or not np.isfinite(w).all() or not np.isfinite(t).all()):
            raise ValueError('Invalid IViDR feature, exposure or treatment dimensions')
        self.register_buffer('treatment', torch.from_numpy(t.copy()))
        self.register_buffer('features', torch.from_numpy(w.copy()))
        at = a.T.tocoo()
        self.register_buffer('exposure_t', torch.sparse_coo_tensor(
            np.array([at.row, at.col]), at.data, at.shape, check_invariants=True).coalesce())
        bases = np.zeros((a.shape[1], w.shape[1], w.shape[1]), dtype=np.float32)
        ranks = []
        columns = a.tocsc()
        for j in range(a.shape[1]):
            users = columns.indices[columns.indptr[j]:columns.indptr[j+1]]
            raw = w[users].T.astype(np.float64)
            u, s, _ = np.linalg.svd(raw, full_matrices=False)
            rank = int(np.count_nonzero(s > s[0]*1e-8)) if len(s) else 0
            bases[j, :, :rank] = u[:, :rank]
            ranks.append(rank)
        self.register_buffer('raw_bases', torch.from_numpy(bases))
        # Rank groups are structural data, independent of every learned parameter.
        self.rank_groups = [(rank, [j for j, r in enumerate(ranks) if r == rank])
                            for rank in sorted(set(ranks))]
        self.feature_embedding = nn.Linear(w.shape[1], dimension, bias=False)
        self.phi = mlp(t.shape[1], hidden_dim, dimension, 3)
        self.gate_columns = nn.Parameter(torch.full((2, len(w)), 1/math.sqrt(len(w))))
        self.alpha_fitted = mlp(2*dimension, hidden_dim, 1, 3)
        self.alpha_residual = mlp(2*dimension, hidden_dim, 1, 3)

    def components(self):
        t = self.phi(self.treatment)
        embedded = self.feature_embedding(self.features)
        fitted = torch.zeros_like(t)
        for rank, indices in self.rank_groups:
            if rank == 0:
                continue
            index = torch.as_tensor(indices, dtype=torch.long, device=t.device)
            if rank >= t.shape[1]:
                projected = t[index]  # Full row rank: Z Z^dagger is identity.
            else:
                mapped = self.feature_embedding.weight @ self.raw_bases[index, :, :rank]
                q, r = torch.linalg.qr(mapped, mode='reduced')
                if torch.any(r.diagonal(dim1=-2, dim2=-1).abs() < 1e-7):
                    raise FloatingPointError('Learned instrument embedding lost column rank')
                projected = (q @ (q.transpose(1, 2) @ t[index, :, None])).squeeze(-1)
            fitted = fitted.index_copy(0, index, projected)
        residual = t-fitted
        summaries = [torch.sparse.mm(self.exposure_t, embedded*self.gate_columns[k, :, None])
                     for k in range(2)]
        return (t, fitted, residual,
                self.alpha_fitted(torch.cat((t, summaries[0]), 1)),
                self.alpha_residual(torch.cat((t, summaries[1]), 1)))

    def forward(self):
        _, fitted, residual, a, b = self.components()
        return a*fitted+b*residual


EQ10_BRIDGES = ('tied_item_lift', 'tied_item_lift_rownorm')
RECONSTRUCTIONS = ('full', 'treatment', 'fitted', 'residual')


class PaperExposureIVAE(ExposureIVAE):
    """Eq. (40)-(44) on A, conditioned on original/reconstructed inputs.

Explicit Eq. (10) completion: lift the reconstructed treatment back into item
coordinates using the SAME transformed item vectors, rather than a free Linear:
P = (A T_re) T_0^T / sqrt(d). `tied_item_lift` (v2) uses X_re = A + P; the
gates then shrink P to ~0.3% of A because the ELBO only pays for perturbation.
`tied_item_lift_rownorm` (v3) rescales P per user to the norm of A_u, keeping
Eq. (10)'s unit-weight addition so the gates set direction, not existence.
`reconstruction` selects Table 4's ablations: full Eq. (8), treatment (T),
fitted only or residual only. Both decoders target observed binary A (Eq. 44).
"""
    def __init__(self, n_items, aux_dim, latent_dim, hidden_dim, n_layers,
                 item_embeddings, exposure, instruments, treatment_dim,
                 eq10_bridge='tied_item_lift', reconstruction='full', prior_mean='learned'):
        super().__init__(n_items, aux_dim, latent_dim, hidden_dim, n_layers)
        if (eq10_bridge not in EQ10_BRIDGES or reconstruction not in RECONSTRUCTIONS
                or prior_mean not in ('learned', 'zero')):
            raise ValueError('Unknown IViDR Eq. (10) bridge, reconstruction or prior mean')
        # 'learned' follows Eq. (42); 'zero' is the iDCF author-code prior N(0, v_w(W)).
        self.prior_mean_mode = prior_mean
        self.prior_mean = mlp(aux_dim, hidden_dim, latent_dim, n_layers)
        self.iv = LearnedInstruments(item_embeddings, exposure, instruments, treatment_dim, hidden_dim)
        self.eq10_bridge, self.reconstruction = eq10_bridge, reconstruction

    def reconstructed_input(self, a):
        t, fitted, residual, alpha, beta = self.iv.components()
        t_re = {'full': lambda: alpha*fitted+beta*residual, 'treatment': lambda: t,
                'fitted': lambda: alpha*fitted, 'residual': lambda: beta*residual}[self.reconstruction]()
        lift = ((a @ t_re) @ t.T)/math.sqrt(t.shape[1])
        if self.eq10_bridge == 'tied_item_lift_rownorm':
            lift = lift*(a.norm(dim=1, keepdim=True)/(lift.norm(dim=1, keepdim=True)+1e-8))
        return a + lift

    def posteriors(self, a, w):
        m1, l1 = self.encode(self.reconstructed_input(a), w)
        m2, l2 = self.encode(a, w)
        return m1, l1, m2, l2

    def dual_elbo(self, a, w, beta=1., generator=None):
        m1, l1, m2, l2 = self.posteriors(a, w)
        pl = self.prior_log_var(w)
        pm = self.prior_mean(w) if self.prior_mean_mode == 'learned' else torch.zeros_like(pl)
        losses = []
        for mean, logvar in ((m1, l1), (m2, l2)):
            noise = torch.randn(mean.shape, device=mean.device, generator=generator)
            z = mean+torch.exp(.5*logvar)*noise
            losses.append(elbo_loss(a, self.decoder(z), mean, logvar, pm, pl, beta))
        return .5*(losses[0]+losses[1])

    def confounders(self, a, w, rho=.9, tau=.9):
        m1, l1, m2, l2 = self.posteriors(a, w)
        return rho*m1+tau*m2, torch.sqrt(rho*rho*l1.exp()+tau*tau*l2.exp())


class IViDRMarginalMF(nn.Module):
    """Eq. (23)-(25): sigmoid(MF + latent score), THEN marginalize C.

Training uses 10 Monte Carlo draws. Deterministic inference integrates the
one-dimensional Gaussian logit using Gauss-Hermite quadrature. This scorer has
no factor shortcut: E[sigmoid(score)] is not a dot product of mean factors.
The output is logit(E[p]), for stable BCEWithLogits and identical ranking.
"""
    def __init__(self, num_users, num_items, latent_dim, embedding_dim=64,
                 init_scheme='author_uniform', sample_size=10, quadrature_points=32,
                 phi=1., lambda_mf=1.):
        super().__init__()
        self.mf = MatrixFactorization(num_users, num_items, embedding_dim, use_bias=True,
                                      train_global_bias=False, init_scheme=init_scheme)
        self.item_c = nn.Embedding(num_items, latent_dim)
        nn.init.uniform_(self.item_c.weight, -.01, .01)
        self.register_buffer('c_mean', torch.zeros(num_users, latent_dim))
        self.register_buffer('c_std', torch.zeros(num_users, latent_dim))
        nodes, weights = np.polynomial.hermite.hermgauss(quadrature_points)
        self.register_buffer('quadrature_nodes', torch.tensor(nodes, dtype=torch.float32))
        self.register_buffer('quadrature_log_weights', torch.tensor(np.log(weights), dtype=torch.float32))
        self.sample_size, self.phi, self.lambda_mf = sample_size, phi, lambda_mf

    def set_confounders(self, mean, std):
        self.c_mean.copy_(mean); self.c_std.copy_(std)
        return self

    def forward(self, users, items, sample=False):
        e, mean, std = self.item_c(items), self.c_mean[users], self.c_std[users]
        base = self.lambda_mf*self.mf(users, items)
        if sample:
            z = mean + std*torch.randn((self.sample_size, *mean.shape), device=mean.device)
            logits = base[None, :]+self.phi*(e*z).sum(-1)
            log_weights = torch.zeros((self.sample_size, 1), device=logits.device)
        else:
            mu = base+self.phi*(e*mean).sum(-1)
            sigma = abs(self.phi)*torch.sqrt((e.square()*std.square()).sum(-1))
            logits = mu[None, :]+math.sqrt(2)*self.quadrature_nodes[:, None]*sigma[None, :]
            log_weights = self.quadrature_log_weights[:, None]
        # The common normalization cancels when converting E[p] to log-odds.
        return (torch.logsumexp(F.logsigmoid(logits)+log_weights, dim=0)
                -torch.logsumexp(F.logsigmoid(-logits)+log_weights, dim=0))
