"""Diagnostic: Hu et al. 'Neumf base' row (Table II) via train_rec_with_ips.py settings with propensity = 1."""
import sys, json
import numpy as np, torch, torch.nn.functional as F
sys.path.insert(0, sys.argv[1])
from src.models.mrdr_cal.data import load
from src.models.mrdr_cal.model import NeuMF
from src.models.mrdr_cal.metrics import evaluate
torch.set_num_threads(3)
data = load("coat"); tr, te = data["train"], data["test"]
out = []
for seed in range(3):
    torch.manual_seed(seed); rng = np.random.default_rng(seed)
    m = NeuMF(data["num_users"], data["num_items"], 64, 64, [64, 32, 16], dropout=.2)
    opt = torch.optim.Adam(m.parameters(), lr=1e-3, weight_decay=float(sys.argv[2]))
    u, i, y = (torch.as_tensor(tr[k]) for k in ("user", "item", "target"))
    u, i = u.long(), i.long()
    for epoch in range(200):
        m.train()
        for b in torch.as_tensor(rng.permutation(len(y))).split(1024):
            loss = torch.sum(F.binary_cross_entropy(m(u[b], i[b]), y[b], reduction="none"))
            opt.zero_grad(); loss.backward(); opt.step()
    m.eval()
    with torch.no_grad():
        s = m(torch.as_tensor(te["user"]).long(), torch.as_tensor(te["item"]).long()).numpy()
    r = evaluate(te["target"], s, data["test_users"], 16); out.append(r)
    print(json.dumps({"seed": seed, **{k: round(v, 4) for k, v in r.items() if k in ("AUC", "DCG@2", "Recall@2")}}))
print("mean AUC", np.mean([r["AUC"] for r in out]), "DCG@2", np.mean([r["DCG@2"] for r in out]))
