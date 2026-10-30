# Benchmark v4: kết quả theo giao thức từng mô hình

**SMOKE TEST — kiểm tra vận hành, chưa phải kết quả hội tụ.**

**Thời gian cập nhật:** 2026-10-30 13:41:14

Ranking trên exposure đã ghi log. MF/iDCF chọn checkpoint bằng validation; CDR source dừng theo train loss.
Bảng chỉ hiển thị Recall@5 bounded; JSON giữ cả hai Recall. AUC có giá trị và loại riêng ở từng dòng.
H30: split 30/70 theo user, loại zero-positive; S-full: toàn random log và giữ empty-positive Recall=1; S-KR: dữ liệu KuaiRand địa phương.
LCDR cài đặt lại từ paper (không có mã tác giả) trên pipeline iDCF, cùng protocol H30. C-src: ConAlign theo source (seed 0, para()); tháp unbiased trên test unbiased; Coat/Yahoo chia ngẫu nhiên, rating >=4; KuaiRand train 22/04-05/05 theo paper. NDCG@5 = NDCG của source (user có cả hai nhãn); không có Recall bounded/HitRate.
MF/iDCF/LCDR giữ MSE; IViDR, CDR và ConAlign dùng BCE. IViDR: BCE trên xác suất đã marginalize, giai đoạn 1 prior mean 0 và mẫu âm trọng số .1 (khác Eq. 42/25 của paper); coordinate adapter Eq. (10) ghi trong metadata, chưa chứng nhận tái lập tác giả. Không paired-test chéo protocol.
Tất cả điểm đo từ checkpoint thực, không thay bằng số paper. CDR source dùng một phần nhãn random chấm điểm để calibration, không phải held-out độc lập.

### Kết quả theo giao thức từng mô hình:

| Tập dữ liệu | Mô hình       | Giao thức |  NDCG@5  | Recall@5 bounded | Precision@5 | HitRate@5 |   AUC    | Loại AUC   |
| :---------- | :------------ | :-------: | -------: | ---------------: | ----------: | --------: | -------: | :--------- |
| **Coat**    | MF            |    H30    | 0.356273 |         0.429641 |    0.273054 |  0.724551 | 0.560906 | macro-user |
| **Coat**    | iDCF          |    H30    | 0.375360 |         0.457186 |    0.283832 |  0.760479 | 0.596855 | macro-user |
| **Coat**    | IViDR         |    H30    | 0.388053 |         0.464770 |    0.294611 |  0.760479 | 0.614349 | macro-user |
| **Coat**    | LCDR          |    H30    | 0.376627 |         0.453792 |    0.283832 |  0.760479 | 0.585741 | macro-user |
| **Coat**    | DR-BIAS + CDR |  S-full   | 0.540071 |         0.554483 |    0.451724 |  0.882759 | 0.624691 | global     |
| **Coat**    | ConAlign      |   C-src   | 0.603922 |              N/A |    0.309827 |       N/A | 0.633157 | global     |

- ConAlign Coat: UAUC 0.575661 | UNDCG@5 0.610673 | Recall (source) 0.836788

Recall@5 bounded = hits/min(5,n_positive). CDR S-full giữ empty-positive Recall=1; Precision/HitRate=0. Recall/all positives vẫn lưu trong JSON.
Gộp để đọc kết quả; các dòng khác protocol không tương đương về điều kiện thực nghiệm.

### Candidate pool coat

- Users: 203; zero-positive users: 36; candidates: 3,248.
- Positive prevalence: 0.1930; candidate size p10/p50/p90: [16.0, 16.0, 16.0].
- Cold users: 0.00%; cold candidates: 0.00%.
- Validation positive prevalence: 0.1674; validation candidate p50: 16.

- MF: ΔNDCG@5 so với Popularity = +0.0052; CI95 NDCG của mô hình, theo user ≈ ±0.0447.
- iDCF: ΔNDCG@5 so với Popularity = +0.0243; CI95 NDCG của mô hình, theo user ≈ ±0.0440.
- IViDR: ΔNDCG@5 so với Popularity = +0.0369; CI95 NDCG của mô hình, theo user ≈ ±0.0472.
- LCDR: ΔNDCG@5 so với Popularity = +0.0255; CI95 NDCG của mô hình, theo user ≈ ±0.0456.

### Kiểm định theo cặp user (coat, test)

| So sánh | ΔNDCG@5 | CI95 | Wilcoxon p | Thắng / thua (user) |
| :-- | --: | --: | --: | :--: |
| MF vs Popularity | +0.0052 | ±0.0482 | 0.528 | 70 / 62 |
| iDCF vs Popularity | +0.0243 | ±0.0448 | 0.355 | 68 / 62 |
| iDCF vs MF | +0.0191 | ±0.0347 | 0.256 | 69 / 56 |
| IViDR vs Popularity | +0.0369 | ±0.0459 | 0.129 | 69 / 53 |
| IViDR vs MF | +0.0318 | ±0.0412 | 0.15 | 74 / 56 |
| LCDR vs Popularity | +0.0255 | ±0.0471 | 0.33 | 71 / 62 |
| LCDR vs MF | +0.0204 | ±0.0310 | 0.113 | 67 / 49 |

p < 0.05: khác biệt có ý nghĩa thống kê trên tập user này (một seed huấn luyện; chưa tính biến thiên seed).

Coat train/random overlap: 366 cặp; test overlap: 247 cặp, gồm 63 cặp dương.

### Cấu hình CDR Coat

- Implementation: `cdr_released`; selection: `source_train_loss_last`.
- LR 0.05, weight decay 0.001, batch 256, eta 10.0, patience None.

### Giới hạn sai số

- Khoảng tin cậy trong JSON là xấp xỉ theo người dùng của một lần chạy; chưa bao gồm biến thiên do seed hoặc chọn cấu hình.
- Random (expected) là kỳ vọng xếp hạng ngẫu nhiên có điều kiện trên candidate pool hiện có; Popularity dùng tần suất exposure trong train.
- KuaiRand dùng is_click, ghép hai standard log, lọc user/item tối thiểu 10 exposure một lượt và chia random log theo user. CDR source calibration 5% validation; dữ liệu/sampler là adaptation địa phương.
- Coat H30 dùng rating ≥4 và split user seed 1234; CDR S-full dùng rating ≥3, toàn bộ 4.640 random ratings. Giữ overlap train/random.
- Yahoo H30 dùng rating ≥4, raw IDs trừ 1; CDR S-full dùng ≥3 và giữ raw IDs. iDCF dùng survey thật, user thiếu survey có missing category; đây là mở rộng địa phương.
- iDCF dùng exposure iVAE rồi feedback MSE. IViDR dùng learned IV và hai posterior, feature embedding học được, sau đó tối ưu BCE trên xác suất đã marginalize; Eq. (10) có coordinate adapter được công bố trong metadata.
