> **ĐỀ CƯƠNG, KHÔNG PHẢI BÁO CÁO KẾT QUẢ.** Điểm số và giới hạn: [CURRENT_STATE](../CURRENT_STATE.md).

# Đề cương chi tiết, Phần 2: Học sâu trong hệ thống gợi ý

**Phụ trách chính:** Phùng Nguyễn Hoài Bo (2312585, CTK47A). **Giáo viên hướng dẫn:** TS. Nguyễn Thị Lương.
[Đề cương tổng hợp](DeCuong_NghienCuuUngDungHocMayDeXuatVideoNgan.md).

## 1. Mục tiêu

1. Tìm hiểu kiến trúc mạng nơ-ron trong gợi ý, từ NCF đến các mô hình sinh biến phân.
2. Dùng iVAE học biến nhiễu tiềm ẩn $C$ từ dữ liệu hiển thị, với proxy $W$ để bảo đảm tính định danh.
3. Nghiên cứu biến công cụ (Instrumental Variable) trong học sâu, xử lý đồng thời biến nhiễu quan sát được và không quan sát được.
4. Triển khai và so sánh iDCF, IViDR, LCDR.
5. Đóng gói API và tích hợp vào ứng dụng TopTop.

## 2. Cơ sở lý thuyết

### 2.1. Neural Collaborative Filtering (phần tổng quan)

NCF thay tích vô hướng bằng các lớp ẩn phi tuyến, kết hợp GMF và MLP:

$$\hat{y}_{ui} = \sigma \left( h^T \left[ \phi^{\text{GMF}} \oplus \phi^{\text{MLP}} \right] \right)$$

Đây là nền lý thuyết của Chương I, không thuộc bộ mô hình thực nghiệm: NCF không xử lý thiên lệch hiển thị.

### 2.2. Identifiable VAE

Prior chuẩn $p(z)=\mathcal{N}(0,I)$ không bảo đảm khôi phục đúng biến ẩn. iVAE đưa proxy $W$ vào tiên nghiệm có điều kiện:

$$p(C \mid W) = \frac{\prod_k Q_k(C_k)}{Z(W)} \exp \left( \sum_{k=1}^K T_{k}(C_k) \lambda_{k}(W) \right)$$

Dự án dùng tiên nghiệm Gaussian, tối ưu ELBO trên vector hiển thị nhị phân $A_u$, có KL warm-up.

### 2.3. Biến công cụ

Biến công cụ $Z$ cần tương quan với quyết định hiển thị (relevance), độc lập với biến nhiễu ẩn (unconfoundedness) và chỉ tác
động tới hành vi qua hiển thị (exclusion restriction).

### 2.4. iDCF

Mô hình hai giai đoạn. Giai đoạn 1: iVAE học $q(C \mid A, W)$. Giai đoạn 2: feedback model giữ $C$ cố định:

$$\hat{s}_{ui} = \text{MF}(u, i) + \langle e_i, C_u \rangle$$

Huấn luyện bằng MSE với 10 mẫu $C$, suy luận dùng trung bình của $C$.

### 2.5. IViDR

Cùng khung hai giai đoạn. Giai đoạn 1 học biến công cụ để tái dựng treatment, rồi cho hai posterior cùng tái tạo $A$:

$$T^{re} = \alpha_1 T^{fit} + \alpha_2 T^{res}, \qquad C = \rho C_1 + \tau C_2$$

Giai đoạn 2 lấy kỳ vọng xác suất trước BCE: $p = \mathbb{E}_C[\sigma(\hat{s}_{ui})]$. Mô hình **giữ** $C$ trong dự đoán, không loại bỏ nó.
Paper không định nghĩa phép đổi kích thước ở Eq. (10), dự án tự hoàn thiện và công bố trong
[đặc tả IViDR](../benchmarks/ividr_reference_20261022.md). Cấu hình mặc định lệch paper ở prior mean và trọng số mẫu âm BCE.

### 2.6. LCDR

Thêm một VAE $q(Z_{lc} \mid A)$ không cần proxy, được ràng buộc về gần biểu diễn của iVAE bằng $\lambda \|Z_{lc} - Z\|_2$. Giai đoạn
feedback dùng $Z_{lc}$ theo khung iDCF. Không có mã tác giả, dự án cài đặt lại từ paper.

## 3. Kế hoạch triển khai

| Mô hình | Cách thực hiện | Feedback |
| :-- | :-- | :-- |
| **iDCF** | Theo mã tác giả: iVAE rồi MF + latent | MSE |
| **IViDR** | Theo công thức arXiv, learned IV + dual iVAE, treatment lấy từ MF; quét 10 cặp LR/WD trên validation | BCE kỳ vọng |
| **LCDR** | Cài đặt lại từ paper trên pipeline iDCF | MSE |

Cả ba dùng protocol H30, chọn checkpoint bằng validation NDCG@5, chấm test một lần. Coat báo cáo nhiều seed vì dữ liệu nhỏ.
Phân tích khoảng cách với paper: [IViDR](../benchmarks/ividr_root_cause_20261027.md),
[LCDR và ConAlign](../benchmarks/lcdr_conalign_20261027.md).

### API và tích hợp

- FastAPI với `/api/v1/recommend` và `/api/v1/interaction`, phục vụ MF và DR-BIAS + CDR; người dùng mới dùng popularity.
- IViDR chưa phục vụ trên app vì dữ liệu TopTop chưa có đặc trưng người dùng làm biến công cụ và proxy.
- Chạy trên Google Colab qua Cloudflare Tunnel, ghi URL vào Firebase Realtime Database (`server_config/recsys_url`).
- Ứng dụng Flutter tự phát hiện URL, tự chuyển về Firestore khi máy chủ AI ngoại tuyến.

## 4. Sản phẩm bàn giao

- **Mã nguồn:** `src/models/idcf/`, `src/models/ividr/`, `src/models/lcdr/`, `src/api/`, `notebooks/TopTop_RecSys_Colab_API.ipynb`.
- **Báo cáo:** Chương I và Chương II, phần Học sâu và triển khai API.
- **Kiểm thử:** `tests/`, chạy bằng `experiments/run.py test`.
