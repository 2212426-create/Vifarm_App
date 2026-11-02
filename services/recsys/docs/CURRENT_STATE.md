# Trạng thái RecSys hiện hành

Mốc mã đã kiểm chứng: **02/11/2026**, source
`4e05072a90c309d7122c826e480cc921c095c56c2b505ebc10b1fbcfb32de5c6`.
Mốc này sửa lỗi ConAlign không khôi phục checkpoint tốt nhất và chạy lại ConAlign 3 seed. MF, iDCF, IViDR, LCDR, CDR
không đổi điểm. Lịch sử trước đó nằm trong Git, xem [cách khôi phục](MAINTENANCE.md#khôi-phục-tài-liệu-cũ).

## Bộ mô hình và cách đọc điểm

`benchmark --model all` chạy sáu mô hình trên Coat, Yahoo!R3 và KuaiRand-Pure.

| Nhóm protocol | Mô hình | Nhãn, tập chấm, metric |
| :-- | :-- | :-- |
| **H30** | MF, iDCF, IViDR, LCDR | Coat/Yahoo ≥4, KuaiRand is_click; random log chia user 30/70; loại user không positive |
| **S-full / S-KR** | DR-BIAS + CDR | Theo script tác giả: ≥3, toàn random log, 5% nhãn tập chấm để hiệu chỉnh, user không positive = 1 (S-full Coat/Yahoo; S-KR là KuaiRand địa phương) |
| **C-src** | ConAlign | Theo source tác giả: chia ngẫu nhiên riêng, tháp unbiased, seed 0–2 |

**Chỉ so sánh được trong cùng nhóm.** CDR và ConAlign có điểm cao hơn trên Coat chủ yếu vì protocol dễ hơn:
giữ nguyên checkpoint CDR script nhưng chấm theo ≥4/test pool H30 chỉ còn .4797
([phân tích](benchmarks/root_cause_analysis.md)).

## Kết quả test NDCG@5

Mỗi ô một seed, riêng ConAlign là trung bình 3 seed với KuaiRand cửa sổ train của paper.
Nguồn và source hash: [catalog kết quả](../results/CATALOG.md).

| Dataset | MF | iDCF | IViDR | LCDR | CDR (S-full/S-KR) | ConAlign (C-src) |
| :-- | --: | --: | --: | --: | --: | --: |
| Coat | .5476 | .5699 | .5288 | .5629 | .6567 | .7016 |
| Yahoo!R3 | .5797 | .6558 | .6460 | .6569 | .6559 | .7690 |
| KuaiRand | .3772 | .4053 | .4095 | .4209 | .2740 | .5893 |

ConAlign đo theo metric của source, 3 seed ([chi tiết](benchmarks/lcdr_conalign_20261027.md#kết-quả-đầy-đủ-ba-dataset-2830102026)):

| Dataset | UAUC | UAUC paper | UNDCG | "NDCG@5" paper |
| :-- | --: | --: | --: | --: |
| Coat | .6838 ± .0077 | .6856 | .7078 ± .0171 | .7066 |
| Yahoo!R3 | .6771 ± .0077 | .6841 | .7783 ± .0055 | .7761 |
| KuaiRand | .6607 ± .0002 | .6372 | .6141 ± .0003 | .5656 |

Coat nhỏ nên phải đọc theo nhiều seed:

| Mô hình (Coat, H30) | Seed | Test NDCG@5 | Paper |
| :-- | :-- | --: | --: |
| iDCF | 42–51 | .5699 ± .0107 | .5638 trong paper IViDR |
| **IViDR mặc định** (prior 0, mẫu âm .1) | 42–51 | **.5657 ± .0212** | .5903 |
| IViDR theo chữ paper (Eq. 42, BCE không trọng số) | 42–51 | .5325 ± .0067 | .5903 |
| LCDR | 42–44 | .5674 ± .0054 | .5973 |
| iDCF, cùng seed với LCDR | 42–44 | .5755 ± .0072 | |
| MF | 42–44 | .5396 ± .0286 | .5590 trong paper IViDR |

Seed 42 là seed thấp của IViDR mặc định (.5288), nên khi trích dẫn Coat dùng dòng 10 seed.
IViDR mặc định không khác biệt có ý nghĩa với iDCF (Wilcoxon p ≈ .6, thắng 4/10 seed).
Chưa có mô hình nào trong nhóm H30 được chứng minh vượt iDCF trên Coat.

## Cấu hình mặc định

- **MF, iDCF, LCDR:** feedback MSE; chọn checkpoint bằng validation NDCG@5; seed 42.
- **IViDR:** learned IV + dual iVAE + BCE kỳ vọng xác suất; treatment lấy từ MF; quét 10 cặp LR/WD trên
  validation. Hai điểm **lệch paper** từ 28/10: prior mean giai đoạn 1 bằng 0 (Eq. 42 học nó) và BCE trọng số
  mẫu âm .1 (Eq. 25 không có). Eq. (10) dùng coordinate adapter tự chọn. Metadata:
  `ividr_version=reference_v2_prior0_neg0.1`. Bản theo chữ paper:
  `ivae_overrides=dict(prior_mean='learned')`, `negative_weight=1`.
- **CDR:** bản released của tác giả, seed 2020, dim 4, trần 1000 epoch, dừng theo train loss, lấy trọng số cuối.
  Huấn luyện độc lập, không nạp checkpoint MF.
- **LCDR:** không có mã tác giả; cài đặt lại từ paper trên pipeline iDCF, lựa chọn địa phương ghi ở
  `src/models/lcdr/source.json`.
- **ConAlign:** port từ source `f6171bb`, seed tác giả là 0; KuaiRand mặc định cửa sổ train của paper vì loader source
  bỏ sót 01–05/05. `EarlyStopping` sao chép `best_state`, khác source trên CPU (source chỉ khôi phục đúng khi chạy GPU).
- **API:** chỉ phục vụ MF và CDR released trên dữ liệu TopTop, user mới dùng popularity; yêu cầu `ividr` trả về
  mô hình thay thế kèm `fallback_reason`. Không có random log nên dùng propensity proxy, ghi ở `training_stats.cdr`.

Tham số chi tiết: [config MF/CDR](../src/training/config.py), `IDCF_CONFIG` trong
[train_idcf.py](../src/models/idcf/train_idcf.py), [định nghĩa mô hình](benchmarks/paper_model_alignment.md).

## Kiểm chứng

**160 test: 159 đạt, 1 CUDA skip** ([log](archive/2026-11-02/conalign_fix/tests.log)); smoke sáu mô hình
trên ba dataset ([log](archive/2026-11-02/conalign_fix/smoke.log)); CDR validation ba seed khớp chính xác mốc trước
([validation](../results/conalign_fix_validation_20261102.json)).

Môi trường: Python 3.12.10, PyTorch 2.14.1+cpu, NumPy 2.5.4, pandas 3.0.6, CPU.

## Giới hạn còn tồn tại

- **Không mô hình nào là tái lập paper.** Mọi số là kết quả của triển khai trong dự án.
- **Cấu hình IViDR mặc định được chọn sau phân tích nguyên nhân trên seed 42–44**, các seed này nằm trong 10 seed
  xác nhận; p ≈ .006 so với bản theo paper không phải kiểm định độc lập hoàn toàn.
- **Yahoo:** dự án giữ 15.400 user, paper iDCF chỉ giữ 5.400 user có survey; 10.000 user nhận category thiếu.
- **KuaiRand:** preprocessing và proxy địa phương; CDR dùng sampler có hoàn lại; IViDR giai đoạn 1 mất khoảng 20 giờ trên CPU.
- **CDR source protocol** dùng nhãn tập chấm để hiệu chỉnh propensity, không phải held-out độc lập.
- **MF/iDCF/CDR Yahoo và KuaiRand** thuộc lượt 20/10 (source `134b536cc623`); chỉ Coat được đối chiếu lại tensor ở các mốc sau.
- **IViDR chạy song song trên CPU không tái lập từng bit** (giai đoạn 1 seed 44 từng tách nhánh).
- **ConAlign KuaiRand cao hơn paper** (+.024 UAUC); paper mô tả tập 1.000 user, khác log thật 27.285 user, nên hai bên không cùng dữ liệu.
- **IViDR giai đoạn 1 không có phạt L2 .01 như iDCF và LCDR.** Khác biệt được ghi trong metadata, chưa đo tác động lên điểm.
- **CUDA chưa kiểm chứng.** Lỗi lệch thiết bị của IViDR và ConAlign đã sửa, có unit test, nhưng chưa chạy thật trên GPU.
- **Đề cương `.docx` chính thức** (ngoài repo) vẫn ghi NCF và độ chính xác cao; `docs/de_cuong/` theo mã hiện hành và liệt kê
  [khác biệt](de_cuong/README.md#khác-biệt-với-bản-docx).
