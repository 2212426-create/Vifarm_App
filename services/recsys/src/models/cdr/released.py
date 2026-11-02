"""DR-BIAS+CDR as released by Song et al., CIKM 2023 (Apache-2.0).

Adapted from CrazyDumpling/CDR_CIKM2023 at
6b4e6cca3df23b8d85b38fdc2e7eb5c812861ea9, CDR/MF_mcdropout.py.
Retains variance filtering, output masking, reversed imputation BCE, sum losses,
initialization and cumulative train-loss stopping. See CDR_UPSTREAM_LICENSE.txt.
Flat catalog IDs replace the source's materialized array of all (u,i) pairs;
the permutation and resulting pairs are identical on CPU.
"""
import numpy as np
import torch
from torch import nn
import torch.nn.functional as F

UPSTREAM_COMMIT = "6b4e6cca3df23b8d85b38fdc2e7eb5c812861ea9"
UPSTREAM_URL = f"https://github.com/CrazyDumpling/CDR_CIKM2023/tree/{UPSTREAM_COMMIT}"


class ReleasedDotMF(nn.Module):
    def __init__(self, num_users, num_items, embedding_dim, xavier=False):
        super().__init__()
        self.W = nn.Embedding(num_users, embedding_dim)
        self.H = nn.Embedding(num_items, embedding_dim)
        if xavier:
            nn.init.xavier_normal_(self.W.weight)
            nn.init.xavier_normal_(self.H.weight)

    def forward(self, users, items):
        return (self.W(users) * self.H(items)).sum(1)


class ReleasedCDR(nn.Module):
    def __init__(self, num_users, num_items, embedding_dim=4, un_thres=10., dropout_rate=.5):
        super().__init__()
        self.num_users, self.num_items = num_users, num_items
        self.un_thres, self.dropout_rate = un_thres, dropout_rate
        self.rec_model = ReleasedDotMF(num_users, num_items, embedding_dim, xavier=True)
        self.imp_model = ReleasedDotMF(num_users, num_items, embedding_dim)

    def forward(self, users, items):
        return self.rec_model(users, items)

    def predict_user_all(self, users):
        return self.rec_model.W(users) @ self.rec_model.H.weight.T

    def get_evaluation_factors(self):
        return (self.rec_model.W.weight.detach().cpu().numpy(), self.rec_model.H.weight.detach().cpu().numpy())

    def mask(self, x):
        return (torch.rand(x.shape, device=x.device) > self.dropout_rate).float() * x

    @torch.no_grad()
    def sample_predict(self, users, items, samples=10):
        # Keep mask draw order and output probability dropout of the source.
        predictions = torch.stack([(self.mask(self.imp_model.W(users)) *
                                     self.mask(self.imp_model.H(items))).sum(1) for _ in range(samples)])
        return self.mask(predictions.sigmoid())

    @staticmethod
    def sample_bce(predictions, pseudo):
        errors = torch.stack([F.binary_cross_entropy(predictions, row, reduction="none") for row in pseudo])
        mean = errors.mean(0)
        return mean, ((errors - mean) ** 2).mean(0)


def released_inverse_propensity(x, y, calibration, population_size=None):
    """Source Naive Bayes; None retains its exact max-ID denominator convention."""
    x, y, calibration = np.asarray(x), np.asarray(y), np.asarray(calibration)
    if not len(y) or not len(calibration) or not np.isin(y,[0,1]).all() or not np.isin(calibration,[0,1]).all():
        raise ValueError("Released CDR propensity requires nonempty binary labels")
    py1, py1o1 = calibration.sum()/len(calibration), y.sum()/len(y)
    denominator = population_size if population_size is not None else int(x[:,0].max()) * int(x[:,1].max())
    if denominator <= 0 or not 0 < py1 < 1 or not 0 < py1o1 < 1:
        raise ValueError("Released CDR calibration requires both classes and a valid population")
    po1 = len(x) / denominator
    propensity = np.where(y == 1, py1o1*po1/py1, (1-py1o1)*po1/(1-py1))
    return torch.tensor(1/propensity, dtype=torch.float32), dict(
        method="released_naive_bayes", calibration_rows=len(calibration),
        calibration_positive_rate=float(py1), train_positive_rate=float(py1o1),
        population_denominator=int(denominator), observed_fraction=float(po1))


def fit_released(model, x, y, inverse, *, epochs=1000, batch_size=128, lr=.05,
                 weight_decay=.001, G=4, samples=10, tol=1e-5, stop=5, on_epoch=None,
                 catalog_sampler="permutation", on_progress=None):
    """CPU matches source update order/RNG. on_epoch implements held-out selection.

    With no callback, preserve the released script's cumulative (non-resetting)
    train-loss stopping counter. The callback receives (epoch, training_stats).
    """
    if epochs < 1 or batch_size < 1 or G < 1 or samples < 1 or len(x) < batch_size:
        raise ValueError("Released CDR needs a positive budget and at least one full observed batch")
    device = next(model.parameters()).device
    xt, yt = torch.as_tensor(x, dtype=torch.long, device=device), torch.as_tensor(y, dtype=torch.float32, device=device)
    inverse = inverse.to(device)
    opt_rec = torch.optim.Adam(model.rec_model.parameters(), lr=lr, weight_decay=weight_decay)
    opt_imp = torch.optim.Adam(model.imp_model.parameters(), lr=lr, weight_decay=weight_decay)
    population = model.num_users * model.num_items
    if catalog_sampler not in ("permutation", "replacement"):
        raise ValueError("Unknown catalog sampler")
    if catalog_sampler == "permutation" and G * (len(x)//batch_size) * batch_size > population:
        raise ValueError("Released sampling budget exceeds the finite catalog; reduce G")
    last_loss, early, batches, history = 1e9, 0, len(x)//batch_size, []
    for epoch in range(epochs):
        observed = np.random.permutation(len(x))
        catalog = np.random.permutation(population) if catalog_sampler == "permutation" else None
        epoch_loss, rec_total, imp_total, removed, count = 0, 0., 0., 0, 0
        for batch in range(batches):
            idx = observed[batch*batch_size:(batch+1)*batch_size]
            users, items, labels, w = xt[idx,0], xt[idx,1], yt[idx], inverse[idx]
            pred = model(users, items).sigmoid()
            pseudo = model.sample_predict(users, items, samples)
            ids = (catalog[G*batch*batch_size:G*(batch+1)*batch_size] if catalog is not None
                   else np.random.randint(population, size=G*batch_size))
            su = torch.as_tensor(ids//model.num_items, dtype=torch.long, device=device)
            si = torch.as_tensor(ids%model.num_items, dtype=torch.long, device=device)
            pred_direct = model(su,si).sigmoid()
            pseudo_direct = model.sample_predict(su,si,samples)
            factual = F.binary_cross_entropy(pred, labels, weight=w, reduction="sum")
            imp, variance = model.sample_bce(pred,pseudo)
            direct, direct_variance = model.sample_bce(pred_direct,pseudo_direct)
            keep, keep_direct = variance < model.un_thres, direct_variance < model.un_thres
            loss = (factual-(imp*keep).sum()+(direct*keep_direct).sum())/len(ids)
            if not torch.isfinite(loss): raise FloatingPointError("Non-finite released recommendation loss")
            opt_rec.zero_grad(); loss.backward(); opt_rec.step()
            epoch_loss += factual.detach().cpu().numpy()  # Preserve source float32 accumulation.
            with torch.no_grad():
                pred_fixed = model(users,items).sigmoid()
            imputation = model.imp_model(users,items).sigmoid()
            error = F.binary_cross_entropy(pred_fixed,labels,reduction="none")
            estimated = F.binary_cross_entropy(imputation,pred_fixed,reduction="none")
            imp_loss = ((error-estimated).square()*w**3*(1-1/w)**2).sum()
            if not torch.isfinite(imp_loss): raise FloatingPointError("Non-finite released imputation loss")
            opt_imp.zero_grad(); imp_loss.backward(); opt_imp.step()
            rec_total += float(loss.detach()); imp_total += float(imp_loss.detach())
            removed += int((~keep).sum())+int((~keep_direct).sum());count += len(keep)+len(keep_direct)
        stats = dict(epoch=epoch+1, weighted_factual_sum=float(epoch_loss),
            rec_loss=rec_total/batches,imp_loss=imp_total/batches,
            filtered_fraction=removed/count,observed_rows_used=batches*batch_size,
            observed_rows_dropped=len(x)-batches*batch_size)
        history.append(stats)
        if on_progress is not None:
            on_progress(epoch+1, dict(stats))
        if on_epoch is not None:
            if on_epoch(epoch+1,stats): break
            continue
        if (last_loss-epoch_loss)/(last_loss+1e-10) < tol:
            if early > stop: break
            early += 1
        last_loss = epoch_loss
    return history
