# Benchmark v4: kết quả theo giao thức từng mô hình

**Đầy đủ dữ liệu; mỗi mô hình huấn luyện và đánh giá theo giao thức ghi ở từng dòng.**

**Thời gian cập nhật:** 2026-10-30 13:33:26

Ranking trên exposure đã ghi log. MF/iDCF chọn checkpoint bằng validation; CDR source dừng theo train loss.
Bảng chỉ hiển thị Recall@5 bounded; JSON giữ cả hai Recall. AUC có giá trị và loại riêng ở từng dòng.
H30: split 30/70 theo user, loại zero-positive; S-full: toàn random log và giữ empty-positive Recall=1; S-KR: dữ liệu KuaiRand địa phương.
MF/iDCF giữ MSE; IViDR và CDR dùng BCE. IViDR: BCE trên xác suất đã marginalize, giai đoạn 1 prior mean 0 và mẫu âm trọng số .1 (khác Eq. 42/25 của paper); coordinate adapter Eq. (10) ghi trong metadata, chưa chứng nhận tái lập tác giả. Không paired-test chéo protocol.
Tất cả điểm đo từ checkpoint thực, không thay bằng số paper. CDR source dùng một phần nhãn random chấm điểm để calibration, không phải held-out độc lập.

### Kết quả theo giao thức từng mô hình:

| Tập dữ liệu       | Mô hình | Giao thức |  NDCG@5  | Recall@5 bounded | Precision@5 | HitRate@5 |   AUC    | Loại AUC   |
| :---------------- | :------ | :-------: | -------: | ---------------: | ----------: | --------: | -------: | :--------- |
| **KuaiRand-Pure** | IViDR   |    H30    | 0.409491 |         0.456803 |    0.309228 |  0.780995 | 0.611478 | macro-user |

Recall@5 bounded = hits/min(5,n_positive). CDR S-full giữ empty-positive Recall=1; Precision/HitRate=0. Recall/all positives vẫn lưu trong JSON.
Gộp để đọc kết quả; các dòng khác protocol không tương đương về điều kiện thực nghiệm.

### Candidate pool kuairand

- Users: 16,473; zero-positive users: 2,971; candidates: 671,360.
- Positive prevalence: 0.1764; candidate size p10/p50/p90: [10.0, 20.0, 93.0].
- Cold users: 0.00%; cold candidates: 0.00%.
- Validation positive prevalence: 0.1782; validation candidate p50: 20.

- IViDR: ΔNDCG@5 so với Popularity = +0.0517; CI95 NDCG của mô hình, theo user ≈ ±0.0051.

### Kiểm định theo cặp user (kuairand, test)

| So sánh | ΔNDCG@5 | CI95 | Wilcoxon p | Thắng / thua (user) |
| :-- | --: | --: | --: | :--: |
| IViDR vs Popularity | +0.0517 | ±0.0046 | 7.04e-113 | 6312 / 4176 |

p < 0.05: khác biệt có ý nghĩa thống kê trên tập user này (một seed huấn luyện; chưa tính biến thiên seed).

### Giới hạn sai số

- Khoảng tin cậy trong JSON là xấp xỉ theo người dùng của một lần chạy; chưa bao gồm biến thiên do seed hoặc chọn cấu hình.
- Random (expected) là kỳ vọng xếp hạng ngẫu nhiên có điều kiện trên candidate pool hiện có; Popularity dùng tần suất exposure trong train.
- KuaiRand dùng is_click, ghép hai standard log, lọc user/item tối thiểu 10 exposure một lượt và chia random log theo user. CDR source calibration 5% validation; dữ liệu/sampler là adaptation địa phương.
- Coat H30 dùng rating ≥4 và split user seed 1234; CDR S-full dùng rating ≥3, toàn bộ 4.640 random ratings. Giữ overlap train/random.
- Yahoo H30 dùng rating ≥4, raw IDs trừ 1; CDR S-full dùng ≥3 và giữ raw IDs. iDCF dùng survey thật, user thiếu survey có missing category; đây là mở rộng địa phương.
- iDCF dùng exposure iVAE rồi feedback MSE. IViDR dùng learned IV và hai posterior, feature embedding học được, sau đó tối ưu BCE trên xác suất đã marginalize; Eq. (10) có coordinate adapter được công bố trong metadata.
