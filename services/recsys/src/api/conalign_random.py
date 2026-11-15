# -*- coding: utf-8 -*-
"""
Huấn luyện ConAlign phục vụ bằng log hiển thị ngẫu nhiên của chính ứng dụng.

Gọi lại nguyên bản port tác giả `src.models.conalign.train.train_conalign` với cấu hình
"coat" (không đổi siêu tham số): giai đoạn 1 học tháp biased trên log thường, giai đoạn 2
học tháp unbiased trên log ngẫu nhiên. Ứng dụng không có tập test riêng nên test_* dùng lại
validation; metric test trong kết quả của train_conalign vì thế không phải điểm đánh giá.
Project: ViFarm (services/recsys)
"""

import tempfile

import numpy as np
import torch

from src.models.conalign.model import DualTowerMF
from src.models.conalign.train import setup_seed, train_conalign

DATASET_CONFIG = "coat"
RANDOM_VAL_DIVISOR = 6   # tỷ lệ train:val 50:10 của log ngẫu nhiên trong source
BIASED_VAL_DIVISOR = 8   # tỷ lệ train:val 70:10 của log thường trong source


def _stratified_split(y, divisor, rng):
    """Chia theo nhãn: mỗi nhãn lấy max(1, round(n/divisor)) dòng làm validation.

    Trả (chỉ số train, chỉ số val) hoặc None khi một nhãn có ít hơn 2 dòng, vì khi đó
    không thể để cả train lẫn validation đều có đủ hai nhãn.
    """
    labels = y.detach().cpu().numpy()
    train_idx, val_idx = [], []
    for label in (0.0, 1.0):
        rows = np.flatnonzero(labels == label)
        if len(rows) < 2:
            return None
        rows = rows[rng.permutation(len(rows))]
        n_val = max(1, round(len(rows) / divisor))
        val_idx.append(rows[:n_val])
        train_idx.append(rows[n_val:])
    return np.sort(np.concatenate(train_idx)), np.sort(np.concatenate(val_idx))


def _sparse(u, i, y, idx, shape):
    idx = torch.as_tensor(idx, dtype=torch.long)
    indices = torch.stack([u.detach().cpu()[idx].long(), i.detach().cpu()[idx].long()])
    return torch.sparse_coo_tensor(indices, y.detach().cpu()[idx].float(), shape, check_invariants=True)


def fit_conalign_with_random_log(biased, random, n_users, n_items, seed):
    """Huấn luyện DualTowerMF bằng train_conalign của tác giả; None nếu không chia được dữ liệu.

    biased, random: bộ (u, i, y) dạng tensor chỉ số người dùng, chỉ số video và nhãn 0/1.
    """
    setup_seed(seed)  # như module train yêu cầu: đặt seed trước khi dựng dữ liệu
    rng = np.random.default_rng(seed)
    random_split = _stratified_split(random[2], RANDOM_VAL_DIVISOR, rng)
    biased_split = _stratified_split(biased[2], BIASED_VAL_DIVISOR, rng)
    if random_split is None or biased_split is None:
        return None
    shape = (n_users, n_items)
    data = {
        "train_biased": _sparse(*biased, biased_split[0], shape),
        "val_biased": _sparse(*biased, biased_split[1], shape),
        "train_unbiased": _sparse(*random, random_split[0], shape),
        "val_unbiased": _sparse(*random, random_split[1], shape),
    }
    # Không có tập test riêng: test_* trỏ về validation để train_conalign chạy đúng giao diện.
    data["test_biased"] = data["val_biased"]
    data["test_unbiased"] = data["val_unbiased"]
    counts = {name: int(data[name]._nnz()) for name in
              ("train_biased", "val_biased", "train_unbiased", "val_unbiased")}
    data["info"] = dict(protocol="serving_random_log_v1", n_users=n_users, n_items=n_items,
                        seed=seed, counts=counts)
    with tempfile.TemporaryDirectory() as checkpoint_dir:
        result = train_conalign(data, DATASET_CONFIG, seed=seed, device="cpu",
                                checkpoint_dir=checkpoint_dir, verbose=False)
        checkpoint = torch.load(result["checkpoint_path"], map_location="cpu", weights_only=True)
    config = result["identity"]["config"]
    model = DualTowerMF(n_users, n_items, dim=config["dim"], alignment_weight=config["alignment_weight"])
    model.load_state_dict(checkpoint["model_state_dict"])
    model.eval()
    info = dict(implementation="conalign_author_port", config=DATASET_CONFIG, protocol="serving_random_log_v1",
                counts=counts,
                stage1_best_epoch=result["stage1"]["best_epoch"],
                stage2_best_epoch=result["stage2"]["best_epoch"],
                stage2_best_val_auc=round(float(result["stage2"]["best_val_auc"]), 6))
    return model, info
