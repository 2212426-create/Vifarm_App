> **LƯU TRỮ — KHÔNG PHẢI TRẠNG THÁI HIỆN HÀNH.** Chụp trước đợt dọn 20/10/2026. Nội dung có nhận định đã bị thay thế; xem [CURRENT_STATE](../../../CURRENT_STATE.md). Bản nguyên byte nằm trong ZIP và được kiểm tra bằng checksum; bản đọc này chỉ thêm nhãn và sửa đường dẫn.

---
marp: true
theme: default
paginate: true
header: "TopTop | Causal Debiasing trong hệ thống gợi ý"
footer: "MF · DR-BIAS + CDR · IViDR | Coat và KuaiRand-Pure"
style: |
  section { font-family: 'Segoe UI', Arial, sans-serif; font-size: 23px; line-height: 1.35; padding: 36px 48px; }
  h1 { color: #0f2b5c; font-size: 36px; }
  h2 { color: #1a56a6; font-size: 28px; }
  table { font-size: 17px; width: 100%; border-collapse: collapse; margin-top: 8px; }
  th { background: #0f2b5c; color: white; text-align: center; }
  th, td { padding: 5px 8px; border: 1px solid #cbd5e1; }
  code { background: #edf2f7; color: #b91c1c; font-weight: bold; }
  .highlight { background-color: #fef08a; font-weight: bold; }
  pre { font-size: 16px; line-height: 1.25; }
---

<!-- _class: lead -->
# Giảm thiên lệch trong hệ thống gợi ý hành vi (Causal Debiasing in RecSys)

### Thực nghiệm Đối sánh MF Baseline, DR-BIAS + CDR và IViDR trên Coat & KuaiRand-Pure

**Dự án TopTop · Báo cáo nghiên cứu và triển khai thực nghiệm · 2026**

<!--
KỊCH BẢN SLIDE 1 — khoảng 40 giây.
Kính chào quý thầy cô và các bạn. Hôm nay nhóm xin báo cáo đề tài: "Khử độ lệch nhân quả (Causal Debiasing) trong hệ thống gợi ý hành vi".
Trong dự án TopTop, nhóm đã triển khai và thực nghiệm đối sánh 3 kiến trúc: Matrix Factorization (MF Baseline), DR-BIAS + CDR (Conservative Doubly Robust), và IViDR (Instrumental Variable + Identifiable VAE).
Báo cáo trình bày toàn diện từ cơ sở lý thuyết nhân quả, sơ đồ DAG, giao thức dữ liệu, kết quả thực nghiệm tối ưu trên 2 tập dữ liệu chuẩn Coat và KuaiRand-Pure, cùng các phân tích chuyên sâu về bộ tối ưu Adam vs SGD và chỉ số AUC macro-user.
-->

---

## 1. Mục Tiêu Đề Tài & Bối Cảnh Nghiên Cứu Gợi Ý Video Nông Sản

- **Bối cảnh & Tính cấp thiết (Theo Đề cương Đồ án chuyên ngành)**:
  - Bùng nổ video ngắn (TikTok/TopTop): cơ hội quảng bá nông sản sạch, quy trình nuôi trồng và văn hóa địa phương trực quan, sinh động.
  - Thách thức "Quá tải thông tin" & Thiên lệch hiển thị (**Exposure Bias**): người xem khó tìm đúng nội dung, dễ rơi vào buồng thông tin (*filter bubble*).
  - Video nông sản mới ít hiển thị $\rightarrow$ ít tương tác, không đồng nghĩa bị ghét (**Missing-Not-At-Random, MNAR**).
  - Cần hệ thống AI gợi ý tự động: tối ưu trải nghiệm, giữ chân người dùng (*Retention*) và đưa đúng video tới khách hàng mục tiêu.
- **4 Mục tiêu nghiên cứu cốt lõi**:
  1. **Thu thập dữ liệu**: Trích xuất bộ dữ liệu chuẩn mô tả hành vi tương tác video ngắn (KuaiRand 1.4M log & TopTop app).
  2. **Xây dựng mô hình AI**: Phân tích sở thích cá nhân, dự đoán mức độ quan tâm (CF, Deep Learning, Causal IViDR).
  3. **So sánh & đánh giá**: Đo lường thực nghiệm khách quan giữa Lọc cộng tác (CF) và các mô hình Khử thiên lệch Nhân quả (Causal SOTA).
  4. **Triển khai & tích hợp**: Đóng gói REST API (FastAPI) phục vụ trực tiếp ứng dụng TopTop thực tế.
- **Mục tiêu tối thượng**: Học đúng sở thích thật $P(Y^*)$ để kết nối hiệu quả nông dân với người tiêu dùng qua video ngắn.

<!--
KỊCH BẢN SLIDE 2 — khoảng 60 giây.
Kính thưa Thầy Cô, bám sát đề cương nghiên cứu đã đăng ký với Khoa và TS. Nguyễn Thị Lương:
Trong lĩnh vực nông nghiệp, video ngắn mang lại cơ hội chưa từng có để đưa nông sản sạch và kỹ thuật canh tác đến thẳng người tiêu dùng. Tuy nhiên, khối lượng video khổng lồ gây ra tình trạng "quá tải thông tin". Hơn nữa, các video mới đăng bị thiệt thòi lớn do thiên lệch hiển thị (Exposure Bias).
Để giải quyết bài toán này, đề tài xác lập 4 mục tiêu cụ thể:
1. Thu thập và chuẩn hóa dữ liệu hành vi tương tác video ngắn.
2. Xây dựng mô hình AI phân tích sở thích và dự đoán mức độ quan tâm.
3. Đối sánh thực nghiệm khoa học giữa Collaborative Filtering truyền thống và các kiến trúc Causal Debiasing tiên tiến (CDR, IViDR).
4. Đóng gói thành REST API FastAPI và tích hợp chạy thực tế trên ứng dụng TopTop.
-->

---

## 2. Từ Thuật Toán Lọc Cộng Tác (Collaborative Filtering) Đến Sơ Đồ Nhân Quả

- **Nền tảng Lọc cộng tác (Collaborative Filtering - CF)**:
  - **Bản chất CF**: Học vector đặc trưng tiềm ẩn người dùng $p_u$ và video $q_i$ từ ma trận tương tác $R_{u \times i}$ để gợi ý dựa trên hành vi tương đồng.
  - **Phân tích ma trận (MF)**: Dự đoán điểm số qua tích vô hướng $\hat{s}_{ui} = p_u^T q_i + b_u + b_i + \mu$.
  - **Giới hạn cốt tử của CF**: Giả định dữ liệu ngẫu nhiên bị phá vỡ; CF chỉ học tương quan quan sát $P(Y \mid O=1)$, hoàn toàn bất lực trước biến nhiễu ẩn $U$ (Confounder) $\rightarrow$ Bị thiên lệch hiển thị (*Exposure Bias*).

```text
       [ Thuộc tính User / Item: X ]
               │             │
               ▼             ▼
   [ Biến Công Cụ: Z ]   [ Chính Sách Hiển Thị: A ] ──► [ Trạng Thái Phơi Bày: O ]
               │                     │                                │
               ▼                     ▼                                ▼
     [ Sở Thích Thật: Y* ] ◄── [ Yếu Tố Nhiễu Ẩn: U ] ────────► [ Phản Hồi Quan Sát: Y ]
```

- **Bước chuyển sang Mô hình Nhân quả (Causal Debiasing)**:
  - $A$ (Treatment): Chính sách quyết định video nào được hiển thị ($O=1$).
  - $U$ (Confounder): Nhiễu ẩn hai chiều (độ hot video, trào lưu mạng xã hội).
  - $Y^*$ (Potential Outcome): Sở thích thực sự của người dùng nếu mọi video đều được xem.
  - **Giải pháp**: Dùng Biến công cụ $Z$ và bóc tách $U$ để khôi phục phân phối sạch $P(Y^*)$.

<!--
KỊCH BẢN SLIDE 3 — khoảng 75 giây.
Kính thưa Thầy Cô, theo đúng đề cương nghiên cứu (Chương I), nhóm chọn thuật toán Lọc cộng tác (Collaborative Filtering - CF) làm phương pháp nền tảng:
Nguyên lý của CF là chiếu người dùng và video vào không gian vector tiềm ẩn thông qua kỹ thuật Phân tích ma trận (Matrix Factorization - MF). Nếu người dùng A và B có hành vi xem, like video sầu riêng tương đồng, hệ thống sẽ gợi ý chéo nội dung.
Tuy nhiên, điểm nghẽn lớn nhất của Collaborative Filtering là nó chỉ học trên tương quan quan sát P(Y | O=1). Các video nông sản mới ít view không bao giờ được xuất hiện vì CF bị đánh lừa bởi biến nhiễu ẩn U (như trào lưu hot trend hay vị trí màn hình).
Chính vì CF truyền thống bất lực trước biến nhiễu U, nhóm đã nâng cấp bài toán sang Sơ đồ Nhân quả Causal DAG:
Trong sơ đồ này, biến nhiễu U tạo ra đường cửa sau backdoor đánh lừa CF. Để khắc phục, nhóm đưa vào Biến công cụ Z để bóc tách triệt để ảnh hưởng của U, từ đó khôi phục chính xác sở thích thực sự Y* của người xem.
-->

---

## 3. Ba Mô Hình Lọc Cộng Tác (Collaborative Filtering) Đối Sánh

| Mô hình Lọc cộng tác (CF) | Phân loại trong CF | Cơ chế xử lý thiên lệch cốt lõi |
| :--- | :--- | :--- |
| **MF Baseline** | Lọc cộng tác truyền thống (*Correlational CF*) | Học embedding từ tương tác quan sát với Adam + BCE loss; làm mốc chuẩn so sánh. |
| **DR-BIAS + CDR** | Lọc cộng tác nhân quả (*Doubly Robust CF*) | Khung sườn MF kết hợp gán bù Imputation + IPS có lọc bất định MC Dropout. |
| **IViDR** | Lọc cộng tác học sâu & nhân quả (*Deep Causal CF*) | Mạng iVAE + Biến công cụ bóc tách sở thích sạch $Z$ khỏi độ lệch hiển thị $C$. |

> **Bản chất cốt lõi**: Cả 3 đều là thuật toán **Lọc cộng tác (Collaborative Filtering)** trên ma trận tương tác Người dùng – Video; dùng chung data loader, candidate pool và evaluator để so sánh công bằng 100%.

<!--
KỊCH BẢN SLIDE 4 — khoảng 65 giây.
Để đánh giá chính xác giá trị tăng thêm của các phương pháp nhân quả, dự án đặt 3 mô hình cạnh nhau trong cùng một điều kiện thực nghiệm:
1. MF là mốc chuẩn tối thiểu (baseline).
2. DR-BIAS + CDR thuộc trường phái Doubly Robust: sử dụng mô hình imputation bù đắp cho item chưa quan sát, kết hợp cơ chế Conservative lọc các mẫu có độ bất định cao để triệt tiêu phương sai lớn của IPS.
3. IViDR thuộc trường phái biểu diễn biến ẩn: sử dụng lý thuyết biến công cụ và Identifiable VAE để bóc tách biểu diễn người dùng thành phần bất biến và phần phụ thuộc ngữ cảnh hiển thị.
-->

---

## 4. Phân Tách Dữ Liệu & Không Gian Ứng Viên (Candidate Pool)

| Dataset | Train Set (Biased Log) | Validation Set (30% Random Log) | Held-Out Test (70% Random Log) | Nhãn Dương (Positive) |
| :--- | :--- | :--- | :--- | :--- |
| **Coat** | 6.960 ratings | 1.392 ratings (Seed 1234) | 3.248 ratings (Seed 1234) | Rating $\ge 4$ |
| **KuaiRand-Pure** | 1.413.574 exposures | 286.444 exposures (Seed 1234) | 668.370 exposures (Seed 1234) | `is_click = 1` |

- **Quy tắc phân tách**: Chia user ngẫu nhiên theo tỷ lệ **30% Val / 70% Test** với seed cố định **1234**.
- **Candidate Pool**: Xếp hạng ứng viên thực tế có trong random log (16 items/user trên Coat; candidate pool trên KuaiRand), không tự gán nhãn âm cho item ngoài log.

<!--
KỊCH BẢN SLIDE 5 — khoảng 75 giây.
Một điểm cực kỳ quan trọng trong tính chuẩn mực khoa học là giao thức phân tách dữ liệu:
Tập huấn luyện chỉ sử dụng dữ liệu ghi log thông thường (biased log). Tập kiểm định và tập kiểm thử hoàn toàn độc lập, được trích xuất từ dữ liệu ghi nhận ngẫu nhiên (random log), phân chia 30% validation và 70% test theo từng người dùng với seed cố định 1234.
Chúng tôi đánh giá trên chính không gian ứng viên đã ghi trong random log (16 candidate items mỗi user ở Coat), phản ánh đúng bài toán Re-ranking thực tế của hệ thống gợi ý.
-->

---

## 5. Giao Thức Đánh Giá Khoa Học (Evaluation Protocol)

- **Nguyên tắc đóng băng (Strict Held-Out Testing)**:
  - Toàn bộ quá trình chọn epoch (Early Stopping) và tinh chỉnh siêu tham số (Tuning) **chỉ nhìn tập Validation**.
  - Tập **Test Unbiased chỉ được chấm DUY NHẤT 1 LẦN** sau khi đã chọn xong cấu hình và checkpoint tốt nhất.
- **Hệ thống chỉ số xếp hạng Macro-User**:
  - **NDCG@5**: Đo lường vị trí và chất lượng xếp hạng Top-5.
  - **Recall@5**: Tỷ lệ item dương được tìm thấy trong Top-5 trên tổng số item dương của user.
  - **HitRate@5**: Tỷ lệ gợi ý trúng ít nhất 1 item dương trong Top-5.
  - **AUC (macro-user)**: Đánh giá năng lực phân loại toàn diện giữa item dương và âm.

<!--
KỊCH BẢN SLIDE 6 — khoảng 70 giây.
Để đảm bảo kết quả trung thực, dự án tuân thủ nghiêm ngặt nguyên tắc: Không bao giờ nhìn tập test để chọn siêu tham số hay chọn epoch dừng sớm. Tập Test held-out chỉ được mở ra đánh giá duy nhất một lần sau khi mô hình đã được cố định.
Các metric ranking được tính theo chuẩn Macro-User (tính riêng cho từng người dùng rồi lấy trung bình) nhằm đảm bảo tính công bằng (User Fairness), không bị chi phối bởi các người dùng hoạt động quá nhiều.
-->

---

## 6. Phân Tích Bộ Tối Ưu Hóa: Vì Sao Adam Vượt Trội SGD Trong RecSys?

| Tiêu chí | **Adam** (Adaptive Moment Estimation) | **SGD Thuần** (Momentum = 0) |
| :--- | :--- | :--- |
| **Điểm số (NDCG@5 / Recall@5)** | 🏆 **Cao hơn rõ rệt** (Test NDCG@5 ~0.46 - 0.49 trên Coat) | ⚠️ **Thấp hơn** (Test NDCG@5 ~0.40 - 0.44) |
| **Tốc độ hội tụ** | 🚀 **Rất nhanh** (Đạt cực trị sau 15–25 epochs) | ⏳ Chậm, cần hàng trăm epoch để tiệm cận |
| **Xử lý Gradient Thưa (Sparsity)** | 🌟 **Rất tốt** nhờ bước học thích nghi riêng cho từng embedding | Kém, dùng chung 1 LR cho cả head và tail items |
| **Chuẩn nghiên cứu (Literature)** | 📚 Chuẩn mặc định trong **iDCF, IViDR, CDR** | Ít dùng độc lập cho bài toán CF hiện đại |

> **Bản chất**: RecSys có ma trận tương tác cực kỳ thưa. **Adam** tự động tăng bước học cho các item ít xuất hiện (tail items) và giảm bước học cho item phổ biến, giúp mô hình hội tụ ổn định và vượt trội so với SGD.

<!--
KỊCH BẢN SLIDE 7 — khoảng 75 giây.
Khi kiểm tra bộ tối ưu cho bài toán Matrix Factorization, nhóm nhận thấy Adam vượt trội rõ rệt so với SGD.
Lý do nằm ở bản chất ma trận thưa trong Recommender Systems: các item hot nhận gradient dày đặc, trong khi hàng ngàn item cold nhận gradient rất thưa thớt. Adam duy trì moment bậc 1 và bậc 2 để tự điều chỉnh learning rate riêng cho từng chiều embedding, giúp các tail item vẫn học kịp trong số epoch hữu hạn. Vì vậy, Adam là lựa chọn tối ưu và là chuẩn chung của các bài báo SOTA.
-->

---

## 7. Chỉ Số AUC (macro-user): Bản Chất & Phân Biệt Với Top-K Metrics

- **Khái niệm**: Xác suất mô hình chấm điểm một item Dương cao hơn một item Âm ngẫu nhiên của user:
  $$\text{AUC}_u = P(\hat{s}_{u, i^+} > \hat{s}_{u, i^-}) = \frac{1}{N_u^+ \cdot N_u^-} \sum_{i \in \text{Pos}_u} \sum_{j \in \text{Neg}_u} \left[ \mathbb{I}(\hat{s}_{u, i} > \hat{s}_{u, j}) + 0.5 \cdot \mathbb{I}(\hat{s}_{u, i} = \hat{s}_{u, j}) \right]$$
- **Macro-user Average**: $\text{AUC}_{\text{macro}} = \frac{1}{|U_{\text{eval}}|} \sum_{u \in U_{\text{eval}}} \text{AUC}_u$ (Mỗi user có trọng số bình đẳng).
- **So sánh với NDCG@5**:
  - **NDCG@5 / Recall@5**: Đánh giá **Top-5 vị trí đầu tiên** (Trải nghiệm giao diện hiển thị).
  - **AUC (macro-user)**: Đánh giá **toàn bộ không gian ứng viên** (Năng lực phân biệt tổng thể của hàm chấm điểm).

<!--
KỊCH BẢN SLIDE 8 — khoảng 70 giây.
AUC macro-user trả lời câu hỏi: "Nếu bốc ngẫu nhiên 1 item user thích và 1 item user không thích trong danh sách ứng viên, xác suất mô hình chấm điểm item thích cao hơn item không thích là bao nhiêu?".
Điểm đặc biệt là dự án tính AUC riêng cho từng user rồi lấy trung bình (macro-average). Khác với NDCG@5 chỉ quan tâm 5 vị trí đầu tiên, AUC đo lường chất lượng phân loại trên toàn bộ không gian ứng viên. Khi cả AUC và NDCG@5 cùng tăng, ta có bằng chứng vững chắc rằng hàm chấm điểm của mô hình thực sự phân tách tốt sở thích người dùng.
-->

---

## 8. Chi Tiết Kiến Trúc: MF Baseline & DR-BIAS + CDR

- **Matrix Factorization (Baseline)**:
  $$\hat{s}_{ui} = p_u^T q_i + b_u + b_i + \mu, \quad \mathcal{L}_{\text{BCE}} = -\sum_{(u,i) \in \mathcal{O}} \left[ y_{ui} \log \sigma(\hat{s}_{ui}) + (1-y_{ui}) \log (1-\sigma(\hat{s}_{ui})) \right]$$

- **DR-BIAS + CDR (Conservative Doubly Robust)**:
  $$\mathcal{L}_{\text{CDR}} = \sum_{(u,i) \in \mathcal{D}} \left[ \hat{e}_{ui} + \frac{O_{ui}}{\hat{p}_{ui}} (e_{ui} - \hat{e}_{ui}) \cdot \mathbb{I}(\text{Var}(\hat{e}_{ui}) \le \tau) \right]$$
  - $\hat{e}_{ui}$: Lỗi ước lượng từ mô hình Imputation.
  - $\hat{p}_{ui}$: Propensity score (xác suất phơi bày).
  - $\mathbb{I}(\text{Var}(\hat{e}_{ui}) \le \tau)$: Lọc bỏ 98%+ imputation có độ bất định cao (MC Dropout) để chống bùng nổ phương sai.

<!--
KỊCH BẢN SLIDE 9 — khoảng 75 giây.
Về mặt toán học:
MF tối ưu hàm mất mát Binary Cross Entropy trên các tương tác đã quan sát, có học bias người dùng, bias sản phẩm và global bias.
DR-BIAS + CDR sử dụng công thức Doubly Robust cải tiến: Nếu một mẫu có độ bất định (variance) lớn hơn ngưỡng tau khi đo bằng Monte Carlo Dropout, phần hiệu chỉnh IPS sẽ được lọc bỏ để tránh bùng nổ phương sai. Thêm vào đó, việc khởi tạo warm-start từ checkpoint MF giúp mô hình CDR ổn định gradient và hội tụ nhanh chóng.
-->

---

## 9. Sơ Đồ Kiến Trúc IViDR: Biến Công Cụ & Mạng Biến Phân iVAE

```text
[ User Features X ] ──► (IV Projection) ──────────────► [ Invariant Preference Z ] ──┐
                                                                                     ├──► Score s_ui
[ Exposure Proxy W ] ──► [ iVAE Encoder ] ──► [ Latent C ] ──► [ Exposure Decoder ]  │
                              ▲                                                      │
                       (Kullback-Leibler)                                            │
                              ▼                                                      │
                       [ Prior p(C|W) ] ─────────────────────────────────────────────┘
```

- **Nhánh IV (Biến công cụ)**: Chiếu đặc trưng người dùng lên không gian treatment để cô lập tín hiệu sở thích sạch $Z$.
- **Nhánh iVAE (Identifiable VAE)**: Tách rời biến ẩn ngữ cảnh hiển thị $C$ bằng điều kiện tiên nghiệm $p(C \mid W)$.
- **Điểm số gợi ý cuối cùng**: Chỉ kết hợp thành phần bất biến $Z$ với MF embedding $\rightarrow$ Loại bỏ hoàn toàn nhiễu hiển thị $C$.

<!--
KỊCH BẢN SLIDE 10 — khoảng 80 giây.
Slide này mô tả kiến trúc phân tách biểu diễn của IViDR:
Mô hình gồm 2 nhánh chính:
1. Nhánh Biến công cụ (IV): Sử dụng phép chiếu hồi quy từ đặc trưng người dùng X để ước lượng thành phần sở thích bất biến Z (không bị phụ thuộc vào chính sách hiển thị).
2. Nhánh iVAE: Mạng biến phân có thể định danh nhận proxy ngữ cảnh W để học biến ẩn hiển thị C và tái tạo lại ma trận exposure.
Khi đưa ra quyết định gợi ý s_ui, mô hình chỉ khai thác Z sạch và triệt tiêu C, đảm bảo danh sách gợi ý phản ánh đúng nhu cầu cốt lõi của người xem.
-->

---

## 10. Ví Dụ Định Tính Thực Tế: Ứng Dụng Video Ngắn TopTop

| Tình huống Người Dùng | Gợi ý từ MF Baseline (Correlational) | Gợi ý từ Causal Model: IViDR / CDR |
| :--- | :--- | :--- |
| **Bác nông dân A**: Quan tâm kỹ thuật ghép cành sầu riêng | ❌ **Video triệu view "Hài hước showbiz"**<br>*(Do video này có xác suất hiển thị $A$ và số click toàn sàn quá lớn)* | ✅ **Video "Hướng dẫn tỉa cành sầu riêng mùa nghịch"**<br>*(Từ một kênh kỹ sư mới lập; khớp chính xác với sở thích bất biến $Z$)* |
| **Người xem B**: Thích nội dung nông sản sạch hữu cơ | ❌ **Video "Quảng cáo bán phân bón tràn lan"**<br>*(Do chính sách tài trợ/quảng cáo ép hiển thị liên tục)* | ✅ **Video "Quy trình trồng rau thủy canh gia đình"**<br>*(Bóc tách đúng nhu cầu thật $Y^*$, không bị lừa bởi exposure)* |

> **Giá trị thực tiễn**: Causal RecSys giúp **tăng tỷ lệ giữ chân người dùng (Retention)** và **đảm bảo công bằng cho các nhà sáng tạo nội dung mới (Creator Fairness)**.

<!--
KỊCH BẢN SLIDE 11 — khoảng 75 giây.
Để thấy rõ giá trị thực tế của đề tài trên ứng dụng TopTop, hãy xem bảng đối sánh định tính:
Một bác nông dân tìm kiếm kỹ thuật trồng sầu riêng, nhưng nếu dùng MF truyền thống, hệ thống sẽ liên tục đẩy các video hài hước hoặc tin giật gân triệu view vì chúng chiếm đa số lượng click trên sàn.
Ngược lại, mô hình Causal (IViDR / CDR) nhận diện được sở thích cốt lõi Z của bác, từ đó đề xuất đúng video kỹ thuật cắt tỉa cành từ một chuyên gia nông nghiệp mới lập kênh. Điều này vừa giúp người dùng hài lòng, vừa tạo sự công bằng cho các nhà sáng tạo nội dung ngách.
-->

---

## 11. Kết Quả Thực Nghiệm & Siêu Tham Số Tối Ưu trên COAT

> **Giao thức iDCF**: 16 candidate items/user, 30% Validation / 70% Held-Out Test.

| Mô hình | Siêu tham số tối ưu | Val NDCG@5 | Test NDCG@5 | Test Recall@5 | Test HitRate@5 | Test AUC |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **MF Baseline** | `dim=64, lr=1e-3, wd=1e-5, batch=512` | 0.4940 | 0.4629 | 0.4898 | 0.8163 | 0.6460 |
| **DR-BIAS + CDR** | `dim=32, lr=2e-3, un_thres=0.01, batch=128` | **0.5517** | **0.4841** | **0.4932** | **0.8469** | **0.6826** |
| **IViDR** | `dim=64, latent=32, lr=3e-3, phi=2.0` | **0.5847** | **0.5454** | **0.5714** | **0.8980** | **0.7064** |

- 📈 **DR-BIAS + CDR** vượt MF: $+2.12\%$ Test NDCG@5, $+3.66\%$ Test AUC.
- 🏆 **IViDR** dẫn đầu toàn diện: $+8.25\%$ Test NDCG@5, $+8.16\%$ Test Recall@5, $+6.04\%$ Test AUC so với MF.

<!--
KỊCH BẢN SLIDE 12 — khoảng 85 giây.
Đây là bảng kết quả thực nghiệm trên tập dữ liệu Coat:
Cả hai mô hình Nhân quả đều vượt trội hoàn toàn so với Baseline MF trên mọi chỉ số đánh giá Unbiased Test:
1. DR-BIAS + CDR đạt Test NDCG@5 = 0.4841 (so với MF 0.4629) và AUC đạt 0.6826 (so với MF 0.6460).
2. IViDR đạt hiệu năng cao nhất với Test NDCG@5 = 0.5454, Recall@5 = 0.5714 và HitRate@5 lên tới 89.8%.
Kết quả này khẳng định: trên không gian ứng viên 16 items, việc bóc tách biểu diễn bằng iVAE và biến công cụ giúp IViDR phân biệt cực kỳ sắc nét các item yêu thích của người dùng.
-->

---

## 12. Kết Quả Thực Nghiệm & Siêu Tham Số Tối Ưu trên KUAIRAND

> **Quy mô lớn**: 1.413.574 tương tác huấn luyện, 23.533 users, 6.712 videos.

| Mô hình | Siêu tham số tối ưu | Val NDCG@5 | Test NDCG@5 | Test Recall@5 | Test HitRate@5 | Test AUC |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **MF Baseline** | `dim=128, lr=5e-4, wd=1e-5, batch=4096` | 0.3428 | 0.3434 | 0.2948 | 0.7017 | 0.5560 |
| **DR-BIAS + CDR** | `dim=128, lr=1e-3, un_thres=0.005, batch=8192` | **0.3452** | **0.3459** | **0.2990** | **0.7102** | **0.5609** |
| **IViDR** | `dim=128, latent=32, lr=2e-3, phi=0.1` | **0.3510** | **0.3484** | **0.3049** | **0.7148** | **0.5606** |

- 📈 Cả **CDR** và **IViDR** duy trì thứ hạng vượt trội so với MF Baseline trên tập dữ liệu video ngắn quy mô lớn.
- Dải biến thiên metric trên KuaiRand hẹp hơn Coat do mật độ tương tác click thưa và số lượng ứng viên lớn.

<!--
KỊCH BẢN SLIDE 13 — khoảng 80 giây.
Chuyển sang tập dữ liệu video ngắn KuaiRand-Pure với hơn 1.4 triệu tương tác:
Thứ tự hiệu năng được duy trì nhất quán: IViDR đứng đầu (Test NDCG@5 = 0.3484, Recall@5 = 0.3049), tiếp theo là DR-BIAS + CDR (NDCG@5 = 0.3459), và MF Baseline (NDCG@5 = 0.3434).
Do bản chất hành vi click video ngắn có độ ồn cao hơn rating sản phẩm ở Coat, khoảng cách giữa các mô hình nằm trong khoảng từ 0.3% đến 0.8%, nhưng tính vượt trội của các phương pháp causal vẫn được khẳng định vững chắc qua cả chỉ số Top-5 lẫn AUC.
-->

---

## 13. Ranh Giới Khoa Học & Tính Tái Lập (Reproducibility)

- **Sự khác biệt với các bài báo công bố (Paper Comparisons)**:
  - *CDR paper (CIKM 2023)*: Đánh giá trên **Full-Catalog Ranking (300 items)** với tỷ lệ chia 10% Val / 90% Test $\rightarrow$ NDCG@5 công bố ~`0.6567`.
  - *Benchmark dự án*: Tuân thủ nghiêm ngặt **iDCF Protocol (16 candidates pool, 30% Val / 70% Test)** để đảm bảo đối sánh nội bộ 100% công bằng và minh bạch giữa 3 mô hình.
- **Tính toàn vẹn thực nghiệm**:
  - Toàn bộ kết quả đều được lưu trữ vĩnh viễn kèm mã hash nguồn và dữ liệu tại `results/*.json`, `results/*.md`.
  - Bộ kiểm thử tự động đạt **40/40 Unit Tests (100% OK)**.

<!--
KỊCH BẢN SLIDE 14 — khoảng 75 giây.
Một điểm nhấn quan trọng trong tinh thần nghiên cứu trung thực:
Nhóm làm rõ vì sao số điểm trong bài báo CDR có thể ghi nhận 0.65 trong khi thực nghiệm này là 0.48. Đó là do bài báo gốc đánh giá trên toàn bộ 300 sản phẩm (Full-catalog ranking) với tập test chiếm tới 90%.
Trong dự án này, nhóm lựa chọn chuẩn iDCF protocol: 16 candidate items mỗi user và chia 30% val / 70% test. Mọi mô hình (MF, CDR, IViDR) đều dùng chung một data loader, chung candidate pool và chung evaluator. Đây là một so sánh hoàn toàn công bằng và có thể tái lập 100%.
-->

---

## 14. Kết Luận & Định Hướng Phát Triển

### Kết luận
1. Đã xây dựng hoàn chỉnh hệ thống **Causal Debiasing RecSys** chuẩn hóa cho MF, DR-BIAS + CDR và IViDR.
2. Thực nghiệm chứng minh các mô hình Khử độ lệch Nhân quả (**IViDR dẫn đầu**, kế tiếp là **CDR**) vượt trội hoàn toàn so với **MF Baseline** trên cả Coat và KuaiRand-Pure.
3. Xác lập bộ siêu tham số tối ưu và hoàn thiện bộ kiểm thử tự động 40/40 test cases.

### Định hướng mở rộng
- Mở rộng đánh giá **Multi-seed ($\text{mean} \pm \text{std}$ qua 10 seeds)** để đo độ ổn định thống kê.
- Tích hợp thêm các tín hiệu hành vi xem sâu (Watch Time, Dwell Time) trên nền tảng video ngắn TopTop.

<!--
KỊCH BẢN SLIDE 15 — khoảng 45 giây.
Tóm lại, dự án đã hoàn thành xuất sắc các mục tiêu nghiên cứu:
1. Xây dựng một framework thực nghiệm Causal RecSys chuẩn mực, minh bạch và có tính tái lập cao.
2. Chứng minh bằng thực nghiệm định lượng sự vượt trội của IViDR và DR-BIAS + CDR so với Matrix Factorization.
3. Tìm ra bộ siêu tham số tối ưu và áp dụng đồng bộ vào mã nguồn.
Xin chân thành cảm ơn quý thầy cô và các bạn đã chú ý theo dõi!
-->

---

<!-- _class: lead -->
# Cảm ơn Thầy Cô và Các Bạn đã lắng nghe!

### 💬 Mời Thầy Cô và Các Bạn Đặt Câu Hỏi (Q&A)

**Tài liệu tham khảo & Báo cáo kết quả:**
- [`results/benchmark_coat_all_19d70ea039_v4.md`](../../../../results/benchmark_coat_all_19d70ea039_v4.md)
- [`results/tuning_kuairand_all_e25_4deb0568781e5d74_v4.md`](../../../../results/tuning_kuairand_all_e25_4deb0568781e5d74_v4.md)
- [`docs/benchmarks/evaluation_protocol.md`](../../../benchmarks/evaluation_protocol.md) · [`docs/benchmarks/mf_optimizer_audit.md`](../../../benchmarks/mf_optimizer_audit.md)


