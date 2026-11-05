"""Train GMF, MLP or NeuMF on the H30 protocol with the author's NCF training loop.

From the author code (GMF.py, MLP.py, NeuMF.py @ 4aab159): log loss on positives plus num_neg uniformly sampled
items that are not positives of the user, new negatives every epoch, shuffled mini-batches, Adam, a fixed number of
epochs, evaluation of the untrained model, and the best evaluated epoch kept. Local choices are listed in
src/models/ncf/source.json: positives are the H30 labels and the selection score is validation NDCG@5.
"""
import os

import numpy as np
import torch
import torch.nn as nn

from src.evaluation.evaluator import evaluate_unbiased_model
from src.evaluation.protocol import TOP_K
from src.models.ncf.ncf_model import NCF, VARIANTS
from src.utils import training_log
from src.utils.artifacts import (checkpoint_path, evaluate_checkpoint, load_checkpoint, make_metadata,
                                 save_checkpoint, validate_training)
from src.utils.helpers import CHECKPOINT_DIR, get_device, set_seed

AUTHOR_DEFAULTS = dict(embedding_dim=8, layers=(64, 32, 16, 8), num_negatives=4, lr=1e-3, batch_size=256,
                       optimizer="adam", epochs=100, patience=None)
NCF_CONFIG = {dataset: dict(AUTHOR_DEFAULTS) for dataset in ("coat", "yahoo", "kuairand")}
DISPLAY_NAMES = {"gmf": "GMF", "mlp": "MLP", "neumf": "NeuMF"}
PRETRAIN_ALPHA = 0.5  # NeuMF.load_pretrain_model


def sample_training_instances(pos_u, pos_i, n_items, num_negatives, rng):
    """get_train_instances: each positive followed by num_negatives items the user has no positive for."""
    pos_u, pos_i = np.asarray(pos_u, dtype=np.int64), np.asarray(pos_i, dtype=np.int64)
    if np.any(np.bincount(pos_u) >= n_items):
        raise ValueError("A user is positive on every item; no negative can be sampled")
    known = np.unique(pos_u * n_items + pos_i)
    neg_u = np.repeat(pos_u, num_negatives)
    neg_i = rng.integers(0, n_items, len(neg_u))
    clash = np.isin(neg_u * n_items + neg_i, known)
    while clash.any():  # the author's `while train.has_key((u, j))` rejection loop
        neg_i[clash] = rng.integers(0, n_items, int(clash.sum()))
        clash = np.isin(neg_u * n_items + neg_i, known)
    block = 1 + num_negatives
    users = np.empty(len(pos_u) * block, dtype=np.int64)
    items = np.empty_like(users)
    labels = np.zeros(len(users), dtype=np.float32)
    users[::block], items[::block], labels[::block] = pos_u, pos_i, 1.0
    for offset in range(num_negatives):
        users[offset + 1::block] = neg_u[offset::num_negatives]
        items[offset + 1::block] = neg_i[offset::num_negatives]
    return users, items, labels


def load_pretrained_towers(paths, device):
    towers = []
    for path in paths:
        state = load_checkpoint(path, device)
        model = NCF(**state["metadata"]["model_kwargs"]).to(device)
        model.load_state_dict(state["model_state_dict"])
        towers.append(model)
    return towers


def train_ncf(data, dataset_name, variant="neumf", seed=42, checkpoint_dir=None, checkpoint_tag="manual",
              device=None, evaluate_test=True, pretrain=None, **overrides):
    if variant not in VARIANTS:
        raise ValueError(f"variant must be one of {VARIANTS}")
    if pretrain is not None and variant != "neumf":
        raise ValueError("Pre-training only applies to NeuMF")
    config = dict(NCF_CONFIG[dataset_name])
    unknown = set(overrides) - set(config)
    if unknown:
        raise ValueError(f"Unknown NCF options: {sorted(unknown)}")
    config.update({key: value for key, value in overrides.items() if value is not None})
    config["layers"] = tuple(config["layers"])
    validate_training(epochs=config["epochs"], embedding_dim=config["embedding_dim"], lr=config["lr"],
                      batch_size=config["batch_size"], patience=config["patience"])
    if config["optimizer"] not in ("adam", "sgd") or config["num_negatives"] < 1:
        raise ValueError("optimizer must be adam or sgd and num_negatives positive")
    set_seed(seed)
    rng = np.random.default_rng(seed)
    device = device or get_device()
    n_users, n_items = data["n_users"], data["n_items"]
    positive = np.asarray(data["train_y"]) > 0
    pos_u, pos_i = np.asarray(data["train_u"])[positive], np.asarray(data["train_i"])[positive]
    if len(pos_u) == 0:
        raise ValueError("Training data has no positive interaction")

    model_kwargs = dict(num_users=n_users, num_items=n_items, variant=variant,
                        embedding_dim=config["embedding_dim"], layers=list(config["layers"]))
    model = NCF(**model_kwargs).to(device)
    pretrain_info = None
    if pretrain is not None:
        gmf, mlp = load_pretrained_towers(pretrain, device)
        model.load_pretrained(gmf, mlp, alpha=PRETRAIN_ALPHA)
        pretrain_info = dict(gmf=str(pretrain[0]), mlp=str(pretrain[1]), alpha=PRETRAIN_ALPHA)
    optimizer_class = torch.optim.Adam if config["optimizer"] == "adam" else torch.optim.SGD
    optimizer = optimizer_class(model.parameters(), lr=config["lr"])
    loss_fn = nn.BCEWithLogitsLoss()

    name = DISPLAY_NAMES[variant] + ("-pre" if pretrain else "")
    metadata = make_metadata("ncf", dataset_name, data,
        dict(config, layers=list(config["layers"]), variant=variant, seed=seed, device=str(device),
             pretrain=pretrain_info, loss="bce_negative_sampling", positives="train_y > 0",
             selection="validation NDCG@5 over every evaluated epoch, untrained model included",
             method_reference="hexiangnan/neural_collaborative_filtering@4aab159 GMF.py MLP.py NeuMF.py",
             paper_reproduction=False),
        model_kwargs)
    save_path = checkpoint_path(checkpoint_dir or os.path.join(CHECKPOINT_DIR, "ncf"),
                                f"{dataset_name}_{variant}{'_pre' if pretrain else ''}_{checkpoint_tag}", metadata)
    training_log.header(name, dataset_name, {"Thiết bị": str(device), "Dim": config["embedding_dim"],
        "Layers": list(config["layers"]), "LR": config["lr"], "Batch": config["batch_size"],
        "Neg": config["num_negatives"], "Seed": seed}, "Held-out | chọn epoch bằng Val NDCG@5")

    def validate():
        return evaluate_unbiased_model(model, data["val_candidates"], data["val_ground_truth"], k=TOP_K,
                                       device=device,
                                       include_zero_positive_users=data.get("evaluation_include_zero_positive_users", True))

    best = validate()
    best_epoch, patience_count = 0, 0
    save_checkpoint(model, save_path, metadata, 0, best)
    epoch = 0
    for epoch in range(1, config["epochs"] + 1):
        model.train()
        users, items, labels = sample_training_instances(pos_u, pos_i, n_items, config["num_negatives"], rng)
        order = rng.permutation(len(labels))
        total = 0.0
        for start in range(0, len(order), config["batch_size"]):
            batch = order[start:start + config["batch_size"]]
            u = torch.as_tensor(users[batch], device=device)
            i = torch.as_tensor(items[batch], device=device)
            y = torch.as_tensor(labels[batch], device=device)
            optimizer.zero_grad()
            loss = loss_fn(model(u, i), y)
            if not torch.isfinite(loss):
                raise FloatingPointError("Non-finite training loss")
            loss.backward()
            optimizer.step()
            total += loss.item() * len(batch)
        validation = validate()
        training_log.progress(name, dataset_name, epoch, config["epochs"], {"Train Loss": total / len(order),
            "Val NDCG@5": validation["NDCG@5"], "Val Recall@5": validation["Recall@5"]})
        if validation["NDCG@5"] > best["NDCG@5"]:
            best, best_epoch, patience_count = validation, epoch, 0
            save_checkpoint(model, save_path, metadata, epoch, validation)
        else:
            patience_count += 1
            if config["patience"] is not None and patience_count >= config["patience"]:
                break
    training_log.finish(name, dataset_name, epoch, config["epochs"], selected_epoch=best_epoch,
                        best_label="Best Val NDCG@5", best=best["NDCG@5"])
    if not evaluate_test:
        return {"best_val_ndcg": best["NDCG@5"], "best_epoch": best_epoch, "checkpoint_path": save_path,
                "validation": best, "metadata": metadata, "epochs_run": epoch}
    metrics = evaluate_checkpoint(save_path, data, device)
    training_log.result(name, dataset_name, metrics, "TEST", save_path)
    return metrics
