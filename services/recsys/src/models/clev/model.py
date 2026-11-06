"""CLEV-DR: Zhang et al., "Addressing Correlated Latent Exogenous Variables in Debiased Recommender Systems",
KDD 2025 ("Ours-DR" in Table 2). Ported to CPU from WallaceSUI/kdd25-background-variable @ 66a0e5f
(new_model.py: NCF_BaseModel_3, MF_BV_Multi_bin_JL_G_DR). This is a re-implementation of the same
behaviour, not a copy. The name CLEV-DR is local; the paper has none.

Order of operations, losses, clipping constants and the sampling of epsilon follow the author code so that the
same seed reproduces the same run; the only change is that every tensor stays on the CPU.
"""
import numpy as np
import scipy.sparse as sps
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.distributions.normal import Normal
from torch.nn.parameter import Parameter


def all_pairs(num_users, num_items):
    """utils.generate_total_sample: every (user, item) pair, users outer, items inner."""
    users = np.repeat(np.arange(num_users), num_items)
    items = np.tile(np.arange(num_items), num_users)
    return np.stack([users, items], axis=1)


class NCFBase(nn.Module):
    """NCF_BaseModel_3: concat(user, item) embeddings -> Linear(2k, k) -> ReLU -> Linear(k, k) -> ReLU -> Linear(k, 1)."""

    def __init__(self, num_users, num_items, embedding_k=4):
        super().__init__()
        self.num_users, self.num_items, self.embedding_k = num_users, num_items, embedding_k
        self.W = nn.Embedding(num_users, embedding_k)
        self.H = nn.Embedding(num_items, embedding_k)
        self.linear_1 = nn.Linear(embedding_k * 2, embedding_k, bias=True)
        self.linear_2 = nn.Linear(embedding_k, embedding_k, bias=True)
        self.linear_3 = nn.Linear(embedding_k, 1, bias=True)
        self.relu = nn.ReLU()

    def forward(self, x, is_training=False):
        user_idx = torch.LongTensor(x[:, 0])
        item_idx = torch.LongTensor(x[:, 1])
        u_emb, v_emb = self.W(user_idx), self.H(item_idx)
        out = self.linear_3(self.relu(self.linear_2(self.relu(self.linear_1(torch.cat([u_emb, v_emb], axis=1))))))
        if is_training:
            return torch.squeeze(out), u_emb, v_emb
        return torch.squeeze(out)

    def predict(self, x):
        return self.forward(x).detach().cpu()


class CLEVDR(nn.Module):
    """MF_BV_Multi_bin_JL_G_DR: prediction g_y, selection g_o (probit), IPS tower and imputation tower,
    correlated latent noise rho = tanh(rho_v), Monte Carlo likelihood with `monte_sample_num` draws."""

    def __init__(self, num_users, num_items, batch_size, embedding_k=4, batch_size_prop=1024, monte_sample_num=10,
                 rho=None, rho_given=None, materialize_pairs=True):
        super().__init__()
        self.num_users, self.num_items = num_users, num_items
        self.embedding_k, self.batch_size, self.batch_size_prop = embedding_k, batch_size, batch_size_prop
        # Creation order follows the author code so a seed gives the same initial weights.
        self.prediction_model = NCFBase(num_users, num_items, embedding_k)
        self.propensity_model = NCFBase(num_users, num_items, embedding_k)
        self.monte_sample_num = monte_sample_num
        self.propensity_model_2 = NCFBase(num_users, num_items, embedding_k)
        self.imputation_model = NCFBase(num_users, num_items, embedding_k)
        self.normal = Normal(torch.tensor([0.0]), torch.tensor([1.0]))
        self.rho_num = rho_given
        self.rho_v = Parameter(torch.Tensor([0 if rho is None else rho]), requires_grad=True)
        self.sigmoid = nn.Sigmoid()
        self.tanh = nn.Tanh()
        self.x_all = all_pairs(num_users, num_items) if materialize_pairs else None

    def rho(self):
        if self.rho_num is None:
            return self.tanh(self.rho_v)
        return torch.Tensor([self.rho_num])

    def _dense(self, x, values):
        return sps.csr_matrix((values, (x[:, 0], x[:, 1])), shape=(self.num_users, self.num_items),
                              dtype=np.float32).toarray().reshape(-1)

    def compute_ips(self, x, num_epoch=1000, lr=0.05, lamb=1e-4, tol=1e-5, verbose=False):
        """_compute_IPS: propensity_model_2 regresses the observation indicator on every pair with MSE."""
        obs = self._dense(x, np.ones(x.shape[0]))
        optimizer = torch.optim.Adam(self.propensity_model_2.parameters(), lr=lr, weight_decay=lamb)
        last_loss, early_stop = 1e9, 0
        total_batch = len(obs) // self.batch_size_prop
        info = {"epochs_run": 0, "converged": False}
        for epoch in range(num_epoch):
            ul_idxs = np.arange(self.x_all.shape[0])
            np.random.shuffle(ul_idxs)
            epoch_loss = 0
            for idx in range(total_batch):
                x_all_idx = ul_idxs[idx * self.batch_size_prop:(idx + 1) * self.batch_size_prop]
                prop = self.sigmoid(self.propensity_model_2.forward(self.x_all[x_all_idx]))
                prop_loss = nn.MSELoss()(prop, torch.Tensor(obs[x_all_idx]))
                optimizer.zero_grad()
                prop_loss.backward()
                optimizer.step()
                epoch_loss += prop_loss.detach().cpu().numpy()
            info["epochs_run"] = epoch + 1
            relative_loss_div = (last_loss - epoch_loss) / (last_loss + 1e-10)
            if relative_loss_div < tol:
                if early_stop > 5:
                    info["converged"] = True
                    break
                early_stop += 1
            last_loss = epoch_loss
            if verbose:
                print(f"[CLEV-DR IPS] epoch {epoch} loss {epoch_loss:.6f}")
        return info

    def fit(self, x, y, num_epoch=1000, lr=0.05, lamb=0, tol=1e-4, verbose=False, alpha=None, G=1, gamma=0.015):
        obs = self._dense(x, np.ones(x.shape[0]))
        y_all = self._dense(x, y)
        optimizer = torch.optim.Adam(self.parameters(), lr=lr, weight_decay=lamb)
        optimizer_imputation = torch.optim.Adam(self.imputation_model.parameters(), lr=lr, weight_decay=lamb)
        last_loss, early_stop = 1e9, 0
        num_sample = len(x)
        epsilon_all = self.normal.sample((self.num_users * self.num_items, self.monte_sample_num)).squeeze(-1)
        total_batch = num_sample // self.batch_size
        x_all = self.x_all
        info = {"epochs_run": 0, "converged": False}
        for epoch in range(num_epoch):
            all_idx = np.arange(num_sample)
            np.random.shuffle(all_idx)
            epoch_loss = 0
            ul_idxs = np.arange(x_all.shape[0])
            np.random.shuffle(ul_idxs)
            for idx in range(total_batch):
                selected_idx = all_idx[self.batch_size * idx:(idx + 1) * self.batch_size]
                sub_x = x[selected_idx]
                sub_y = torch.Tensor(y[selected_idx])
                sub_epsilon = epsilon_all[sub_x[:, 0] * self.num_items + sub_x[:, 1]]
                x_sampled_idx = ul_idxs[G * idx * self.batch_size:G * (idx + 1) * self.batch_size]
                x_sampled = x_all[x_sampled_idx]
                sub_o = obs[x_sampled_idx]
                x_sampled_o1 = x_sampled[sub_o == 1]
                y_sampled = torch.Tensor(y_all[x_sampled_idx][sub_o == 1])

                # Outcome likelihood on observed pairs (bivariate probit with correlated latent noise).
                g_y = self.prediction_model.forward(sub_x, False).unsqueeze(-1)
                g_o = self.propensity_model.forward(sub_x, False).unsqueeze(-1).detach()
                logphi_o = self.normal.cdf(g_o).squeeze(-1)
                pos_idx = sub_epsilon + g_o > 0
                logphi = self.normal.cdf((g_y + self.rho() * sub_epsilon) / torch.sqrt(1 - self.rho() ** 2)) \
                    * pos_idx.detach()
                e_logphi = torch.mean(logphi, axis=1)
                y_loss = -torch.mean(torch.log(torch.clip(e_logphi, min=1e-5)) * sub_y
                                     + torch.log(torch.clip(logphi_o - e_logphi, min=1e-5)) * (1 - sub_y))

                # Doubly robust squared-error loss with the IPS tower and the imputation tower.
                inv_prop = 1 / torch.clip(self.sigmoid(self.propensity_model_2.forward(sub_x)).detach(), gamma, 1)
                pred = self.sigmoid(g_y)
                imputation_y = self.sigmoid(self.imputation_model.predict(sub_x))
                pred_u = self.sigmoid(self.prediction_model.forward(x_sampled))
                imputation_y1 = self.sigmoid(self.imputation_model.predict(x_sampled))
                xent_loss = torch.sum(F.mse_loss(pred.reshape(-1), sub_y.reshape(-1), reduction="none")
                                      * inv_prop.reshape(-1))
                imputation_loss = F.mse_loss(pred.reshape(-1), imputation_y, reduction="sum")
                ips_loss = xent_loss - imputation_loss
                direct_loss = F.mse_loss(pred_u, imputation_y1, reduction="sum")
                mf_loss = (ips_loss + direct_loss) / x_sampled.shape[0]
                if alpha is None:
                    y_loss = y_loss * torch.clip(self.rho().detach(), min=0.01, max=0.99) \
                        + torch.clip(1 - self.rho().detach(), min=0.01, max=0.99) * mf_loss
                else:
                    y_loss = y_loss * alpha + (1 - alpha) * mf_loss
                optimizer.zero_grad()
                y_loss.backward()
                optimizer.step()

                # Imputation tower.
                pred = self.sigmoid(self.prediction_model.predict(sub_x))
                imputation_y = self.sigmoid(self.imputation_model.forward(sub_x))
                e_loss = F.mse_loss(pred, sub_y, reduction="none")
                e_hat_loss = F.mse_loss(imputation_y, pred, reduction="none")
                imp_loss = (((e_loss.detach() - e_hat_loss) ** 2) * inv_prop).sum()
                optimizer_imputation.zero_grad()
                imp_loss.backward()
                optimizer_imputation.step()

                # Selection model g_o on sampled pairs, symmetric likelihood with g_y fixed.
                g_y = self.prediction_model.forward(x_sampled_o1, False).unsqueeze(-1).detach()
                g_o = self.propensity_model.forward(x_sampled, False).unsqueeze(-1)
                sub_epsilon = epsilon_all[x_sampled_idx][sub_o == 1]
                pos_idx = sub_epsilon + g_y > 0
                logphi = self.normal.cdf((g_o[sub_o == 1] + self.rho() * sub_epsilon)
                                         / torch.sqrt(1 - self.rho() ** 2)) * pos_idx.detach()
                e_logphi = torch.mean(logphi, axis=1)
                logphi_o = self.normal.cdf(g_o[sub_o == 1]).squeeze(-1)
                o_loss1 = -torch.sum(torch.log(torch.clip(e_logphi, min=1e-5)) * y_sampled
                                     + torch.log(torch.clip(logphi_o - e_logphi, min=1e-5)) * (1 - y_sampled))
                o_loss0 = -torch.sum(torch.clip(self.normal.cdf(-g_o[sub_o == 0]), min=1e-5).log())
                o_loss = o_loss0 + o_loss1
                optimizer.zero_grad()
                o_loss.backward()
                optimizer.step()
                epoch_loss += (y_loss + o_loss).detach().cpu().numpy()
            info["epochs_run"] = epoch + 1
            relative_loss_div = (last_loss - epoch_loss) / (last_loss + 1e-10)
            if relative_loss_div < tol:
                if early_stop > 5:
                    info["converged"] = True
                    break
                early_stop += 1
            last_loss = epoch_loss
            if verbose:
                print(f"[CLEV-DR] epoch {epoch} loss {float(epoch_loss):.6f} rho {float(self.rho()):.4f}")
        info["rho"] = float(self.rho().detach())
        return info

    def predict(self, x):
        return self.sigmoid(self.prediction_model.forward(x)).detach().cpu().numpy()


class CLEVDRLarge(CLEVDR):
    """CLEVDR without the |U| x |I| arrays, for KuaiRand-Pure (207M pairs, the author layout needs ~33 GB).

    Identical algorithm and random stream: pairs are decoded from flat indices (row-major, as all_pairs), the
    observation and label lookups use the sorted observed codes, and the Monte Carlo noise is drawn chunk by chunk
    in the same order as Normal.sample((|U| * |I|, M)) but only the rows of observed pairs are kept, which are the
    only rows the likelihood reads. Training pairs must be unique (the author's csr build would sum duplicates).
    """

    def __init__(self, num_users, num_items, batch_size, embedding_k=4, batch_size_prop=1024, monte_sample_num=10,
                 rho=None, rho_given=None, epsilon_chunk=1_000_000):
        super().__init__(num_users, num_items, batch_size, embedding_k, batch_size_prop, monte_sample_num, rho,
                         rho_given, materialize_pairs=False)
        self.epsilon_chunk = epsilon_chunk

    @property
    def n_pairs(self):
        return self.num_users * self.num_items

    def _pair_indices(self):
        return np.arange(self.n_pairs, dtype=np.int32)

    def _pairs(self, idx):
        return np.stack([idx // self.num_items, idx % self.num_items], axis=1)

    def _codes(self, x):
        codes = x[:, 0].astype(np.int64) * self.num_items + x[:, 1].astype(np.int64)
        if len(np.unique(codes)) != len(codes):
            raise ValueError("CLEVDRLarge needs unique (user, item) training pairs")
        return codes

    @staticmethod
    def _lookup(sorted_codes, idx):
        pos = np.searchsorted(sorted_codes, idx)
        hit = pos < len(sorted_codes)
        hit[hit] = sorted_codes[pos[hit]] == idx[hit]
        return hit, pos

    def _chunks(self):
        """Row ranges whose draws equal one Normal.sample((n_pairs, M)) call: torch fills normals in blocks of 16
        values, so every chunk holds a multiple of 16 rows and a tail under 16 values joins the previous chunk."""
        rows = max(16, -(-self.epsilon_chunk // 16) * 16)
        bounds = list(range(0, self.n_pairs, rows)) + [self.n_pairs]
        if len(bounds) > 2 and (bounds[-1] - bounds[-2]) * self.monte_sample_num < 16:
            del bounds[-2]
        return list(zip(bounds[:-1], bounds[1:]))

    def _observed_epsilon(self, sorted_codes):
        """Rows of Normal.sample((|U| |I|, M)) at the observed codes, without holding the full array."""
        out = torch.empty(len(sorted_codes), self.monte_sample_num)
        for start, stop in self._chunks():
            block = self.normal.sample((stop - start, self.monte_sample_num)).squeeze(-1)
            lo, hi = np.searchsorted(sorted_codes, [start, stop])
            if hi > lo:
                out[lo:hi] = block[torch.as_tensor(sorted_codes[lo:hi] - start)]
        return out

    def compute_ips(self, x, num_epoch=1000, lr=0.05, lamb=1e-4, tol=1e-5, verbose=False):
        sorted_codes = np.sort(self._codes(x))
        optimizer = torch.optim.Adam(self.propensity_model_2.parameters(), lr=lr, weight_decay=lamb)
        last_loss, early_stop = 1e9, 0
        total_batch = self.n_pairs // self.batch_size_prop
        info = {"epochs_run": 0, "converged": False}
        for epoch in range(num_epoch):
            ul_idxs = self._pair_indices()
            np.random.shuffle(ul_idxs)
            epoch_loss = 0
            for idx in range(total_batch):
                x_all_idx = ul_idxs[idx * self.batch_size_prop:(idx + 1) * self.batch_size_prop]
                prop = self.sigmoid(self.propensity_model_2.forward(self._pairs(x_all_idx)))
                sub_obs = self._lookup(sorted_codes, x_all_idx)[0].astype(np.float32)
                prop_loss = nn.MSELoss()(prop, torch.Tensor(sub_obs))
                optimizer.zero_grad()
                prop_loss.backward()
                optimizer.step()
                epoch_loss += prop_loss.detach().cpu().numpy()
            info["epochs_run"] = epoch + 1
            relative_loss_div = (last_loss - epoch_loss) / (last_loss + 1e-10)
            if relative_loss_div < tol:
                if early_stop > 5:
                    info["converged"] = True
                    break
                early_stop += 1
            last_loss = epoch_loss
            if verbose:
                print(f"[CLEV-DR IPS] epoch {epoch} loss {epoch_loss:.6f}")
        return info

    def fit(self, x, y, num_epoch=1000, lr=0.05, lamb=0, tol=1e-4, verbose=False, alpha=None, G=1, gamma=0.015):
        codes = self._codes(x)
        order = np.argsort(codes)
        sorted_codes, sorted_y = codes[order], np.asarray(y, dtype=np.float32)[order]
        rank_of_row = np.empty(len(codes), dtype=np.int64)
        rank_of_row[order] = np.arange(len(codes))
        optimizer = torch.optim.Adam(self.parameters(), lr=lr, weight_decay=lamb)
        optimizer_imputation = torch.optim.Adam(self.imputation_model.parameters(), lr=lr, weight_decay=lamb)
        last_loss, early_stop = 1e9, 0
        num_sample = len(x)
        epsilon_obs = self._observed_epsilon(sorted_codes)
        total_batch = num_sample // self.batch_size
        info = {"epochs_run": 0, "converged": False}
        for epoch in range(num_epoch):
            all_idx = np.arange(num_sample, dtype=np.int32)
            np.random.shuffle(all_idx)
            epoch_loss = 0
            ul_idxs = self._pair_indices()
            np.random.shuffle(ul_idxs)
            for idx in range(total_batch):
                selected_idx = all_idx[self.batch_size * idx:(idx + 1) * self.batch_size]
                sub_x = x[selected_idx]
                sub_y = torch.Tensor(y[selected_idx])
                sub_epsilon = epsilon_obs[torch.as_tensor(rank_of_row[selected_idx])]
                x_sampled_idx = ul_idxs[G * idx * self.batch_size:G * (idx + 1) * self.batch_size]
                x_sampled = self._pairs(x_sampled_idx)
                hit, pos = self._lookup(sorted_codes, x_sampled_idx)
                sub_o = hit.astype(np.float32)
                x_sampled_o1 = x_sampled[sub_o == 1]
                y_sampled = torch.Tensor(sorted_y[pos[hit]])

                g_y = self.prediction_model.forward(sub_x, False).unsqueeze(-1)
                g_o = self.propensity_model.forward(sub_x, False).unsqueeze(-1).detach()
                logphi_o = self.normal.cdf(g_o).squeeze(-1)
                pos_idx = sub_epsilon + g_o > 0
                logphi = self.normal.cdf((g_y + self.rho() * sub_epsilon) / torch.sqrt(1 - self.rho() ** 2)) \
                    * pos_idx.detach()
                e_logphi = torch.mean(logphi, axis=1)
                y_loss = -torch.mean(torch.log(torch.clip(e_logphi, min=1e-5)) * sub_y
                                     + torch.log(torch.clip(logphi_o - e_logphi, min=1e-5)) * (1 - sub_y))

                inv_prop = 1 / torch.clip(self.sigmoid(self.propensity_model_2.forward(sub_x)).detach(), gamma, 1)
                pred = self.sigmoid(g_y)
                imputation_y = self.sigmoid(self.imputation_model.predict(sub_x))
                pred_u = self.sigmoid(self.prediction_model.forward(x_sampled))
                imputation_y1 = self.sigmoid(self.imputation_model.predict(x_sampled))
                xent_loss = torch.sum(F.mse_loss(pred.reshape(-1), sub_y.reshape(-1), reduction="none")
                                      * inv_prop.reshape(-1))
                imputation_loss = F.mse_loss(pred.reshape(-1), imputation_y, reduction="sum")
                ips_loss = xent_loss - imputation_loss
                direct_loss = F.mse_loss(pred_u, imputation_y1, reduction="sum")
                mf_loss = (ips_loss + direct_loss) / x_sampled.shape[0]
                if alpha is None:
                    y_loss = y_loss * torch.clip(self.rho().detach(), min=0.01, max=0.99) \
                        + torch.clip(1 - self.rho().detach(), min=0.01, max=0.99) * mf_loss
                else:
                    y_loss = y_loss * alpha + (1 - alpha) * mf_loss
                optimizer.zero_grad()
                y_loss.backward()
                optimizer.step()

                pred = self.sigmoid(self.prediction_model.predict(sub_x))
                imputation_y = self.sigmoid(self.imputation_model.forward(sub_x))
                e_loss = F.mse_loss(pred, sub_y, reduction="none")
                e_hat_loss = F.mse_loss(imputation_y, pred, reduction="none")
                imp_loss = (((e_loss.detach() - e_hat_loss) ** 2) * inv_prop).sum()
                optimizer_imputation.zero_grad()
                imp_loss.backward()
                optimizer_imputation.step()

                g_y = self.prediction_model.forward(x_sampled_o1, False).unsqueeze(-1).detach()
                g_o = self.propensity_model.forward(x_sampled, False).unsqueeze(-1)
                sub_epsilon = epsilon_obs[torch.as_tensor(pos[hit])]
                pos_idx = sub_epsilon + g_y > 0
                logphi = self.normal.cdf((g_o[sub_o == 1] + self.rho() * sub_epsilon)
                                         / torch.sqrt(1 - self.rho() ** 2)) * pos_idx.detach()
                e_logphi = torch.mean(logphi, axis=1)
                logphi_o = self.normal.cdf(g_o[sub_o == 1]).squeeze(-1)
                o_loss1 = -torch.sum(torch.log(torch.clip(e_logphi, min=1e-5)) * y_sampled
                                     + torch.log(torch.clip(logphi_o - e_logphi, min=1e-5)) * (1 - y_sampled))
                o_loss0 = -torch.sum(torch.clip(self.normal.cdf(-g_o[sub_o == 0]), min=1e-5).log())
                o_loss = o_loss0 + o_loss1
                optimizer.zero_grad()
                o_loss.backward()
                optimizer.step()
                epoch_loss += (y_loss + o_loss).detach().cpu().numpy()
            info["epochs_run"] = epoch + 1
            relative_loss_div = (last_loss - epoch_loss) / (last_loss + 1e-10)
            if relative_loss_div < tol:
                if early_stop > 5:
                    info["converged"] = True
                    break
                early_stop += 1
            last_loss = epoch_loss
            if verbose:
                print(f"[CLEV-DR] epoch {epoch} loss {float(epoch_loss):.6f} rho {float(self.rho().detach()):.4f}")
        info["rho"] = float(self.rho().detach())
        return info
