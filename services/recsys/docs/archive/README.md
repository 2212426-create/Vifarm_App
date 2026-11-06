# Script thực nghiệm và log mốc hiện hành

Thư mục này chỉ còn những gì đứng sau số liệu đang được trích dẫn. Tài liệu và log cũ hơn nằm trong Git,
xem [cách khôi phục](../MAINTENANCE.md#khôi-phục-tài-liệu-cũ).

| Thư mục | Tạo ra |
| :-- | :-- |
| `2026-10-27/ividr_optimization/` | Ablation Eq. (10) |
| `2026-10-27/ividr_rootcause/` | Thí nghiệm hoán đổi latent/feedback, BCE budget, marginal inference |
| `2026-10-28/ividr_bce/` | MF + BCE, BCE có trọng số mẫu âm, prior mean bằng 0 |
| `2026-10-28/ividr_ten_seed/` | Xác nhận 10 seed trên Coat |
| `2026-10-28/full_benchmark/` | Chấm lại IViDR Coat/Yahoo từ checkpoint |
| `2026-10-28/conalign_paper_window/` | Cửa sổ train KuaiRand của ConAlign |
| `2026-10-28/lcdr_constraint/` | Biến thể ràng buộc và lưới LR × WD của LCDR |
| `2026-10-30/console_models/` | `summarize.py` tạo file tổng hợp LCDR và cửa sổ KuaiRand của ConAlign |
| `2026-11-02/conalign_fix/` | Script validation của mốc 02/11 (log đã thay bằng mốc 04/11) |
| `2026-11-03/ncf/` | Script validation của mốc NeuMF (log đã thay bằng mốc 04/11 chiều) |
| `2026-11-04/mrdr_cal_clev/` | Parity CLEV-DR và metric MRDR-CAL với mã tác giả, chẩn đoán MRDR-CAL; test, smoke, validation của mốc hiện hành |

Chạy từ `services/recsys`; lệnh mẫu ở đầu mỗi script. Script ghi báo cáo mới vào `results/`.
