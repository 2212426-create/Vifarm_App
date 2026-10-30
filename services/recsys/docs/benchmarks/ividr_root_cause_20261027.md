# IViDR thấp hơn paper: phân tích nguyên nhân — 27/10/2026

Mục tiêu: giải thích vì sao IViDR của project đạt NDCG@5 khoảng .53 trên Coat, trong khi paper
báo .5903 ± .0101. Mọi thí nghiệm dùng Coat, protocol H30, seed 42/43/44; chọn cấu hình bằng
validation, test chấm một lần. Không sửa mô hình mặc định trong đợt này.
Tiếp nối [ablation Eq. (10)](ividr_eq10_ablation_20261027.md). Script và log:
[thư mục bằng chứng](../archive/2026-10-27/ividr_rootcause/factorial.py); báo cáo
`results/ividr_rootcause_*_20261027.json`.

## 1. Mốc đối chiếu cùng seed

| Mô hình | Feedback | Val NDCG@5 | Test NDCG@5 mean ± std |
| :-- | :-- | --: | --: |
| MF | MSE | .6110 | .5396 ± .0286 |
| iDCF | MSE | .5991 | .5755 ± .0072 |
| IViDR v2 | BCE kỳ vọng (Eq. 25) | .5707 | .5315 ± .0101 |
| Paper IViDR / iDCF / MF | — | — | .5903 / .5638 / .5590 |

MF và iDCF của project đạt hoặc vượt số paper, nên dữ liệu, split và evaluator không giải thích
được khoảng cách riêng của IViDR.

## 2. Thí nghiệm hoán đổi hai giai đoạn

Giữ latent đã lưu, chỉ huấn luyện lại giai đoạn feedback ([factorial.py](../archive/2026-10-27/ividr_rootcause/factorial.py)).

| Latent \ feedback | MSE (iDCF) | BCE kỳ vọng (IViDR) |
| :-- | --: | --: |
| Latent iDCF (\|mean\| ≈ .37, std ≈ 1.2) | **.5755** | .4764 |
| Latent IViDR (\|mean\| ≈ 4.3, std ≈ .6) | .4604, chọn ở epoch 2 | .5315 |
| Latent IViDR gộp (C1+C2)/2 thay .9C1+.9C2 | — | .5326 |
| Latent IViDR trừ offset theo chiều | — | .4973 |

## 3. Giả thuyết đã kiểm tra

| Giả thuyết | Phép thử tối thiểu | Kết quả |
| :-- | :-- | :-- |
| Nhánh IV Eq. (10) bị triệt tiêu | v3 chuẩn hóa phần cộng, ablation T/F/R | Phần cộng 0.3% → 100% nhưng NDCG không đổi: **bác bỏ** là nguyên nhân chính |
| Suy luận lấy tích phân phương sai làm méo thứ hạng | Chấm lại checkpoint với c_std = 0 ([script](../archive/2026-10-27/ividr_rootcause/marginal_inference.py)) | Thay đổi ≤ .003: **bác bỏ** |
| Hệ số gộp ρ = τ = .9 làm latent quá lớn | Dùng (C1+C2)/2 | .5326 so với .5315: **bác bỏ** |
| BCE bị học thiếu vì lưới LR của paper dừng ở 1e-3 | LR 1e-3/3e-3/1e-2, tối đa 300 epoch ([script](../archive/2026-10-27/ividr_rootcause/bce_budget.py)) | Không cải thiện, dừng sớm trước giới hạn: **bác bỏ** |
| Mục tiêu BCE tự nó kém hơn MSE trên dữ liệu này | MF không latent với đầu BCE | Xem mục 4: **xác nhận** |

## 4. Nguyên nhân

**Nguyên nhân chính: mục tiêu feedback BCE.** MF không có latent, chỉ đổi MSE sang BCE:

| Mô hình | Val NDCG@5 | Test NDCG@5 |
| :-- | --: | --: |
| MF + MSE | .6110 | .5396 ± .0286 |
| MF + BCE, LR 1e-3 / 3e-3 / 1e-2 | .5421 / .5448 / .5402 | .4897 / .4990 / .5016 |

Riêng việc đổi sang BCE đã làm validation giảm khoảng .07 và test giảm khoảng .04–.05. Latent iDCF
không giúp gì dưới BCE (.4764, ngang MF + BCE). Latent IViDR kéo lên .53 chủ yếu nhờ phần offset
lớn: trừ offset thì về .4973. Như vậy IViDR mang sẵn mức thiệt hại của BCE, và nhánh latent chỉ
bù lại một phần.

**Nguyên nhân phụ: thang đo latent giai đoạn 1.** Eq. (42) dùng prior $N(\mu_w(W), v_w(W))$ với
mean học được. Project làm đúng như vậy, còn mã iDCF cố định mean prior bằng 0. Kết quả là latent
IViDR lệch lớn (|mean| ≈ 4.3, gấp khoảng 10 lần iDCF) và gần như tất định. Vì thế chỉ đổi feedback
sang MSE **không** sửa được IViDR: đầu MSE overfit ngay epoch 2 (.4604).

**Vì sao paper vẫn đạt .5903:** không xác định được từ bằng chứng hiện có. Paper không công bố mã
và không mô tả init, thang latent hay chi tiết huấn luyện BCE. MF/iDCF baseline của paper khớp với
MSE của project. Bản BCE trong project mất khoảng .05 ngay cả với MF thuần, nên nhiều khả năng cách
huấn luyện BCE của tác giả khác project ở một chi tiết chưa được công bố.

## 5. Theo hướng 2 (giữ BCE): tìm chi tiết huấn luyện, 28/10/2026

Người dùng chọn giữ BCE. Script và log: [thư mục 28/10](../archive/2026-10-28/ividr_bce/mf_objective.py);
báo cáo `results/ividr_bce_*_20261028.json`. Coat, seed 42/43/44, chọn bằng validation.

**Regularization: bác bỏ.** MF + BCE với dim {64, 16, 4} × weight decay {1e-5 … 1e-2}: tăng regularization
hoặc giảm dim đều làm điểm thấp hơn; tốt nhất vẫn là dim 64, weight decay nhỏ (val .544).

**Một vòng huấn luyện, mỗi lần đổi một chi tiết**
([mf_objective.py](../archive/2026-10-28/ividr_bce/mf_objective.py)):

| MF, cùng vòng huấn luyện | Val NDCG@5 | Test NDCG@5 |
| :-- | --: | --: |
| MSE (đối chứng) | .6177 | .5353 ± .0199 |
| BCE | .5160 | .4853 ± .0452 |
| BCE + global bias | .5334 | .5106 ± .0098 |
| BCE, init N(0, .1²) | .5012 | .4749 ± .0247 |
| BCE, trọng số mẫu âm .5 | .5420 | .5135 ± .0066 |
| **BCE, trọng số mẫu âm .2** | **.6066** | .5191 ± .0121 |

Chi tiết quyết định là **trọng số của mẫu âm**. Mẫu âm của Coat là món user tự chọn xem rồi chấm thấp,
nên vẫn gần gu của họ. BCE phạt chúng mạnh ngay từ đầu (sai số ±.5 khi điểm ≈ 0), còn MSE gần như bỏ qua
(sai số ≈ 0). Giảm trọng số mẫu âm có quan hệ liều–đáp ứng rõ, và ở .2 đưa validation về mức MSE.
Trainer có tùy chọn `negative_weight` (mặc định 1, chỉ dùng cho BCE); paper không nhắc chi tiết này.

**Áp vào đầu feedback của IViDR** ([ividr_weighted.py](../archive/2026-10-28/ividr_bce/ividr_weighted.py),
lưới lr/wd của paper):

| Latent | Trọng số mẫu âm | Val NDCG@5 | Test NDCG@5 |
| :-- | :-- | --: | --: |
| iDCF | 1 (BCE gốc) | .5269 | .4764 ± .0180 |
| iDCF | .2 | .5905 | .5439 ± .0074 |
| IViDR v2 | 1 (mặc định) | .5707 | .5315 ± .0101 |
| IViDR v2 | .2 | .5612 | .5116 ± .0407 (một seed .4646) |
| IViDR v2 | .1 | .5761 | .5391 ± .0037 |

Trọng số mẫu âm sửa được BCE cho latent iDCF (+.067 test). Với latent IViDR, mức tăng tốt nhất
(.1: +.008 test, +.005 validation) nằm trong nhiễu seed. Lý do: latent IViDR có offset lớn do prior mean
học được (mục 4), nên trước đó đã tự bù một phần cho BCE. Mức thiệt hại còn lại gắn với **thang đo latent
giai đoạn 1**, không còn nằm ở hàm loss. IViDR vẫn thấp hơn paper (.5903) khoảng .05.

## 6. Prior mean bằng 0 kèm BCE có trọng số mẫu âm, 28/10/2026

Theo đồng ý của người dùng, giai đoạn 1 được huấn luyện lại với prior $N(0, v_w(W))$ như mã iDCF
(`ivae_overrides=dict(prior_mean='zero')`). Đây là thay đổi **lệch khỏi Eq. (42)**. Eq. (10) giữ v2.
Bước feedback dùng BCE kỳ vọng Eq. (25) với `negative_weight`, dò lưới lr/wd của paper.
[Script](../archive/2026-10-28/ividr_bce/ividr_zero_prior.py) ·
`results/ividr_bce_zero_prior_neg*_seed*_20261028.json`.

| IViDR | Trọng số mẫu âm | Latent \|mean\| / std | Val NDCG@5 | Test NDCG@5 | Recall/all | Recall bounded |
| :-- | :-- | :-- | --: | --: | --: | --: |
| v2, prior học được (mặc định) | 1 | 4.3 / .6 | .5707 | .5315 ± .0101 | .5409 | .5962 |
| v2, prior học được | .1 | 4.3 / .6 | .5761 | .5391 ± .0037 | .5453 | .6025 |
| prior = 0 | 1 | .98 / 1.39 | .5431 | .4803 ± .0240 | .4959 | .5495 |
| prior = 0 | .2 | .98 / 1.39 | .6001 | .5415 ± .0204 | .5330 | .5886 |
| **prior = 0** | **.1** | .98 / 1.39 | **.6184** | **.5464 ± .0155** | .5285 | .5828 |
| iDCF (MSE), cùng seed | — | .37 / 1.2 | .5991 | .5755 ± .0072 | .5514 | .6023 |

Nhận xét:

1. Prior bằng 0 đưa thang latent về gần iDCF (|mean| 4.3 → .98). Không có trọng số mẫu âm, nó tụt
   xuống .4803, ngang iDCF + BCE (.4764). Điều này khớp với phân tích: offset lớn trước đây đang bù cho BCE.
2. Kết hợp prior bằng 0 với trọng số mẫu âm .1 cho **validation cao nhất trong mọi biến thể IViDR**
   (.6184, cao hơn cả iDCF .5991). Test tăng +.015 so với mặc định, nhưng vẫn thấp hơn iDCF .03 và paper .044.
3. Validation và test lệch chiều nhau: validation vượt iDCF, test thì không. Coat chỉ có khoảng 87 user
   validation, nên ba seed chưa đủ kết luận. Cần chạy 10 seed (42–51) trước khi đổi mặc định.

## 7. Xác nhận 10 seed (42–51), 28/10/2026

Một source hash, chạy lại cả ba cấu hình ([script](../archive/2026-10-28/ividr_ten_seed/run_seed.py),
[tổng hợp](../../results/ividr_ten_seed_summary_20261028.json)). Chọn bằng validation, test chấm một lần.

| Mô hình | Val NDCG@5 | Test NDCG@5 | Test Recall/all | Test Recall bounded |
| :-- | --: | --: | --: | --: |
| IViDR mặc định (Eq. 42, BCE) | 0.5878 ± 0.0199 | 0.5325 ± 0.0067 | 0.5371 | 0.5931 |
| IViDR prior = 0, trọng số mẫu âm .1 | 0.6292 ± 0.0161 | 0.5657 ± 0.0212 | 0.5481 | 0.6031 |
| iDCF | 0.6092 ± 0.0159 | 0.5699 ± 0.0107 | 0.5537 | 0.6071 |

Kiểm định ghép cặp theo seed (Wilcoxon, 10 cặp):

| So sánh | Test: chênh / thắng / p | Val: chênh / thắng / p |
| :-- | :-- | :-- |
| prior 0 + .1 − mặc định | +0.0332 / 9/10 / 0.0059 | +0.0414 / 10/10 / 0.0020 |
| prior 0 + .1 − iDCF | -0.0042 / 4/10 / 0.6250 | +0.0201 / 7/10 / 0.0488 |
| mặc định − iDCF | -0.0374 / 0/10 / 0.0020 | -0.0213 / 2/10 / 0.0273 |

Kết luận:

1. Hai sửa đổi tìm từ phân tích nguyên nhân (prior mean bằng 0 và giảm trọng số mẫu âm của BCE) nâng
   IViDR có ý nghĩa thống kê so với mặc định. Test tăng khoảng +.033 NDCG, thắng 9/10 seed.
2. So với iDCF: test **không khác biệt có ý nghĩa** (p ≈ .6), validation cao hơn (p ≈ .05).
   Bản sửa đóng được khoảng cách IViDR–iDCF, nhưng chưa chứng minh IViDR vượt iDCF trên test.
3. Vẫn thấp hơn paper (.5903) khoảng .025. Cả hai sửa đổi đều **lệch khỏi mô tả paper**
   (Eq. 42 và BCE không trọng số), nên phải mang tên biến thể riêng.
4. Tái lập: seed 42/43 trùng tuyệt đối với lần chạy trước. Ở seed 44, giai đoạn 1 tách nhánh (epoch được chọn
   486 so với 573) do số học dấu phẩy động không tất định trên CPU khi chạy song song; treatment MF trùng tuyệt đối.
   Muốn tái lập từng bit cần chạy tuần tự hoặc bật thuật toán tất định.

## 8. Hướng sửa có căn cứ

Cả hai hướng đều lệch khỏi chữ của paper (Eq. 25 BCE, Eq. 42 prior mean), cần người dùng quyết định.

1. **Feedback MSE + prior mean bằng 0 như iDCF**: xử lý cả nguyên nhân chính lẫn phụ. Đây là
   biến thể có tên riêng, không gọi là IViDR theo paper.
2. **Giữ BCE**: tìm điểm khác của huấn luyện BCE (init, global bias, chuẩn hóa latent) bằng
   MF + BCE trước. Nếu MF + BCE chưa đạt mức MF + MSE thì IViDR-BCE khó đạt số paper.
