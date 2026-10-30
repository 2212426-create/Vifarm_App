# IViDR: triển khai lại theo tài liệu arXiv — 22/10/2026

[Trạng thái](../CURRENT_STATE.md) · [Giao thức](evaluation_protocol.md).

Nguồn đặc tả là **IViDR arXiv 2410.12451v1**, tương ứng bản chép
[IViDR.md](../paper_summaries/IViDR.md) trong dự án:
[toàn văn gốc](https://arxiv.org/html/2410.12451v1). Đây là triển khai tham chiếu
các công thức đã công bố; không chứng nhận khớp mã tác giả hoặc toàn bộ bản xuất bản cuối.

## Những phần đã triển khai lại

| Đặc tả | Thực thi |
| :-- | :-- |
| Eq. (3), (6): Z_j từ user liên quan item j | Chỉ lấy user có biased exposure với item j; feature embedding là Linear học được |
| Eq. (6): Z_j Z_j^dagger MLP0(T_j) | Cache basis trong feature thô; tính QR sau embedding ở mỗi forward, nên projector cập nhật theo embedding |
| Eq. (7)–(9): fitted, residual và hai trọng số học được | Giữ cả hai phần; hai gate có lớp tuyến tính phân tích theo cột của toàn Z_j; không dùng trung bình feature cố định |
| Eq. (10): X_re = X + T_re | Dùng coordinate adapter gắn với cùng treatment item, công khai bên dưới; bỏ Linear bridge độc lập và mean-history pooling |
| Eq. (40)–(44): posterior/prior Gaussian, ELBO | Prior mean và variance học từ W; cả hai nhánh giải mã observed binary exposure A theo Eq. (44) |
| Eq. (15): C=.9 C1+.9 C2 | Mean và variance ghép theo hai draw Gaussian độc lập |
| Eq. (23)–(25): MF và kỳ vọng dự đoán, BCE | Định nghĩa xác suất sigmoid(MF + latent score), lấy kỳ vọng xác suất trước BCE; phi=lambda=1 |

Mã mới: [ividr_reference.py](../../src/models/ividr/ividr_reference.py).
[Pipeline](../../src/models/ividr/train_ividr.py) gọi `implementation=reference_v2`.
Feedback có model identity `ividr_reference`, architecture `ividr_reference_bce_v2`;
stage1 là `paper_ivae_learned_instruments_v2`. Tên trên bảng: IViDR (trước 28/10/2026 hiển thị IViDR-BCE).

Feature embedding nhận gradient từ ELBO qua projector và gate. Basis cache nằm
trong feature **thô**, nên không đóng băng Z khi embedding thay đổi. QR thực hiện
cùng phép chiếu Moore–Penrose khi embedding giữ rank; mất column rank sẽ báo lỗi
thay vì trả về projector sai. Trường hợp Z rỗng có fitted bằng 0.

## Các lựa chọn tài liệu chưa định nghĩa đầy đủ

Tài liệu đặt treatment/feature embedding Coat=32, Yahoo=96, KuaiRand=128 chiều,
nhưng Eq. (10) không định nghĩa cách cộng treatment với input exposure có số chiều
bằng số item. Không thể khẳng định tái lập chính xác phần thiếu này chỉ từ công thức.

Bản này công khai **tied item-coordinate lift**:

```text
T0   = MLP0(T)                    # n_items x d
Tre  = alpha1 * fitted + alpha2 * residual
Xre  = A + (A @ Tre) @ T0.T / sqrt(d)
```

Kết quả có đúng shape của A, không tạo thêm ma trận Linear d→n_items độc lập.
Đây vẫn là phép hoàn thiện kích thước của dự án, không phải công thức có nguyên
văn trong paper. Không chọn adapter này bằng test hoặc thử nhiều adapter để lấy điểm tốt.

Eq. (9) cũng không mô tả padding hay kiến trúc MLP cho Z_j có số cột thay đổi.
Gate ở đây dùng lớp tuyến tính đầu được factorize theo cột user rồi MLP;
đó là một parameterization cụ thể của đầu vào toàn Z_j. Encoder/prior/decoder
được dùng chung giữa hai posterior, cũng là lựa chọn chia sẻ tham số của dự án.

## Kỳ vọng xác suất và đánh giá

Với score Gaussian s khi C Gaussian, dự đoán được định nghĩa là
`p = E_C[sigmoid(s(C))]`. Training dùng 10 mẫu Monte Carlo; inference dùng
Gauss–Hermite 32 điểm để tích phân Gaussian một chiều một cách tất định.
Model trả `logit(p)` cho BCEWithLogits ổn định. Đây là cách hiện thực hóa kỳ vọng
trong Eq. (25) khi chọn point-wise predictor là xác suất Bernoulli.

Không thay `E[sigmoid(s)]` bằng `sigmoid(E[s])`; không dùng factor shortcut tuyến
tính để chấm một predictor phi tuyến. Đã kiểm tra bằng ví dụ Monte Carlo tính tay,
tích phân số độc lập và nạp lại checkpoint. Legacy BCE-v1/iDCF giữ scorer cũ để
đọc checkpoint đúng phiên bản; không diễn giải lại trọng số cũ thành bản mới.

## Dữ liệu, lựa chọn checkpoint và phạm vi so sánh

Giữ MF/iDCF, CDR source protocol và cả ba dataset. Stage1 dùng exposure/proxy
biased train, chọn ELBO trên exposure-user validation sau full-beta warm-up.
Feedback quét 10 cặp LR/weight decay của paper trên ranking validation khi
budget >=20 epoch và không override LR/WD. Chỉ checkpoint thắng được chấm test.

Optimizer/ELBO schedule của stage1 còn là cấu hình địa phương. Yahoo vẫn giữ
15.400 user với missing survey category, khác cohort 5.400 user trong tài liệu;
KuaiRand vẫn dùng preprocessing/proxy địa phương. Recall trên bảng là bounded;
khi đối chiếu paper phải dùng đúng Recall/all positives trong JSON. Không gọi
smoke là benchmark chất lượng, hoặc một seed là mean/std nhiều lần chạy.

Chạy từ `services/recsys`:

```powershell
.\venv\Scripts\python.exe experiments\run.py benchmark --dataset coat --model ividr --device cpu --threads 2
.\venv\Scripts\python.exe experiments\run.py benchmark --dataset all --model all --device cpu --threads 2
```

## Kết quả đã chạy trên Coat

[Báo cáo đủ bốn mô hình](../../results/benchmark_coat_all_02b9e8eb46_20261022_073711_146173c9_v4.md)
· [Kiểm chứng](../../results/ividr_reference_verification_20261022.json)
· [CDR validation](../../results/ividr_reference_validation_20261022.json).

| Phiên bản | NDCG@5 | Recall/all positives | Recall bounded |
| :-- | --: | --: | --: |
| iDCF cùng lượt chạy, seed42 | .569884 | .551969 | .602295 |
| IViDR-BCE-v1, lịch sử seed42 | .529125 | .535279 | .590419 |
| IViDR reference v2, seed42 | .541201 | .558345 | .613273 |

Bản mới tăng cả hai metric so với BCE-v1. So với iDCF, Recall cao hơn nhưng
NDCG vẫn thấp hơn. Đây là một seed, không xác nhận thắng trung bình hoặc tái lập
mean/std của paper. Không chỉnh kiến trúc hay chọn lại cấu hình bằng các điểm test này.

Stage1 chọn epoch463, dừng563/2000; validation ELBO82.058253. Feedback chọn
LR .001 / WD 1e-6, epoch43/100 bằng validation NDCG .552078 trong 10 trial.
MF/iDCF/CDR giữ chính xác metric và mọi tensor trọng số của mốc trước.
132 test: 131 đạt, 1 CUDA skip. Smoke đủ bốn mô hình trên ba dataset.
Stage1 nạp lại xuất mean/std khớp từng phần tử; feedback nạp lại khớp metric.
Feature embedding có update norm .2144568 so với khởi tạo, xác nhận thực sự được học.

Source kiểm chứng:
`dd068e23091a263bd967f9cc776d3352082b46842d27f9cc51e02a3d54ce2556`.
Kết quả/mã của phiên bản cũ giữ nguyên provenance; không gán điểm cũ sang model identity mới.
