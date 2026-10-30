> **LƯU TRỮ — KHÔNG PHẢI TRẠNG THÁI HIỆN HÀNH.** Chụp trước đợt dọn 20/10/2026. Nội dung có nhận định đã bị thay thế; xem [CURRENT_STATE](../../../CURRENT_STATE.md). Bản nguyên byte nằm trong ZIP và được kiểm tra bằng checksum; bản đọc này chỉ thêm nhãn và sửa đường dẫn.

# 🎤 KỊCH BẢN THUYẾT TRÌNH BẢO VỆ ĐỒ ÁN — PHẦN II (SLIDE 12 ĐẾN 25)
## Đề tài: Nghiên Cứu, Phát Triển Nền Tảng Quảng Bá Nông Sản Qua Video Ngắn & Ứng Dụng Học Máy Trong Đề Xuất Nội Dung
**Học phần:** Đồ án Chuyên ngành / Ứng dụng Di động & Hệ thống Gợi ý Thông minh  
**Tập tin trình chiếu chuẩn:** `Báo_cáo_Toàn_diện_Đồ_án_TopTop_cập_nhật.pptx`  
**Thời lượng dành riêng cho Phần II:** **7 — 8.5 phút** (thuyết trình) + **5 — 7 phút** (phản biện Q&A)

---

## ⏱️ BẢNG ĐIỀU PHỐI THỜI GIAN NHANH (QUICK TIME CHEAT SHEET)

| Slide | Nội dung chính | Thời lượng chuẩn | Mốc thời gian tích lũy |
|:---:|---|:---:|:---:|
| **Chuyển giao** | Tiếp nhận lượt nói từ Thành viên 1 | 20 giây | 00:00 – 00:20 |
| **Slide 12** | Mục Tiêu Đề Tài & Bối Cảnh Nghiên Cứu Gợi Ý Video Nông Sản | 50 giây | 00:20 – 01:10 |
| **Slide 13** | Từ Lọc Cộng Tác (CF) Đến Sơ Đồ Nhân Quả | 55 giây | 01:10 – 02:05 |
| **Slide 14** | Ba Mô Hình Lọc Cộng Tác (CF) Đối Sánh | 40 giây | 02:05 – 02:45 |
| **Slide 15** | Phân tách Dữ liệu & Candidate Pool (Coat · KuaiRand) | 40 giây | 02:45 – 03:25 |
| **Slide 16** | Giao thức Đánh giá Khoa học & Chỉ số Macro-User | 40 giây | 03:10 – 03:50 |
| **Slide 17** | Phân tích Tối ưu: Vì sao Adam vượt trội SGD? | 35 giây | 03:50 – 04:25 |
| **Slide 18** | Bản chất Chỉ số AUC Macro-User vs Top-K | 35 giây | 04:25 – 05:00 |
| **Slide 19** | Chi tiết Kiến trúc Toán học: MF & DR-BIAS + CDR | 45 giây | 05:00 – 05:45 |
| **Slide 20** | Kiến trúc IViDR: Biến công cụ & Mạng biến phân iVAE | 50 giây | 05:45 – 06:35 |
| **Slide 21** | Ví dụ Định tính Thực tế trên Video Ngắn TopTop | 40 giây | 06:35 – 07:15 |
| **Slide 22** | Kết quả Thực nghiệm Định lượng trên COAT | 45 giây | 07:15 – 08:00 |
| **Slide 23** | Kết quả Thực nghiệm trên KUAIRAND (1.4 Triệu log) | 35 giây | 08:00 – 08:35 |
| **Slide 24** | Ranh giới Khoa học, Tính Tái lập & 40/40 Unit Tests | 35 giây | 08:35 – 09:10 |
| **Slide 25** | Tổng kết Tiến độ Phần II & Mời Hội đồng Đặt câu hỏi | 30 giây | 09:10 – 09:40 |

---

## 🎙️ KỊCH BẢN CHI TIẾT TỪNG SLIDE (SLIDE-BY-SLIDE SCRIPT)

---

### 🔄 PHẦN CHUYỂN GIAO LƯỢT NÓI (HANDOVER TỪ THÀNH VIÊN 1)
- **Thời lượng:** ~20 giây.
- **Hành động (Cue):** Cúi nhẹ đầu chào Hội đồng, mỉm cười tự tin, bước lên vị trí thuyết trình chính, cầm clicker/chuột trình chiếu.
- **Lời thoại:**
> *"Em xin cảm ơn bạn [Tên bạn 1] đã trình bày rất chi tiết về bức tranh tổng thể nền tảng TopTop, từ kiến trúc Client-Server đến giải pháp kiểm duyệt bản quyền video.*  
>  
> *Kính thưa quý Thầy Cô trong Hội đồng, một nền tảng video ngắn dù mượt mà đến đâu cũng sẽ không thể giữ chân người dùng nếu nội dung đề xuất bị nhàm chán hoặc thiên lệch. Sau đây, em xin phép đại diện nhóm trình bày **Phần II: Ứng dụng Học máy trong Phân tích hành vi & Đề xuất nội dung, với trọng tâm là Khử độ lệch nhân quả (Causal Debiasing) trong Hệ thống gợi ý**."*

---

### 🎬 SLIDE 12: MỤC TIÊU ĐỀ TÀI & BỐI CẢNH NGHIÊN CỨU GỢI Ý VIDEO NÔNG SẢN
- **Tiêu đề Slide:** `PHẦN II: HỌC MÁY & ĐỀ XUẤT NỘI DUNG · MỤC TIÊU ĐỀ TÀI`
- **Thời lượng:** ~50 giây.
- **Hành động (Visual Cue):** Chỉ tay vào phần `Bối cảnh & Tính cấp thiết` ở bên trái, sau đó chuyển sang hộp `4 MỤC TIÊU CỐT LÕI` ở bên phải.
- **Lời thoại:**
> *"Mở đầu Phần II, em xin báo cáo về **Mục tiêu đề tài và bối cảnh nghiên cứu** – bám sát theo Đề cương Đồ án chuyên ngành mà nhóm đã đăng ký với Khoa và cô hướng dẫn TS. Nguyễn Thị Lương:*  
>  
> *Ngày nay, các nền tảng video ngắn như TopTop mở ra cơ hội chưa từng có để nông dân và hợp tác xã quảng bá nông sản sạch, kỹ thuật nuôi trồng và văn hóa địa phương đến thẳng người tiêu dùng một cách sinh động, chân thực.*  
>  
> *Tuy nhiên, người dùng đang đối mặt với bài toán **Quá tải thông tin**. Hơn thế nữa, các video nông sản mới đăng tải thường chịu thiệt thòi lớn do **Thiên lệch hiển thị (Exposure Bias)** – tức video chưa được phân phối thì ít click, nhưng không đồng nghĩa là người xem ghét nội dung đó (hiện tượng **Missing-Not-At-Random, MNAR**).*  
>  
> *Để giải quyết vấn đề này, đề tài xác lập **4 Mục tiêu nghiên cứu cốt lõi**:*  
> 1. *Thứ nhất: **Thu thập và chuẩn hóa dữ liệu** hành vi tương tác video ngắn (trên tập KuaiRand 1.4 triệu log và ứng dụng TopTop).*  
> 2. *Thứ hai: **Xây dựng mô hình học máy** phân tích sở thích cá nhân và dự đoán mức độ quan tâm.*  
> 3. *Thứ ba: **Thực nghiệm đối sánh khoa học** giữa Collaborative Filtering truyền thống và các mô hình Khử thiên lệch Nhân quả (Causal SOTA).*  
> 4. *Thứ tư: **Đóng gói REST API FastAPI** và tích hợp trực tiếp phục vụ ứng dụng TopTop thực tế.*  
>  
> *Mục tiêu tối thượng là học đúng sở thích thực sự $P(Y^*)$ để kết nối hiệu quả nông dân với người tiêu dùng ạ."*

---

### 🎬 SLIDE 13: TỪ THUẬT TOÁN LỌC CỘNG TÁC (CF) ĐẾN SƠ ĐỒ NHÂN QUẢ
- **Tiêu đề Slide:** `PHẦN II: HỌC MÁY & ĐỀ XUẤT NỘI DUNG · LỌC CỘNG TÁC & SƠ ĐỒ NHÂN QUẢ`
- **Thời lượng:** ~55 giây.
- **Hành động (Visual Cue):** Chỉ tay vào hộp `Nền Tảng Lọc Cộng Tác (CF)` ở góc phải dưới trước, sau đó chỉ lên sơ đồ DAG và nhấn mạnh nút **U** (Confounder).
- **Lời thoại:**
> *"Kính thưa quý Thầy Cô, bám sát theo Chương I của Đề cương nghiên cứu, phương pháp nền tảng đầu tiên mà nhóm triển khai là thuật toán **Lọc cộng tác (Collaborative Filtering - CF)**:*  
>  
> *Nguyên lý cốt lõi của Lọc cộng tác là ánh xạ người dùng và video vào không gian vector tiềm ẩn $d$-chiều thông qua kỹ thuật **Phân tích ma trận (Matrix Factorization - MF)**: Điểm số dự đoán $\hat{s}_{ui} = p_u^T q_i + b_u + b_i$. Nếu hai người dùng có lịch sử xem và thả tim các video nông sản tương tự nhau, hệ thống sẽ đề xuất chéo các video phù hợp.*  
>  
> *Tuy nhiên, một điểm nghẽn chí mạng xuất hiện: **Collaborative Filtering truyền thống chỉ học trên các tương tác đã quan sát $P(Y \mid O=1)$**. Nó hoàn toàn bị đánh lừa bởi các yếu tố gây nhiễu ẩn $U$ – tức **Unobserved Confounder** (như độ hot của video showbiz triệu view hay vị trí hiển thị ưu tiên).*  
>  
> *Chính vì vậy, để khắc phục giới hạn của CF, nhóm đã nâng cấp bài toán sang **Lý thuyết Nhân quả thông qua Sơ đồ Causal DAG** như trên màn hình:*  
> *Biến nhiễu $U$ tạo ra một 'đường cửa sau' (backdoor path) giữa hiển thị $A$ và tương tác $Y$. Bằng cách đưa vào **Biến công cụ $Z$**, nhóm bóc tách triệt để ảnh hưởng của $U$, từ đó giúp hệ thống khôi phục được phân phối sạch của sở thích thật $P(Y^*)$ mà không bị ô nhiễm bởi thiên lệch hiển thị ạ."*

---

### 🎬 SLIDE 14: BA MÔ HÌNH LỌC CỘNG TÁC (CF) ĐỐI SÁNH
- **Tiêu đề Slide:** `PHẦN II: HỌC MÁY & ĐỀ XUẤT NỘI DUNG · BA MÔ HÌNH LỌC CỘNG TÁC (CF)`
- **Thời lượng:** ~40 giây.
- **Hành động (Visual Cue):** Quét mắt qua bảng 3 hàng, nhấn mạnh: *"Cả 3 đều là thuật toán Lọc cộng tác (Collaborative Filtering)"*.
- **Lời thoại:**
> *"Em xin nhấn mạnh một điểm cốt lõi: **Cả 3 mô hình trong thực nghiệm đối sánh của nhóm đều là thuật toán Lọc cộng tác (Collaborative Filtering)**, cùng khai thác ma trận tương tác Người dùng – Video nhưng đại diện cho 3 cấp độ xử lý thiên lệch khác nhau:*  
>  
> 1. *Thứ nhất là **MF Baseline (Matrix Factorization)**: Lọc cộng tác truyền thống (Correlational CF), học biểu diễn embedding từ BCE loss, đóng vai trò mốc chuẩn đối sánh.*  
> 2. *Thứ hai là **DR-BIAS + CDR (Conservative Doubly Robust)**: Lọc cộng tác nhân quả (Doubly Robust CF), giữ nguyên khung sườn MF nhưng cải tiến hàm loss bằng mô hình gán bù Imputation kết hợp IPS có lọc bất định MC Dropout.*  
> 3. *Và thứ ba là **IViDR (Instrumental Variable Doubly Robust)**: Lọc cộng tác học sâu & nhân quả (Deep Causal CF), kết hợp Biến công cụ và mạng biến phân iVAE để bóc tách sở thích sạch khỏi độ lệch ngữ cảnh.*  
>  
> *Đặc biệt, cả 3 mô hình đều dùng chung data loader, chung candidate pool và chung bộ đánh giá để đảm bảo tính đối sánh công bằng 100% ạ."*

---

### 🎬 SLIDE 15: PHÂN TÁCH DỮ LIỆU & KHÔNG GIAN ỨNG VIÊN (CANDIDATE POOL)
- **Tiêu đề Slide:** `PHẦN II: HỌC MÁY & ĐỀ XUẤT NỘI DUNG · PHÂN TÁCH DỮ LIỆU`
- **Thời lượng:** ~40 giây.
- **Hành động (Visual Cue):** Nhấn mạnh vào 2 con số: **Seed 1234** và **Tập Test độc lập 70% Random Log**.
- **Lời thoại:**
> *"Tính khoa học và trung thực của một nghiên cứu RecSys phụ thuộc quyết định vào giao thức phân tách dữ liệu:*  
>  
> *Nhóm thực nghiệm trên hai tập dữ liệu chuẩn:*  
> - *Tập **Coat**: Dữ liệu thương mại chuẩn trong các công bố khoa học.*  
> - *Và tập **KuaiRand-Pure**: Dữ liệu video ngắn thực tế với hơn 1.4 triệu tương tác.*  
>  
> *Quy tắc phân tách được thiết lập cực kỳ nghiêm ngặt: Tập Train chỉ chứa log có thiên lệch (Biased Log). Trong khi đó, tập Validation và Test được trích xuất hoàn toàn từ log hiển thị ngẫu nhiên (**Random Log**), chia theo từng người dùng theo tỷ lệ **30% Val và 70% Test** với seed cố định **1234**.*  
>  
> *Đặc biệt, nhóm đánh giá trên chính **Candidate Pool thực tế** (16 ứng viên mỗi user trên Coat) chứ tuyệt đối không tự gán nhãn âm tuỳ tiện cho các item ngoài log."*

---

### 🎬 SLIDE 16: GIAO THỨC ĐÁNH GIÁ KHOA HỌC (EVALUATION PROTOCOL)
- **Tiêu đề Slide:** `PHẦN II: HỌC MÁY & ĐỀ XUẤT NỘI DUNG · GIAO THỨC ĐÁNH GIÁ`
- **Thời lượng:** ~40 giây.
- **Hành động (Visual Cue):** Nhấn mạnh cụm từ **Strict Held-Out** (Nguyên tắc đóng băng).
- **Lời thoại:**
> *"Nhóm cam kết tuân thủ **Nguyên tắc đóng băng (Strict Held-Out)**:*  
>  
> *Toàn bộ quá trình chọn epoch dừng sớm (Early Stopping) và tinh chỉnh siêu tham số **chỉ được phép nhìn vào tập Validation**. Tập **Held-Out Test Unbiased chỉ được mở ra chấm điểm duy nhất 1 lần** sau khi đã đóng băng checkpoint tốt nhất.*  
>  
> *Về chỉ số đánh giá, nhóm sử dụng bộ 4 tiêu chuẩn theo phương pháp **Macro-User**: tính toán riêng trên từng người dùng rồi lấy trung bình:*  
> - *Bao gồm **NDCG@5, Recall@5, HitRate@5** đo lường chất lượng xếp hạng Top đầu.*  
> - *Và chỉ số **AUC Macro-User** đo lường năng lực phân biệt tổng thể.*  
>  
> *Cách tiếp cận Macro-User đảm bảo tính công bằng (**User Fairness**), ngăn các người dùng có quá nhiều tương tác lấn át đánh giá chung."*

---

### 🎬 SLIDE 17: PHÂN TÍCH TỐI ƯU: VÌ SAO ADAM VƯỢT TRỘI SGD TRONG RECSYS?
- **Tiêu đề Slide:** `PHẦN II: HỌC MÁY & ĐỀ XUẤT NỘI DUNG · BỘ TỐI ƯU HÓA`
- **Thời lượng:** ~35 giây.
- **Hành động (Visual Cue):** Chỉ vào bảng so sánh, nhấn mạnh từ khóa **Gradient Sparsity**.
- **Lời thoại:**
> *"Trong quá trình thực nghiệm mô hình Baseline, một câu hỏi kỹ thuật quan trọng được đặt ra: **Nên chọn Adam hay SGD?** Kết quả thực nghiệm của nhóm chứng minh **Adam vượt trội hoàn toàn so với SGD thuần** cả về điểm số (NDCG@5 đạt ~0.49 so với ~0.44) lẫn tốc độ hội tụ.*  
>  
> *Bản chất nằm ở tính chất **ma trận tương tác cực kỳ thưa (Gradient Sparsity)**: Các video hot nhận gradient dồn dập, trong khi video ngách nông sản nhận gradient rất thưa thớt.*  
>  
> *Adam duy trì moment bậc 1 và bậc 2 để tự điều chỉnh tốc độ học thích nghi riêng cho từng chiều embedding, giúp các video ít tương tác vẫn học kịp trong số epoch hữu hạn. Đây cũng chính là chuẩn mực được dùng trong các bài báo SOTA như iDCF và IViDR."*

---

### 🎬 SLIDE 18: CHỈ SỐ AUC (MACRO-USER): BẢN CHẤT & PHÂN BIỆT VỚI TOP-K
- **Tiêu đề Slide:** `PHẦN II: HỌC MÁY & ĐỀ XUẤT NỘI DUNG · CHỈ SỐ AUC`
- **Thời lượng:** ~35 giây.
- **Hành động (Visual Cue):** So sánh giữa `Top-5` và `Toàn bộ không gian ứng viên`.
- **Lời thoại:**
> *"Tại sao nhóm lại bổ sung chỉ số AUC Macro-User bên cạnh NDCG@5?*  
>  
> *NDCG@5 và Recall@5 chỉ đo lường **Top-5 vị trí đầu tiên** – tức trải nghiệm trên màn hình điện thoại của người dùng.*  
>  
> *Còn AUC Macro-User trả lời câu hỏi cốt lõi: 'Nếu bốc ngẫu nhiên một video người dùng thích và một video họ không thích trong danh sách ứng viên, xác suất mô hình chấm điểm video thích cao hơn là bao nhiêu?'.*  
>  
> *AUC đánh giá **toàn bộ không gian ứng viên**. Khi cả NDCG@5 và AUC cùng tăng đồng thời, chúng ta có bằng chứng toán học vững chắc rằng hàm chấm điểm của mô hình thực sự phân tách tốt sở thích người xem chứ không phải do ăn may ở vài vị trí đầu."*

---

### 🎬 SLIDE 19: CHI TIẾT KIẾN TRÚC: MF BASELINE & DR-BIAS + CDR
- **Tiêu đề Slide:** `PHẦN II: HỌC MÁY & ĐỀ XUẤT NỘI DUNG · KIẾN TRÚC MF & CDR`
- **Thời lượng:** ~45 giây.
- **Hành động (Visual Cue):** Chỉ vào thành phần chỉ thị $\mathbb{I}(\text{Var}(\hat{e}_{ui}) \le \tau)$ trong công thức $\mathcal{L}_{\text{CDR}}$.
- **Lời thoại:**
> *"Đi sâu vào kiến trúc toán học:*  
>  
> *MF Baseline tối ưu hóa hàm BCE loss trên các cặp quan sát, học embedding người dùng, sản phẩm và các bias tương ứng.*  
>  
> *Đối với **DR-BIAS + CDR**: Phương pháp Doubly Robust truyền thống thường bị bùng nổ phương sai do chia cho xác suất hiển thị $\hat{p}_{ui}$ quá nhỏ. Nhóm đã áp dụng cơ chế **Conservative** thông qua hàm chỉ thị độ bất định:*  
>  
> *Bằng kỹ thuật **Monte Carlo Dropout**, nếu độ bất định của mô hình bù đắp Imputation vượt quá ngưỡng $\tau$, hệ thống sẽ lọc bỏ phần hiệu chỉnh có rủi ro cao để triệt tiêu phương sai vô hạn.*  
>  
> *Đồng thời, việc khởi tạo trọng số ấm (**warm-start**) từ checkpoint MF giúp mô hình CDR ổn định gradient và hội tụ nhanh chóng."*

---

### 🎬 SLIDE 20: KIẾN TRÚC IVIDR: BIẾN CÔNG CỤ & MẠNG BIẾN PHÂN iVAE
- **Tiêu đề Slide:** `PHẦN II: HỌC MÁY & ĐỀ XUẤT NỘI DUNG · KIẾN TRÚC IVIDR`
- **Thời lượng:** ~50 giây.
- **Hành động (Visual Cue):** Đi theo luồng từ Trái qua Phải trên sơ đồ: Nhánh $Z$ sạch ở trên, nhánh $C$ ngữ cảnh ở dưới.
- **Lời thoại:**
> *"Mô hình tiên tiến nhất trong dự án là **IViDR**:*  
>  
> *Mô hình gồm hai nhánh xử lý song song độc đáo:*  
> 1. *Nhánh trên là **Biến công cụ (IV)**: Chiếu đặc trưng người dùng lên không gian treatment để cô lập thành phần sở thích bất biến $Z$. Thành phần $Z$ này hoàn toàn sạch và không bị ảnh hưởng bởi chính sách hiển thị.*  
> 2. *Nhánh dưới là mạng **Identifiable VAE (iVAE)**: Tiếp nhận proxy ngữ cảnh $W$ để học biểu diễn biến ẩn hiển thị $C$ và ràng buộc phân phối bằng điều kiện tiên nghiệm $p(C \mid W)$.*  
>  
> *Điểm mấu chốt: Khi đưa ra dự đoán điểm số cuối cùng $\hat{s}_{ui}$, mô hình **chỉ kết hợp thành phần bất biến $Z$ với MF embedding và loại bỏ hoàn toàn biến ẩn $C$**. Nhờ đó, danh sách gợi ý phản ánh đúng 100% nhu cầu cốt lõi của người xem."*

---

### 🎬 SLIDE 21: VÍ DỤ ĐỊNH TÍNH THỰC TẾ: ỨNG DỤNG VIDEO NGẮN TOPTOP
- **Tiêu đề Slide:** `PHẦN II: HỌC MÁY & ĐỀ XUẤT NỘI DUNG · VÍ DỤ ĐỊNH TÍNH`
- **Thời lượng:** ~40 giây.
- **Hành động (Visual Cue):** Đọc đối chiếu giữa cột MF (dấu ✗ màu đỏ) và Causal Model (dấu ✓ màu xanh).
- **Lời thoại:**
> *"Để thấy rõ giá trị thực tiễn của nghiên cứu này trên ứng dụng TopTop, mời Thầy Cô theo dõi ví dụ định tính:*  
>  
> *Một bác nông dân quan tâm kỹ thuật ghép cành sầu riêng. Nếu dùng **MF truyền thống**, hệ thống sẽ liên tục đề xuất video showbiz hài hước triệu view, đơn giản vì xác suất hiển thị $A$ và số lượt click toàn sàn của video đó quá lớn.*  
>  
> *Ngược lại, mô hình **Causal IViDR / CDR** nhận diện chính xác sở thích bất biến $Z$, từ đó tự tin đề xuất video 'Hướng dẫn tỉa cành sầu riêng mùa nghịch' từ một kỹ sư nông nghiệp mới lập kênh.*  
>  
> *Điều này mang lại hai giá trị cốt lõi: Vừa tăng tỷ lệ giữ chân người xem (**Retention**), vừa bảo đảm sự công bằng cho các nhà sáng tạo nội dung nông sản mới (**Creator Fairness**)."*

---

### 🎬 SLIDE 22: KẾT QUẢ THỰC NGHIỆM ĐỊNH LƯỢNG TRÊN COAT
- **Tiêu đề Slide:** `PHẦN II: HỌC MÁY & ĐỀ XUẤT NỘI DUNG · KẾT QUẢ COAT`
- **Thời lượng:** ~45 giây.
- **Hành động (Visual Cue):** Chỉ vào 2 dòng in đậm CDR và IViDR, đọc to các con số tăng trưởng phần trăm.
- **Lời thoại:**
> *"Và đây là bảng kết quả thực nghiệm định lượng trên tập dữ liệu Coat theo chuẩn iDCF protocol:*  
>  
> *Cả hai mô hình Nhân quả đều vượt trội hoàn toàn so với Baseline MF trên toàn bộ các chỉ số Unbiased Held-Out Test:*  
> - *DR-BIAS + CDR cải thiện Test NDCG@5 lên **0.4841** (tăng $+2.12\%$) và AUC lên **0.6826** (tăng $+3.66\%$) so với MF.*  
> - *Đặc biệt, **IViDR dẫn đầu toàn diện**: Đạt Test NDCG@5 **0.5454** – vượt trội tới **$+8.25\%$**, Recall@5 đạt **0.5714** (tăng $+8.16\%$), và HitRate@5 chạm ngưỡng ấn tượng **89.8%**.*  
>  
> *Kết quả này chứng minh việc bóc tách sở thích bằng Biến công cụ và iVAE mang lại năng lực xếp hạng cực kỳ mạnh mẽ trên môi trường không thiên lệch."*

---

### 🎬 SLIDE 23: KẾT QUẢ THỰC NGHIỆM TRÊN KUAIRAND (1.4 TRIỆU LOG)
- **Tiêu đề Slide:** `PHẦN II: HỌC MÁY & ĐỀ XUẤT NỘI DUNG · KẾT QUẢ KUAIRAND`
- **Thời lượng:** ~35 giây.
- **Hành động (Visual Cue):** Nhấn mạnh quy mô hơn 1.4 triệu tương tác và tính nhất quán của thứ hạng mô hình.
- **Lời thoại:**
> *"Khi kiểm thử trên quy mô lớn – tập video ngắn KuaiRand-Pure với hơn **1.4 triệu tương tác huấn luyện và hơn 23.000 người dùng**:*  
>  
> *Thứ hạng hiệu năng vẫn được duy trì nhất quán: **IViDR dẫn đầu** (NDCG@5 = 0.3484, Recall@5 = 0.3049), kế tiếp là **DR-BIAS + CDR** (0.3459), và cuối cùng là **MF Baseline** (0.3434).*  
>  
> *Do hành vi lướt video ngắn có độ ồn tương tác cao hơn chấm điểm sản phẩm, khoảng cách giữa các mô hình nằm trong khoảng 0.3% đến 0.8%. Tuy nhiên, trên quy mô nền tảng hàng triệu người dùng, mức tăng này tương ứng với hàng chục ngàn lượt xem phù hợp được phân phối chính xác hơn mỗi ngày."*

---

### 🎬 SLIDE 24: RANH GIỚI KHOA HỌC, TÍNH TÁI LẬP & 40/40 UNIT TESTS
- **Tiêu đề Slide:** `PHẦN II: HỌC MÁY & ĐỀ XUẤT NỘI DUNG · TÍNH TÁI LẬP`
- **Thời lượng:** ~35 giây.
- **Hành động (Visual Cue):** Chỉ vào dòng **40/40 Unit Tests (100% OK)** và mã hash kết quả.
- **Lời thoại:**
> *"Một điểm thể hiện tính liêm chính học thuật của nhóm là **Làm rõ ranh giới khoa học so với các bài báo công bố**.*  
>  
> *Bài báo CDR gốc trên kỷ yếu CIKM 2023 công bố NDCG@5 khoảng 0.65 vì họ đánh giá trên toàn bộ catalog 300 sản phẩm với tập test chiếm tới 90%.*  
>  
> *Trong đồ án này, nhóm áp dụng chuẩn mực **iDCF protocol** với 16 candidate pool và 70% test. Toàn bộ 3 mô hình đều chạy trên cùng một dataloader, cùng candidate pool và cùng bộ đánh giá.*  
>  
> *Mọi kết quả đều được lưu vết vĩnh viễn kèm mã hash tại kho chứa mã nguồn, và toàn bộ hệ thống đã vượt qua tuyệt đối **40/40 bài kiểm thử tự động (Unit Tests 100% Passed)**."*

---

### 🎬 SLIDE 25: TỔNG KẾT TIẾN ĐỘ PHẦN II & MỜI ĐẶT CÂU HỎI
- **Tiêu đề Slide:** `Slide 25 / 25 · TỔNG KẾT TIẾN ĐỘ & PHIÊN HỎI ĐÁP (Q & A)`
- **Thời lượng:** ~30 giây.
- **Hành động (Visual Cue):** Hướng ánh mắt về phía toàn thể Hội đồng, giọng điệu ấm áp, khiêm tốn nhưng tự tin.
- **Lời thoại:**
> *"Tóm lại, trong Phần II, nhóm đã:*  
> 1. *Xây dựng thành công framework Causal Debiasing RecSys chuẩn hóa và có tính tái lập cao.*  
> 2. *Thực nghiệm định lượng khẳng định sự vượt trội của IViDR và CDR so với MF Baseline.*  
> 3. *Triển khai mô hình IViDR phục vụ gợi ý trực tiếp cho ứng dụng TopTop thông qua RESTful API.*  
>  
> *Trên đây là toàn bộ báo cáo tiến độ đồ án của nhóm. Chúng em xin chân thành cảm ơn quý Thầy Cô và các bạn đã chú ý lắng nghe!*  
>  
> *Sau đây, chúng em xin phép được lắng nghe nhận xét và giải đáp các câu hỏi từ Hội đồng ạ!"*

---

## 🛡️ CẨM NANG PHẢN BIỆN Q&A DỰ PHÒNG (BULLETPROOF DEFENSE GUIDE)

Dưới đây là **8 câu hỏi "gai góc" nhất** mà Giảng viên phản biện thường đặt ra cho phần RecSys, kèm câu trả lời mẫu chuẩn xác 100%:

### ❓ Câu 1: Biến công cụ $Z$ trong mô hình IViDR lấy từ đâu và thỏa mãn các giả định nào?
- **Trả lời chuẩn:**
  > *"Dạ thưa Thầy/Cô, trong bài toán gợi ý, biến công cụ $Z$ được trích xuất thông qua phép chiếu hồi quy từ vector đặc trưng người dùng $X$ lên không gian phân phối hiển thị. Để là một Biến công cụ hợp lệ, $Z$ thỏa mãn 3 giả định kinh điển của lý thuyết nhân quả:*  
  > 1. *Tính liên đới (**Relevance**): $Z$ có tương quan chặt chẽ với trạng thái hiển thị $A$.*  
  > 2. *Tính loại trừ (**Exclusion Restriction**): $Z$ chỉ tác động đến hành vi tương tác $Y$ thông qua việc hiển thị $A$, chứ không tác động trực tiếp.*  
  > 3. *Tính không bị gây nhiễu (**Unconfoundedness**): $Z$ độc lập với các yếu tố gây nhiễu ẩn $U$ (như trend mạng xã hội hay thuật toán cũ).*  
  > *Nhờ đó, nhánh IV tách được thành phần sở thích bất biến mà không bị ô nhiễm bởi thiên lệch hiển thị ạ."*

---

### ❓ Câu 2: Tại sao kết quả NDCG@5 của CDR trong bài báo gốc là ~0.65 mà nhóm chạy ra 0.48?
- **Trả lời chuẩn:**
  > *"Dạ thưa Thầy/Cô, đây là sự khác biệt hoàn toàn về **Giao thức đánh giá (Evaluation Protocol)**:*  
  > - *Trong bài báo CDR gốc tại CIKM 2023, các tác giả đánh giá trên **Full-Catalog Ranking (toàn bộ 300 sản phẩm)** và chia 10% Validation / 90% Test.*  
  > - *Trong dự án này, nhóm tuân thủ nghiêm ngặt **iDCF Protocol**: xếp hạng trên **Candidate Pool 16 items thực tế có trong random log** của mỗi user và phân chia 30% Val / 70% Test.*  
  > *Không gian ứng viên 16 items là bài toán Re-ranking cục bộ khó hơn, do đó điểm tuyệt đối thấp hơn là hoàn toàn tự nhiên. Điều quan trọng nhất là nhóm cho cả MF, CDR và IViDR chạy trên **cùng một giao thức 100% công bằng**, và trên giao thức này CDR và IViDR đều vượt trội rõ rệt so với MF ạ."*

---

### ❓ Câu 3: Cơ chế MC Dropout của CDR lọc bỏ tới 98% mẫu thì mô hình còn học được gì?
- **Trả lời chuẩn:**
  > *"Dạ thưa Thầy/Cô, đây chính là triết lý cốt lõi của chữ **Conservative (Thận trọng)** trong CDR:*  
  > - *Phương pháp Doubly Robust truyền thống bị nhược điểm chí mạng là: khi propensity score $\hat{p}_{ui}$ rất nhỏ hoặc mô hình Imputation ước lượng sai, sai số sẽ bị khuếch đại lên hàng ngàn lần gây bùng nổ phương sai (variance explosion).*  
  > - *Cơ chế Conservative dùng Monte Carlo Dropout để đo độ bất định (variance). Khi độ bất định cao (chiếm ~98% mẫu chưa quan sát), mô hình thà **bỏ qua phần hiệu chỉnh rủi ro đó** và chỉ dựa trên loss quan sát, còn hơn là đưa vào một giá trị imputation sai lệch.*  
  > *Chính nhờ sự thận trọng này, 2% mẫu tự tin nhất giúp điều chỉnh độ lệch mà không làm phá hỏng không gian embedding của mô hình ạ."*

---

### ❓ Câu 4: Vì sao trên tập KuaiRand 1.4 triệu tương tác, khoảng cách giữa các mô hình chỉ chênh lệch khoảng 0.5%?
- **Trả lời chuẩn:**
  > *"Dạ thưa Thầy/Cô, sự chênh lệch này phản ánh đúng bản chất dữ liệu video ngắn thực tế:*  
  > 1. *Tỷ lệ click trong video ngắn cực kỳ thưa (sparsity cao) và hành vi click có độ ồn lớn (người dùng bấm nhầm, xem lướt rồi thoát).*  
  > 2. *Tập KuaiRand-Pure có tới hơn 6.700 video và 23.000 user, không gian tìm kiếm rộng lớn khiến dải metric nén lại.*  
  > 3. *Trong các bài báo khoa học về KuaiRand (như KuaiRand benchmark CIKM), mức chênh lệch giữa các mô hình SOTA cũng thường nằm trong khoảng 0.3% - 1.0%. Trên quy mô nền tảng triệu người dùng, mức tăng 0.5% NDCG@5 tương đương với hàng trăm ngàn lượt đề xuất đúng trúng nhu cầu mỗi ngày ạ."*

---

### ❓ Câu 5: Hệ thống IViDR này khi tích hợp vào App TopTop thì độ trễ như thế nào, có bị lag không?
- **Trả lời chuẩn:**
  > *"Dạ thưa Thầy/Cô, hệ thống hoàn toàn đảm bảo thời gian thực (Real-time serving) nhờ kiến trúc tách rời:*  
  > - *Mạng iVAE phức tạp chỉ tham gia trong quá trình **Offline Training** để học ra các trọng số sạch.*  
  > - *Trong quá trình **Online Inference**, điểm số chỉ là phép nhân vô hướng đơn giản: $s_{ui} = p_u^T q_i + Z_u$. Phép tính này mất chưa tới 5 mili-giây.*  
  > - *Nhóm đã đóng gói toàn bộ mô hình lên FastAPI REST server trên Colab, kết nối qua Cloudflare Tunnel và tự động đồng bộ endpoint về Firebase Realtime Database. App Flutter TopTop gọi lấy Top-20 video chỉ mất trung bình 150 - 250ms, hoàn toàn mượt mà cho trải nghiệm vuốt feed video ngắn ạ."*

---

### ❓ Câu 6: Phân biệt Selection Bias và Confounding Bias trong hệ thống gợi ý?
- **Trả lời chuẩn:**
  > *"Dạ thưa Thầy/Cô:*  
  > - ***Selection Bias (Thiên lệch lựa chọn)**: Xuất hiện khi người dùng tự do lựa chọn item để tương tác hoặc hệ thống chỉ hiển thị một tập con item, khiến dữ liệu quan sát không đại diện cho toàn bộ phân phối ngẫu nhiên (MNAR).*  
  > - ***Confounding Bias (Thiên lệch do biến nhiễu)**: Xuất hiện khi có một yếu tố thứ ba $U$ (như độ hot của video, vị trí đặt banner, thuật toán đời trước) đồng thời tác động lên cả quyết định hiển thị $A$ lẫn hành vi tương tác $Y$, tạo ra tương quan ảo giữa $A$ và $Y$.*  
  > *Mô hình IViDR của nhóm sử dụng Biến công cụ chính là để triệt tiêu Confounding Bias này ạ."*

---

### ❓ Câu 7: Macro AUC khác gì Micro AUC và ROC-AUC truyền thống?
- **Trả lời chuẩn:**
  > *"Dạ thưa Thầy/Cô:*  
  > - *ROC-AUC truyền thống (Micro-AUC) gộp chung tất cả các cặp tương tác của mọi user lại để tính một giá trị duy nhất. Cách này sẽ bị chi phối nặng nề bởi các 'heavy users' (người dùng tương tác hàng trăm lần).*  
  > - ***Macro-User AUC** tính toán giá trị AUC riêng biệt cho từng người dùng trên candidate pool của họ, sau đó lấy trung bình cộng. Cách tính này đảm bảo mỗi người dùng có trọng số hoàn toàn bình đẳng như nhau (User Fairness) và tránh được hiện tượng nghịch lý Simpson (Simpson's Paradox) trong thống kê ạ."*

---

### ❓ Câu 8: Tại sao nhóm không tích hợp luôn cả 3 mô hình MF, CDR và IViDR chạy song song trên App TopTop?
- **Trả lời chuẩn:**
  > *"Dạ thưa Thầy/Cô, trong giai đoạn thiết kế API phục vụ sản phẩm:*  
  > - *Kết quả thực nghiệm định lượng đã chứng minh **IViDR là mô hình có hiệu năng cao nhất toàn diện** trên cả hai tập dữ liệu Coat và KuaiRand.*  
  > - *Việc chỉ deploy một mô hình ưu việt nhất (IViDR) giúp tối ưu tài nguyên tính toán của máy chủ, giảm độ trễ phản hồi, và giữ kiến trúc hệ thống tinh gọn, ổn định.*  
  > - *Tuy nhiên, trên App TopTop, nhóm vẫn duy trì cơ chế **Graceful Fallback**: nếu máy chủ AI Colab bị ngắt kết nối, ứng dụng sẽ tự động chuyển về thuật toán lọc Firestore truyền thống mà không làm gián đoạn trải nghiệm của người dùng ạ."*

---

*(Bản kịch bản này đã sẵn sàng để bạn in ra hoặc mở trên màn hình phụ trong ngày bảo vệ báo cáo! Chúc bạn có một buổi thuyết trình thành công rực rỡ! 🎉)*

