"""Parity of DCG/Recall@{2,4,6}: Hu et al. utils/metrics.py (author) vs src.models.mrdr_cal.metrics (port)."""
import importlib.util, sys, types, json
import numpy as np
AUTHOR, ROOT = sys.argv[1], sys.argv[2]
sys.modules.setdefault("sklearn", types.ModuleType("sklearn")); sk = types.ModuleType("sklearn.metrics")
sk.roc_auc_score = lambda *a, **k: 0.0; sys.modules["sklearn.metrics"] = sk
tm = types.ModuleType("torchmetrics"); tmf = types.ModuleType("torchmetrics.functional"); tmf.accuracy = None
sys.modules["torchmetrics"] = tm; sys.modules["torchmetrics.functional"] = tmf
spec = importlib.util.spec_from_file_location("author_metrics", AUTHOR); author = importlib.util.module_from_spec(spec)
spec.loader.exec_module(author)
sys.path.insert(0, ROOT)
from src.models.mrdr_cal import metrics as port
rng = np.random.default_rng(0); worst = 0.0
for trial in range(50):
    users, per = 40, 16
    label = (rng.random(users * per) < .2).astype(float); score = rng.random(users * per)
    for f in ("dcg_at_k", "recall_at_k"):
        a = getattr(author, f)(label, score, users, per, dataset="coat")
        b = getattr(port, f)(label, score, users, per)
        worst = max(worst, float(np.abs(a - b).max()))
    uid = np.sort(rng.integers(0, 30, 600)); label = (rng.random(600) < .2).astype(float); score = rng.random(600)
    for f in ("dcg_at_k", "recall_at_k"):
        a = getattr(author, f)(label, score, None, None, dataset="kuairand", user_ids=uid)
        b = getattr(port, f)(label, score, None, None, user_ids=uid)
        worst = max(worst, float(np.abs(a - b).max()))
print(json.dumps({"trials": 50, "max_abs_diff": worst}))
