"""Parity: author MF_BV_Multi_bin_JL_G_DR (CPU-patched) vs src.models.clev.model.CLEVDR, same seed, real Coat."""
import sys, json
import numpy as np, torch
AUTHOR, ROOT = sys.argv[1], sys.argv[2]
torch.Tensor.cuda = lambda self, *a, **k: self
torch.nn.Module.cuda = lambda self, *a, **k: self
sys.path.insert(0, ROOT); sys.path.insert(0, AUTHOR)
import new_model as author
from src.models.clev.model import CLEVDR
from src.models.clev.data import load
from src.models.clev.train import CLEV_CONFIG, setup_seed
cfg = CLEV_CONFIG["coat"]
x_tr, y_tr, x_te, y_te, nu, ni = load("coat")
out = {}
for name, cls in (("author", author.MF_BV_Multi_bin_JL_G_DR), ("port", CLEVDR)):
    setup_seed(0)
    m = cls(nu, ni, batch_size=cfg["batch_size"], monte_sample_num=cfg["monte_sample_num"], embedding_k=cfg["emb_dim"],
            batch_size_prop=cfg["batch_size_prop"])
    (m._compute_IPS if name == "author" else m.compute_ips)(x_tr, num_epoch=2, lr=cfg["lr_prop"], lamb=cfg["weight_decay_prop"], tol=1e-5)
    m.fit(x_tr, y_tr, num_epoch=3, lr=cfg["lr"], lamb=cfg["weight_decay"], tol=1e-5, alpha=.6, G=cfg["G"])
    out[name] = (m.predict(x_te), float(m.rho().detach()))
diff = float(np.abs(out["author"][0] - out["port"][0]).max())
print(json.dumps({"max_abs_prediction_diff": diff, "rho_author": out["author"][1], "rho_port": out["port"][1],
                  "test_rows": int(len(x_te)), "epochs": {"ips": 2, "fit": 3}, "alpha": .6, "seed": 0}))
