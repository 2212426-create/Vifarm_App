# Cấu trúc thư mục RecSys

Mốc sắp xếp: **22/10/2026**. Trạng thái thực thi và kiểm chứng thuộc
[CURRENT_STATE](../CURRENT_STATE.md); lệnh chạy thuộc [README dịch vụ](../../README.md).

## Bố trí và trách nhiệm

```text
recsys/
├── src/
│   ├── models/
│   │   ├── mf/                 # MF và train_mf.py
│   │   ├── cdr/                # Released/source protocol và biến thể equation
│   │   ├── idcf/               # iVAE, iDCF và trainer feedback dùng chung
│   │   ├── ividr/              # Reference v2, pipeline và biến thể cũ có tên riêng
│   │   ├── lcdr/               # LCDR thực nghiệm: iVAE + LCVAE, feedback theo iDCF
│   │   └── conalign/           # ConAlign thực nghiệm: port source tác giả, protocol riêng
│   ├── data_pipeline/          # Đọc dữ liệu, preprocessing, split, cache
│   ├── evaluation/             # Metric, protocol, evaluator và bảng kết quả
│   ├── training/               # Cấu hình và điều phối training chung
│   ├── api/                    # FastAPI, phục vụ và kết nối ứng dụng
│   ├── utils/                  # Đường dẫn, seed, artifact identity, logging, lock
│   ├── baselines/              # Import tương thích cho MF cũ
│   └── causal/                 # Import tương thích cho CDR/iDCF/IViDR cũ
├── experiments/
│   ├── run.py                  # CLI duy nhất cho người chạy
│   └── workflows/              # Benchmark, tuning, tải dữ liệu, tổng hợp report
├── tests/                      # Kiểm thử thuật toán, pipeline, API, tương thích
├── third_party/                # Source tác giả đúng byte tại commit khóa + manifest (ConAlign)
├── data/
│   ├── raw/                    # Dữ liệu gốc; không đưa vào Git
│   └── processed/              # Cache theo preprocessing identity
├── checkpoints/                # Trọng số, metadata và checkpoint từng lượt chạy
├── results/                    # Artifact bất biến; CATALOG.md là điểm tra cứu
├── docs/
│   ├── CURRENT_STATE.md        # Điểm bắt đầu đọc trạng thái
│   ├── architecture/           # Cấu trúc và quy tắc mở rộng
│   ├── benchmarks/             # Định nghĩa, giao thức và đối chiếu paper/source
│   ├── papers/                 # Paper tham khảo
│   ├── paper_summaries/        # Bản đọc/tóm tắt paper
│   ├── archive/                # Snapshot và bằng chứng theo mốc
│   ├── catalog.json            # Phân loại và checksum tài liệu/artifact
│   └── check_docs.py           # Kiểm tra tính nhất quán
├── notebooks/                  # Colab và template notebook
├── temporary/                  # File tạm từ các lượt chạy trước
└── venv/                       # Môi trường Python cục bộ
```

Các thư mục dữ liệu, checkpoint và kết quả giữ vị trí hiện tại vì artifact cũ
có đường dẫn đến chúng. Không dùng tên thư mục để suy ra chất lượng hoặc bản paper.
Archive và kết quả lịch sử giữ nguyên; tra cứu qua mục lục thay vì di chuyển chúng.

## Đường dẫn mã chuẩn

| Thành phần | Đường dẫn hiện hành |
| :-- | :-- |
| MF backbone | [matrix_factorization.py](../../src/models/mf/matrix_factorization.py) |
| MF training | [train_mf.py](../../src/models/mf/train_mf.py) |
| CDR người dùng chọn | [source_protocol.py](../../src/models/cdr/source_protocol.py) |
| Estimator CDR công bố | [released.py](../../src/models/cdr/released.py), [giấy phép](../../src/models/cdr/CDR_UPSTREAM_LICENSE.txt) |
| iDCF | [idcf_model.py](../../src/models/idcf/idcf_model.py), [train_idcf.py](../../src/models/idcf/train_idcf.py) |
| IViDR reference v2 | [ividr_reference.py](../../src/models/ividr/ividr_reference.py), [train_ividr.py](../../src/models/ividr/train_ividr.py) |
| LCDR (thực nghiệm) | [lcvae.py](../../src/models/lcdr/lcvae.py), [train_lcdr.py](../../src/models/lcdr/train_lcdr.py), [source.json](../../src/models/lcdr/source.json) |
| ConAlign (thực nghiệm) | [train.py](../../src/models/conalign/train.py), [data.py](../../src/models/conalign/data.py), [source.json](../../src/models/conalign/source.json) |

iVAE ở `models/idcf/ivae.py` được IViDR tái sử dụng. Trainer feedback
`models/idcf/train_idcf.py` vẫn phục vụ cả hai mô hình qua factory tường minh;
pipeline IViDR thuộc `models/ividr/train_ividr.py`. Chưa đổi logic trong đợt sắp xếp này.

Các file `src/causal/...`, `src/baselines/train_mf.py` và
`src/models/matrix_factorization.py` chỉ chuyển import tới module chuẩn. Chúng dùng
cùng đối tượng module để patch/mock qua import cũ vẫn tác động đúng trainer.
Không đặt implementation mới vào các file tương thích. Notebook/API và script cũ
vẫn dùng được; CLI `experiments/run.py` đã dùng đường dẫn chuẩn.
[Danh sách chuyển file và checksum](../archive/2026-10-22/package_layout/moves.json).

Mốc sắp xếp thư mục trước tích hợp chỉ thay vị trí mã/import và bootstrap đường dẫn MF. Loss, seed,
hyperparameter, nhãn, split, checkpoint selection và evaluator giữ nguyên.
[Đối chiếu AST và nạp checkpoint](../../results/package_layout_parity_20261022.json)
giữ hash huấn luyện cũ riêng với hash mã đánh giá mới.
