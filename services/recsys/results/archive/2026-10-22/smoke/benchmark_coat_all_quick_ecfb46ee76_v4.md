# Benchmark v4: validation và test độc lập

**SMOKE TEST — kiểm tra vận hành, chưa phải kết quả hội tụ.**

**Thời gian cập nhật:** 2026-10-20 18:52:18

Chỉ xếp hạng các exposure đã ghi log. Chọn epoch trên validation; test giữ riêng.
Chỉ số chính: NDCG@5 và Recall@5. AUC là chỉ số phụ lấy trung bình theo user có hai lớp; không mặc định tương đương AUC trong bài CDR.
Coat và KuaiRand chia random log theo user, 30% validation / 70% test; macro metric chỉ chấm user có nhãn dương.
MF/iDCF giữ loss MSE của mã iDCF; CDR khởi tạo độc lập, BCE và Eq. (7), không nạp MF-MSE. IViDR-approx chỉ chạy khi yêu cầu riêng, chưa phải IViDR chuẩn.
Đây là đánh giá trên giao thức chung của dự án; không ghép điểm từ các bài báo có giao thức khác vào bảng này.

### Kết quả trên held-out test:

| Tập Dữ Liệu | Mô Hình Thuật Toán | NDCG@5 | Recall@5 | Precision@5 | HitRate@5 | AUC (macro-user) |
| :---------- | :----------------- | :----: | :------: | :---------: | :-------: | :--------------: |
| **Coat**    | MF                 | 0.3563 |  0.3820  |   0.2731    |  0.7246   |      0.5609      |
| **Coat**    | iDCF               | 0.3590 |  0.3421  |   0.2743    |  0.6826   |      0.5528      |
| **Coat**    | DR-BIAS + CDR      | 0.3593 |  0.3896  |   0.2671    |  0.7784   |      0.5524      |

### Candidate pool coat

- Users: 203; zero-positive users: 36; candidates: 3,248.
- Positive prevalence: 0.1930; candidate size p10/p50/p90: [16.0, 16.0, 16.0].
- Cold users: 0.00%; cold candidates: 0.00%.
- Validation positive prevalence: 0.1674; validation candidate p50: 16.

- MF: ΔNDCG@5 so với Popularity = +0.0052; CI95 NDCG của mô hình, theo user ≈ ±0.0447.
- iDCF: ΔNDCG@5 so với Popularity = +0.0079; CI95 NDCG của mô hình, theo user ≈ ±0.0488.
- DR-BIAS + CDR: ΔNDCG@5 so với Popularity = +0.0082; CI95 NDCG của mô hình, theo user ≈ ±0.0420.

### Kiểm định theo cặp user (coat, test)

| So sánh | ΔNDCG@5 | CI95 | Wilcoxon p | Thắng / thua (user) |
| :-- | --: | --: | --: | :--: |
| MF vs Popularity | +0.0052 | ±0.0482 | 0.528 | 70 / 62 |
| iDCF vs Popularity | +0.0079 | ±0.0475 | 0.482 | 69 / 59 |
| iDCF vs MF | +0.0027 | ±0.0285 | 0.469 | 60 / 50 |
| DR-BIAS + CDR vs Popularity | +0.0082 | ±0.0574 | 0.922 | 70 / 75 |
| DR-BIAS + CDR vs MF | +0.0030 | ±0.0559 | 0.985 | 69 / 73 |

p < 0.05: khác biệt có ý nghĩa thống kê trên tập user này (một seed huấn luyện; chưa tính biến thiên seed).

Coat train/random overlap: 366 cặp; test overlap: 247 cặp, gồm 63 cặp dương.

### Giới hạn sai số

- Khoảng tin cậy trong JSON là xấp xỉ theo người dùng của một lần chạy; chưa bao gồm biến thiên do seed hoặc chọn cấu hình.
- Random (expected) là kỳ vọng xếp hạng ngẫu nhiên có điều kiện trên candidate pool hiện có; Popularity dùng tần suất exposure trong train.
- KuaiRand dùng duy nhất is_click, ghép hai standard log, lọc user/item tối thiểu 10 exposure một lượt và chia random log theo user. CDR dùng tần suất exposure theo item làm proxy propensity.
- Coat dùng rating ≥ 4 là dương; 6.960 biased ratings để train và 4.640 random ratings chia theo user seed 1234. Các cặp trùng train/test giữ nguyên để đối chiếu giao thức bài báo.
- iDCF/IViDR huấn luyện 2 giai đoạn như mã tác giả iDCF: iVAE trên vector exposure của user (W = đặc trưng user one-hot), rồi MF + <e_i, C_u> với MSE. IViDR thêm nhánh C1 từ treatment MF tái tạo bằng 2SLS (giả định địa phương; tác giả chưa công bố mã).
