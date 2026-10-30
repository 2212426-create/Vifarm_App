# LCDR và ConAlign: hai mô hình thực nghiệm

Mốc tích hợp: **27/10/2026**. Từ **30/10/2026**, theo yêu cầu người dùng, `benchmark --model all`
chạy cả LCDR và ConAlign (`--model lcdr|conalign` để chạy riêng). Bảng benchmark ghi protocol từng dòng:
LCDR là **H30**, ConAlign là **C-src** (protocol source). Lệnh riêng `lcdr`, `conalign` vẫn dùng được.
[Trạng thái](../CURRENT_STATE.md) · [Bản đọc LCDR](../paper_summaries/LCDR.md) ·
[Bản đọc ConAlign](../paper_summaries/ConAlign.md).

| | LCDR | ConAlign |
| :-- | :-- | :-- |
| Paper | arXiv 2505.16708v1 (2025) | RecSys 2026, arXiv 2607.24092v1 |
| Mã tác giả | **Không công bố** | [JcZhangzz/ConAlign](https://github.com/JcZhangzz/ConAlign) `f6171bb`, không có LICENSE |
| Cách làm trong project | Cài đặt lại từ paper trên pipeline iDCF | Port từ source, đối chiếu từng epoch với source |
| Protocol | H30 của iDCF, cùng dữ liệu/evaluator với iDCF | Protocol riêng của source |
| Lệnh | `run.py lcdr` | `run.py conalign` |

## Cách chạy

Chạy từ `services/recsys`:

```powershell
# LCDR, 3 seed, chạy kèm iDCF cùng seed để so sánh cùng protocol
.\venv\Scripts\python.exe experiments\run.py lcdr --dataset coat --seeds 42 43 44 --compare-idcf
# ConAlign với seed mặc định của tác giả
.\venv\Scripts\python.exe experiments\run.py conalign --dataset coat
# Chạy thử nhanh cả ba dataset
.\venv\Scripts\python.exe experiments\run.py lcdr --dataset all --smoke --compare-idcf
.\venv\Scripts\python.exe experiments\run.py conalign --dataset all --smoke
```

`--dataset` nhận `coat`, `yahoo`, `kuairand`, `all`. Báo cáo: `results/lcdr_<dataset>_<run>.json`,
`results/conalign_<dataset>_<run>.json`; checkpoint ở `checkpoints/lcdr/`, `checkpoints/conalign/`.

## LCDR: phần theo paper và phần tự chọn

Theo paper: Algorithm 1 hai bước; iVAE $q(Z\mid A,W)$ và LCVAE $q(Z_{lc}\mid A)$ chạy song song,
lấy mẫu reparameterization; Eq. (6) với prior $N(0,I)$, decoder Bernoulli và
$\lambda\lVert Z_{lc}-Z\rVert_2$ (L2 không bình phương, trung bình theo user);
$\lambda$ = 0.9 / 0.1 / 0.9 cho Coat / Yahoo / KuaiRand; Adam; dữ liệu và split theo iDCF.

Paper không công bố nên project tự chọn, ghi trong
[source.json](../../src/models/lcdr/source.json):

1. Kiến trúc, số chiều latent, proxy W, KL anneal, L2 penalty, chia user 80/20 để chọn mô hình:
   dùng nguyên cấu hình iDCF trong `src/models/idcf/train_idcf.py`.
2. iVAE tối ưu ELBO của chính nó trong cùng loss; $Z$ bị **detach** trong ràng buộc, để
   LCVAE không kéo ngược iVAE. Paper gọi iVAE là tín hiệu dẫn hướng.
3. Eq. (18) được hiểu là $MF(u,i)+\langle e_i,Z_{lc,u}\rangle$, đúng dạng MFMF của iDCF;
   loss MSE, chọn epoch theo validation NDCG@5, chấm test một lần.
4. Bước 1 chọn checkpoint theo tổng loss validation của hai nhánh sau giai đoạn warm-up beta.

Vì các điểm trên, kết quả là **cài đặt lại theo paper**, không phải tái lập.

## ConAlign: port từ source

Source đúng byte ở [third_party/conalign](../../third_party/conalign/upstream_manifest.json).
Package `src/models/conalign/` giữ nguyên thuật toán, cấu hình `para()`, thứ tự tiêu thụ RNG và
metric. Khác biệt duy nhất là đọc `data/raw` thay cho thư mục `datasets/` của repo; các dòng dựng
lại trùng từng byte với `user.txt`/`random.txt` (Coat, Yahoo) và CSV KuaiRand-Pure (bỏ ký tự CR).

Kiểm chứng trong `tests/test_conalign.py`: 21 file source khớp SHA-256; dữ liệu trùng byte;
khởi tạo và forward của DualTowerMF trùng tensor; chạy source gốc và bản port 2 + 2 epoch trên
Coat, mọi dòng log epoch và mọi metric test trùng đến 4 chữ số in ra.

Protocol của source: Coat/Yahoo rating ≥ 4; biased chia ngẫu nhiên 70/10/20, unbiased 50/10/40
cùng seed; KuaiRand validation 06/05, test 07–08/05. Cửa sổ train KuaiRand: xem
[mục cửa sổ KuaiRand](#cửa-sổ-train-kuairand-của-conalign-2830102026). Metric giữ tên source: `AUC`, `UAUC`, `UNDCG`,
`NDCG`, `Precision`, `Recall`, `BCE`, cho cả hai tháp trên test unbiased và test biased.
Tháp unbiased là đầu ra cuối của ConAlign.

## Kết quả Coat, 27/10/2026

**LCDR** ([báo cáo](../../results/lcdr_coat_20261027_220934_6395e1a8.json),
[log](../archive/2026-10-27/lcdr_conalign/lcdr_coat_full.log)): ba seed 42/43/44,
ngân sách đầy đủ (bước 1 tối đa 2000 epoch, feedback 100 epoch), iDCF chạy cùng seed và dữ liệu.

| Mô hình | NDCG@5 mean ± std | Recall@5 mean ± std | NDCG@5 theo seed |
| :-- | :-- | :-- | :-- |
| LCDR (project) | .5674 ± .0054 | .5450 ± .0195 | .5629 / .5734 / .5659 |
| iDCF (project, cùng seed) | .5755 ± .0072 | .5514 ± .0035 | .5699 / .5730 / .5836 |
| LCDR (paper, 10 lần) | .5973 ± .0101 | .5878 ± .0119 | — |

Bản cài đặt lại **không vượt iDCF** trên cùng protocol và seed, và thấp hơn số paper khoảng .03.
Khoảng cách $\lVert Z_{lc}-Z\rVert_2$ ở validation còn 6.4–7.5: ràng buộc $\lambda=.9$ của paper
chưa kéo $Z_{lc}$ sát $Z$ trong cấu hình kiến trúc của project. Do paper thiếu nhiều chi tiết,
kết quả này cho thấy giới hạn của việc cài đặt lại; nó không chứng minh phương pháp sai.

**ConAlign** ([báo cáo](../../results/conalign_coat_20261027_220711_8da7d449.json)): seed 0
của tác giả. Bước 1 dừng sớm ở epoch 145 (chọn epoch 84); bước 2 chạy hết 500 epoch, chọn epoch 486.

| Tập test | Tháp | UAUC | UNDCG | NDCG (`calc`) | AUC |
| :-- | :-- | --: | --: | --: | --: |
| Unbiased (random) | unbiased | .6733 | .7100 | .7050 | .7490 |
| Biased | unbiased | .6839 | .7734 | .7614 | .7108 |
| Unbiased (random) | biased | .6839 | .7053 | .7002 | .7538 |

Paper báo UAUC / NDCG@5 của ConAlign trên Coat: unbiased .6856 / .7066, biased .6954 / .7746.
NDCG của project sát paper (.7100 / .7734), UAUC thấp hơn khoảng .012. Một seed, nên không dùng để
khẳng định thắng/thua baseline. Bước 2 dừng vì chạm giới hạn 500 epoch của source, không phải do
early stopping.

Đính chính 28/10: câu "Yahoo và KuaiRand mới chạy smoke" ở bản 27/10 đã cũ; kết quả đầy đủ ở dưới.

## Kết quả đầy đủ ba dataset, 28–30/10/2026

Source `fd1df699561e` (mốc IViDR mặc định 28/10), một seed mỗi mô hình (LCDR/IViDR seed 42, ConAlign
seed 0 của tác giả), chọn cấu hình theo validation, test chấm một lần. ConAlign dùng cửa sổ KuaiRand
của source (trước khi đổi mặc định). Log: [archive/2026-10-28/full_benchmark](../archive/2026-10-28/full_benchmark/).

| Dataset | LCDR NDCG@5 / Recall@5 | Paper LCDR | IViDR NDCG@5 / Recall@5 | Paper IViDR |
| :-- | :-- | :-- | :-- | :-- |
| Coat | .5629 / .5406 | .5973 / .5878 | .5288 / .5031 | .5903 / .5783 |
| Yahoo!R3 | .6569 / .7856 | .6631 / .7928 | .6460 / .7792 | .6602 / .7901 |
| KuaiRand | .4209 / .3588 | .4176 / .3575 | .4095 / .3493 | .4161 / .3549 |

Báo cáo: [LCDR Coat](../../results/lcdr_coat_20261028_081517_b71fff26.json),
[Yahoo](../../results/lcdr_yahoo_20261028_081517_b71fff26.json),
[KuaiRand](../../results/lcdr_kuairand_20261028_081517_b71fff26.json);
[IViDR KuaiRand](../../results/benchmark_kuairand_ividr_be219eee39_20261029_193713_d87515c9_v4.json),
[IViDR Coat/Yahoo](../../results/ividr_benchmark_recovered_coat_yahoo_20261029.json). Lượt IViDR ba dataset bị
dừng vì máy khởi động lại khi đang ở KuaiRand; Coat/Yahoo được chấm lại từ checkpoint đã chọn theo validation
(cùng quy tắc với pipeline, [script](../archive/2026-10-28/full_benchmark/recover_coat_yahoo.py)), KuaiRand chạy lại
riêng. Coat seed 42 trùng chính xác lượt 10 seed (.5288; trung bình 10 seed .5657 ± .0212).

ConAlign, tháp unbiased trên test unbiased (C-src):

| Dataset | UAUC (project / paper) | NDCG (`calc`) | UNDCG | Paper "NDCG@5" |
| :-- | :-- | --: | --: | --: |
| Coat | .6733 / .6856 | .7050 | .7100 | .7066 |
| Yahoo!R3 | .6892 / .6841 | .7773 | .7867 | .7761 |
| KuaiRand (cửa sổ source) | .5958 / .6372 | .5278 | .5564 | .5656 |

Báo cáo: [Coat](../../results/conalign_coat_20261028_081519_b614253e.json),
[Yahoo](../../results/conalign_yahoo_20261028_081519_b614253e.json),
[KuaiRand](../../results/conalign_kuairand_20261028_081519_b614253e.json).

## Cửa sổ train KuaiRand của ConAlign, 28–30/10/2026

Paper (Sec. 4.1) dùng log 22/04–08/05: train 22/04–05/05, validation 06/05, test 07–08/05. Source
`utils/load_kuairand.py` tạo ngày train bằng `20220408 + i` (i < 28): sau 20220430 là 20220431…20220435,
không phải ngày thật, nên **01–05/05 không vào train** (khoảng 463 nghìn dòng random, 90 nghìn dòng biased).
Ba cửa sổ, tháp unbiased trên test unbiased ([tổng hợp](../../results/lcdr_conalign_studies_summary_20261030.json),
[script](../archive/2026-10-28/conalign_paper_window/run.py)):

| Cửa sổ train | Seed | UAUC | NDCG (`calc`) | UNDCG |
| :-- | :-: | --: | --: | --: |
| source như công bố | 0, 1, 2 | .5967 ± .0009 | .5282 ± .0006 | .5568 |
| đúng docstring source (08/04–05/05) | 0, 1 | .6015 ± .0014 | .5359 ± .0017 | .5640 |
| paper (22/04–05/05) | 0, 1, 2 | .6018 ± .0033 | .5369 ± .0033 | .5650 |

Cửa sổ paper cao hơn ở mọi seed (+.005 UAUC, +.009 NDCG); lợi ích đến từ việc đưa 01–05/05 vào train.
UNDCG .5650 gần "NDCG@5" .5656 của paper, nhưng UAUC vẫn thấp hơn paper khoảng .035. Paper ghi
KuaiRand-Pure có 1.000 user và 7.388 video, khác log thật (27.285 user, 7.583 video trong 17 ngày);
không đủ thông tin để thu hẹp khoảng này.

**Mặc định từ 30/10:** `kuairand_window='paper'` (`--kuairand-window paper|source` ở lệnh `conalign`;
benchmark dùng paper). Cửa sổ `source` cho dữ liệu trùng từng tensor với loader gốc (test
`ConAlignKuaiRandWindowTest`); cả hai cửa sổ cho hash dữ liệu trùng các lượt chạy 28/10.

## LCDR Coat: các lựa chọn paper để ngỏ, 28/10/2026

Ba biến thể ràng buộc và lưới LR × weight decay của paper (Sec. 5.1) cho bước 2, seed 42/43/44, chọn theo
validation ([tổng hợp](../../results/lcdr_conalign_studies_summary_20261030.json),
[script](../archive/2026-10-28/lcdr_constraint/)):

| Cấu hình | Val NDCG@5 | Test NDCG@5 | ‖Z_lc − Z‖ |
| :-- | --: | --: | --: |
| mặc định (L2, Z detach, λ .9) | .6163 | .5674 ± .0054 | 6.4–7.5 |
| gradient qua Z (`shared`) | .6131 | .5678 ± .0012 | 3.5–3.8 |
| L2 bình phương | .5729 | .5259 ± .0409 | 29–61 |
| λ = 10 | .5719 | .5112 ± .0447 | 5.3–7.7 |
| mặc định + lưới LR × WD | .6191 | .5685 ± .0024 | — |
| iDCF + cùng lưới | .6047 | .5757 ± .0094 | — |

Không cấu hình nào vượt mặc định trên validation đủ để đổi; **giữ mặc định**. Paper LCDR tự chạy lại iDCF
Coat được .5643, còn iDCF của project .5755: một phần khoảng cách với paper nằm ở baseline mạnh hơn.
