# RecSys: MF, CDR, iDCF, IViDR, LCDR và ConAlign

[Trạng thái hiện hành](docs/CURRENT_STATE.md) · [Mục lục](docs/README.md) ·
[Catalog kết quả](results/CATALOG.md).
Theo yêu cầu ngày 21/10/2026, bộ mặc định gồm bốn mô hình trên
**Coat, Yahoo! R3, KuaiRand-Pure**. **IViDR** học reconstruction và feature embedding,
hai posterior iVAE và feedback BCE theo công thức arXiv, lấy kỳ vọng xác suất trước BCE;
Eq. (10) dùng coordinate adapter được ghi rõ. Từ 28/10/2026 mặc định có hai điều chỉnh
từ [phân tích nguyên nhân](docs/benchmarks/ividr_root_cause_20261027.md): prior mean giai đoạn 1
bằng 0 (như mã iDCF) và mẫu âm trong BCE có trọng số .1. Chưa chứng nhận khớp mã tác giả.
Các lựa chọn triển khai địa phương được ghi metadata; chưa chứng nhận tái lập paper.
CDR mặc định dùng bản released và source protocol; Coat/Yahoo theo script khóa commit,
KuaiRand có điều chỉnh dữ liệu/sampler được ghi metadata;
MF/iDCF giữ MSE; IViDR và CDR dùng BCE. IViDR dùng MF làm treatment;
CDR huấn luyện độc lập, không nạp checkpoint MF.

## Cấu trúc mã nguồn

Mỗi mô hình có package riêng trong `src/models/`: `mf/`, `cdr/`, `idcf/`, `ividr/`.
Các import cũ được giữ tương thích; dữ liệu và artifact giữ đường dẫn hiện tại.
Xem [cây thư mục, trách nhiệm và đường dẫn mã chuẩn](docs/architecture/directory_layout.md).

Từ 30/10/2026 `benchmark --model all` chạy thêm hai mô hình thực nghiệm: LCDR (cài đặt lại từ paper
trên protocol H30 của iDCF) và ConAlign (port từ source tác giả, protocol riêng, ghi `C-src` trong bảng;
KuaiRand dùng cửa sổ train của paper). Lệnh riêng vẫn dùng được:

```powershell
.\venv\Scripts\python.exe experiments\run.py lcdr --dataset coat --smoke --compare-idcf
.\venv\Scripts\python.exe experiments\run.py conalign --dataset coat --smoke
```

Xem [lệnh chạy, giao thức và giới hạn](docs/benchmarks/lcdr_conalign_20261027.md).

## Chuẩn bị và dữ liệu

Chạy từ `services/recsys`. Môi trường venv hiện tại đã được kiểm chứng trên CPU.
Nếu cài mới:

```powershell
py -3.12 -m venv venv
.\venv\Scripts\python.exe -m pip install -r requirements.txt
```

Coat cần `train.ascii`, `test.ascii`, `propensities.ascii` và thư mục
`user_item_features/` ở `data/raw/coat/`.
KuaiRand cần hai standard log, random log và `user_features_pure.csv` trong
`data/raw/kuairand_pure/data/` hoặc `kuairand_pure/`.
Loader ưu tiên `./data/`, rồi `../data/`; data_dir tường minh không tự fallback.

Yahoo đã tải đầy đủ vào `data/raw/yahoo/`. Để tải lại trên máy khác:

```powershell
.\venv\Scripts\python.exe experiments\run.py download-yahoo
```

Lệnh lấy đúng 6 file từ commit
`6b4e6cca3df23b8d85b38fdc2e7eb5c812861ea9`, kiểm tra SHA-256 và giữ README
Yahoo Webscope cùng điều kiện sử dụng đi kèm. Raw data không đưa vào Git.
Dữ liệu: 15.400 user, 1.000 item, 311.704 biased / 54.000 random ratings.
iDCF Yahoo dùng survey thật; nhóm thiếu survey có category thiếu. Đây là mở
rộng dataset của dự án, chưa phải kết quả Yahoo từ paper iDCF.

## Chạy thử và chạy đầy đủ

Kiểm tra nhanh sáu mô hình trên Yahoo: MF/iDCF/IViDR/LCDR subset 64 user, CDR source và ConAlign toàn dữ liệu;
1 epoch feedback / 2 epoch iVAE:

```powershell
.\venv\Scripts\python.exe experiments\run.py smoke --dataset yahoo
```

Chạy đầy đủ sáu mô hình trên Yahoo với ngân sách riêng của từng mô hình:

```powershell
.\venv\Scripts\python.exe experiments\run.py benchmark --dataset yahoo --model all --device cpu --threads 2
```

Chạy đầy đủ sáu mô hình trên Coat:

```powershell
.\venv\Scripts\python.exe experiments\run.py benchmark --dataset coat --model all --device cpu --threads 2
```

Đổi `--dataset all` để chạy cả Coat, Yahoo và KuaiRand.
Đổi `--model mf|idcf|ividr|lcdr|cdr|conalign` để chạy riêng (chọn một giá trị).
Mỗi lượt benchmark tạo JSON/Markdown riêng trong `results/`, checkpoint riêng
trong `checkpoints/benchmark_runs/`. iVAE mặc định có trần 2000 epoch và chọn
checkpoint sau full-beta warm-up, nên có thể cần nhiều thời gian.
CDR có seed 2020, trần 1000 epoch, train-loss stopping và lấy trọng số cuối như source;
không dùng epoch budget 100 mặc định của MF. `--epochs` là override tường minh cho cả bốn.
MF/iDCF/IViDR chọn checkpoint bằng validation. Bảng tổng hợp có đủ 12 dòng, ghi giao thức
và loại AUC ở mỗi dòng. Gộp bảng để đọc không có nghĩa các protocol tương đương.

Log huấn luyện dùng chung định dạng `[Mô hình][DATASET] Epoch ...`.
iDCF hiển thị tiến độ cả iVAE và feedback; CDR hiển thị rec/imp loss từng epoch.
Kết quả cuối ghi rõ `TEST` hoặc `SOURCE EVAL`, metric đúng tên và đường dẫn checkpoint.
Log mới có hiệu lực từ lần khởi chạy tiếp theo, không thay đổi thuật toán hoặc điểm số.

Mỗi dòng chỉ hiển thị `Recall@5 bounded` (chia min(5, số positive)), Precision,
HitRate. JSON vẫn giữ cả Recall/all positives và Recall bounded. CDR tính metric bổ sung từ cùng
ranking và cùng tập user của source; với empty-positive, source giữ Recall=1,
còn Precision/HitRate=0. AUC ghi rõ `macro-user` hoặc `global`.

Cập nhật bảng cho báo cáo đã chạy, **không huấn luyện lại**:

```powershell
.\venv\Scripts\python.exe experiments\run.py report --input results\benchmark_all_8e44de4472_20261020_232046_d992f0ff_v4.json --threads 2
```

Lệnh đọc lại checkpoint CDR, kiểm tra điểm gốc không đổi và tạo JSON/Markdown mới.
Báo cáo cũ và metadata source của lượt huấn luyện được giữ nguyên.

Thử toàn dữ liệu Yahoo với ngân sách ngắn:
`benchmark --dataset yahoo --model all --quick --epochs 1 --ivae-epochs 2 --device cpu --threads 2`.
Điểm smoke/quick không dùng để so chất lượng với paper.

## CDR source đã là mặc định

```powershell
.\venv\Scripts\python.exe experiments\run.py cdr-source --dataset coat --threads 2
.\venv\Scripts\python.exe experiments\run.py cdr-source --dataset yahoo --threads 2
```

Lệnh này giữ điều kiện script: >=3, 5% nhãn random chấm điểm dùng cho propensity,
toàn bộ random log, zero-positive nhận 1, Recall bounded và dừng theo train loss.
Kết quả Coat kiểm chứng: NDCG .656665 / Recall bounded .667816.
`benchmark --dataset coat --model cdr` gọi cùng hàm với lệnh trên và đạt cùng điểm.
Yahoo source đầy đủ đã đạt NDCG .655929 / Recall bounded .731299 / AUC global .684930.
Source protocol dùng nhãn tập chấm cho calibration, không phải held-out test độc lập.
MF/iDCF vẫn dùng >=4, user split 30/70. Muốn so cùng protocol, chọn CDR
`--cdr-implementation shared` tường minh; điểm này sẽ khác source protocol.
Xem [định nghĩa và khác biệt paper/source](docs/benchmarks/paper_model_alignment.md).

## Các lệnh khác

| Lệnh sau `experiments/run.py` | Phạm vi |
| :-- | :-- |
| `test` | Suite kiểm thử |
| `smoke` | MF/iDCF Yahoo/KuaiRand 64 user; CDR Coat/Yahoo toàn dữ liệu, KuaiRand 64 user; ngân sách ngắn |
| `evaluate --dataset yahoo --checkpoint FILE` | Chấm checkpoint tương thích, không huấn luyện lại |
| `coat-seeds` | MF/iDCF/IViDR/CDR released, seed 42–51; có `--cdr-implementation equation` |
| `benchmark ... --cdr-implementation shared` | Released CDR trên giao thức held-out chung; lựa chọn đối chứng |
| `benchmark ... --cdr-implementation equation` | Biến thể Eq. (7)/CV cũ; chỉ chạy tường minh |
| `benchmark --dataset coat --model cdr --cdr-implementation equation --cdr-propensity provided_coat` | Đối chứng propensity file Coat của bản Eq. (7) |
| `tune --model mf` / `tune-kr --model mf` | Tuning MF trên Coat / KuaiRand |
| `tune --model cdr` / `tune-kr --model cdr` | Grid 1.120 cấu hình released estimator; calibration/chọn cấu hình chỉ validation; chưa có CLI tune Yahoo |
| `mf --dataset yahoo` | MF riêng |
| `optimizers` | Thí nghiệm Adam/SGD riêng |
| `cdr-author` / `cdr-tune` | Alias của cdr-source / tuning released |
| `protocol` | In giao thức đánh giá |
| `clean` / `clean --apply` | Xem trước / dọn checkpoint, log, bytecode; giữ raw data và báo cáo |

Mỗi lệnh có `--help`. IViDR thuộc bộ mặc định. Với budget feedback >=20 epoch
và không override LR/weight decay, pipeline quét 10 cấu hình LR/WD theo khoảng
paper, chọn bằng validation, rồi chỉ chấm test checkpoint thắng. Smoke không quét.
Yahoo dùng survey địa phương/missing category, chưa tái lập dữ liệu tác giả.
Xem [triển khai IViDR hiện hành](docs/benchmarks/ividr_reference_20261022.md)
và [đối chiếu MSE/BCE của bản cũ](docs/benchmarks/ividr_bce_20261021.md).

## Kiểm chứng và API

```powershell
.\venv\Scripts\python.exe experiments\run.py test
.\venv\Scripts\python.exe docs\check_docs.py
.\venv\Scripts\python.exe -m uvicorn src.api.app:app --port 8000
```

[Giao thức từng mô hình](docs/benchmarks/evaluation_protocol.md) ·
[Config MF/CDR](src/training/config.py) · [Config iDCF](src/causal/idcf/train_idcf.py).
API TopTop giữ cấu hình phục vụ riêng, user mới dùng popularity.
CDR API dùng ReleasedCDR; không có random log nên ghi rõ propensity proxy và sampler
có hoàn lại trong `training_stats.cdr`, không coi là thí nghiệm paper.
[Hướng dẫn API/Colab](docs/api/colab_api_guide.md).
