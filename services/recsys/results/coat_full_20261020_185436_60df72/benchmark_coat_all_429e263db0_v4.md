# Benchmark v4: validation và test độc lập

**Benchmark đầy đủ dữ liệu; một seed huấn luyện, chọn checkpoint bằng validation.**

**Thời gian cập nhật:** 2026-10-20 18:54:54

Chỉ xếp hạng các exposure đã ghi log. Chọn epoch trên validation; test giữ riêng.
Chỉ số chính: NDCG@5 và Recall@5. AUC là chỉ số phụ lấy trung bình theo user có hai lớp; không mặc định tương đương AUC trong bài CDR.
Coat và KuaiRand chia random log theo user, 30% validation / 70% test; macro metric chỉ chấm user có nhãn dương.
MF/iDCF giữ loss MSE của mã iDCF; CDR khởi tạo độc lập, BCE và Eq. (7), không nạp MF-MSE. IViDR-approx chỉ chạy khi yêu cầu riêng, chưa phải IViDR chuẩn.
Đây là đánh giá trên giao thức chung của dự án; không ghép điểm từ các bài báo có giao thức khác vào bảng này.

### Kết quả trên held-out test:

| Tập Dữ Liệu | Mô Hình Thuật Toán | NDCG@5 | Recall@5 | Precision@5 | HitRate@5 | AUC (macro-user) |
| :---------- | :----------------- | :----: | :------: | :---------: | :-------: | :--------------: |
| **Coat**    | MF                 | 0.5476 |  0.5295  |   0.3497    |  0.8503   |      0.6931      |
| **Coat**    | iDCF               | 0.4637 |  0.4775  |   0.3281    |  0.8144   |      0.6728      |
| **Coat**    | DR-BIAS + CDR      | 0.3770 |  0.4008  |   0.2683    |  0.7605   |      0.5609      |

### Candidate pool coat

- Users: 203; zero-positive users: 36; candidates: 3,248.
- Positive prevalence: 0.1930; candidate size p10/p50/p90: [16.0, 16.0, 16.0].
- Cold users: 0.00%; cold candidates: 0.00%.
- Validation positive prevalence: 0.1674; validation candidate p50: 16.

- MF: ΔNDCG@5 so với Popularity = +0.1965; CI95 NDCG của mô hình, theo user ≈ ±0.0500.
- iDCF: ΔNDCG@5 so với Popularity = +0.1126; CI95 NDCG của mô hình, theo user ≈ ±0.0478.
- DR-BIAS + CDR: ΔNDCG@5 so với Popularity = +0.0259; CI95 NDCG của mô hình, theo user ≈ ±0.0446.

### Kiểm định theo cặp user (coat, test)

| So sánh | ΔNDCG@5 | CI95 | Wilcoxon p | Thắng / thua (user) |
| :-- | --: | --: | --: | :--: |
| MF vs Popularity | +0.1965 | ±0.0550 | 3.31e-10 | 105 / 39 |
| iDCF vs Popularity | +0.1126 | ±0.0528 | 8.3e-05 | 90 / 50 |
| iDCF vs MF | -0.0839 | ±0.0481 | 0.00118 | 50 / 81 |
| DR-BIAS + CDR vs Popularity | +0.0259 | ±0.0616 | 0.514 | 77 / 69 |
| DR-BIAS + CDR vs MF | -0.1706 | ±0.0580 | 3.07e-07 | 47 / 98 |

p < 0.05: khác biệt có ý nghĩa thống kê trên tập user này (một seed huấn luyện; chưa tính biến thiên seed).

Coat train/random overlap: 366 cặp; test overlap: 247 cặp, gồm 63 cặp dương.

### Giới hạn sai số

- Khoảng tin cậy trong JSON là xấp xỉ theo người dùng của một lần chạy; chưa bao gồm biến thiên do seed hoặc chọn cấu hình.
- Random (expected) là kỳ vọng xếp hạng ngẫu nhiên có điều kiện trên candidate pool hiện có; Popularity dùng tần suất exposure trong train.
- KuaiRand dùng duy nhất is_click, ghép hai standard log, lọc user/item tối thiểu 10 exposure một lượt và chia random log theo user. CDR dùng tần suất exposure theo item làm proxy propensity.
- Coat dùng rating ≥ 4 là dương; 6.960 biased ratings để train và 4.640 random ratings chia theo user seed 1234. Các cặp trùng train/test giữ nguyên để đối chiếu giao thức bài báo.
- iDCF/IViDR huấn luyện 2 giai đoạn như mã tác giả iDCF: iVAE trên vector exposure của user (W = đặc trưng user one-hot), rồi MF + <e_i, C_u> với MSE. IViDR thêm nhánh C1 từ treatment MF tái tạo bằng 2SLS (giả định địa phương; tác giả chưa công bố mã).
