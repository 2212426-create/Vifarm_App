# RecSys: Hệ Thống Gợi Ý Video Ngắn Khử Thiên Lệch & Học Sâu NCF

[Trạng thái hiện hành](docs/CURRENT_STATE.md) · [Mục lục tài liệu](docs/README.md) · [Catalog kết quả](results/CATALOG.md)

Hệ thống gợi ý video ngắn của đồ án ViFarm được tổ chức thành **hai module kiến trúc độc lập**:

1. **Module 1: Lọc cộng tác & Khử thiên lệch nhân quả (CF & Causal Debiasing):**
   Gồm 5 mô hình cốt lõi trên **Coat, Yahoo! R3, KuaiRand-Pure**:
   * **`MF`**: Baseline phân rã ma trận cổ điển (Matrix Factorization).
   * **`iDCF`**: Khử thiên lệch qua tách biến tiềm ẩn nhân quả (Causal Disentanglement).
   * **`LCDR`**: Học biểu diễn tiềm ẩn kết hợp khử thiên lệch (Latent Causal Debiased Rec).
   * **`DR-BIAS + CDR`**: Mô hình khử thiên lệch kép Doubly Robust.
   * **`ConAlign`**: Học tương phản cân chỉnh phân phối (Contrastive Alignment).

2. **Module 2: Mạng nơ-ron học sâu (Neural Collaborative Filtering - NCF):**
   * **`GMF`**: Generalized Matrix Factorization (nhánh tuyến tính).
   * **`MLP`**: Multi-Layer Perceptron (nhánh phi tuyến nhiều tầng).
   * **`NeuMF`**: Ghép song song tháp đôi GMF + MLP.
   * **`NeuMF-pre`**: NeuMF khởi tạo trọng số tiền huấn luyện từ GMF và MLP.

3. **Các mô hình hội thảo đỉnh cao mở rộng (2025):**
   * **`MRDR-CAL`** (Hu et al., TKDE 2025).
   * **`CLEV-DR`** (Zhang et al., KDD 2025, "Ours-DR").

---

## Cấu trúc mã nguồn

Mỗi mô hình có package riêng trong `src/models/`: `mf/`, `idcf/`, `lcdr/`, `cdr/`, `conalign/`, `ncf/`, `mrdr_cal/`, `clev/`.
Xem [cây thư mục, trách nhiệm và đường dẫn mã chuẩn](docs/architecture/directory_layout.md).

---

## Chuẩn bị môi trường & Dữ liệu

Chạy từ thư mục `services/recsys`:
```powershell
# Nếu cài mới:
py -3.12 -m venv venv
.\venv\Scripts\python.exe -m pip install -r requirements.txt
```

Cả 3 bộ dữ liệu đã được nạp sẵn tại `data/raw/`:
* **Coat:** `data/raw/coat/` (`train.ascii`, `test.ascii`, `propensities.ascii`, `user_item_features/`).
* **KuaiRand-Pure:** `data/raw/kuairand_pure/data/` (standard log, random log, `user_features_pure.csv`).
* **Yahoo! R3:** `data/raw/yahoo/` (15.400 user, 1.000 item, 311.704 biased / 54.000 random ratings).

Để tải lại Yahoo nếu chạy trên máy mới:
```powershell
.\venv\Scripts\python.exe experiments\run.py download-yahoo
```

---

## Hướng dẫn chạy thực nghiệm

### 1. Module 1: Benchmark Causal CF (`experiments/run.py benchmark`)

* **Kiểm tra nhanh (Smoke/Quick test - ~1-2 phút):**
  ```powershell
  .\venv\Scripts\python.exe experiments\run.py benchmark --dataset all --model all --quick --epochs 2 --ivae-epochs 2 --threads 4
  ```

* **Chạy Full đầy đủ trên tập Coat (~2-3 phút - Khuyên dùng):**
  ```powershell
  .\venv\Scripts\python.exe experiments\run.py benchmark --dataset coat --model all --threads 4
  ```

* **Chạy Full đầy đủ trên tập Yahoo! R3 (~15-20 phút):**
  ```powershell
  .\venv\Scripts\python.exe experiments\run.py benchmark --dataset yahoo --model all --threads 4
  ```

* **Chạy Full đầy đủ trên tập KuaiRand-Pure (~35-45 phút):**
  ```powershell
  .\venv\Scripts\python.exe experiments\run.py benchmark --dataset kuairand --model all --threads 4
  ```

* **Chạy Full TOÀN BỘ 3 DATASET (~1 giờ):**
  ```powershell
  .\venv\Scripts\python.exe experiments\run.py benchmark --dataset all --model all --threads 4
  ```

* **Chạy riêng từng mô hình:**
  Thêm `--model mf|idcf|lcdr|cdr|conalign` (ví dụ: `--dataset coat --model idcf`).

---

### 2. Module 2: NCF Deep Learning (`experiments/run.py ncf` hoặc `cf-dl`)

* **Kiểm tra nhanh (Smoke test - ~30 giây):**
  ```powershell
  .\venv\Scripts\python.exe experiments\run.py ncf --dataset coat --smoke
  ```

* **Chạy Full NCF trên tập Coat (~1-2 phút):**
  ```powershell
  .\venv\Scripts\python.exe experiments\run.py ncf --dataset coat --seeds 42
  ```

* **Chạy Full NCF trên tất cả Dataset:**
  ```powershell
  .\venv\Scripts\python.exe experiments\run.py ncf --dataset all --seeds 42 --threads 4
  ```

---

### 3. Chạy tự động cả 2 Module liên tiếp trên tất cả Dataset:
```powershell
.\venv\Scripts\python.exe experiments\run.py benchmark --dataset all --model all --threads 4; .\venv\Scripts\python.exe experiments\run.py ncf --dataset all --seeds 42 --threads 4
```

---

### 4. Chạy các mô hình hội thảo mới 2025:
```powershell
.\venv\Scripts\python.exe experiments\run.py mrdr-cal --dataset coat
.\venv\Scripts\python.exe experiments\run.py clev --dataset coat
```

---

## Bảng kết quả và Chỉ số đánh giá

Mỗi lượt chạy xuất báo cáo Markdown và JSON vào thư mục `results/`, checkpoint lưu trong `checkpoints/benchmark_runs/`.

* **`NDCG@5`**: Chỉ số xếp hạng top-5 quan trọng nhất.
* **`Recall@5 bounded`**: `hits / min(5, tổng_positive)`.
* **`Precision@5`**: Tỷ lệ gợi ý chính xác trong top-5.
* **`HitRate@5`**: Xác suất có ít nhất 1 video phù hợp.
* **`AUC`**: `macro-user` cho H30 hoặc `global` cho CDR-src.

---

## Kiểm thử và API Serving cho Ứng dụng

* **Chạy toàn bộ Suite kiểm thử (200 tests):**
  ```powershell
  .\venv\Scripts\python.exe experiments\run.py test
  ```

* **Lint (import/biến thừa, lỗi thường gặp) theo `ruff.toml`:**
  ```powershell
  .\venv\Scripts\python.exe -m pip install ruff
  .\venv\Scripts\python.exe -m ruff check src experiments tests
  ```

* **Khởi chạy RecSys Serving API (FastAPI) phục vụ Mobile App:**
  ```powershell
  .\venv\Scripts\python.exe -m uvicorn src.api.app:app --host 0.0.0.0 --port 8000 --reload
  ```
  Truy cập Swagger docs: [http://localhost:8000/docs](http://localhost:8000/docs).
  Kiểm tra trạng thái hệ thống: [http://localhost:8000/health](http://localhost:8000/health).

* **Mở Cloudflare Tunnel kết nối ra Internet:**
  ```powershell
  .\venv\Scripts\python.exe -m src.api.tunnel --port 8000
  ```
