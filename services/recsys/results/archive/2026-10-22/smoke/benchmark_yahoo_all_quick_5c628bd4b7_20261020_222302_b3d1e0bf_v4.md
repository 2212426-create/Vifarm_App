# Benchmark v4: validation và test độc lập

**SMOKE TEST — kiểm tra vận hành, chưa phải kết quả hội tụ.**

**Thời gian cập nhật:** 2026-10-20 22:23:30

Chỉ xếp hạng các exposure đã ghi log. Chọn epoch trên validation; test giữ riêng.
Chỉ số chính: NDCG@5 và Recall@5. AUC là chỉ số phụ lấy trung bình theo user có hai lớp; không mặc định tương đương AUC trong bài CDR.
Coat/Yahoo/KuaiRand chia random log theo user, 30% validation / 70% test; macro metric chỉ chấm user có nhãn dương.
MF/iDCF giữ MSE; CDR-BCE huấn luyện độc lập. Coat/Yahoo mặc định dùng thuật toán released CDR; KuaiRand dùng Eq. (7). Metadata ghi implementation từng model. IViDR-approx chưa thuộc bộ chuẩn.
Đây là đánh giá trên giao thức chung của dự án; không ghép điểm từ các bài báo có giao thức khác vào bảng này.

### Kết quả trên held-out test:

| Tập Dữ Liệu   | Mô Hình Thuật Toán | NDCG@5 | Recall@5 | Precision@5 | HitRate@5 | AUC (macro-user) |
| :------------ | :----------------- | :----: | :------: | :---------: | :-------: | :--------------: |
| **Yahoo! R3** | MF                 | 0.5407 |  0.6766  |   0.2519    |  0.8308   |      0.6595      |
| **Yahoo! R3** | iDCF               | 0.5495 |  0.7006  |   0.2583    |  0.8506   |      0.6695      |
| **Yahoo! R3** | DR-BIAS + CDR      | 0.4311 |  0.5968  |   0.2235    |  0.7669   |      0.5735      |

### Candidate pool yahoo

- Users: 3,780; zero-positive users: 2,060; candidates: 37,800.
- Positive prevalence: 0.0894; candidate size p10/p50/p90: [10.0, 10.0, 10.0].
- Cold users: 0.00%; cold candidates: 0.00%.
- Validation positive prevalence: 0.0845; validation candidate p50: 10.

- MF: ΔNDCG@5 so với Popularity = +0.0488; CI95 NDCG của mô hình, theo user ≈ ±0.0158.
- iDCF: ΔNDCG@5 so với Popularity = +0.0577; CI95 NDCG của mô hình, theo user ≈ ±0.0154.
- DR-BIAS + CDR: ΔNDCG@5 so với Popularity = -0.0608; CI95 NDCG của mô hình, theo user ≈ ±0.0149.

### Kiểm định theo cặp user (yahoo, test)

| So sánh | ΔNDCG@5 | CI95 | Wilcoxon p | Thắng / thua (user) |
| :-- | --: | --: | --: | :--: |
| MF vs Popularity | +0.0488 | ±0.0102 | 2.69e-23 | 656 / 337 |
| iDCF vs Popularity | +0.0577 | ±0.0130 | 7.91e-15 | 684 / 454 |
| iDCF vs MF | +0.0088 | ±0.0115 | 0.493 | 532 / 522 |
| DR-BIAS + CDR vs Popularity | -0.0608 | ±0.0221 | 7.06e-09 | 661 / 862 |
| DR-BIAS + CDR vs MF | -0.1096 | ±0.0205 | 5.65e-25 | 551 / 920 |

p < 0.05: khác biệt có ý nghĩa thống kê trên tập user này (một seed huấn luyện; chưa tính biến thiên seed).

### Giới hạn sai số

- Khoảng tin cậy trong JSON là xấp xỉ theo người dùng của một lần chạy; chưa bao gồm biến thiên do seed hoặc chọn cấu hình.
- Random (expected) là kỳ vọng xếp hạng ngẫu nhiên có điều kiện trên candidate pool hiện có; Popularity dùng tần suất exposure trong train.
- KuaiRand dùng duy nhất is_click, ghép hai standard log, lọc user/item tối thiểu 10 exposure một lượt và chia random log theo user. CDR dùng tần suất exposure theo item làm proxy propensity.
- Coat dùng rating ≥ 4 là dương; 6.960 biased ratings để train và 4.640 random ratings chia theo user seed 1234. Các cặp trùng train/test giữ nguyên để đối chiếu giao thức bài báo.
- Yahoo dùng rating ≥ 4, raw IDs trừ 1; survey thực làm proxy iDCF, các user không có survey nhận missing category. Đây là mở rộng dataset, chưa phải kết quả Yahoo của paper iDCF.
- iDCF/IViDR huấn luyện 2 giai đoạn như mã tác giả iDCF: iVAE trên vector exposure của user (W = đặc trưng user one-hot), rồi MF + <e_i, C_u> với MSE. IViDR thêm nhánh C1 từ treatment MF tái tạo bằng 2SLS (giả định địa phương; tác giả chưa công bố mã).
