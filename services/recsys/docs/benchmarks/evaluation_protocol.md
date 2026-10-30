# Giao thức đánh giá theo mô hình

Mốc CDR source làm mặc định: 20/10/2026.
[Trạng thái](../CURRENT_STATE.md) · [Định nghĩa mô hình](paper_model_alignment.md).

LCDR dùng đúng protocol H30 và evaluator của iDCF bên dưới. ConAlign dùng protocol và metric
của source tác giả (chia ngẫu nhiên biased/unbiased, cổng thời gian KuaiRand riêng); xem
[LCDR và ConAlign](lcdr_conalign_20261027.md). Từ 30/10 bảng benchmark gộp có dòng ConAlign ghi
protocol `C-src` (NDCG = `NDCG` của source, AUC global, không có Recall bounded/HitRate; UAUC/UNDCG
in dưới bảng). Không so trực tiếp hay paired-test dòng C-src với H30/CDR; KuaiRand dùng cửa sổ paper.

## MF/iDCF/IViDR và chế độ CDR shared

Nguồn thực thi: src/evaluation/protocol.py và evaluator.py.
Giữ nhãn Coat/Yahoo >=4, KuaiRand is_click; biased train; random log chia
30% validation / 70% test theo user, seed 1234.
Ranking trên logged candidates, NDCG nhị phân, Recall chia toàn bộ positive.
Macro loại user không positive; AUC macro theo user có hai lớp, ties 0,5.
Chọn checkpoint/config bằng validation; test chỉ chấm sau lựa chọn.
Std theo seed dùng ddof=1; một seed trả null/N/A. CI theo user không thay std theo seed.

Coat giữ và công bố overlap train/random. Yahoo không có overlap; 1.620 user
validation / 3.780 test, mỗi user 10 random ratings. Không tự mask train items.
KuaiRand gộp positive theo any-click khi ranking và công bố preprocessing địa phương.
Nguồn quy ước:
[iDCF utils.py](https://github.com/BgmLover/iDCF/blob/main/utils.py).

## CDR mặc định: source protocol

Nguồn thực thi: [source_protocol.py](../../src/models/cdr/source_protocol.py).
`benchmark`, `cdr-source` và `coat-seeds` gọi cùng đường chạy.

| Thành phần | Coat / Yahoo |
| :-- | :-- |
| Nhãn | Rating >=3 |
| Seed mặc định | 2020; coat-seeds dùng danh sách seed chỉ định |
| Huấn luyện | Trần 1000 epoch, train-loss stopping với counter tích lũy; lấy trọng số cuối |
| Calibration | Chọn ngẫu nhiên 5% nhãn toàn random log chấm điểm |
| Propensity | Naive Bayes; giữ mẫu số max_user_id*max_item_id như script |
| Tập chấm | Toàn bộ random log, không split 30/70 |
| Zero-positive user | NDCG và Recall bằng 1 |
| Recall | Bounded: hits/min(k,n_positive) |
| AUC | Toàn cục, ties 0,5 |

Nguồn:
[script Coat](https://github.com/CrazyDumpling/CDR_CIKM2023/blob/6b4e6cca3df23b8d85b38fdc2e7eb5c812861ea9/CDR/mf_cdr_bias_coat.py),
[script Yahoo](https://github.com/CrazyDumpling/CDR_CIKM2023/blob/6b4e6cca3df23b8d85b38fdc2e7eb5c812861ea9/CDR/mf_cdr_bias_yahoo.py).

Paper prose và script khác nhau. Kết quả này tái lập điều kiện script, có dùng
nhãn tập chấm cho calibration; không gọi là held-out test độc lập.
Báo cáo giữ metric gốc Recall@5_bounded / AUC_global. Bảng hiển thị được gộp
với cột protocol và loại AUC; bổ sung Recall/all positives, Precision, HitRate
từ cùng ranking/cùng tập user, không đổi training hoặc các metric gốc.
User empty-positive của S-full vẫn nhận Recall=1; Precision/HitRate=0.
Các metric phụ này không phải metric nguồn công bố. Không ghép vào
paired tests, không lấy chênh điểm thô để xếp hạng với MF/iDCF dùng giao thức khác.

## KuaiRand, tuning và serving

KuaiRand dùng cùng estimator released nhưng local preprocessing/user split,
5% validation cho calibration; zero-positive bị loại, Recall chia toàn positive.
Array sampler thay DataLoader; khi catalog >20 triệu cặp, sampling có hoàn lại
được ghi metadata. Smoke quá ít lớp có thể mở calibration ra toàn validation,
có ghi adaptation. Không gọi đây là tái lập chính xác processed CSV của tác giả.

Tuning CDR dùng released estimator, >=3 trên Coat, seed 2020, dừng theo train loss,
calibration 5% validation, chọn cấu hình theo validation. Evaluator tuning là
held-out của dự án, loại user không positive; không chuyển số tuning sang source protocol.
MF và CDR tuning có nhãn khác nhau trên Coat, không kết luận hơn/kém từ hai dòng.

API không có randomized log nên dùng item-frequency propensity, sampler có
hoàn lại và ngân sách phục vụ; công bố training_stats.cdr.
`--cdr-implementation shared` dùng released trong giao thức chung;
`equation` giữ Eq. (7)/CV cũ cho đối chứng tường minh.

Kiểm tra bằng `experiments/run.py test`; smoke chỉ xác nhận vận hành.

## Bảng tổng hợp và cập nhật báo cáo — 21/10/2026

H30: MF/iDCF/IViDR hoặc CDR shared, split 30/70 theo user; Coat/Yahoo >=4; AUC macro-user.
S-full: CDR Coat/Yahoo source, >=3, toàn random log, calibration 5% nhãn chấm điểm;
AUC toàn cục. S-KR: CDR KuaiRand local split, calibration validation, AUC toàn cục.
Hai Recall luôn được tính và lưu JSON; bảng chỉ hiển thị Recall@5 bounded theo
lựa chọn người dùng ngày 21/10. Khác macro population/empty-user policy
vẫn phải đọc theo protocol của dòng đó. Không paired-test chéo protocol.

`experiments/run.py report --input FILE` bổ sung metric từ checkpoint CDR,
kiểm tra metric đã có không đổi, giữ metadata huấn luyện và ghi source hash riêng
cho lần tính lại. Tạo artifact mới; không ghi đè báo cáo cũ, không retrain.
Nếu checkpoint thiếu, lệnh báo lỗi; nếu AUC không có hai lớp thì giá trị thật
không xác định vẫn là null/N/A, không gán số thay thế.
