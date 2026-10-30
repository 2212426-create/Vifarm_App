# -*- coding: utf-8 -*-
"""
Huấn luyện LCDR hai bước theo Algorithm 1 (arXiv 2505.16708v1), dựng trên pipeline iDCF:
  1. iVAE(A, W) và LCVAE(A) chạy song song, ràng buộc lambda * ||Z_lc - Z||_2 (lcvae.py).
  2. Mô hình gợi ý f(u, i, Z_lc) = MF(u, i) + <e_i, Z_lc,u>: Eq. (18) cộng phần đóng góp của
     Z_lc với MF; dùng đúng dạng MFMF của iDCF (mô hình cũ tương đương), MSE trên nhãn,
     chọn epoch theo validation NDCG@5, chấm test một lần qua evaluate_checkpoint.
Dữ liệu, proxy W và protocol H30 giống iDCF ("Following iDCF" trong paper). lambda theo
paper: Coat .9, Yahoo!R3 .1, KuaiRand .9. Kích thước mạng/optimizer paper không công bố:
giữ cấu hình iDCF của project (lr 5e-4 và wd 1e-6 nằm trong lưới paper).
Project: ViFarm (services/recsys)
"""

import copy

from src.models.idcf.train_idcf import DATASET_INPUTS, IDCF_CONFIG, train_idcf
from src.models.lcdr.lcvae import train_lcdr_representations
from src.utils import training_log
from src.utils.helpers import get_device

PAPER_LAMBDA = {"coat": 0.9, "yahoo": 0.1, "kuairand": 0.9}
LCDR_CONFIG = {dataset: {"representation": dict(copy.deepcopy(config["ivae"]), constraint_weight=PAPER_LAMBDA[dataset]),
                         "train": copy.deepcopy(config["train"])}
               for dataset, config in IDCF_CONFIG.items()}


def fit_lcdr_pipeline(data, dataset_name, seed=42, checkpoint_dir=None, checkpoint_tag="manual",
                      evaluate_test=True, epochs=100, representation_epochs=2000, train_overrides=None,
                      representation_overrides=None, device=None):
    config = copy.deepcopy(LCDR_CONFIG[dataset_name])
    train_overrides, representation_overrides = train_overrides or {}, representation_overrides or {}
    if set(train_overrides) - set(config["train"]):
        raise ValueError("Unknown LCDR stage 2 override")
    allowed = {"constraint_weight", "latent_dim", "hidden_dim", "n_layers", "lr", "weight_decay", "l2_penalty",
               "batch_size", "patience", "beta_max", "train_ratio", "split_seed", "validation_samples",
               "validation_seed", "verbose"}
    if set(representation_overrides) - allowed:
        raise ValueError("Unknown LCDR stage 1 override")
    config["train"].update(train_overrides)
    config["representation"].update(representation_overrides)
    device = get_device(device)
    inputs = DATASET_INPUTS[dataset_name](data)
    stage1 = config["representation"]
    training_log.header("LCDR", dataset_name, {"Thiết bị": str(device), "Lambda": stage1["constraint_weight"],
        "Latent dim": stage1["latent_dim"], "Hidden dim": stage1["hidden_dim"], "Layers": stage1["n_layers"],
        "LR": stage1.get("lr", 5e-4), "Batch": stage1["batch_size"], "Seed": seed},
        "Exposure-user validation | chọn loss iVAE + LCVAE sau full-beta warm-up",
        stage="Giai đoạn 1/2: iVAE + LCVAE")

    def progress(epoch, stats):
        training_log.progress("LCDR", dataset_name, epoch, representation_epochs, {
            "Train loss": stats["train_loss"], "Val loss": stats["val_loss"],
            "Val ||Zlc-Z||": stats["val_constraint"], "Beta": stats["beta"], "Phase": stats["phase"]},
            stage="LCVAE")

    mean, std, info = train_lcdr_representations(inputs["exposure"], inputs["proxy"], seed=seed,
                                                 epochs=representation_epochs, device=device,
                                                 on_progress=progress, **stage1)
    training_log.finish("LCDR", dataset_name, info["epochs_run"], representation_epochs,
                        selected_epoch=info["best_epoch"], best_label="Best Val loss",
                        best=info["best_val_loss"], stage="LCVAE")
    extra = {"variant": "lcdr", "representation_training": info,
             "method_reference": "LCDR_arXiv2505.16708v1_Alg1_Eq6_Eq18_as_iDCF_MFMF",
             "paper_lambda": PAPER_LAMBDA[dataset_name]}
    if dataset_name == "yahoo":
        extra["proxy_features"] = data["user_feature_info"]
    result = train_idcf(data, mean, std, dataset_name, seed=seed, epochs=epochs, evaluate_test=evaluate_test,
                        checkpoint_dir=checkpoint_dir, checkpoint_tag=checkpoint_tag, extra_config=extra,
                        device=device, **config["train"])
    return {**result, "representation_info": info}
