# Benchmark v4: kết quả theo giao thức từng mô hình

**SMOKE TEST — MF/iDCF subset 64 user; dữ liệu CDR theo metadata riêng, không dùng so điểm bài báo.**

**Thời gian cập nhật:** 2026-10-20 22:50:33

Chỉ xếp hạng các exposure đã ghi log. Chọn epoch trên validation; test giữ riêng.
Chỉ số chính: NDCG@5 và Recall@5. AUC là chỉ số phụ lấy trung bình theo user có hai lớp; không mặc định tương đương AUC trong bài CDR.
Coat/Yahoo/KuaiRand chia random log theo user, 30% validation / 70% test; macro metric chỉ chấm user có nhãn dương.
MF/iDCF giữ MSE; CDR-BCE huấn luyện độc lập. CDR mặc định dùng source protocol, bảng riêng bên dưới; không thuộc kiểm định theo cặp của giao thức chung. IViDR-approx chưa thuộc bộ chuẩn.
Đây là đánh giá trên giao thức chung của dự án; không ghép điểm từ các bài báo có giao thức khác vào bảng này.

### Kết quả trên held-out test:

| Tập Dữ Liệu       | Mô Hình Thuật Toán | NDCG@5 | Recall@5 | Precision@5 | HitRate@5 | AUC (macro-user) |
| :---------------- | :----------------- | :----: | :------: | :---------: | :-------: | :--------------: |
| **KuaiRand-Pure** | MF                 | 0.4855 |  0.6145  |   0.2452    |  0.8387   |      0.4715      |
| **KuaiRand-Pure** | iDCF               | 0.5311 |  0.6618  |   0.2774    |  0.8710   |      0.5317      |

### CDR theo source protocol

Coat/Yahoo: rating >=3, toàn random log, 5% nhãn random chấm điểm để calibration, zero-positive nhận 1; Recall bounded và AUC toàn cục.
KuaiRand: cùng thuật toán released, dữ liệu/sampler được điều chỉnh và ghi metadata; calibration 5% validation, Recall chia toàn bộ positive.
Các dòng này có giao thức khác bảng held-out MF/iDCF; không dùng để kết luận mô hình nào tốt hơn.

| Dataset  |  NDCG@5  | Recall bounded | Recall/all positives | AUC global |
| :------- | -------: | -------------: | -------------------: | ---------: |
| kuairand | 0.524673 |            N/A |             0.672581 |   0.510491 |

- kuairand: seed 2020, epochs run 1; selection train-loss/last. Adaptations: ['local KuaiRand preprocessing/user split; original processed CSVs unavailable', 'array trainer sampling instead of source Torch DataLoader', 'zero-based local user IDs, including user 0 in evaluation', 'global AUC half-credit ties instead of source arbitrary tie ranks', 'smoke-only calibration expanded to all validation rows to retain both classes'].

### Candidate pool kuairand

- Users: 50; zero-positive users: 19; candidates: 402.
- Positive prevalence: 0.2164; candidate size p10/p50/p90: [2.0, 4.5, 18.1].
- Cold users: 0.00%; cold candidates: 0.00%.
- Validation positive prevalence: 0.2683; validation candidate p50: 5.

- MF: ΔNDCG@5 so với Popularity = -0.1809; CI95 NDCG của mô hình, theo user ≈ ±0.1164.
- iDCF: ΔNDCG@5 so với Popularity = -0.1353; CI95 NDCG của mô hình, theo user ≈ ±0.1143.

### Kiểm định theo cặp user (kuairand, test)

| So sánh | ΔNDCG@5 | CI95 | Wilcoxon p | Thắng / thua (user) |
| :-- | --: | --: | --: | :--: |
| MF vs Popularity | -0.1809 | ±0.0972 | 0.00266 | 5 / 18 |
| iDCF vs Popularity | -0.1353 | ±0.1070 | 0.024 | 7 / 17 |
| iDCF vs MF | +0.0456 | ±0.0532 | 0.0427 | 14 / 4 |

p < 0.05: khác biệt có ý nghĩa thống kê trên tập user này (một seed huấn luyện; chưa tính biến thiên seed).

### Giới hạn sai số

- Khoảng tin cậy trong JSON là xấp xỉ theo người dùng của một lần chạy; chưa bao gồm biến thiên do seed hoặc chọn cấu hình.
- Random (expected) là kỳ vọng xếp hạng ngẫu nhiên có điều kiện trên candidate pool hiện có; Popularity dùng tần suất exposure trong train.
- KuaiRand dùng duy nhất is_click, ghép hai standard log, lọc user/item tối thiểu 10 exposure một lượt và chia random log theo user. CDR dùng tần suất exposure theo item làm proxy propensity.
- Coat dùng rating ≥ 4 là dương; 6.960 biased ratings để train và 4.640 random ratings chia theo user seed 1234. Các cặp trùng train/test giữ nguyên để đối chiếu giao thức bài báo.
- Yahoo dùng rating ≥ 4, raw IDs trừ 1; survey thực làm proxy iDCF, các user không có survey nhận missing category. Đây là mở rộng dataset, chưa phải kết quả Yahoo của paper iDCF.
- iDCF/IViDR huấn luyện 2 giai đoạn như mã tác giả iDCF: iVAE trên vector exposure của user (W = đặc trưng user one-hot), rồi MF + <e_i, C_u> với MSE. IViDR thêm nhánh C1 từ treatment MF tái tạo bằng 2SLS (giả định địa phương; tác giả chưa công bố mã).
