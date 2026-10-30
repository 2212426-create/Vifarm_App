# -*- coding: utf-8 -*-
"""
Workflow Tìm Kiếm & Tối Ưu Hóa Siêu Tham Số (Hyperparameter Tuning) Cho Coat Dataset.

Tuân thủ nghiêm ngặt nguyên tắc thực nghiệm khoa học:
1. Toàn bộ các trial trong Grid Search chỉ được lựa chọn dựa trên điểm số Validation NDCG@5 (30% Random split).
2. Checkpoint tối ưu nhất của mỗi mô hình mới được đánh giá DUY NHẤT 1 LẦN trên tập Held-Out Test (70% Random split).
3. CDR huấn luyện độc lập theo loss và backbone riêng, không nạp MF-MSE.

ViFarm Project (services/recsys)
"""

import argparse
import hashlib
import json
import sys
import time
from uuid import uuid4
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from src.models.mf.train_mf import train_baseline_mf
from src.models.cdr.train_released_cdr import train_released_cdr
from src.utils.helpers import RESULTS_DIR
from src.utils.artifacts import evaluate_checkpoint, data_signature, source_signature, digest
from src.data_pipeline.coat_dataset import load_coat_processed
from src.training.config import mf_config, released_cdr_config, released_tuning_grids

from src.evaluation.protocol import protocol_metadata
from src.evaluation.table_formatter import format_grid_table

def cdr_config(dataset, **overrides):
    return dict(released_cdr_config(dataset, **overrides), patience=overrides.get("patience") or 5)


class TeeLogger:
    """Ghi đồng thời log ra file và hiển thị thời gian thực lên màn hình console."""
    def __init__(self, file_path: Path):
        self.file = open(file_path, "a", encoding="utf-8")
        self.terminal = sys.stdout

    def write(self, message):
        self.file.write(message)
        self.file.flush()
        self.terminal.write(message)
        self.terminal.flush()

    def flush(self):
        self.file.flush()
        self.terminal.flush()

    def close(self):
        self.file.close()


# =============================================================================
# LƯỚI TÌM KIẾM SIÊU THAM SỐ (SEARCH GRIDS) ĐÃ TINH CHỈNH CHO COAT DATASET
# =============================================================================
GRIDS = released_tuning_grids("coat")


def train_model(name: str, config: dict, epochs: int, evaluate_test: bool, tag: str,
                data_dict: dict = None, patience: int = None):
    common = {
        "dataset_name": "coat",
        "epochs": epochs,
        "patience": patience if patience is not None else (mf_config if name == "mf" else cdr_config)("coat")["patience"],
        "evaluate_test": evaluate_test,
        "checkpoint_tag": tag,
    }
    if data_dict is not None:
        common["data_dict"] = data_dict
    if name == "mf":
        effective = mf_config(common["dataset_name"], **config)
        effective.pop("epochs")
        effective.pop("patience")
        return train_baseline_mf(**common, **effective)
    if name == "cdr":
        cfg = cdr_config("coat", **config)
        cfg.pop("epochs")
        cfg.pop("patience")
        return train_released_cdr(**common, **cfg, selection="source_train_loss_last", calibration_fraction=.05, seed=2020)
    raise ValueError(f"Mô hình không được hỗ trợ: {name}")


def write_report(payload: dict, json_path: Path):
    """Ghi file kết quả định dạng JSON và Markdown kèm bảng đối sánh khoa học."""
    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    
    lines = [
        "# Coat Dataset: Báo Cáo Tinh Chỉnh Siêu Tham Số (Validation Tuning)",
        "",
        f"- **Số Epoch Tối Đa**: {payload['epochs']} epochs (kèm Early Stopping)",
        f"- **Giao thức thực nghiệm**: Chọn cấu hình tốt nhất hoàn toàn bằng tập Validation (30% Random log).",
        f"- **Đánh giá khách quan**: Chỉ chấm điểm Held-Out Test DUY NHẤT 1 LẦN cho mô hình được chọn.",
        "",
        "CDR tuning uses the released estimator, source train-loss stopping and 5% validation calibration. It is not the default source-protocol benchmark; Coat labels: CDR >=3, MF >=4. Do not compare these rows as identical protocols.",
        "",
        "| Mô hình | Cấu hình tối ưu | Val NDCG@5 | Test NDCG@5 | Test Recall@5 | Test Precision@5 | Test HitRate@5 | Test AUC |",
        "| :-- | :-- | --: | --: | --: | --: | --: | --: |"
    ]
    for name, selected in payload["selected"].items():
        test = selected["test"]
        cfg_str = json.dumps(selected['config'], sort_keys=True)
        auc_str = f"{test['AUC']:.4f}" if test.get("AUC") is not None else "N/A"
        prec_str = f"{test.get('Precision@5', 0.0):.4f}"
        hr_str = f"{test.get('HitRate@5', 0.0):.4f}"
        lines.append(
            f"| {name.upper()} | `{cfg_str}` | {selected['validation_ndcg']:.4f} | "
            f"{test['NDCG@5']:.4f} | {test['Recall@5']:.4f} | {prec_str} | {hr_str} | {auc_str} |"
        )
    
    for name, selected in payload["selected"].items():
        if selected.get("best_epoch") == 0 and name == "cdr":
            lines.extend(["", "CDR selected epoch 0: retained MF warm start; no CDR update improved validation."])

    lines.extend([
        "",
        "### Chi Tiết Toàn Bộ Các Trials Trong Grid Search",
        "",
        "| Mô hình | Cấu hình thử nghiệm | Best Epoch | Val NDCG@5 | Thời gian (s) |",
        "| :-- | :-- | --: | --: | --: |"
    ])
    for t in payload.get("trials", []):
        cfg_str = json.dumps(t['config'], sort_keys=True)
        lines.append(f"| {t['model'].upper()} | `{cfg_str}` | {t['best_epoch']} | {t['best_val_ndcg']:.4f} | {t['elapsed_seconds']:.1f}s |")

    lines.extend(["", "*(Báo cáo tự động tạo bởi TopTop Collaborative Filtering Pipeline)*", ""])
    json_path.with_suffix(".md").write_text("\n".join(lines), encoding="utf-8")


def print_summary_table(selected_results: dict):
    """In bảng tổng kết kết quả đẹp mắt ra Console bằng format_grid_table."""
    headers = [
        "Mô Hình",
        "Cấu Hình Tối Ưu",
        "Val NDCG@5",
        "Test NDCG@5",
        "Test Recall@5",
        "Test AUC"
    ]
    rows = []
    for model_name, sel in selected_results.items():
        t = sel["test"]
        cfg = json.dumps(sel["config"])
        if len(cfg) > 42:
            cfg = cfg[:39] + "..."
        auc_str = f"{t['AUC']:.4f}" if t.get("AUC") is not None else "N/A"
        rows.append([
            model_name.upper(),
            cfg,
            f"{sel['validation_ndcg']:.4f}",
            f"{t['NDCG@5']:.4f}",
            f"{t['Recall@5']:.4f}",
            auc_str
        ])

    table_str = format_grid_table(
        headers=headers,
        rows=rows,
        col_aligns=["left", "left", "center", "center", "center", "center"],
        title="KẾT QUẢ CUỐI CÙNG SAU KHI TUNING TRÊN COAT DATASET",
        row_divider=True
    )
    print("\n" + table_str + "\n")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", choices=("all", "mf", "cdr"), default="all",
                        help="Chọn mô hình cần tuning (mặc định: all)")
    parser.add_argument("--epochs", type=int, default=None,
                        help="Override epoch budget; default follows each model's benchmark config")
    parser.add_argument("--patience", type=int, default=None,
                        help="Override early stopping patience; default follows benchmark config")
    parser.add_argument("--quick", action="store_true",
                        help="Chế độ chạy nhanh (lấy mẫu nhỏ grid để kiểm tra pipeline)")
    args = parser.parse_args(argv)

    if args.epochs is not None and args.epochs < 1:
        parser.error("--epochs phải lớn hơn 0")

    if args.patience is not None and args.patience < 1:
        parser.error("--patience must be positive")

    names = list(GRIDS) if args.model == "all" else [args.model]
    budgets = {name: (mf_config if name == "mf" else cdr_config)("coat",
                epochs=args.epochs, patience=args.patience) for name in names}
    
    effective_grids = {}
    for name in names:
        if args.quick:
            effective_grids[name] = GRIDS[name][:1]
        else:
            effective_grids[name] = GRIDS[name]

    print("=" * 85)
    print(" BẮT ĐẦU QUY TRÌNH TINH CHỈNH SIÊU THAM SỐ (TUNING) TRÊN COAT DATASET")
    print(f" Mô hình: {names} | Epochs: { {n: c['epochs'] for n, c in budgets.items()} } | Patience: { {n: c['patience'] for n, c in budgets.items()} }")
    print("=" * 85)
    
    print(" Đang nạp dữ liệu Coat...")
    data = load_coat_processed()
    cdr_data = load_coat_processed(pos_threshold=3) if 'cdr' in names else None
    identity = {
        "models": names,
        "epochs": {name: cfg["epochs"] for name, cfg in budgets.items()},
        "patience": {name: cfg["patience"] for name, cfg in budgets.items()},
        "seed": 42,
        "version": 4,
        "grids": effective_grids,
        "data": data_signature(data),
        "cdr_data": data_signature(cdr_data) if cdr_data is not None else None,
        "code_sha256": source_signature()
    }
    run_digest = digest(identity) + "_" + uuid4().hex[:8]
    json_path = Path(RESULTS_DIR) / f"tuning_coat_{args.model}_e{args.epochs}_{run_digest}_v4.json"
    log_path = json_path.with_suffix(".log")
    
    payload = {
        "identity": identity,
        "protocol": "paper_idcf_30_70_user_seed1234",
        "evaluation_protocol": protocol_metadata(data),
        "selection": "validation_ndcg_only",
        "cdr_protocol": "released estimator; train-loss last; seed2020; 5% validation calibration; tuning only, not source-protocol benchmark",
        "epochs": {name: cfg["epochs"] for name, cfg in budgets.items()},
        "patience": {name: cfg["patience"] for name, cfg in budgets.items()},
        "grids": effective_grids,
        "trials": [],
        "selected": {}
    }
    write_report(payload, json_path)

    original_stdout = sys.stdout
    tee = TeeLogger(log_path)
    sys.stdout = tee

    try:
        for name in names:
            candidates = []
            trial_epochs = budgets[name]["epochs"]
            trial_patience = budgets[name]["patience"]
            grid_list = effective_grids[name]
            total_trials = len(grid_list)
            print(f"\n" + "#" * 85)
            print(f" >>> BẮT ĐẦU TINH CHỈNH MÔ HÌNH: {name.upper()} (Tổng cộng: {total_trials} trials)")
            print("#" * 85)

            for idx, config in enumerate(grid_list, 1):
                config_digest = hashlib.sha256(json.dumps(config, sort_keys=True).encode()).hexdigest()[:10]
                tag = f"tune_coat_e{trial_epochs}_{config_digest}"
                
                print(f"\n--- [{name.upper()} Trial {idx}/{total_trials}] Cấu hình: {config} ---")
                started = time.perf_counter()
                
                effective_config = dict(config)
                result = train_model(name, effective_config, trial_epochs, False, tag,
                                     data_dict=cdr_data if name=='cdr' else data, patience=trial_patience)
                
                elapsed = time.perf_counter() - started
                trial = {
                    "epochs": trial_epochs, "patience": trial_patience,
                    "model": name,
                    "config": config,
                    "best_val_ndcg": result["best_val_ndcg"],
                    "best_epoch": result["best_epoch"],
                    "checkpoint_path": result["checkpoint_path"],
                    "metadata": result["metadata"],
                    "cdr_training": result.get("cdr_training"),
                    "training_history": result.get("training_history"),
                    "elapsed_seconds": round(elapsed, 2)
                }
                payload["trials"].append(trial)
                candidates.append(trial)
                write_report(payload, json_path)
                
                print(f" [KẾT QUẢ TRIAL {idx}] Best Val NDCG@5 = {trial['best_val_ndcg']:.4f} (tại epoch {trial['best_epoch']}) | Thời gian: {elapsed:.1f}s")

            best = max(candidates, key=lambda trial: trial["best_val_ndcg"])
            best_config = best["config"]
            
            print(f"\n>>> [LỰA CHỌN TỐI ƯU CHO {name.upper()}] Cấu hình: {best_config}")
            print(f"    Điểm Validation NDCG@5 cao nhất: {best['best_val_ndcg']:.4f} (epoch {best['best_epoch']})")
            print(f"    -> Đang tiến hành đánh giá DUY NHẤT 1 LẦN trên tập Held-Out Test...")
            
            test_metrics = evaluate_checkpoint(best["checkpoint_path"], cdr_data if name=='cdr' else data)
            payload["selected"][name] = {
                "config": best_config,
                "validation_ndcg": best["best_val_ndcg"],
                "best_epoch": best["best_epoch"],
                "test": test_metrics
            }
            write_report(payload, json_path)
            
            auc_str = f"{test_metrics['AUC']:.4f}" if test_metrics.get("AUC") is not None else "N/A"
            print(f"    -> KẾT QUẢ TEST: NDCG@5 = {test_metrics['NDCG@5']:.4f} | Recall@5 = {test_metrics['Recall@5']:.4f} | AUC = {auc_str}")

        print_summary_table(payload["selected"])
        print(f"[HOÀN THÀNH] Báo cáo chi tiết JSON : {json_path}")
        print(f"[HOÀN THÀNH] Báo cáo khoa học Markdown: {json_path.with_suffix('.md')}")
        print(f"[HOÀN THÀNH] Toàn bộ nhật ký Log    : {log_path}\n")

    finally:
        sys.stdout = original_stdout
        tee.close()


if __name__ == "__main__":
    main()
