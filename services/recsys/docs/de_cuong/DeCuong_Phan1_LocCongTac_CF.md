> **ĐỀ CƯƠNG, KHÔNG PHẢI BÁO CÁO KẾT QUẢ.** Điểm số và giới hạn: [CURRENT_STATE](../CURRENT_STATE.md).

# Đề cương chi tiết, Phần 1: Lọc cộng tác (Collaborative Filtering)

**Phụ trách chính:** Vũ Thế Huỳnh (2312639, CTK47A). **Giáo viên hướng dẫn:** TS. Nguyễn Thị Lương.
[Đề cương tổng hợp](DeCuong_NghienCuuUngDungHocMayDeXuatVideoNgan.md).

## 1. Mục tiêu

1. Khảo sát lý thuyết Lọc cộng tác, từ phương pháp dựa trên bộ nhớ đến Matrix Factorization.
2. Khai thác phản hồi của người dùng: rating (Coat, Yahoo! R3), click (KuaiRand-Pure) và hành vi trên ứng dụng TopTop
   (like hoặc xem từ 3 giây).
3. Nghiên cứu thiên lệch hiển thị: dữ liệu thiếu không ngẫu nhiên (MNAR) khiến CF truyền thống nhầm tương quan quan sát
   $P(Y \mid O=1)$ với sở thích thật.
4. Triển khai Lọc cộng tác khử thiên lệch: DR-BIAS + CDR và ConAlign.

## 2. Cơ sở lý thuyết

### 2.1. Lọc cộng tác dựa trên bộ nhớ

User-based CF dự đoán dựa trên độ tương đồng giữa người dùng:

$$\text{sim}(u, v) = \frac{\sum_{i \in I_{uv}} (r_{ui} - \bar{r}_u)(r_{vi} - \bar{r}_v)}{\sqrt{\sum_{i \in I_{uv}} (r_{ui} - \bar{r}_u)^2} \sqrt{\sum_{i \in I_{uv}} (r_{vi} - \bar{r}_v)^2}}$$

Item-based CF tìm các video có tập người xem tương đồng để đề xuất chéo.

### 2.2. Matrix Factorization

Phân rã ma trận tương tác thành embedding người dùng $p_u$ và video $q_i$. Dự án dùng điểm thô có bias, không có intercept:

$$\hat{s}_{ui} = p_u^T q_i + b_u + b_i$$

Hàm mục tiêu là MSE trên điểm thô, theo mã iDCF, tối ưu bằng Adam:

$$\mathcal{L}_{\text{MF}} = \frac{1}{|\mathcal{O}|} \sum_{(u,i) \in \mathcal{O}} (\hat{s}_{ui} - y_{ui})^2 + \lambda \|\Theta\|^2$$

### 2.3. Thiên lệch hiển thị và CDR

MF chỉ tối ưu trên các tương tác đã quan sát $\mathcal{O}$. Doubly Robust kết hợp mô hình bù đắp (imputation) với nghịch đảo
xác suất hiển thị (IPS). CDR dùng Monte Carlo Dropout để loại các giá trị bù đắp không đáng tin, theo Eq. (7) của paper:

$$\mathcal{L}_{\text{CDR}} = \frac{1}{|\mathcal{D}|} \sum_{(u,i) \in \mathcal{D}} \left( \frac{o_{ui} e_{ui}}{\hat{p}_{ui}} + \gamma_{ui} \hat{e}_{ui} \left( 1 - \frac{o_{ui}}{\hat{p}_{ui}} \right) \right)$$

$\hat{e}_{ui}$ là sai số ước lượng, $\hat{p}_{ui}$ là propensity, $\gamma_{ui} \in \{0,1\}$ cho biết giá trị bù đắp có được giữ lại không.
Bộ lọc dựa trên phương sai của $\hat{e}_{ui}$; khi bị loại, số hạng đó về IPS. Mã công bố khác paper ở một số chi tiết:
[định nghĩa mô hình](../benchmarks/paper_model_alignment.md).

### 2.4. ConAlign

MF hai tháp: tháp biased học trên log thường, tháp unbiased học trên log ngẫu nhiên và được căn chỉnh theo tháp biased
qua alignment loss. Đầu ra cuối là tháp unbiased.

## 3. Kế hoạch triển khai

| Mô hình | Cách thực hiện | Protocol |
| :-- | :-- | :-- |
| **MF** | Baseline, MSE, embedding 64 chiều | H30 |
| **DR-BIAS + CDR** | Tích hợp bản công bố của tác giả, BCE, dim 4, huấn luyện độc lập với MF | CDR source |
| **ConAlign** | Port từ source tác giả, seed 0 | ConAlign source |

Đánh giá trên random log: NDCG@5, Recall@5, Precision@5, HitRate@5, AUC. Ba protocol khác nhau về nhãn và tập chấm nên không
so trực tiếp ([giao thức](../benchmarks/evaluation_protocol.md)). Lý do CDR đạt điểm cao theo script tác giả:
[phân tích](../benchmarks/root_cause_analysis.md).

## 4. Sản phẩm bàn giao

- **Mã nguồn:** `src/models/mf/`, `src/models/cdr/`, `src/models/conalign/`.
- **Báo cáo:** Chương I và Chương II, phần Lọc cộng tác.
- **Kiểm thử:** `tests/`, chạy bằng `experiments/run.py test`.
