> **ĐỀ CƯƠNG/KẾ HOẠCH — KHÔNG PHẢI BÁO CÁO TRIỂN KHAI HIỆN HÀNH.** Phạm vi mô hình và mốc dự kiến bên dưới có thể chưa thực hiện. Đọc [CURRENT_STATE](../CURRENT_STATE.md) và metadata kết quả trước khi dùng làm kết luận. Bản trước khi thêm nhãn được giữ trong ZIP archive ngày 20/10/2026.

# ĐỀ CƯƠNG CHI TIẾT — PHẦN 1: THUẬT TOÁN LỌC CỘNG TÁC (COLLABORATIVE FILTERING - CF)
## Đề tài: Nghiên cứu ứng dụng học máy trong phân tích hành vi người dùng và đề xuất video ngắn trên nền tảng quảng bá sản phẩm nông nghiệp
**Sinh viên phụ trách chính:** **Vũ Thế Huỳnh** (MSSV: `2312639` - Lớp `CTK47A`)  
**Giáo viên hướng dẫn:** **TS. Nguyễn Thị Lương**  
**Tập tin tổng hợp:** [`DeCuong_NghienCuuUngDungHocMayDeXuatVideoNgan.md`](DeCuong_NghienCuuUngDungHocMayDeXuatVideoNgan.md)

---

## 🎯 1. Mục tiêu & Phạm vi nghiên cứu của Phần 1

1. **Khảo sát lý thuyết Lọc cộng tác (CF):** Từ các thuật toán cổ điển (Memory-based CF) đến các mô hình dựa trên nhân tử hóa ma trận (Model-based Matrix Factorization).
2. **Khai thác phản hồi ẩn (Implicit Feedback):** Xử lý các hành vi lướt, thời lượng xem video ($\ge 3$s), like, chia sẻ trong môi trường video ngắn nông nghiệp.
3. **Nghiên cứu Thiên lệch dữ liệu trong CF (Exposure Bias):** Nhận diện hiện tượng dữ liệu thiếu không ngẫu nhiên (MNAR - Missing-Not-At-Random), phân tích sự thất bại của CF truyền thống trước các video triệu view showbiz.
4. **Triển khai Lọc cộng tác Khử thiên lệch (Debiased CF):** Ứng dụng kỹ thuật **Conservative Doubly Robust (DR-BIAS + CDR)** để ổn định phương sai và tăng độ chuẩn xác xếp hạng.

---

## 📚 2. Cơ sở lý thuyết chi tiết (Chương I - Phần 1)

### 2.1. Lọc cộng tác dựa trên bộ nhớ (Memory-based CF)
* **User-based Collaborative Filtering:** Dự đoán điểm số dựa trên sự tương đồng giữa các người dùng:
  $$\text{sim}(u, v) = \frac{\sum_{i \in I_{uv}} (r_{ui} - \bar{r}_u)(r_{vi} - \bar{r}_v)}{\sqrt{\sum_{i \in I_{uv}} (r_{ui} - \bar{r}_u)^2} \sqrt{\sum_{i \in I_{uv}} (r_{vi} - \bar{r}_v)^2}}$$
* **Item-based Collaborative Filtering:** Tìm kiếm các video có tập người xem tương đồng để đề xuất chéo.

### 2.2. Lọc cộng tác dựa trên mô hình (Model-based Matrix Factorization)
* Phân rã ma trận tương tác $R \in \mathbb{R}^{|U| \times |I|}$ thành tích của hai ma trận embedding tiềm ẩn:
  - Vector người dùng: $p_u \in \mathbb{R}^d$
  - Vector video: $q_i \in \mathbb{R}^d$
* Điểm dự đoán sở thích:
  $$\hat{s}_{ui} = p_u^T q_i + b_u + b_i + \mu$$
* Hàm mục tiêu tối ưu hóa BCE (Binary Cross-Entropy):
  $$\mathcal{L}_{\text{BCE}} = -\sum_{(u,i) \in \mathcal{O}} \left[ y_{ui} \log \sigma(\hat{s}_{ui}) + (1 - y_{ui}) \log (1 - \sigma(\hat{s}_{ui})) \right] + \lambda (\|p_u\|^2 + \|q_i\|^2)$$

### 2.3. Vấn đề Exposure Bias & Mô hình Causal Debiased CF (CDR)
* **Thách thức:** Thuật toán MF chỉ tối ưu trên các tương tác đã quan sát $\mathcal{O}$ ($O=1$), nhầm lẫn tương quan quan sát $P(Y \mid O=1)$ với sở thích thật $P(Y^*)$.
* **Cơ chế Conservative Doubly Robust (CDR):**
  $$\mathcal{L}_{\text{CDR}} = \sum_{(u,i)} \left[ \hat{e}_{ui} + \frac{O_{ui}}{\hat{p}_{ui}} (e_{ui} - \hat{e}_{ui}) \cdot \mathbb{I}(\text{Var}(\hat{e}_{ui}) \le \tau) \right]$$
  - $\hat{e}_{ui}$: Sai số ước lượng từ mô hình bù đắp Imputation.
  - $\hat{p}_{ui}$: Propensity score (xác suất hiển thị video).
  - $\mathbb{I}(\text{Var} \le \tau)$: Lọc bất định bằng **Monte Carlo Dropout** nhằm triệt tiêu bùng nổ phương sai của IPS.

---

## 🔬 3. Kế hoạch triển khai & Kết quả thực nghiệm Phần 1 (Chương II - Phần 1)

### 3.1. Các mô hình xây dựng:
1. **MF Baseline:** Khung sườn Matrix Factorization chuẩn mực, tối ưu bằng Adam optimizer và embedding 64 chiều.
2. **Implicit ALS:** Mô hình giải tích ma trận xen kẽ cho dữ liệu phản hồi ẩn.
3. **DR-BIAS + CDR:** Mô hình Lọc cộng tác nhân quả Doubly Robust với cơ chế lọc bất định MC Dropout.

### 3.2. Kết quả đo lường trên tập kiểm thử độc lập (Held-Out Test):
* **Trên tập Coat:**
  - MF Baseline: NDCG@5 = `0.4629`, Recall@5 = `0.4898`, AUC = `0.6460`.
  - DR-BIAS + CDR: NDCG@5 = `0.4841` ($+2.12\%$), AUC = `0.6826` ($+3.66\%$).
* **Trên tập KuaiRand-Pure (1.4M tương tác):**
  - MF Baseline: NDCG@5 = `0.3434`.
  - DR-BIAS + CDR: NDCG@5 = `0.3459`.

---

## 📅 4. Phân công & Sản phẩm bàn giao Phần 1

* **Mã nguồn:** Module `src/models/matrix_factorization.py`, `src/baselines/train_mf.py`, `src/causal/cdr/`.
* **Báo cáo chuyên đề:** Chương I & Chương II (Phần Lọc cộng tác).
* **Kiểm thử tự động:** Bộ kiểm thử đơn vị cho MF và CDR đạt 100% Passed.
