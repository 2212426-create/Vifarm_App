# CDR theo mã công bố và định nghĩa các mô hình

[Trạng thái và kiểm chứng](../CURRENT_STATE.md) · [Giao thức từng mô hình](evaluation_protocol.md).

## CDR mặc định

Tích hợp DR-BIAS+CDR từ
[commit 6b4e6cca của CDR_CIKM2023](https://github.com/CrazyDumpling/CDR_CIKM2023/tree/6b4e6cca3df23b8d85b38fdc2e7eb5c812861ea9).
[released.py](../../src/models/cdr/released.py) giữ dot MF không bias, khởi tạo rec
Xavier/imp mặc định, BCE, MC 10, variance filter, dropout cả embedding/output,
reverse BCE imputation, DR-BIAS sum loss, rec step trước imp.
Kiểm thử tham số khớp lớp gốc sau 3 epoch CPU.

| Dataset | Dim | LR | Weight decay | Batch | Variance threshold | Dropout | G |
| :-- | --: | --: | --: | --: | --: | --: | --: |
| Coat | 4 | .05 | .001 | 128 | 10 | .5 | 4 |
| Yahoo | 4 | .05 | .0001 | 2048 | 10 | .7 | 1 |
| KuaiRand | 4 | .05 | .0001 | 2048 | 10 | .5 | 1 |

Trần 1000 epoch; seed 2020; stop=5, tol=1e-5 với counter tích lũy.
Source protocol không chọn checkpoint theo validation.
Coat/Yahoo chạy cùng đường với cdr-source người dùng xác nhận:
[source_protocol.py](../../src/models/cdr/source_protocol.py).
Giữ nhãn >=3, calibration 5% nhãn random chấm điểm, mẫu số propensity của source,
toàn random log, zero-positive nhận 1 và Recall bounded.

KuaiRand dùng estimator released và cấu hình script, nhưng dữ liệu local khác
processed CSV tác giả; array sampling khác DataLoader, catalog lớn dùng sampler
có hoàn lại. Đây là adaptation có ghi metadata, chưa khớp quỹ đạo source KuaiRand.

## Từng luồng thực thi

- Benchmark và coat-seeds: CDR source protocol; MF/iDCF giao thức riêng.
  Bảng gộp có protocol/loại AUC từng dòng, không kiểm định chéo protocol.
- Tuning Coat/KuaiRand: released estimator, source train-loss stop/lấy trọng số
  cuối, 5% validation calibration; chọn cấu hình bằng validation. Coat dùng >=3
  cho CDR, >=4 cho MF. Đây là tuning adaptation, không phải source benchmark.
- API: ReleasedCDR 4 chiều, LR .05, wd .0001, dropout .5, variance 10.
  Không có random log nên dùng item-frequency propensity và sampler có hoàn lại;
  seed/ngân sách app giữ theo cấu hình phục vụ. Ghi training_stats.cdr.
- cdr-author là alias cdr-source, cdr-tune alias tuning released.
- Bản Eq. (7)/CV cũ chỉ chạy tường minh qua equation; không phải default.
  shared là released với calibration/checkpoint/evaluator held-out chung.

Không đổi hàm legacy hoặc diễn giải lại checkpoint cũ thành lớp released.
Tên profile paper của Eq. (7) không chứng nhận tái lập thí nghiệm.

## MF, iDCF và Yahoo

MF giữ MSE, raw score + user/item bias, intercept 0, Uniform(-.01,.01),
Adam và decay mọi tham số. iDCF giữ iVAE exposure/proxy rồi MF + item/latent,
feedback MSE; training 10 mẫu, inference mean. Không đổi MF sang BCE để giống CDR.

iVAE Coat/Yahoo 16/32/3; KuaiRand 32/64/2. Chọn sau full-beta warm-up; budget ngắn
được ghi rõ. Cấu hình optimizer/schedule còn là mặc định địa phương.
Yahoo survey thật có 7 câu cho 5.400 user, one-hot 39 chiều với category thiếu
cho 10.000 user còn lại. Không tạo proxy từ random/test labels. Đây là adaptation
địa phương, chưa phải tái lập chính xác pipeline Yahoo của tác giả; giả định nhân
quả cho nhóm thiếu survey chưa được xác minh. **Đính chính 21/10/2026:** paper
iDCF có thí nghiệm Yahoo. Notebook tác giả lọc train/random còn 5.400 user có
survey; dự án giữ 15.400 user nên dữ liệu train khác nhau. Xem
[nguồn và giới hạn xác minh](source_repository_review_20261021.md).

Nguồn:
[iDCF](https://github.com/BgmLover/iDCF),
[CDR paper](https://jiawei-chen.github.io/paper/CIKM23-CDR.pdf).
[Config thực thi](../../src/training/config.py).
