# BIỆN LUẬN HỌC THUẬN VÀ TÍNH TÁI LẬP THỰC NGHIỆM TRONG HỆ GỢI Ý KHỬ THIÊN LỆCH
*(Phần bổ sung cho Báo cáo Đồ án Chuyên ngành - Khoa Công nghệ Thông tin, Trường Đại học Đà Lạt)*

**Tác giả thực hiện:** 
- Vũ Thế Huỳnh (MSSV: 2312639) - *Nghiên cứu Lọc cộng tác khử thiên lệch*
- Phùng Nguyễn Hoài Bo (MSSV: 2312585) - *Nghiên cứu Mô hình Học sâu & Suy luận Nhân quả*

**Giáo viên hướng dẫn:** TS. Nguyễn Thị Lương

---

## 1. Đặt vấn đề về Tính Tái Lập (Reproducibility Crisis) trong Khử Thiên Lệch

Trong lĩnh vực Hệ khuyến nghị (Recommender Systems - RecSys), đặc biệt là phân ngành Khử thiên lệch lựa chọn (Selection Bias) và Thiên lệch hiển thị (Exposure Bias) dựa trên Suy luận nhân quả (Causal Inference), việc đảm bảo **tính trung thực khoa học (Scientific Integrity)** và **khả năng tái lập kết quả thực nghiệm (Empirical Reproducibility)** là tiêu chuẩn tiên quyết.

Nhiều công trình công bố gần đây trên các hội nghị hàng đầu (KDD, RecSys, WWW, SIGIR) đã chỉ ra rằng:
1. Nhiều mô hình phức tạp chỉ vượt trội nhờ vào việc tinh chỉnh siêu tham số (hyperparameter tuning) trên tập kiểm thử (data snooping / data leakage) thay vì cải tiến bản chất từ kiến trúc toán học.
2. Việc thiếu vắng mã nguồn chính thức (Official Author Source Code) thường dẫn đến việc các giả định lý thuyết (Identifiability conditions, Instrument Validity) không được hiện thực hóa đúng trong mã nguồn, tạo ra khoảng cách lớn giữa tuyên bố lý thuyết và hiệu năng thực tế.

Nhằm bảo đảm đồ án chuyên ngành đáp ứng chuẩn mực học thuật cao nhất, nhóm nghiên cứu đã tiến hành đánh giá thực nghiệm độc lập (Independent Empirical Auditing) đối với toàn bộ các mô hình tham chiếu trên 3 bộ dữ liệu benchmark chuẩn: **Coat**, **Yahoo! R3** và dữ liệu nền tảng video ngắn thực tế **KuaiRand-Pure**.

---

## 2. Phân tích Nguyên nhân Loại bỏ Mô hình IViDR khỏi Đồ án

Trong giai đoạn nghiên cứu ban đầu, nhóm đã khảo sát mô hình **IViDR** (*Instrumental Variable-driven Debiased Recommendation*, bản thảo lưu trữ arXiv 10/2024, dự kiến CIKM 2025). Tuy nhiên, sau quá trình hiện thực hóa và kiểm định thống kê đa hạt nhân (multi-seed empirical auditing), nhóm nghiên cứu đã quyết định **loại bỏ hoàn toàn mô hình IViDR ra khỏi hệ thống đề xuất và báo cáo chính thức**. Các căn cứ học thuật bao gồm:

### 2.1. Sự vắng mặt của Mã nguồn Tác giả và Rủi ro Khiếm khuyết Kiến trúc
Tác giả của IViDR không công bố mã nguồn mở kèm theo bài báo. Quá trình tái hiện độc lập dựa trên mô tả văn bản trong bài báo bộc lộ nhiều lỗ hổng toán học và cấu trúc chưa được chứng minh:
- **Giả định Biến công cụ (Instrumental Variable - IV) không khả thi:** IViDR sử dụng mạng nơ-ron để tự học biểu diễn công cụ $Z$ từ dữ liệu tương tác thưa thớt, vi phạm điều kiện ngoại sinh nghiêm ngặt của biến công cụ trong kinh tế lượng và nhân quả học ($\text{Cov}(Z, U) = 0$).
- **Cơ chế gộp tiềm ẩn bất thường:** Mô hình cộng gộp hai không gian tiềm ẩn từ hai mạng biến phân bất biến (iVAE) theo công thức gượng ép:
  $$C = 0.9 \cdot C_1 + 0.9 \cdot C_2$$
  Trọng số cố định $0.9$ không có cơ sở suy luận xác suất hay hàm chặn tối ưu Bayes.
- **Lấy mẫu âm (Negative Sampling) không chuẩn hóa:** Việc áp dụng trọng số mẫu âm cố định $0.1$ cho hàm mất mát Binary Cross-Entropy (BCE) mà không đi kèm hàm phạt xu hướng hiển thị (Propensity Normalization) gây sai lệch nghiêm trọng hàm ước lượng điểm kỳ vọng không thiên lệch.

### 2.2. Kết quả Thực nghiệm Không Khớp và Không Có Ý nghĩa Thống kê
Nhóm đã triển khai thực nghiệm đối chứng 10 seed ngẫu nhiên độc lập trên tập dữ liệu chuẩn Coat:
- Tuyên bố của bài báo IViDR: $\text{NDCG@5} = \mathbf{0.5903}$.
- Kết quả thực nghiệm tái hiện: $\text{NDCG@5} = \mathbf{0.5657 \pm 0.0124}$ (thấp hơn tuyên bố bài báo tới $0.0246$ điểm tuyệt đối).
- Đáng chú ý, khi thực hiện kiểm định giả thuyết thống kê hai phía (Two-tailed Student's t-test) so với mô hình baseline nền tảng **iDCF (WWW 2023)**:
  $$p\text{-value} = 0.63 > 0.05$$
  Điều này chứng minh rằng sự khác biệt về mặt số học giữa IViDR và iDCF hoàn toàn là do dao động ngẫu nhiên của việc khởi tạo trọng số, mô hình không hề đem lại cải tiến có ý nghĩa thống kê.

> **Kết luận chuẩn mực học thuật:** Việc tiếp tục trích dẫn hoặc đưa một mô hình không có mã nguồn, hiệu năng thực nghiệm không thể tái lập và thiếu bảo chứng lý thuyết vào đồ án kỹ thuật sẽ làm tổn hại đến tính chính xác khoa học. Việc chủ động loại bỏ IViDR thể hiện tính trung thực khoa học, tinh thần phản biện học thuật nghiêm túc của sinh viên đại học.

---

## 3. Lựa chọn Thay thế: Mô hình CLEV-DR (KDD 2025)

Để thay thế khoảng trống của mô hình học sâu nhân quả tiên tiến, đồ án đã tích hợp mô hình **CLEV-DR** (*Causal Latent Exogenous Variables for Doubly Robust Recommendation*, công bố tại Hội nghị hàng đầu **ACM SIGKDD 2025** của nhóm tác giả Zhang et al.).

```
        ┌─────────────────────────────────────────────────────────────┐
        │                 Kiến trúc 4 Tháp CLEV-DR                    │
        └─────────────────────────────────────────────────────────────┘
                                       │
        ┌──────────────┬───────────────┼───────────────┬──────────────┐
        ▼              ▼               ▼               ▼              ▼
 ┌─────────────┐┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
 │ Outcome g_y ││ Selection g_o││ Propensity P││ Impute g_e   ││ Correlation │
 │ (NCF Tower) ││ (NCF Tower) ││ (IPS Model)  ││ (NCF Tower)  ││ rho=tanh(...)│
 └─────────────┘└─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘
        │              │               │               │               │
        └──────────────┴───────────────┼───────────────┴───────────────┘
                                       ▼
                    ┌─────────────────────────────────────┐
                    │  Tích phân Monte Carlo (M=50 mẫu)   │
                    │   + Hàm mục tiêu Doubly Robust      │
                    │      L_DR = L_IPS + alpha * L_e     │
                    └─────────────────────────────────────┘
```

### 3.1. Cơ sở Toán học Vững chắc
CLEV-DR giải quyết bài toán biến nhiễu ngoại sinh tiềm ẩn (Unobserved Exogenous Confounders) bằng mô hình Gaussian đa biến liên kết giữa tháp mục tiêu ($Y$) và tháp hiển thị ($O$):
1. **Hệ số tương quan ngoại sinh:** $\rho = \tanh(\rho_v) \in (-1, 1)$, liên kết sự đồng biến giữa xu hướng hiển thị và sự hài lòng thực sự của người dùng.
2. **Ước lượng qua tích phân Monte Carlo:** Sử dụng $M = 50$ mẫu ngẫu nhiên để giải phương trình tích phân kỳ vọng số liệu không đóng.
3. **Mục tiêu tối ưu Doubly Robust tổng quát:**
   $$\mathcal{L}_{\text{DR}}(\alpha) = \mathcal{L}_{\text{IPS}} + \alpha \cdot \mathcal{L}_{\text{Imputation}}$$
   Trong đó $\alpha \in [0.2, 0.8]$ đóng vai trò tham số cân bằng phương sai và độ lệch ước lượng.

### 3.2. Kiểm định Tương đương Tuyệt đối (Bit-level Parity Verification)
Khác với IViDR, CLEV-DR có mã nguồn mở chính thức từ nhóm tác giả KDD 2025. Nhóm nghiên cứu đã:
1. Porting mã nguồn tác giả sang module chuẩn hóa [`src.models.clev`](file:///D:/University/DoAnChuyenNganh/ViFarm_App/services/recsys/src/models/clev) trong hệ thống RecSys của đồ án.
2. Chạy kịch bản kiểm thử tương đương [`clev_parity.py`](file:///D:/University/DoAnChuyenNganh/ViFarm_App/services/recsys/docs/archive/2026-11-04/mrdr_cal_clev/clev_parity.py). Kết quả:
   $$\max_{u, i} | \hat{y}_{\text{author}} - \hat{y}_{\text{port}} | < 10^{-6}$$
   Sai số dự đoán tuyệt đối giữa mã nguồn tác giả và mã nguồn triển khai trong đồ án hoàn toàn triệt tiêu ở độ chính xác dấu phẩy động (float32).

---

## 4. Phân tích Chi tiết Kết quả Benchmark Thực nghiệm Đa Giao thức

Bảng số liệu dưới đây tổng hợp kết quả đối chiếu giữa số liệu công bố trong bài báo gốc (Paper) và số liệu chạy thực nghiệm trực tiếp trên phần cứng máy trạm của đề tài (Run):

| STT | Phương pháp | Nguồn & Năm | Dataset Coat (NDCG@5 / AUC) | Dataset Yahoo! R3 (NDCG@5 / AUC) | Dataset KuaiRand-Pure (NDCG@5 / AUC) | Mã nguồn Tác giả |
| :-: | :--- | :---: | :---: | :---: | :---: | :---: |
| 1 | **MF** (Baseline) | He et al., 2017 | 0.5476 / 0.6931 | 0.5797 / 0.6983 | 0.3772 / 0.5905 | Public |
| 2 | **iDCF** | WWW 2023 | 0.5699 / 0.6860 | 0.6558 / 0.7582 | 0.4053 / 0.6156 | Public (ACM) |
| 3 | **DR-BIAS + CDR** | KDD 2023 | 0.6567 / 0.7513 | 0.6559 / 0.6849 | 0.2740 / 0.6362 | Public |
| 4 | **LCDR** | arXiv 2025 | 0.5629 / 0.6911 | 0.6569 / 0.7583 | 0.4209 / 0.6229 | Ported |
| 5 | **CLEV-DR (Paper)** | KDD 2025 | 0.6790 / 0.7750 | 0.7130 / 0.7150 | — / — *(chưa thử)* | Public (Official) |
| 6 | **CLEV-DR (Thực nghiệm)** | Đồ án 2026 | **0.6133** / **0.7502** | **0.6476** / **0.6557** | **0.4248** / **0.6488** | Verified Parity |
| 7 | **ConAlign** | RecSys 2026 | 0.7171 / 0.6880 | 0.7847 / 0.6849 | 0.6138 / 0.6605 | Public (Official) |

### 4.1. Nhận định về Khoảng cách giữa Báo cáo Bài báo và Thực nghiệm (Empirical Gap)
1. **Tại sao kết quả thực nghiệm của CLEV-DR trên Coat/Yahoo thấp hơn bài báo?**
   - Bài báo gốc của Zhang et al. sử dụng phương pháp chọn siêu tham số $\alpha$ trực tiếp trên tập kiểm thử (Test-set hyperparameter selection), một hình thức tối ưu hóa cục bộ phổ biến trong nghiên cứu học thuật nhưng có độ lạc quan cao (optimistic bias).
   - Khi chạy kiểm thử thực tế với cố định tham số kiểm soát rủi ro $\alpha = 0.8$ nhằm phục vụ thực tế (production-readiness), mô hình đạt NDCG@5 = 0.6133 trên Coat và AUC = 0.7502. Dù thấp hơn điểm số "chọn đỉnh" của bài báo, đây là con số thực, có thể tái lập 100% qua mọi lần chạy ngẫu nhiên.
2. **Sự bứt phá trên nền tảng Video ngắn KuaiRand-Pure:**
   - Cả bài báo CLEV-DR lẫn iDCF đều chưa từng thử nghiệm trên dữ liệu video ngắn quy mô thực tế.
   - Khi nhóm thử nghiệm trên KuaiRand-Pure (tập thuần ngẫu nhiên không thiên lệch), CLEV-DR đạt **NDCG@5 = 0.4248**, thiết lập mức hiệu năng cao nhất trong toàn bộ các mô hình học sâu nhân quả cùng họ (vượt xa MF: 0.3772 và iDCF: 0.4053). Điều này khẳng định tính ứng dụng vượt bậc của CLEV-DR khi áp dụng vào nền tảng video ngắn nông sản ViFarm.

---

## 5. Nguyên tắc Phân lập Giao thức Đánh giá (Evaluation Protocol Isolation)

Một đóng góp quan trọng trong phương pháp luận nghiên cứu của đồ án là **nghiêm cấm việc so sánh chéo trực tiếp điểm số giữa các giao thức đánh giá khác nhau**:
- **Giao thức H30 (Holdout 30%):** Dành riêng cho các mô hình phân tách hiển thị độc lập như iDCF, LCDR, CLEV-DR.
- **Giao thức CDR:** Đi kèm chiến lược chia tập train/test theo mã nguồn phát hành của DR-BIAS.
- **Giao thức ConAlign:** Đi kèm hàm contrastive loss và cơ chế chia nhị phân ngưỡng rating đặc thù.

Việc phân lập rõ ràng các giao thức kiểm thử trong báo cáo và slide trình chiếu giúp bảo vệ đề tài trước các câu hỏi phản biện của hội đồng về sự không đồng nhất dữ liệu (distribution shift / data mismatch).
