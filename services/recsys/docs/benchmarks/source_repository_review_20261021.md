# Rà soát nguồn CDR, iDCF và IViDR — 21/10/2026

[Trạng thái hiện hành](../CURRENT_STATE.md) · [Định nghĩa mô hình](paper_model_alignment.md).
Đây là rà soát mã nguồn và đính chính tài liệu; chưa tích hợp hoặc chạy các repo mới.

## CDR: nguồn đã xác nhận

[CrazyDumpling/CDR_CIKM2023](https://github.com/CrazyDumpling/CDR_CIKM2023),
commit `6b4e6cca3df23b8d85b38fdc2e7eb5c812861ea9` đã được người dùng chọn.
[README cố định](https://github.com/CrazyDumpling/CDR_CIKM2023/blob/6b4e6cca3df23b8d85b38fdc2e7eb5c812861ea9/README.md)
ghi tên bài Conservative Doubly Robust Learning for Debiased Recommendation,
thư mục CDR, baseline và dữ liệu Coat/Yahoo; KuaiRand có bước tiền xử lý riêng.
Tình trạng tích hợp và khác biệt KuaiRand xem tài liệu định nghĩa mô hình.

## iDCF: mã chính thức do paper dẫn

[Paper KDD 2023 của tác giả](https://reijz.github.io/papers/2023-debiasing-recommendation-by-learning-ide.pdf),
mục 5.1, footnote 6 dẫn thẳng tới [BgmLover/iDCF](https://github.com/BgmLover/iDCF).
Commit kiểm tra: `462014126f6e2fc33053341c1da250f9cf6f1fa0`.
[README](https://github.com/BgmLover/iDCF/blob/462014126f6e2fc33053341c1da250f9cf6f1fa0/README.md)
có Coat, Yahoo! R3, KuaiRand và synthetic; hướng dẫn build dataset, train
`ivae_exposure.py`, export qua `save_ae_params.ipynb`, rồi chạy `iDCF.py`.
Có cả `MF.py`, `models/mf.py`, `models/vae.py`, `utils.py` và `evaluator.py`
để đối chiếu baseline, kiến trúc, split và metric.

**Đính chính:** nhận định trước đây rằng paper iDCF không công bố thí nghiệm
Yahoo là sai. Paper có Yahoo ở Table 1 và Table 2. Cảnh báo đúng là bản dự án
chưa tái lập chính xác dữ liệu/pipeline Yahoo của tác giả.

[Notebook Yahoo của tác giả](https://github.com/BgmLover/iDCF/blob/462014126f6e2fc33053341c1da250f9cf6f1fa0/data_process/Yahoo_R3/build_dataset.ipynb)
trừ ID về 0-based, lấy số dòng survey làm `n_users_with_feat`, rồi lọc cả train
và random bằng `user_id < n_users_with_feat`. Paper Table 1 ghi 5.400 user,
129.179 biased ratings và 54.000 unbiased ratings.
Trong dự án hiện tại, MF/iDCF giữ 15.400 user/311.704 biased ratings và thêm
category thiếu survey cho 10.000 user. Đây là khác biệt dữ liệu huấn luyện thực,
không thể chỉ dựa vào điểm gần paper để gọi là tái lập. Cần đối chiếu thêm
hyperparameter, sampling, checkpoint selection và evaluator trước khi đổi runtime.

## IViDR: paper reference

[arXiv IViDR](https://arxiv.org/html/2410.12451v1#S4.SS6) specifies BCE
in Eq. (25). The project keeps learned IV + dual iVAE + BCE feedback.
See [implementation and local choices](ividr_bce_20261021.md).
The published ACM version and full experimental reproduction remain unverified.
