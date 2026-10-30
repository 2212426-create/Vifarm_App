# Benchmark v4: kết quả theo giao thức từng mô hình

**SMOKE TEST — MF/iDCF subset 64 user; dữ liệu CDR theo metadata riêng, không dùng so điểm bài báo.**

**Thời gian cập nhật:** 2026-10-30 13:42:34

Ranking trên exposure đã ghi log. MF/iDCF chọn checkpoint bằng validation; CDR source dừng theo train loss.
Bảng chỉ hiển thị Recall@5 bounded; JSON giữ cả hai Recall. AUC có giá trị và loại riêng ở từng dòng.
H30: split 30/70 theo user, loại zero-positive; S-full: toàn random log và giữ empty-positive Recall=1; S-KR: dữ liệu KuaiRand địa phương.
LCDR cài đặt lại từ paper (không có mã tác giả) trên pipeline iDCF, cùng protocol H30. C-src: ConAlign theo source (seed 0, para()); tháp unbiased trên test unbiased; Coat/Yahoo chia ngẫu nhiên, rating >=4; KuaiRand train 22/04-05/05 theo paper. NDCG@5 = NDCG của source (user có cả hai nhãn); không có Recall bounded/HitRate.
MF/iDCF/LCDR giữ MSE; IViDR, CDR và ConAlign dùng BCE. IViDR: BCE trên xác suất đã marginalize, giai đoạn 1 prior mean 0 và mẫu âm trọng số .1 (khác Eq. 42/25 của paper); coordinate adapter Eq. (10) ghi trong metadata, chưa chứng nhận tái lập tác giả. Không paired-test chéo protocol.
Tất cả điểm đo từ checkpoint thực, không thay bằng số paper. CDR source dùng một phần nhãn random chấm điểm để calibration, không phải held-out độc lập.

### Kết quả theo giao thức từng mô hình:

| Tập dữ liệu       | Mô hình       | Giao thức |  NDCG@5  | Recall@5 bounded | Precision@5 | HitRate@5 |   AUC    | Loại AUC   |
| :---------------- | :------------ | :-------: | -------: | ---------------: | ----------: | --------: | -------: | :--------- |
| **KuaiRand-Pure** | MF            |    H30    | 0.485544 |         0.620968 |    0.245161 |  0.838710 | 0.471529 | macro-user |
| **KuaiRand-Pure** | iDCF          |    H30    | 0.531144 |         0.671505 |    0.277419 |  0.870968 | 0.531691 | macro-user |
| **KuaiRand-Pure** | IViDR         |    H30    | 0.569758 |         0.664516 |    0.270968 |  0.903226 | 0.591393 | macro-user |
| **KuaiRand-Pure** | LCDR          |    H30    | 0.554737 |         0.713441 |    0.290323 |  0.967742 | 0.527667 | macro-user |
| **KuaiRand-Pure** | DR-BIAS + CDR |   S-KR    | 0.524673 |         0.682258 |    0.277419 |  0.935484 | 0.510491 | global     |
| **KuaiRand-Pure** | ConAlign      |   C-src   | 0.315974 |              N/A |    0.200000 |       N/A | 0.554330 | global     |

- ConAlign KuaiRand-Pure: UAUC 0.493780 | UNDCG@5 0.363148 | Recall (source) 0.405681

Recall@5 bounded = hits/min(5,n_positive). CDR S-full giữ empty-positive Recall=1; Precision/HitRate=0. Recall/all positives vẫn lưu trong JSON.
Gộp để đọc kết quả; các dòng khác protocol không tương đương về điều kiện thực nghiệm.

### Candidate pool kuairand

- Users: 50; zero-positive users: 19; candidates: 402.
- Positive prevalence: 0.2164; candidate size p10/p50/p90: [2.0, 4.5, 18.1].
- Cold users: 0.00%; cold candidates: 0.00%.
- Validation positive prevalence: 0.2683; validation candidate p50: 5.

- MF: ΔNDCG@5 so với Popularity = -0.1809; CI95 NDCG của mô hình, theo user ≈ ±0.1164.
- iDCF: ΔNDCG@5 so với Popularity = -0.1353; CI95 NDCG của mô hình, theo user ≈ ±0.1143.
- IViDR: ΔNDCG@5 so với Popularity = -0.0967; CI95 NDCG của mô hình, theo user ≈ ±0.1192.
- LCDR: ΔNDCG@5 so với Popularity = -0.1117; CI95 NDCG của mô hình, theo user ≈ ±0.1055.

### Kiểm định theo cặp user (kuairand, test)

| So sánh | ΔNDCG@5 | CI95 | Wilcoxon p | Thắng / thua (user) |
| :-- | --: | --: | --: | :--: |
| MF vs Popularity | -0.1809 | ±0.0972 | 0.00266 | 5 / 18 |
| iDCF vs Popularity | -0.1353 | ±0.1070 | 0.024 | 7 / 17 |
| iDCF vs MF | +0.0456 | ±0.0532 | 0.0427 | 14 / 4 |
| IViDR vs Popularity | -0.0967 | ±0.1143 | 0.154 | 8 / 13 |
| IViDR vs MF | +0.0842 | ±0.0918 | 0.0667 | 18 / 7 |
| LCDR vs Popularity | -0.1117 | ±0.0866 | 0.0356 | 7 / 16 |
| LCDR vs MF | +0.0692 | ±0.0506 | 0.0208 | 12 / 3 |

p < 0.05: khác biệt có ý nghĩa thống kê trên tập user này (một seed huấn luyện; chưa tính biến thiên seed).

### Giới hạn sai số

- Khoảng tin cậy trong JSON là xấp xỉ theo người dùng của một lần chạy; chưa bao gồm biến thiên do seed hoặc chọn cấu hình.
- Random (expected) là kỳ vọng xếp hạng ngẫu nhiên có điều kiện trên candidate pool hiện có; Popularity dùng tần suất exposure trong train.
- KuaiRand dùng is_click, ghép hai standard log, lọc user/item tối thiểu 10 exposure một lượt và chia random log theo user. CDR source calibration 5% validation; dữ liệu/sampler là adaptation địa phương.
- Coat H30 dùng rating ≥4 và split user seed 1234; CDR S-full dùng rating ≥3, toàn bộ 4.640 random ratings. Giữ overlap train/random.
- Yahoo H30 dùng rating ≥4, raw IDs trừ 1; CDR S-full dùng ≥3 và giữ raw IDs. iDCF dùng survey thật, user thiếu survey có missing category; đây là mở rộng địa phương.
- iDCF dùng exposure iVAE rồi feedback MSE. IViDR dùng learned IV và hai posterior, feature embedding học được, sau đó tối ưu BCE trên xác suất đã marginalize; Eq. (10) có coordinate adapter được công bố trong metadata.
