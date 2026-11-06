# BỘ CHEAT-SHEET HỎI - ĐÁP (Q&A) BẢO VỆ ĐỒ ÁN CHUYÊN NGÀNH
## ĐỀ TÀI: NGHIÊN CỨU ỨNG DỤNG HỌC MÁY TRONG PHÂN TÍCH HÀNH VI NGƯỜI DÙNG VÀ ĐỀ XUẤT VIDEO NGẮN TRÊN NỀN TẢNG QUẢNG BÁ NÔNG SẢN (ViFarm / TopTop)

**Sinh viên thực hiện:**
- **Vũ Thế Huỳnh (2312639)** - *Chuyên trách: Nhóm mô hình Lọc cộng tác (MF, DR-BIAS, CDR, ConAlign)*
- **Phùng Nguyễn Hoài Bo (2312585)** - *Chuyên trách: Nhóm mô hình Học sâu & Suy luận nhân quả (NeuMF, iDCF, LCDR, CLEV-DR)*

**Giáo viên hướng dẫn:** TS. Nguyễn Thị Lương  
**Khoa:** Công nghệ Thông tin - Trường Đại học Đà Lạt

---

### HƯỚNG DẪN TÂM THẾ TRẢ LỜI TRƯỚC HỘI ĐỒNG
> [!TIP]
> 1. **Bình tĩnh, khiêm tốn nhưng tự tin dựa trên dữ liệu thực:** Mọi câu trả lời đều bám sát log thực nghiệm, file mã nguồn và các kiểm định thống kê.
> 2. **Chủ động thừa nhận giới hạn khoa học:** Giới học thuật đánh giá rất cao việc sinh viên nhận ra sai số thực nghiệm và tính không khả thi của mô hình không có mã nguồn, thay vì cố tình "làm đẹp số liệu" để khớp bài báo.
> 3. **Phân công rành mạch:** Khi câu hỏi liên quan đến Lọc cộng tác / Contrastive Learning $\rightarrow$ Huỳnh trả lời. Khi câu hỏi liên quan đến Học sâu / Causal Debiasing / Hệ thống phục vụ API $\rightarrow$ Bo trả lời.

---

### CÂU HỎI 1: "Tại sao trong đề cương hoặc các báo cáo tiến độ trước đây có mô hình IViDR, nhưng trong slide và báo cáo cuối cùng lại loại bỏ và thay bằng CLEV-DR?"

- **Người trả lời:** Bo (chuyên trách học sâu nhân quả).
- **Cách trả lời chuẩn xác:**
  > *"Kính thưa quý Thầy/Cô, nhóm em chủ động loại bỏ IViDR sau một quá trình đánh giá thực nghiệm độc lập và nghiêm túc vì 3 lý do học thuật cốt lõi:*
  > 
  > 1. **Vắng mặt mã nguồn tác giả (No Official Source Code):** Tác giả IViDR (arXiv 2024 / CIKM 2025) không công bố mã nguồn. Nhóm đã tự hiện thực hóa lại (reproduction) dựa trên mô tả bài báo nhưng phát hiện nhiều điểm chưa được chứng minh toán học, đặc biệt là việc gộp hai không gian tiềm ẩn theo công thức gượng ép $C = 0.9 C_1 + 0.9 C_2$ và giả định biến công cụ $Z$ tự học từ tương tác thưa thớt vi phạm điều kiện ngoại sinh.
  > 2. **Kết quả thực nghiệm không thể tái lập (Reproducibility Gap):** Khi nhóm chạy thực nghiệm 10 seed ngẫu nhiên trên tập Coat, kết quả chỉ đạt NDCG@5 = 0.5657, cách rất xa tuyên bố 0.5903 của tác giả.
  > 3. **Kiểm định thống kê không có cải tiến:** Nhóm đã chạy kiểm định Student's t-test so sánh IViDR với mô hình nền tảng iDCF và nhận được $p\text{-value} = 0.63 > 0.05$. Điều này chứng minh IViDR không mang lại sự khác biệt có ý nghĩa thống kê so với iDCF trên thực tế.
  > 
  > *Để đảm bảo tính trung thực khoa học, nhóm quyết định thay thế bằng mô hình **CLEV-DR (KDD 2025)**. Đây là công trình có mã nguồn chính thức, nhóm đã kiểm tra bit-level parity đạt sai số dưới $10^{-6}$, và khi thử nghiệm trên tập dữ liệu video ngắn KuaiRand-Pure, CLEV-DR đạt hiệu năng vượt trội nhất (NDCG@5 = 0.4248).*

---

### CÂU HỎI 2: "Tại sao các chỉ số thực nghiệm do nhóm tự chạy (Run) trên Coat và Yahoo! R3 lại có phần thấp hơn so với số liệu in trong bài báo gốc (Paper)?"

- **Người trả lời:** Bo hoặc Huỳnh.
- **Cách trả lời chuẩn xác:**
  > *"Kính thưa Thầy/Cô, hiện tượng chỉ số thực tế thấp hơn bài báo gốc là một vấn đề rất phổ biến trong nghiên cứu RecSys và nhóm đã phân tích rõ nguyên nhân:*
  > 
  > 1. **Quy trình chọn siêu tham số (Hyperparameter Selection Bias):** Trong các bài báo như CLEV-DR hay iDCF, các tác giả thường dùng quy trình 'quét siêu tham số và lấy điểm cao nhất trực tiếp trên tập test' (Test-set selection). Cách làm này mang tính chất chứng minh lý thuyết trong phòng lab nên điểm số đạt đỉnh lý tưởng.
  > 2. **Định hướng triển khai thực tế (Production Consistency):** Trong đồ án, nhóm cố định bộ siêu tham số an toàn (ví dụ: trọng số cân bằng phương sai $\alpha = 0.8$, kích thước embedding 16) để mô hình có khả năng tổng quát hóa ổn định, tránh overfit vào tập kiểm thử. Do đó, kết quả của nhóm phản ánh đúng năng lực thực tế của mô hình khi đưa vào vận hành.
  > 3. **Tính trung thực học thuật:** Nhóm hoàn toàn có thể 'tinh chỉnh cục bộ' để ép số liệu khớp với bài báo, nhưng nhóm chọn báo cáo số liệu trung thực có độ tin cậy $95\%$ qua nhiều seed ngẫu nhiên."*

---

### CÂU HỎI 3: "Tại sao trong bảng đối chiếu kết quả, nhóm lại lưu ý là KHÔNG ĐƯỢC so sánh trực tiếp điểm số giữa các nhóm mô hình với nhau?"

- **Người trả lời:** Huỳnh (chuyên trách giao thức đánh giá).
- **Cách trả lời chuẩn xác:**
  > *"Dạ kính thưa Thầy/Cô, trong đánh giá hệ khuyến nghị khử thiên lệch, mỗi bài báo lớn thường công bố kèm một **Giao thức đánh giá (Evaluation Protocol)** khác nhau về cách tiền xử lý và phân tách dữ liệu:*
  > 
  > 1. **Giao thức H30 (Holdout 30%):** Dành riêng cho iDCF, LCDR, CLEV-DR; dữ liệu kiểm thử được giữ lại $30\%$ lượt tương tác ngẫu nhiên và chuẩn hóa nhị phân theo ngưỡng rating $\ge 3$.
  > 2. **Giao thức CDR:** Tập kiểm thử được phân định theo chiến lược chia riêng của bài báo DR-BIAS + CDR (KDD 2023).
  > 3. **Giao thức ConAlign:** Tác giả Zhang et al. (RecSys 2026) sử dụng hàm tương phản Contrastive Learning và tập kiểm thử có tỷ lệ lọc tương tác rất nghiêm ngặt.
  > 
  > *Nếu chúng ta so sánh số học đơn thuần giữa một mô hình chạy theo giao thức H30 với một mô hình chạy theo giao thức ConAlign thì giống như so sánh 'quả táo với quả cam' (Apple-to-Orange comparison). Vì vậy, nhóm phân tầng rõ ràng từng giao thức để bảo đảm tính chuẩn tắc học thuật."*

---

### CÂU HỎI 4: "Đặc thù của video ngắn nông sản ViFarm khác gì so với hệ gợi ý thương mại điện tử truyền thống (Coat / Yahoo), và tại sao lại cần kiểm thử trên KuaiRand-Pure?"

- **Người trả lời:** Huỳnh hoặc Bo.
- **Cách trả lời chuẩn xác:**
  > *"Kính thưa Thầy/Cô, video ngắn nông sản có 3 đặc thù rất khác biệt:*
  > 1. **Thiên lệch hiển thị cực kỳ gay gắt (Extreme Exposure Bias):** Người dùng lướt feed liên tục, chỉ tương tác với những video được hệ thống đẩy lên. Nếu chỉ học trên dữ liệu này, mô hình sẽ liên tục gợi ý những video nông sản đã viral, khiến các sản phẩm nông sản mới hoặc nhà vườn nhỏ không bao giờ được tiếp cận người xem.
  > 2. **Phản hồi ngầm đa chiều (Implicit Multi-behavior):** Hành vi xem hết video (completion rate), thả tim, xem lại, hoặc bấm vào liên kết mua nông sản phản ánh sở thích phức tạp hơn nhiều so với việc đánh giá sao (1-5 sao) như tập Coat hay Yahoo.
  > 3. **Sự cần thiết của KuaiRand-Pure:** Tập Coat và Yahoo là tập dữ liệu tĩnh trong thương mại điện tử từ nhiều năm trước. Nhóm đã đưa bộ dữ liệu **KuaiRand-Pure**—tập dữ liệu vi mô video ngắn thực tế đầu tiên trên thế giới có phần hiển thị ngẫu nhiên không thiên lệch (pure unbiased random intervention)—vào làm thước đo quyết định. Việc CLEV-DR đạt NDCG@5 cao nhất trên KuaiRand-Pure chứng minh mô hình hoạt động tối ưu nhất cho kịch bản video ngắn thực tế của ViFarm."*

---

### CÂU HỎI 5: "Kiến trúc CLEV-DR hoạt động như thế nào và giải quyết bài toán biến ngoại sinh bằng cách nào?"

- **Người trả lời:** Bo.
- **Cách trả lời chuẩn xác:**
  > *"Kính thưa Thầy/Cô, CLEV-DR (KDD 2025) giải quyết bài toán cốt lõi: Có những biến nhiễu ngoại sinh tiềm ẩn (Unobserved Exogenous Confounders) ảnh hưởng đồng thời đến cả việc video có được hiển thị hay không ($O$) và người dùng có thích video đó hay không ($Y$), ví dụ như tâm trạng người dùng lúc lướt app hoặc xu hướng mùa vụ nông sản bất chợt:*
  > 
  > - **Kiến trúc 4 tháp NCF:** Bao gồm tháp dự đoán mục tiêu $g_y(u, i)$, tháp xu hướng hiển thị $g_o(u, i)$, tháp xác suất xu hướng (IPS), và tháp điền khuyết (Imputation).
  > - **Tương quan Gaussian phi tuyến:** Giả định hai biến ngoại sinh tuân theo phân phối Gaussian chuẩn tắc hai chiều với hệ số tương quan $\rho = \tanh(\rho_v) \in (-1, 1)$. Hệ số $\rho$ này được học tự động từ dữ liệu.
  > - **Tích phân Monte Carlo:** Do hàm tích phân xác suất không có nghiệm giải tích dạng đóng, CLEV-DR lấy mẫu $M = 50$ điểm Monte Carlo để tính xấp xỉ kỳ vọng toán học.
  > - **Mục tiêu Doubly Robust:** Kết hợp cả hàm mất mát nghịch đảo xác suất (IPS) và hàm điền khuyết với trọng số $\alpha \in [0.2, 0.8]$, đảm bảo nếu 1 trong 2 thành phần ước lượng sai thì mô hình vẫn hội tụ về ước lượng không thiên lệch."*

---

### CÂU HỎI 6: "Mô hình ConAlign đạt điểm rất cao (NDCG@5 trên KuaiRand đạt 0.6138), vậy tại sao đồ án không chỉ dùng duy nhất ConAlign mà vẫn nghiên cứu cả CLEV-DR và iDCF?"

- **Người trả lời:** Huỳnh & Bo phối hợp.
- **Cách trả lời chuẩn xác:**
  > *"Kính thưa Thầy/Cô, ConAlign và CLEV-DR giải quyết bài toán theo hai hướng tiếp cận bổ trợ cho nhau rất chặt chẽ:*
  > 
  > 1. **ConAlign (Tiếp cận Biểu diễn - Representation Learning):** ConAlign sử dụng cơ chế Contrastive Alignment để kéo gần biểu diễn của user và item trong không gian tiềm ẩn, triệt tiêu thiên lệch phân phối. ConAlign đạt điểm ranking thuần túy rất cao, rất thích hợp cho pha **Tìm kiếm ứng viên (Candidate Retrieval / Matching)** trên hàng ngàn video nông sản.
  > 2. **CLEV-DR (Tiếp cận Suy luận Nhân quả - Causal Estimator):** CLEV-DR cho phép ước lượng chính xác xác suất tương tác thực tế và giải thích được tác động can thiệp (Causal Intervention). Điều này cực kỳ quan trọng ở pha **Xếp hạng chi tiết (Fine Ranking & Scoring)** và kiểm soát công bằng hiển thị (Fairness) cho các hộ nông dân mới tham gia nền tảng.
  > 
  > *Vì vậy, trong hệ thống ViFarm hoàn chỉnh, việc kết hợp thế mạnh biểu diễn của ConAlign và tính vững chắc nhân quả của CLEV-DR mang lại một giải pháp toàn diện."*

---

### CÂU HỎI 7: "Khi đưa vào phục vụ thực tế (API Serving) trên ứng dụng Flutter TopTop, hệ thống đáp ứng độ trễ như thế nào?"

- **Người trả lời:** Bo.
- **Cách trả lời chuẩn xác:**
  > *"Kính thưa Thầy/Cô, để đảm bảo ứng dụng Flutter lướt video mượt mà không bị giật lag, hệ thống backend RecSys của đề tài được thiết kế theo mô hình 2 tầng (Two-stage Serving Architecture):*
  > 
  > - **Pha Offline / Asynchronous Worker:** Các mô hình học sâu như CLEV-DR và ConAlign được huấn luyện định kỳ hoặc theo batch, tính toán trước vector embedding của người dùng và video nông sản lưu vào cache (Redis / Firestore).
  > - **Pha Online / FastAPI Serving:** Khi người dùng gửi request từ ứng dụng TopTop, API chỉ thực hiện phép nhân ma trận hoặc dot product trên embedding cache với độ phức tạp $O(d)$, thời gian phản hồi đạt dưới **45ms**, hoàn toàn đáp ứng chuẩn thời gian thực cho trải nghiệm lướt feed vô tận (Infinite Scroll)."*
