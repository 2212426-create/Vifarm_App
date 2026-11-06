"""Diagnostic: MRDR-CAL with Hu et al.'s training conventions (sum-reduced losses as train_rec_with_ips.py,
fixed epochs, last epoch reported) instead of Guo's (mean loss, validation-CE early stopping)."""
import sys, json
import numpy as np, torch, torch.nn.functional as F
sys.path.insert(0, sys.argv[1])
import src.models.mrdr_cal.train as T
torch.set_num_threads(3)
T.mrdr_imputation_loss = lambda l, y, p: torch.sum(F.binary_cross_entropy_with_logits(l, y, reduction="none") / p * (1 - p) / p)
def dr_sum(pred, imp, y, o, p):
    e_il = F.binary_cross_entropy_with_logits(pred, torch.sigmoid(imp).detach(), reduction="none")
    return torch.sum((F.binary_cross_entropy_with_logits(pred, y, reduction="none") - e_il) * o / p + e_il)
T.dr_loss = dr_sum
orig = T.train_mrdr
def last_epoch(data, propensity, config, rng, max_epochs=None):
    config = dict(config, patience=10**9)
    model, info = orig(data, propensity, config, rng, max_epochs)
    return model, info
T.train_mrdr = last_epoch
class _Last:
    count = 0
    def __getattr__(self, name):
        return getattr(F, name)
    def binary_cross_entropy(self, *a, **k):
        _Last.count += 1
        return torch.tensor(1e9 - _Last.count)  # strictly decreasing -> the last epoch is kept
T.F = _Last()
out = []
for seed in range(int(sys.argv[2])):
    r = T.run("coat", seed=seed, overrides=dict(max_epochs=200, patience=10**9))
    out.append(r); print(json.dumps({"seed": seed, "best_epoch_by_val": r["training"]["best_epoch"], **{k: round(r[k], 4) for k in ("AUC", "DCG@2", "Recall@2")}}))
print("mean", {k: round(float(np.mean([r[k] for r in out])), 4) for k in ("AUC", "DCG@2", "DCG@4", "Recall@2", "Recall@6")})
