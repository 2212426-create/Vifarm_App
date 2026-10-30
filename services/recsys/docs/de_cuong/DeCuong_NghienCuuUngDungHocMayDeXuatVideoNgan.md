> **ĐỀ CƯƠNG/KẾ HOẠCH — KHÔNG PHẢI BÁO CÁO TRIỂN KHAI HIỆN HÀNH.** Phạm vi mô hình và mốc dự kiến bên dưới có thể chưa thực hiện. Đọc [CURRENT_STATE](../CURRENT_STATE.md) và metadata kết quả trước khi dùng làm kết luận. Bản trước khi thêm nhãn được giữ trong ZIP archive ngày 20/10/2026.

# TRƯỜNG ĐẠI HỌC ĐÀ LẠT
## KHOA CÔNG NGHỆ THÔNG TIN

---

# ĐỀ CƯƠNG THỰC HIỆN ĐỒ ÁN CHUYÊN NGÀNH
## Tên đề tài: Nghiên cứu ứng dụng học máy trong phân tích hành vi người dùng và đề xuất video ngắn trên nền tảng quảng bá sản phẩm nông nghiệp.

* **Giáo viên hướng dẫn:** **TS. Nguyễn Thị Lương**
* **Sinh viên thực hiện:**
  1. **Vũ Thế Huỳnh** – MSSV: `2312639` – Lớp: `CTK47A` – Email: `2312639@dlu.edu.vn` *(Trọng tâm: Phần 1 - Lọc cộng tác CF)*
  2. **Phùng Nguyễn Hoài Bo** – MSSV: `2312585` – Lớp: `CTK47A` – Email: `2312585@dlu.edu.vn` *(Trọng tâm: Phần 2 - Học sâu Deep Learning)*

---

## 🎯 TỔNG QUAN & MỤC TIÊU CHUNG CỦA ĐỀ TÀI

### 1. Bối cảnh & Tính cấp thiết
Trong kỷ nguyên bùng nổ của mạng xã hội di động, video ngắn (TopTop, TikTok, Reels) đã trở thành phương tiện trực quan và mạnh mẽ nhất để nông dân và hợp tác xã đưa nông sản sạch, quy trình nuôi trồng sinh thái và câu chuyện văn hóa địa phương đến thẳng người tiêu dùng.

Tuy nhiên, lượng video đăng tải khổng lồ dẫn đến hiện tượng **"quá tải thông tin"** và **thiên lệch hiển thị (Exposure Bias)**: video nông sản mới ít được tiếp cận, người dùng bị giam trong buồng thông tin (*filter bubble*). Việc tích hợp **Hệ thống Gợi ý (Recommender System)** tự động nhằm giữ chân người dùng (*Retention*) và phân phối trúng đích nội dung nông nghiệp là cấp thiết.

### 2. Định hướng phân tách 2 Trụ cột cốt lõi
Để giải quyết bài toán một cách toàn diện và có chiều sâu học thuật, đề tài được phân tách thành **2 Phần nghiên cứu độc lập nhưng bổ trợ mật thiết**:
* **PHẦN 1: THUẬT TOÁN LỌC CỘNG TÁC (COLLABORATIVE FILTERING - CF)**
* **PHẦN 2: HỌC SÂU TRONG HỆ THỐNG GỢI Ý (DEEP LEARNING RECOMMENDATION)**
* **PHẦN 3: ĐỐI SÁNH THỰC NGHIỆM, TỔNG HỢP VÀ TÍCH HỢP HỆ THỐNG (API & FLUTTER APP)**

---

# ========================================================
# 📦 PHẦN 1: THUẬT TOÁN LỌC CỘNG TÁC (COLLABORATIVE FILTERING - CF)
# ========================================================

### 1.1. Mục tiêu của Phần 1
* Khảo sát toàn diện lý thuyết Lọc cộng tác kinh điển và hiện đại trong Recommender System.
* Xây dựng mô hình phân tích hành vi tương tác tiềm ẩn từ ma trận phản hồi ẩn (*Implicit Feedback: xem, thời lượng xem, like, chia sẻ*).
* Nghiên cứu bài toán **Thiên lệch dữ liệu (Exposure/Selection Bias)** trong Lọc cộng tác và triển khai các thuật toán Lọc cộng tác khử thiên lệch (*Debiased Collaborative Filtering*).

### 1.2. Cơ sở lý thuyết Lọc cộng tác (Chương I - Phần 1)
1. **Lọc cộng tác dựa trên bộ nhớ (Memory-based CF):**
   - *User-based CF*: Tìm kiếm người dùng có hành vi tương đồng thông qua độ đo Cosine Similarity, Pearson Correlation.
   - *Item-based CF*: Gợi ý video tương tự dựa trên lịch sử tương tác của cộng đồng người xem.
2. **Lọc cộng tác dựa trên mô hình (Model-based CF - Matrix Factorization):**
   - Ánh xạ người dùng $u$ và video $i$ vào không gian vector tiềm ẩn $d$-chiều ($p_u, q_i \in \mathbb{R}^d$).
   - Hàm chấm điểm: $\hat{s}_{ui} = p_u^T q_i + b_u + b_i + \mu$.
   - Tối ưu hóa với hàm mất mát Binary Cross-Entropy (BCE) và Alternating Least Squares (Implicit ALS).
3. **Thách thức cốt tử của Lọc cộng tác truyền thống trong video ngắn:**
   - *Ma trận cực kỳ thưa (Gradient Sparsity)*: Phần lớn các cặp user-video không có tương tác.
   - *Dữ liệu thiếu không ngẫu nhiên (MNAR - Missing-Not-At-Random)*: Video không có click không phải vì người xem ghét, mà do chưa từng được hiển thị.
4. **Mở rộng nâng cao — Lọc cộng tác Khử thiên lệch Nhân quả (Causal Debiased CF):**
   - Phương pháp **Conservative Doubly Robust (DR-BIAS + CDR)**:
     $$\mathcal{L}_{\text{CDR}} = \sum_{(u,i)} \left[ \hat{e}_{ui} + \frac{O_{ui}}{\hat{p}_{ui}} (e_{ui} - \hat{e}_{ui}) \cdot \mathbb{I}(\text{Var}(\hat{e}_{ui}) \le \tau) \right]$$
   - Khung sườn vẫn là Matrix Factorization, nhưng tích hợp mô hình bù đắp (*Imputation*) và nghịch đảo xác suất hiển thị (*IPS*) có cơ chế Conservative đo bằng Monte Carlo Dropout để chống bùng nổ phương sai.

### 1.3. Triển khai mô hình & Thực nghiệm Phần 1 (Chương II - Phần 1)
* **Xây dựng Pipeline CF:**
  - Tiền xử lý dữ liệu ma trận tương tác người dùng - video.
  - Xây dựng mô hình **MF Baseline** (học embedding $p_u, q_i$ bằng Adam optimizer).
  - Xây dựng mô hình **DR-BIAS + CDR** với kỹ thuật warm-start từ checkpoint MF.
* **Đánh giá hiệu năng CF:**
  - Đo lường trên tập kiểm thử không thiên lệch (Held-Out Random Log): NDCG@5, Recall@5, HitRate@5, Macro-user AUC.
  - Phân tích độ nhạy của siêu tham số: kích thước vector embedding ($d=32, 64, 128$), ngưỡng bất định $\tau$, hệ số learning rate.

---

# ========================================================
# 🧠 PHẦN 2: HỌC SÂU TRONG HỆ THỐNG GỢI Ý (DEEP LEARNING RECOMMENDATION)
# ========================================================

### 2.1. Mục tiêu của Phần 2
* Ứng dụng các kiến trúc mạng nơ-ron sâu (Deep Neural Networks) để trích xuất các mối quan hệ phi tuyến tính phức tạp giữa người dùng và nội dung video.
* Giải quyết triệt để vấn đề biến nhiễu ẩn (*Unobserved Confounders*) bằng các mô hình học sâu biến phân và lý thuyết nhân quả hiện đại.
* Tách rời biểu diễn tiềm ẩn (*Representation Disentanglement*) để cô lập sở thích bất biến của người dùng.

### 2.2. Cơ sở lý thuyết Học sâu trong RecSys (Chương I - Phần 2)
1. **Mạng nơ-ron Lọc cộng tác (Neural Collaborative Filtering - NCF):**
   - Kết hợp hai luồng xử lý: **Generalized Matrix Factorization (GMF)** (học tương tác tuyến tính) và **Multi-Layer Perceptron (MLP)** (học tương tác phi tuyến tính bậc cao).
   - Kiến trúc hợp nhất NeuMF đưa embedding user và item qua các lớp ẩn fully connected với phi tuyến ReLU:
     $$\phi^{\text{NCF}} = \text{MLP}([p_u, q_i]) \oplus (p_u \odot q_i)$$
2. **Mạng nơ-ron Biến phân có thể Định danh (Identifiable VAE - iVAE):**
   - Khắc phục giới hạn của VAE thông thường: VAE truyền thống không đảm bảo khôi phục đúng biến ẩn sinh ra dữ liệu.
   - iVAE đưa thêm thông tin phụ trợ/ngữ cảnh $W$ vào phân phối tiên nghiệm có điều kiện $p(C \mid W)$ để đảm bảo tính định danh toán học của biến ẩn hiển thị $C$.
3. **Lý thuyết Biến công cụ (Instrumental Variable - IV) trong Học sâu:**
   - Dùng mạng nơ-ron ánh xạ thuộc tính người dùng để tìm Biến công cụ $Z$ thỏa mãn:
     1. Tương quan với quyết định hiển thị $A$ (*Relevance*).
     2. Độc lập với biến nhiễu ẩn $U$ (*Unconfoundedness*).
     3. Chỉ tác động tới hành vi qua hiển thị (*Exclusion restriction*).
4. **Kiến trúc Lọc cộng tác Học sâu & Nhân quả IViDR (Deep Causal CF):**
   - *Nhánh IV*: Chiếu hồi quy đặc trưng để cô lập vector sở thích sạch $Z$.
   - *Nhánh iVAE*: Encoder học phân phối biến ẩn ngữ cảnh hiển thị $C$; Decoder tái tạo ma trận phơi bày $O$.
   - *Dự đoán điểm số*: $\hat{s}_{ui} = p_u^T q_i + Z_u$ $\rightarrow$ Triệt tiêu hoàn toàn nhiễu hiển thị $C$.

### 2.3. Triển khai mô hình & Thực nghiệm Phần 2 (Chương II - Phần 2)
* **Xây dựng Pipeline Deep Learning:**
  - Cài đặt kiến trúc iVAE Encoder-Decoder bằng PyTorch với hàm mất mát ELBO kết hợp điều kiện tiên nghiệm.
  - Cài đặt nhánh chiếu biến công cụ IV Projection.
  - Xây dựng mạng kết hợp suy diễn điểm số thời gian thực.
* **Đánh giá hiệu năng Deep Learning:**
  - Kiểm thử khả năng tổng quát hóa trên dữ liệu video ngắn quy mô lớn (KuaiRand 1.4 triệu tương tác).
  - Đo lường khả năng bóc tách biến ẩn và độ ổn định của vector sở thích bất biến $Z$.

---

# ========================================================
# ⚖️ PHẦN 3: ĐỐI SÁNH THỰC NGHIỆM, TỔNG HỢP VÀ TÍCH HỢP HỆ THỐNG
# ========================================================

### 3.1. Đối sánh Định lượng Giữa Lọc Cộng Tác (CF) & Học Sâu (Deep Learning)
Bảng đối sánh hiệu năng toàn diện trên 2 tập dữ liệu benchmark theo chuẩn **iDCF Protocol (Held-Out Random Test)**:

| Tiêu chí đối sánh | **Nhóm 1: Lọc cộng tác truyền thống (MF Baseline)** | **Nhóm 1 mở rộng: Lọc cộng tác nhân quả (CDR)** | **Nhóm 2: Lọc cộng tác Học sâu (IViDR)** |
|---|:---:|:---:|:---:|
| **Trường phái tiếp cận** | Model-based CF (Matrix Factorization) | Doubly Robust CF (MF + MC Dropout) | Deep Causal CF (iVAE + Instrumental Variable) |
| **Test NDCG@5 (Coat)** | 0.4629 | 0.4841 ($+2.12\%$) | **0.5454** ($+8.25\%$) |
| **Test Recall@5 (Coat)** | 0.4898 | 0.4932 ($+0.34\%$) | **0.5714** ($+8.16\%$) |
| **Test HitRate@5 (Coat)** | 0.8163 | 0.8469 | **0.8980** ($89.8\%$) |
| **Test AUC Macro (Coat)** | 0.6460 | 0.6826 ($+3.66\%$) | **0.7064** ($+6.04\%$) |
| **Test NDCG@5 (KuaiRand 1.4M)** | 0.3434 | 0.3459 | **0.3484** (Dẫn đầu) |
| **Khả năng khử Exposure Bias** | ❌ Kém (Bị đánh lừa bởi Confounder $U$) | ⚠️ Tốt (Nhờ lọc bất định MC Dropout) | 🏆 Xuất sắc (Nhờ bóc tách $Z$ bất biến qua iVAE) |
| **Thời gian huấn luyện (Training)** | ⚡ Rất nhanh (~10-15s trên GPU) | ⏱️ Trung bình (~1-2 phút) | ⏳ Lâu hơn (~3-5 phút do mạng iVAE) |
| **Độ trễ suy diễn (Inference Latency)** | 🚀 < 2 ms | 🚀 < 3 ms | 🚀 < 5 ms (Tách rời $Z$ tính sẵn) |

### 3.2. Phân tích Tối ưu Hóa: Adam vs SGD trong RecSys
* **Bản chất**: Trong ma trận tương tác video ngắn, độ thưa cực lớn khiến gradient phân bố không đều giữa video triệu view và video nông sản mới.
* **Kết luận thực nghiệm**: **Adam vượt trội hoàn toàn so với SGD** (NDCG@5 ~0.49 vs ~0.44 trên Coat) nhờ cơ chế điều chỉnh bước học thích nghi riêng cho từng chiều embedding.

### 3.3. Đóng gói REST API & Tích hợp Ứng dụng TopTop Thực tế
1. **Kiến trúc Web Service (FastAPI):**
   - Đóng gói mô hình ưu việt nhất (**IViDR**) lên FastAPI REST Server.
   - Endpoint `/api/v1/recommend`: Trả về danh sách Top-$K$ video cá nhân hóa theo thời gian thực (độ trễ 150–250ms).
   - Endpoint `/api/v1/interaction`: Tiếp nhận và ghi nhận tương tác xem video ($\ge 3$s) và thả tim từ người dùng.
2. **Cơ chế Tự động hóa Zero-Config:**
   - Triển khai server trên Google Colab qua Cloudflare Tunnel công khai.
   - Tự động ghi URL tunnel vào Firebase Realtime Database (`server_config/recsys_url`).
   - Ứng dụng Flutter **TopTop** tự động phát hiện URL và kết nối, kèm cơ chế **Graceful Fallback** về Firestore nếu máy chủ AI ngoại tuyến.
3. **Độ tin cậy kiểm thử:**
   - Hoàn thành **40/40 Unit Tests tự động (100% Passed)** bảo đảm tính toàn vẹn hệ thống.

---

## 🛠️ PHẦN MỀM VÀ CÔNG CỤ SỬ DỤNG

* **Môi trường phát triển:** Visual Studio Code, Google Colab (GPU T4/A100).
* **Framework Học máy & Học sâu:** Python 3.10+, PyTorch, Scikit-learn, Pandas, NumPy, SciPy.
* **Thư viện CF & Xử lý ma trận:** Implicit, Scipy Sparse Matrix.
* **Triển khai Web Service & Tunnel:** FastAPI, Uvicorn, Cloudflare Tunnel (`cloudflared`).
* **Nền tảng Ứng dụng & Dữ liệu:** Flutter SDK (Dart), Firebase Firestore, Firebase Realtime Database.
* **Quản lý mã nguồn & Kiểm thử:** Git, GitHub, Pytest (40 unit test suites).

---

## 📅 KẾ HOẠCH THỰC HIỆN CHI TIẾT & PHÂN CÔNG NHIỆM VỤ

| Mốc thời gian | Nội dung công việc | Sinh viên phụ trách chính | Trạng thái |
|:---:|---|:---:|:---:|
| 03/08 – 10/08/2026 | Làm đề cương chi tiết của đề tài. | Cả nhóm | **Đã hoàn thành** |
| 11/08 – 20/08/2026 | Nghiên cứu tổng quan lý thuyết Học máy, Lọc cộng tác & Học sâu. | Cả nhóm | **Đã hoàn thành** |
| 21/08 – 01/09/2026 | Thu thập, làm sạch và chuẩn hóa dữ liệu (KuaiRand, Coat, Firebase TopTop). | Cả nhóm | **Đã hoàn thành** |
| 02/09 – 13/09/2026 | **Phần 1**: Xây dựng, huấn luyện và kiểm thử mô hình Lọc cộng tác (MF, CDR, ALS). | Vũ Thế Huỳnh | **Đã hoàn thành** |
| 14/09 – 20/09/2026 | **Báo cáo tiến độ lần 1.** | Cả nhóm | **Đã hoàn thành** |
| 21/09 – 04/10/2026 | **Phần 2**: Nghiên cứu và huấn luyện mô hình Học sâu (NCF, iVAE, IViDR). | Phùng Nguyễn Hoài Bo | **Đã hoàn thành** |
| 05/10 – 11/10/2026 | **Phần 3**: Thực nghiệm đối sánh định lượng toàn diện giữa CF và Deep Learning. | Cả nhóm | **Đã hoàn thành** |
| 12/10 – 18/10/2026 | **Báo cáo tiến độ lần 2**; gửi số liệu đối sánh cho GVPB. | Cả nhóm | **Đang thực hiện** |
| 19/10 – 01/11/2026 | Đóng gói FastAPI REST Service; tích hợp luồng gọi API tự động vào app TopTop. | Cả nhóm | **Đã hoàn thành** |
| 02/11 – 10/11/2026 | Tổng hợp số liệu thực nghiệm, viết và hoàn thiện cuốn báo cáo đồ án chuyên ngành. | Cả nhóm | Sắp tới |
| 11/11 – 16/11/2026 | Gửi bản thảo cuốn báo cáo đồ án cho GVHD và GVPB nhận xét. | Cả nhóm | Sắp tới |
| 17/11 – 22/11/2026 | **Bảo vệ đồ án tốt nghiệp/chuyên ngành.** Nộp báo cáo chính thức cho Khoa. | Cả nhóm | Lịch thi |

---

## 📖 TÀI LIỆU THAM KHẢO CHỌN LỌC

### 1. Tài liệu về Lọc cộng tác (Collaborative Filtering):
* `[1]` Hu, Y., Koren, Y., & Volinsky, C. (2008). *Collaborative Filtering for Implicit Feedback Datasets*. 2008 Eighth IEEE International Conference on Data Mining (ICDM).
* `[2]` Aggarwal, C. C. (2016). *Recommender Systems: The Textbook*. Springer.
* `[3]` Steck, H. (2010). *Training and testing of recommender systems on data missing not at random*. Proceedings of the 16th ACM SIGKDD.
* `[4]` CIKM (2023). *Conservative Doubly Robust for Debiased Collaborative Filtering (CDR)*. Proceedings of the 32nd ACM CIKM.

### 2. Tài liệu về Học sâu trong Gợi ý (Deep Learning Recommendation):
* `[5]` He, X., Liao, L., Zhang, H., Nie, L., Hu, X., & Chua, T. S. (2017). *Neural Collaborative Filtering*. Proceedings of the 26th International Conference on World Wide Web (WWW).
* `[6]` Khemakhem, I., Kingma, D., Monti, R., & Hyvarinen, A. (2020). *Variational Autoencoders and Nonlinear ICA: A Factorial Approach to Identifiable Representation Learning (iVAE)*. AISTATS 2020.
* `[7]` Gao, C., Li, S., Zhang, Y., et al. (2022). *KuaiRand: An Unbiased Sequential Recommendation Dataset with Randomly Exposed Videos*. Proceedings of the 31st ACM CIKM.
* `[8]` IViDR Research Group (2023). *Instrumental Variable Doubly Robust Representation Learning for Unbiased Recommendation*.

---

## ✍️ XÁC NHẬN CỦA GIẢNG VIÊN VÀ BỘ MÔN

*Đà Lạt, ngày … tháng … năm 2026*

| Giảng viên hướng dẫn | Sinh viên thực hiện | Ban Chủ nhiệm Khoa CNTT |
|:---:|:---:|:---:|
| *(Ký và ghi rõ họ tên)* | *(Ký và ghi rõ họ tên)* | *(Ký và ghi rõ họ tên)* |
| <br><br>**TS. Nguyễn Thị Lương** | <br><br>**Vũ Thế Huỳnh** &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; **Phùng Nguyễn Hoài Bo** | <br><br> |
