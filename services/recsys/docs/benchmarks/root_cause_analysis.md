# Khác biệt protocol của CDR và các kết luận còn dùng

Phân tích này giải thích vì sao DR-BIAS + CDR đạt .6567 theo script tác giả nhưng thấp hơn nhiều trên protocol H30
của dự án. Phân tích IViDR nằm ở [tài liệu riêng](ividr_root_cause_20261027.md); định nghĩa mô hình ở
[paper_model_alignment](paper_model_alignment.md).

## Đối chứng với mã CDR công bố

Chạy các lớp và điều kiện của script tác giả (commit `6b4e6cca3df23b8d85b38fdc2e7eb5c812861ea9`) cho
NDCG@5 **.656665**, Recall@5 bounded **.667816**, làm tròn đúng .6567 / .6678 của
[CDR Table 2](https://jiawei-chen.github.io/paper/CIKM23-CDR.pdf). Hai ma trận train/test khớp mọi giá trị với
repository gốc, nên không có lỗi tải nhầm dữ liệu.

| Thành phần | Protocol H30 của dự án | Script CDR công bố |
| :-- | :-- | :-- |
| Positive | rating ≥4 | rating ≥3 |
| Tập chấm | 203 user test riêng | Toàn bộ 290 user random log |
| User không positive | Loại khỏi macro | NDCG/Recall bằng 1 |
| Recall | Chia toàn bộ positive | Chia số positive tối đa trong top K |
| Propensity | Hiệu chỉnh từ validation | 5% nhãn random log, cũng là nhãn dùng chấm điểm |

Paper mô tả rating >3 và split 10/90, không đồng nhất với script.

Điểm mấu chốt: giữ nguyên checkpoint của script nhưng chấm theo ≥4/test pool của dự án chỉ còn NDCG **.479693**.
Con số này vẫn là chẩn đoán vì checkpoint đã dùng một phần nhãn random để hiệu chỉnh propensity. Vì vậy chênh lệch
giữa .6567 và các mô hình H30 chủ yếu đến từ protocol, không phải chất lượng mô hình. Dự án giữ CDR source protocol
làm mặc định theo quyết định của người dùng và ghi protocol từng dòng; không paired-test chéo protocol.

## DR-BIAS + CDR

Các đính chính của dự án; công thức và nội dung bài báo nằm ở PDF và bản chép paper.

- Chênh điểm CDR có cả khác giao thức lẫn bất nhất loss/filter ở bản cũ; không kết luận "chỉ do dữ liệu" hoặc "chỉ do BCE".
- Những lượt CDR chọn MF epoch 0 là warm-start ablation, không phải thành tích của CDR nguyên bản.
  Benchmark, tuning và seed runner không nạp checkpoint MF.
- CDR paper cho phép nhiều hàm error. Bản hiện hành chọn BCE; không suy ra mọi MF phải đổi sang BCE.
- Port `cdr-author` cũ không tương đương bitwise mã công bố; hiện `cdr-author` là alias của `cdr-source`.
- Với bản Eq. (7) trên protocol H30, bộ lọc imputation đang bảo vệ mô hình: nới ngưỡng làm validation giảm
  (eta .1 → .4986, eta 1 → .3718, không còn lọc → .3635), nên không nới bộ lọc để tăng điểm.

## iDCF trên Coat

Cấu hình iVAE ví dụ (32/64/2) khác checkpoint Coat đã tune của tác giả (latent 16, hidden 32, 3 lớp, đọc trực tiếp
từ shape của `coat_val_ivae_exposure_best.pt`). Dự án dùng 16/32/3, patience 100 và chỉ chọn checkpoint sau khi KL
warm-up đạt full beta; trước sửa, iVAE dừng ở beta ≈ .13. Sau các sửa đổi này iDCF Coat tăng từ .4637 lên .5699
(một seed, chưa tách riêng tác động của từng thay đổi).
