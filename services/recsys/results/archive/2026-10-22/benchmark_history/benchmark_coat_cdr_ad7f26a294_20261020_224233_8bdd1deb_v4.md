# Benchmark v4: validation và test độc lập

**Benchmark đầy đủ dữ liệu; một seed huấn luyện, chọn checkpoint bằng validation.**

**Thời gian cập nhật:** 2026-10-20 22:42:56

Chỉ xếp hạng các exposure đã ghi log. Chọn epoch trên validation; test giữ riêng.
Chỉ số chính: NDCG@5 và Recall@5. AUC là chỉ số phụ lấy trung bình theo user có hai lớp; không mặc định tương đương AUC trong bài CDR.
Coat/Yahoo/KuaiRand chia random log theo user, 30% validation / 70% test; macro metric chỉ chấm user có nhãn dương.
MF/iDCF giữ MSE; CDR-BCE huấn luyện độc lập. CDR mặc định dùng source protocol, bảng riêng bên dưới; không thuộc kiểm định theo cặp của giao thức chung. IViDR-approx chưa thuộc bộ chuẩn.
Đây là đánh giá trên giao thức chung của dự án; không ghép điểm từ các bài báo có giao thức khác vào bảng này.

### Kết quả trên held-out test:

| Tập Dữ Liệu | Mô Hình Thuật Toán | NDCG@5 | Recall@5 | Precision@5 | HitRate@5 | AUC (macro-user) |
| :---------- | :----------------- | :----: | :------: | :---------: | :-------: | :--------------: |

### CDR theo source protocol

Coat/Yahoo: rating >=3, toàn random log, 5% nhãn random chấm điểm để calibration, zero-positive nhận 1; Recall bounded và AUC toàn cục.
KuaiRand: cùng thuật toán released, dữ liệu/sampler được điều chỉnh và ghi metadata; calibration 5% validation, Recall chia toàn bộ positive.
Các dòng này có giao thức khác bảng held-out MF/iDCF; không dùng để kết luận mô hình nào tốt hơn.

| Dataset |  NDCG@5  | Recall bounded | Recall/all positives | AUC global |
| :------ | -------: | -------------: | -------------------: | ---------: |
| coat    | 0.656665 |       0.667816 |                  N/A |   0.751293 |

- coat: seed 2020, epochs run 29; selection train-loss/last. Adaptations: [].

### Candidate pool coat

- Users: 203; zero-positive users: 36; candidates: 3,248.
- Positive prevalence: 0.1930; candidate size p10/p50/p90: [16.0, 16.0, 16.0].
- Cold users: 0.00%; cold candidates: 0.00%.
- Validation positive prevalence: 0.1674; validation candidate p50: 16.


Coat train/random overlap: 366 cặp; test overlap: 247 cặp, gồm 63 cặp dương.

### Cấu hình CDR Coat

- Implementation: `cdr_released`; propensity: `None`.
- LR 0.05, weight decay 0.001, batch 128, eta 10.0, patience None.

### Giới hạn sai số

- Khoảng tin cậy trong JSON là xấp xỉ theo người dùng của một lần chạy; chưa bao gồm biến thiên do seed hoặc chọn cấu hình.
- Random (expected) là kỳ vọng xếp hạng ngẫu nhiên có điều kiện trên candidate pool hiện có; Popularity dùng tần suất exposure trong train.
- KuaiRand dùng duy nhất is_click, ghép hai standard log, lọc user/item tối thiểu 10 exposure một lượt và chia random log theo user. CDR dùng tần suất exposure theo item làm proxy propensity.
- Coat dùng rating ≥ 4 là dương; 6.960 biased ratings để train và 4.640 random ratings chia theo user seed 1234. Các cặp trùng train/test giữ nguyên để đối chiếu giao thức bài báo.
- Yahoo dùng rating ≥ 4, raw IDs trừ 1; survey thực làm proxy iDCF, các user không có survey nhận missing category. Đây là mở rộng dataset, chưa phải kết quả Yahoo của paper iDCF.
- iDCF/IViDR huấn luyện 2 giai đoạn như mã tác giả iDCF: iVAE trên vector exposure của user (W = đặc trưng user one-hot), rồi MF + <e_i, C_u> với MSE. IViDR thêm nhánh C1 từ treatment MF tái tạo bằng 2SLS (giả định địa phương; tác giả chưa công bố mã).
