> **ĐỀ CƯƠNG/KẾ HOẠCH — KHÔNG PHẢI BÁO CÁO TRIỂN KHAI HIỆN HÀNH.** Phạm vi mô hình và mốc dự kiến bên dưới có thể chưa thực hiện. Đọc [CURRENT_STATE](../CURRENT_STATE.md) và metadata kết quả trước khi dùng làm kết luận. Bản trước khi thêm nhãn được giữ trong ZIP archive ngày 20/10/2026.

# ĐỀ CƯƠNG CHI TIẾT — PHẦN 2: HỌC SÂU TRONG HỆ THỐNG GỢI Ý (DEEP LEARNING RECOMMENDATION)
## Đề tài: Nghiên cứu ứng dụng học máy trong phân tích hành vi người dùng và đề xuất video ngắn trên nền tảng quảng bá sản phẩm nông nghiệp
**Sinh viên phụ trách chính:** **Phùng Nguyễn Hoài Bo** (MSSV: `2312585` - Lớp `CTK47A`)  
**Giáo viên hướng dẫn:** **TS. Nguyễn Thị Lương**  
**Tập tin tổng hợp:** [`DeCuong_NghienCuuUngDungHocMayDeXuatVideoNgan.md`](DeCuong_NghienCuuUngDungHocMayDeXuatVideoNgan.md)

---

## 🎯 1. Mục tiêu & Phạm vi nghiên cứu của Phần 2

1. **Ứng dụng Mạng nơ-ron sâu (Deep Neural Networks):** Học các biểu diễn tiềm ẩn phi tuyến tính phức tạp giữa người dùng và video nông sản vượt ra ngoài phép nhân vô hướng của Matrix Factorization.
2. **Nghiên cứu Kiến trúc Neural Collaborative Filtering (NCF):** Kết hợp Generalized Matrix Factorization (GMF) và Multi-Layer Perceptron (MLP) để mô hình hóa mối quan hệ tương tác đa chiều.
3. **Mạng nơ-ron Biến phân có thể định danh (Identifiable VAE - iVAE):** Tách rời biểu diễn tiềm ẩn (*Representation Disentanglement*) để phân lập biến ẩn ngữ cảnh hiển thị $C$ ra khỏi biểu diễn người dùng.
4. **Lý thuyết Biến công cụ (Instrumental Variable - IV) trong Deep Learning:** Xây dựng mô hình **IViDR (Instrumental Variable Doubly Robust)** cắt đứt ảnh hưởng của biến nhiễu ẩn $U$ (*Unobserved Confounder*).
5. **Đóng gói REST API & Phục vụ Thời gian thực:** Triển khai mô hình IViDR lên FastAPI, kết nối Google Colab qua Cloudflare Tunnel và tích hợp vào App Flutter TopTop.

---

## 📚 2. Cơ sở lý thuyết chi tiết (Chương I - Phần 2)

### 2.1. Neural Collaborative Filtering (NCF / NeuMF)
* **Ý tưởng:** Phân tích ma trận cổ điển bị giới hạn bởi tính tuyến tính của tích vô hướng ($p_u^T q_i$). NCF khắc phục bằng cách xếp chồng các lớp ẩn phi tuyến:
  $$\hat{y}_{ui} = \sigma \left( h^T \left[ \phi^{\text{GMF}} \oplus \phi^{\text{MLP}} \right] \right)$$
  - $\phi^{\text{GMF}} = p_u^G \odot q_i^G$ (Tương tác tuyến tính Hadamard).
  - $\phi^{\text{MLP}} = a_L \left( W_L^T (\dots a_1(W_1^T [p_u^M, q_i^M] + b_1) \dots) + b_L \right)$ (Tương tác phi tuyến tính bậc cao).

### 2.2. Mạng nơ-ron Biến phân có thể định danh (Identifiable VAE)
* **Giới hạn của VAE thông thường:** Phân phối tiên nghiệm chuẩn $p(z) = \mathcal{N}(0, I)$ khiến các biến ẩn bị xoay tùy ý, không đảm bảo tính định danh (*Non-identifiable*).
* **iVAE giải quyết:** Đưa proxy ngữ cảnh hiển thị $W$ vào làm điều kiện tiên nghiệm $p(C \mid W)$:
  $$p(C \mid W) = \frac{\prod_k Q_k(C_k)}{Z(W)} \exp \left( \sum_{k=1}^K T_{k}(C_k) \lambda_{k}(W) \right)$$
* Mạng nơ-ron học cách phân tách biến ẩn hiển thị $C$ độc lập về mặt thống kê.

### 2.3. Mô hình Lọc cộng tác Học sâu & Nhân quả IViDR (Deep Causal CF)
* **Sơ đồ kiến trúc 2 nhánh:**
  ```text
  [ Thuộc tính User X ] ──► [ IV Projection ] ──────────────► [ Sở thích sạch Z ] ──┐
                                                                                   ├──► Điểm số s_ui
  [ Proxy ngữ cảnh W ] ──► [ iVAE Encoder ] ──► [ Biến ẩn C ] ──► [ Exposure Decoder ] │
                               ▲                                                     │
                        (Kullback-Leibler)                                           │
                               ▼                                                     │
                        [ Prior p(C|W) ] ────────────────────────────────────────────┘
  ```
* **Dự đoán điểm số:** Khi đưa ra đề xuất cho người dùng, mô hình **chỉ sử dụng thành phần sạch $Z$ kết hợp cùng embedding MF và loại bỏ hoàn toàn biến ẩn $C$**:
  $$\hat{s}_{ui} = p_u^T q_i + Z_u$$

---

## 🔬 3. Kế hoạch triển khai & Kết quả thực nghiệm Phần 2 (Chương II - Phần 2)

### 3.1. Các mô hình xây dựng:
1. **Kiến trúc iVAE Encoder-Decoder:** Mạng nơ-ron học sâu tối ưu hàm ELBO (Evidence Lower Bound) có điều kiện tiên nghiệm.
2. **Nhánh chiếu biến công cụ IV Projection:** Chiếu hồi quy phi tuyến tính từ vector đặc trưng người dùng.
3. **Mô hình IViDR hoàn chỉnh:** Tích hợp huấn luyện kết thúc - tới - kết thúc (*End-to-End*).

### 3.2. Kết quả đo lường định lượng vượt trội:
* **Trên tập Coat (Candidate Pool 16 items):**
  - **IViDR dẫn đầu toàn diện mọi chỉ số:**
    - Test NDCG@5 = **0.5454** (Vượt Baseline MF tới $+8.25\%$).
    - Test Recall@5 = **0.5714** (Vượt Baseline MF $+8.16\%$).
    - Test HitRate@5 = **0.8980** (Trúng $89.8\%$ nhu cầu người xem).
    - Test AUC Macro = **0.7064** (Vượt Baseline MF $+6.04\%$).
* **Trên tập video ngắn KuaiRand-Pure (1.413.574 tương tác):**
  - IViDR duy trì vị trí quán quân: Test NDCG@5 = **0.3484** (cao nhất trong toàn bộ các mô hình).

### 3.3. Đóng gói REST API & Tích hợp vào Ứng dụng TopTop:
* Đóng gói mô hình IViDR thành module FastAPI phục vụ gợi ý thời gian thực.
* Tự động hóa với Cloudflare Tunnel và Firebase RTDB.
* Tích hợp thành công vào app Flutter TopTop: lướt feed video ngắn được phục vụ trực tiếp bởi AI IViDR từ Colab.

---

## 📅 4. Phân công & Sản phẩm bàn giao Phần 2

* **Mã nguồn:** Module `src/causal/ividr/`, `src/api/`, `notebooks/TopTop_RecSys_Colab_API.ipynb`.
* **Báo cáo chuyên đề:** Chương I & Chương II (Phần Học sâu Deep Learning và Triển khai API).
* **Kiểm thử tự động:** Bộ kiểm thử đơn vị cho iVAE, IV Projection, API Server đạt 100% Passed.
