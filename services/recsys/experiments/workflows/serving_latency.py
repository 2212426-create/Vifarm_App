# -*- coding: utf-8 -*-
"""
Đo độ trễ suy luận (CPU) của các kiến trúc trong benchmark khi chấm N video cho một user.

Độ trễ suy luận chỉ phụ thuộc kiến trúc, kích thước và số ứng viên, không phụ thuộc trọng số đã học,
nên mô hình được khởi tạo ngẫu nhiên với cấu hình KuaiRand của từng pipeline
(23.533 user × 6.712 video). Mỗi phép đo: warm-up rồi lặp, báo median/p95 theo mili giây.
Phần thứ hai đo /api/v1/recommend trong tiến trình (TestClient, không gồm mạng/tunnel)
trên dữ liệu export TopTop.

    python -m experiments.workflows.serving_latency            # từ services/recsys
Project: ViFarm (services/recsys)
"""

import argparse
import json
import os
import platform
import time
import uuid
from datetime import datetime
from pathlib import Path

import numpy as np
import torch

from src.models.cdr.released import ReleasedCDR
from src.models.clev.model import NCFBase
from src.models.clev.train import CLEV_CONFIG
from src.models.conalign.model import DualTowerMF
from src.models.conalign.train import CONALIGN_CONFIG
from src.models.idcf.idcf_model import IDCFModel
from src.models.idcf.train_idcf import IDCF_CONFIG
from src.models.mf.matrix_factorization import MatrixFactorization
from src.models.ncf.ncf_model import NCF
from src.models.ncf.train_ncf import NCF_CONFIG
from src.training.config import MF_CONFIG
from src.utils.artifacts import source_signature
from src.utils.helpers import RESULTS_DIR

N_USERS, N_ITEMS = 23_533, 6_712  # KuaiRand-Pure sau tiền xử lý của pipeline (results benchmark_all_*)


def time_call(fn, warmup, repeats):
    with torch.inference_mode():
        for _ in range(warmup):
            fn()
        samples = []
        for _ in range(repeats):
            started = time.perf_counter()
            fn()
            samples.append((time.perf_counter() - started) * 1000.0)
    samples = np.asarray(samples)
    return {"median_ms": round(float(np.median(samples)), 4), "p95_ms": round(float(np.percentile(samples, 95)), 4),
            "repeats": repeats}


def model_scorers(n_candidates, seed):
    """Mỗi hàm chấm n_candidates video cho user 0 đúng như đường suy luận của pipeline tương ứng."""
    torch.manual_seed(seed)
    rng = np.random.default_rng(seed)
    items = torch.as_tensor(rng.choice(N_ITEMS, n_candidates, replace=False), dtype=torch.long)
    users = torch.zeros_like(items)
    pairs = np.stack([users.numpy(), items.numpy()], 1)

    mf = MatrixFactorization(N_USERS, N_ITEMS, embedding_dim=MF_CONFIG["kuairand"]["embedding_dim"],
                             train_global_bias=False, init_scheme="author_uniform").eval()
    ncf_cfg = NCF_CONFIG["kuairand"]
    neumf = NCF(N_USERS, N_ITEMS, "neumf", embedding_dim=ncf_cfg["embedding_dim"], layers=ncf_cfg["layers"]).eval()
    cdr = ReleasedCDR(N_USERS, N_ITEMS, embedding_dim=4, un_thres=10., dropout_rate=.5).eval()
    idcf_cfg = IDCF_CONFIG["kuairand"]
    idcf = IDCFModel(N_USERS, N_ITEMS, latent_dim=idcf_cfg["ivae"]["latent_dim"],
                     embedding_dim=idcf_cfg["train"]["embedding_dim"]).eval()
    # CLEVDR.predict = sigmoid(prediction_model(x)); prediction_model là NCFBase, không lấy mẫu Monte Carlo.
    clev = NCFBase(N_USERS, N_ITEMS, CLEV_CONFIG["kuairand"]["emb_dim"]).eval()
    conalign = DualTowerMF(N_USERS, N_ITEMS, dim=CONALIGN_CONFIG["kuairand"]["dim"]).eval()

    def conalign_unbiased():
        p_u = conalign.user_latent_unbiased(users)
        q_i = conalign.item_latent_unbiased(items)
        return torch.sigmoid((p_u * q_i).sum(-1) + conalign.user_bias_unbiased(users).squeeze(-1)
                             + conalign.item_bias_unbiased(items).squeeze(-1))

    return {
        "MF": lambda: mf(users, items),
        "NeuMF": lambda: neumf(users, items),
        "DR-BIAS + CDR (released)": lambda: cdr(users, items),
        "iDCF / LCDR (posterior mean)": lambda: idcf(users, items, sample=False),
        "iDCF / LCDR (sample=True, 10 mẫu)": lambda: idcf(users, items, sample=True),
        "CLEV-DR (predict)": lambda: torch.sigmoid(clev(pairs)),
        "ConAlign (tháp unbiased)": conalign_unbiased,
    }


def measure_models(candidates, warmup, repeats, seed):
    out = {}
    for n in candidates:
        out[str(n)] = {name: time_call(fn, warmup, repeats) for name, fn in model_scorers(n, seed).items()}
    return out


def measure_api(export_dir, warmup, repeats):
    from fastapi.testclient import TestClient
    from src.api.app import create_app
    from src.api.auth import ApiAuth
    from src.api.firebase_bridge import load_snapshot
    from src.api.service import RecEngine

    engine = RecEngine(lambda: load_snapshot("export", export_dir=Path(export_dir)), retrain_every=0)
    client = TestClient(create_app(engine, auth=ApiAuth("off")))
    counts = engine.snapshot.interactions["user_id"].value_counts()
    user = str(counts.index[0]) if len(counts) else "guest"  # user nhiều tương tác nhất: đi nhánh cá nhân hóa
    out = {"training_stats": engine.training_stats, "user_interactions": int(counts.iloc[0]) if len(counts) else 0,
           "models": {}}
    for model in ("conalign", "mf", "cdr", "popularity"):
        body = {"user_id": user, "k": 10, "model": model}

        def call():
            res = client.post("/api/v1/recommend", json=body)
            assert res.status_code == 200, res.text
        out["models"][model] = time_call(call, warmup, repeats)
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument("--candidates", type=int, nargs="+", default=[1000, N_ITEMS])
    parser.add_argument("--warmup", type=int, default=20)
    parser.add_argument("--repeats", type=int, default=300)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--export-dir", default=str(Path(__file__).resolve().parents[4] / "data" / "firebase_export"))
    args = parser.parse_args()

    result = {
        "kind": "serving_latency",
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "source_sha256": source_signature(),
        "environment": {"python": platform.python_version(), "torch": torch.__version__,
                        "processor": platform.processor(), "machine": platform.machine(),
                        "torch_threads": torch.get_num_threads(), "device": "cpu", "os": platform.platform()},
        "setup": {"n_users": N_USERS, "n_items": N_ITEMS, "candidates": args.candidates, "warmup": args.warmup,
                  "repeats": args.repeats, "seed": args.seed,
                  "weights": "random init; latency depends on architecture only"},
        "model_inference": measure_models(args.candidates, args.warmup, args.repeats, args.seed),
    }
    if os.path.isdir(args.export_dir):
        result["api_recommend_in_process"] = measure_api(args.export_dir, args.warmup, args.repeats)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    path = Path(RESULTS_DIR) / f"serving_latency_{stamp}_{uuid.uuid4().hex[:8]}.json"
    path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({k: result[k] for k in ("environment", "model_inference")}, ensure_ascii=False, indent=1))
    print(json.dumps(result.get("api_recommend_in_process", {}).get("models"), indent=1))
    print("Saved", path)


if __name__ == "__main__":
    main()
