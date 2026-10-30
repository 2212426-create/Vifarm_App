# Benchmark v4: kết quả theo giao thức từng mô hình

**SMOKE TEST — MF/iDCF subset 64 user; dữ liệu CDR theo metadata riêng, không dùng so điểm bài báo.**

**Thời gian cập nhật:** 2026-10-21 09:59:32

Ranking trên exposure đã ghi log. MF/iDCF chọn checkpoint bằng validation; CDR source dừng theo train loss.
Bảng chỉ hiển thị Recall@5 bounded; JSON giữ cả hai Recall. AUC có giá trị và loại riêng ở từng dòng.
H30: split 30/70 theo user, loại zero-positive; S-full: toàn random log và giữ empty-positive Recall=1; S-KR: dữ liệu KuaiRand địa phương.
MF/iDCF/IViDR-approx giữ MSE, CDR giữ BCE. IViDR-approx được chạy theo yêu cầu, chưa tái lập paper. Không paired-test chéo protocol.
Tất cả điểm đo từ checkpoint thực, không thay bằng số paper. CDR source dùng một phần nhãn random chấm điểm để calibration, không phải held-out độc lập.

### Kết quả theo giao thức từng mô hình:

| Tập dữ liệu       | Mô hình       | Giao thức |  NDCG@5  | Recall@5 bounded | Precision@5 | HitRate@5 |   AUC    | Loại AUC   |
| :---------------- | :------------ | :-------: | -------: | ---------------: | ----------: | --------: | -------: | :--------- |
| **KuaiRand-Pure** | MF            |    H30    | 0.485544 |         0.620968 |    0.245161 |  0.838710 | 0.471529 | macro-user |
| **KuaiRand-Pure** | iDCF          |    H30    | 0.531144 |         0.671505 |    0.277419 |  0.870968 | 0.531691 | macro-user |
| **KuaiRand-Pure** | IViDR-approx  |    H30    | 0.549258 |         0.691935 |    0.277419 |  0.967742 | 0.545587 | macro-user |
| **KuaiRand-Pure** | DR-BIAS + CDR |   S-KR    | 0.524673 |         0.682258 |    0.277419 |  0.935484 | 0.510491 | global     |

Recall@5 bounded = hits/min(5,n_positive). CDR S-full giữ empty-positive Recall=1; Precision/HitRate=0. Recall/all positives vẫn lưu trong JSON.
Gộp để đọc kết quả; các dòng khác protocol không tương đương về điều kiện thực nghiệm.

### Candidate pool kuairand

- Users: 50; zero-positive users: 19; candidates: 402.
- Positive prevalence: 0.2164; candidate size p10/p50/p90: [2.0, 4.5, 18.1].
- Cold users: 0.00%; cold candidates: 0.00%.
- Validation positive prevalence: 0.2683; validation candidate p50: 5.

- MF: ΔNDCG@5 so với Popularity = -0.1809; CI95 NDCG của mô hình, theo user ≈ ±0.1164.
- iDCF: ΔNDCG@5 so với Popularity = -0.1353; CI95 NDCG của mô hình, theo user ≈ ±0.1143.
- IViDR: ΔNDCG@5 so với Popularity = -0.1172; CI95 NDCG của mô hình, theo user ≈ ±0.1119.

### Kiểm định theo cặp user (kuairand, test)

| So sánh | ΔNDCG@5 | CI95 | Wilcoxon p | Thắng / thua (user) |
| :-- | --: | --: | --: | :--: |
| MF vs Popularity | -0.1809 | ±0.0972 | 0.00266 | 5 / 18 |
| iDCF vs Popularity | -0.1353 | ±0.1070 | 0.024 | 7 / 17 |
| iDCF vs MF | +0.0456 | ±0.0532 | 0.0427 | 14 / 4 |
| IViDR vs Popularity | -0.1172 | ±0.0965 | 0.0331 | 7 / 16 |
| IViDR vs MF | +0.0637 | ±0.0644 | 0.0419 | 16 / 6 |

p < 0.05: khác biệt có ý nghĩa thống kê trên tập user này (một seed huấn luyện; chưa tính biến thiên seed).

### Giới hạn sai số

- Khoảng tin cậy trong JSON là xấp xỉ theo người dùng của một lần chạy; chưa bao gồm biến thiên do seed hoặc chọn cấu hình.
- Random (expected) là kỳ vọng xếp hạng ngẫu nhiên có điều kiện trên candidate pool hiện có; Popularity dùng tần suất exposure trong train.
- KuaiRand dùng is_click, ghép hai standard log, lọc user/item tối thiểu 10 exposure một lượt và chia random log theo user. CDR source calibration 5% validation; dữ liệu/sampler là adaptation địa phương.
- Coat H30 dùng rating ≥4 và split user seed 1234; CDR S-full dùng rating ≥3, toàn bộ 4.640 random ratings. Giữ overlap train/random.
- Yahoo H30 dùng rating ≥4, raw IDs trừ 1; CDR S-full dùng ≥3 và giữ raw IDs. iDCF dùng survey thật, user thiếu survey có missing category; đây là mở rộng địa phương.
- iDCF/IViDR huấn luyện 2 giai đoạn như mã tác giả iDCF: iVAE trên vector exposure của user (W = đặc trưng user one-hot), rồi MF + <e_i, C_u> với MSE. IViDR thêm nhánh C1 từ treatment MF tái tạo bằng 2SLS (giả định địa phương; tác giả chưa công bố mã).
