> **ĐỀ CƯƠNG, KHÔNG PHẢI BÁO CÁO KẾT QUẢ.** Điểm số và giới hạn: [CURRENT_STATE](../CURRENT_STATE.md).

# Đề cương chi tiết, Phần 2: Học sâu trong hệ thống gợi ý

**Phụ trách chính:** Phùng Nguyễn Hoài Bo (2312585, CTK47A). **Giáo viên hướng dẫn:** TS. Nguyễn Thị Lương.
[Đề cương tổng hợp](DeCuong_NghienCuuUngDungHocMayDeXuatVideoNgan.md).

## 1. Mục tiêu

1. Tìm hiểu kiến trúc mạng nơ-ron trong gợi ý, từ NCF đến các mô hình sinh biến phân và mô hình khử thiên lệch sâu.
2. Dùng iVAE học biến nhiễu tiềm ẩn $C$ từ dữ liệu hiển thị, với proxy $W$ để bảo đảm tính định danh (iDCF).
3. Nghiên cứu phương pháp ràng buộc biểu diễn tiềm ẩn (LCDR) và các hướng tiếp cận nhân quả sâu mới: hiệu chỉnh độ bất định (MRDR-CAL) và xử lý biến ngoại sinh tiềm ẩn (CLEV-DR).
4. Triển khai và so sánh các mô hình học sâu: iDCF, LCDR, CLEV-DR, MRDR-CAL đối chứng với NeuMF.
5. Đóng gói API và tích hợp vào ứng dụng TopTop.

## 2. Cơ sở lý thuyết

### 2.1. Neural Collaborative Filtering (phần tổng quan)

NCF thay tích vô hướng bằng các lớp ẩn phi tuyến, kết hợp GMF và MLP:

$$\hat{y}_{ui} = \sigma \left( h^T \left[ \phi^{\text{GMF}} \oplus \phi^{\text{MLP}} \right] \right)$$

NCF không xử lý thiên lệch hiển thị. Dự án dùng NeuMF làm mô hình học sâu đối chứng với MF, theo mã tác giả
(embedding 8, MLP [64, 32, 16, 8], BCE với 4 mẫu âm, Adam lr 1e-3, batch 256, 100 epoch).

### 2.2. Identifiable VAE

Prior chuẩn $p(z)=\mathcal{N}(0,I)$ không bảo đảm khôi phục đúng biến ẩn. iVAE đưa proxy $W$ vào tiên nghiệm có điều kiện:

$$p(C \mid W) = \frac{\prod_k Q_k(C_k)}{Z(W)} \exp \left( \sum_{k=1}^K T_{k}(C_k) \lambda_{k}(W) \right)$$

Dự án dùng tiên nghiệm Gaussian, tối ưu ELBO trên vector hiển thị nhị phân $A_u$, có KL warm-up.

### 2.3. CLEV-DR (Zhang et al., KDD 2025)

Khử thiên lệch khi tồn tại biến ngoại sinh tiềm ẩn có tương quan (Correlated Latent Exogenous Variables). Mô hình sử dụng 4 tháp NCF: dự đoán rating $g_y$, xu hướng hiển thị probit $g_o$, tháp IPS hiệu chỉnh và tháp bù đắp (imputation), kết hợp hệ số tương quan $\rho = \tanh(\rho_v)$ ước lượng qua tích phân Monte Carlo.

### 2.4. iDCF

Mô hình hai giai đoạn. Giai đoạn 1: iVAE học $q(C \mid A, W)$. Giai đoạn 2: feedback model giữ $C$ cố định:

$$\hat{s}_{ui} = \text{MF}(u, i) + \langle e_i, C_u \rangle$$

Huấn luyện bằng MSE với 10 mẫu $C$, suy luận dùng trung bình của $C$.

### 2.5. MRDR-CAL (Hu et al., TKDE 2025)

Mô hình Doubly Robust giảm thiểu phương sai tối đa (MRDR) kết hợp hiệu chỉnh độ bất định bằng Platt Scaling trên nền tảng NeuMF. Propensity score được chuẩn hóa nhằm triệt tiêu thiên lệch hiển thị cực đoan trong không gian user–item thưa.

### 2.6. LCDR

Thêm một VAE $q(Z_{lc} \mid A)$ không cần proxy, được ràng buộc về gần biểu diễn của iVAE bằng $\lambda \|Z_{lc} - Z\|_2$. Giai đoạn
feedback dùng $Z_{lc}$ theo khung iDCF. Không có mã tác giả, dự án cài đặt lại từ paper.

## 3. Kế hoạch triển khai

| Mô hình | Cách thực hiện | Feedback / Giao thức |
| :-- | :-- | :-- |
| **iDCF** | Theo mã tác giả: iVAE rồi MF + latent | MSE (H30) |
| **LCDR** | Cài đặt lại từ paper trên pipeline iDCF | MSE (H30) |
| **NeuMF** | Theo mã tác giả NCF, chạy bằng `cf-dl` để so với MF | BCE, 4 mẫu âm (H30) |
| **CLEV-DR** | Port từ mã tác giả KDD 2025, 4 tháp NCF + Monte Carlo | Probit + BCE (protocol tác giả) |
| **MRDR-CAL** | Cài đặt theo Hu et al. (TKDE 2025) + Guo et al. | Platt + MRDR loss (protocol tác giả) |

*(Ghi chú: Mô hình IViDR đã được nhóm nghiên cứu độc lập và loại khỏi danh mục chính do tác giả không công bố mã nguồn và mục tiêu BCE làm suy giảm điểm xếp hạng, xem [phân tích nguyên nhân](../benchmarks/ividr_root_cause_20261027.md)).*

Coat báo cáo nhiều seed vì dữ liệu nhỏ. Phân tích chi tiết:
[LCDR và ConAlign](../benchmarks/lcdr_conalign_20261027.md).

### API và tích hợp

- FastAPI với `/api/v1/recommend` và `/api/v1/interaction`, phục vụ MF và DR-BIAS + CDR; người dùng mới dùng popularity.
- Chạy trên Google Colab qua Cloudflare Tunnel, ghi URL vào Firebase Realtime Database (`server_config/recsys_url`).
- Ứng dụng Flutter tự phát hiện URL, tự chuyển về Firestore khi máy chủ AI ngoại tuyến.

## 4. Sản phẩm bàn giao

- **Mã nguồn:** `src/models/idcf/`, `src/models/lcdr/`, `src/models/clev/`, `src/models/mrdr_cal/`, `src/models/ncf/`, `src/api/`, `notebooks/TopTop_RecSys_Colab_API.ipynb`.
- **Báo cáo:** Chương I và Chương II, phần Học sâu và triển khai API.
- **Kiểm thử:** `tests/`, chạy bằng `experiments/run.py test`.
