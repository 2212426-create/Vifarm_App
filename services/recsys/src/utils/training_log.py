"""Console-only training messages; no evaluation, RNG or checkpoint decisions."""


def header(model, dataset, config, protocol, stage=None):
    label = model if stage is None else f"{model} | {stage}"
    print("\n" + "=" * 72, flush=True)
    print(f" HUẤN LUYỆN {label}: {dataset.upper()}", flush=True)
    print(" " + " | ".join(f"{key}: {value}" for key, value in config.items()), flush=True)
    print(f" Giao thức: {protocol}", flush=True)
    print("=" * 72, flush=True)


def progress(model, dataset, epoch, epochs, values, stage=None):
    label = model if stage is None else f"{model}/{stage}"
    prefix = f"[{label}][{dataset.upper()}] Epoch {epoch:03d}/{epochs:03d}"
    parts = []
    for key, value in values.items():
        if isinstance(value, (int, float)):
            value = f"{value:.4f}"
        parts.append(f"{key}: {value}")
    print(prefix + " | " + " | ".join(parts), flush=True)


def finish(model, dataset, epochs_run, epochs, *, selected_epoch=None, best_label=None, best=None, stage=None):
    label = model if stage is None else f"{model}/{stage}"
    reason = "Dừng sớm" if epochs_run < epochs else "Đạt ngân sách epoch"
    line = f"[{label}][{dataset.upper()}] {reason} tại epoch {epochs_run}"
    if selected_epoch is not None:
        line += f" | Chọn epoch: {selected_epoch}"
    if best_label is not None and best is not None:
        line += f" | {best_label}: {best:.4f}"
    print(line, flush=True)


def result(model, dataset, metrics, scope, checkpoint=None):
    keys = ("NDCG@5", "Recall@5", "Recall@5_bounded", "HitRate@5", "AUC", "AUC_global", "users")
    parts = []
    for key in keys:
        if key in metrics:
            value = metrics[key]
            if value is None:
                value = "N/A"
            elif key != "users":
                value = f"{value:.6f}"
            parts.append(f"{key}: {value}")
    print(f"[{model}][{dataset.upper()}] {scope} | " + " | ".join(parts), flush=True)
    if checkpoint is not None:
        print(f"[{model}][{dataset.upper()}] Checkpoint: {checkpoint}", flush=True)
