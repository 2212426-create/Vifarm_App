# Trạng thái RecSys hiện hành

Mốc mã đã kiểm chứng: **08/11/2026**, source
`97ca516a40dfbf2fdf854a444308ecd5bc773604788ff2bff0d126c5ef577e96`.
Mốc này thêm NDCG@5, Recall@5, Recall@5_bounded (định nghĩa của đồ án) cho MRDR-CAL và chạy lại MRDR-CAL trên ba
dataset. Mốc 07/11 trước đó dọn lint (`ruff.toml`, không đổi hành vi) và xóa toàn bộ mã IViDR và TopPop/ItemKNN-CF theo yêu cầu người dùng; `cf-dl` còn MF, GMF, MLP, NeuMF,
NeuMF-pre. Mốc 04/11 trước đó thêm MRDR-CAL (Hu et al., TKDE 2025) và CLEV-DR (Zhang et al., KDD 2025, "Ours-DR")
theo protocol tác giả. Năm mô hình của `benchmark --model all` không đổi mã và không đổi điểm. Ngày 11/11 đối chiếu báo cáo đồ án với mã
và sáu bài báo gốc, không đổi source: chạy lại MF và iDCF Coat 10 seed, sửa các chỗ tài liệu lệch mã. Lịch sử trước đó nằm trong Git, xem [cách khôi phục](MAINTENANCE.md#khôi-phục-tài-liệu-cũ).

## Bộ mô hình và cách đọc điểm

`benchmark --model all` chạy năm mô hình Causal CF trên Coat, Yahoo!R3 và KuaiRand-Pure (MF, iDCF, LCDR, DR-BIAS + CDR, ConAlign). Module NCF học sâu (NeuMF, GMF, MLP) chạy riêng bằng lệnh `ncf` (hoặc `cf-dl`) trên cùng dữ liệu và evaluator H30.

| Nhóm protocol | Mô hình | Nhãn, tập chấm, metric |
| :-- | :-- | :-- |
| **H30** | MF, NeuMF, iDCF, LCDR | Coat/Yahoo ≥4, KuaiRand is_click; random log chia user 30/70; loại user không positive |
| **CDR-src / CDR-KR** | DR-BIAS + CDR | Theo script tác giả: ≥3, toàn random log, 5% nhãn tập chấm để hiệu chỉnh, user không positive = 1 (CDR-src Coat/Yahoo; CDR-KR là KuaiRand địa phương) |
| **ConAlign-src** | ConAlign | Theo source tác giả: chia ngẫu nhiên riêng, tháp unbiased, seed 0–2 |
| **MRDR-CAL-src** | MRDR-CAL | Theo Hu et al.: train MNAR/log thiên lệch, test MAR/log ngẫu nhiên, nhãn rating > 3 hoặc is_click; AUC, DCG@{2,4,6}, Recall@{2,4,6}; thêm NDCG@5, Recall@5 theo định nghĩa đồ án |
| **CLEV-DR-src** | CLEV-DR | Theo Zhang et al.: train log thiên lệch, test toàn log ngẫu nhiên, nhãn rating ≥ 3 hoặc is_click; AUC toàn cục, Recall@5, NDCG@5 theo mã tác giả. KuaiRand-Pure thay KuaiRec của bài báo |

**Chỉ so sánh được trong cùng nhóm.** CDR và ConAlign có điểm cao hơn trên Coat chủ yếu vì protocol dễ hơn:
giữ nguyên checkpoint CDR script nhưng chấm theo ≥4/test pool H30 chỉ còn .4797
([phân tích](benchmarks/root_cause_analysis.md)).

## Kết quả test NDCG@5

Mỗi ô một seed, riêng ConAlign là trung bình 3 seed với KuaiRand cửa sổ train của paper.
Nguồn và source hash: [catalog kết quả](../results/CATALOG.md).

| Dataset | MF | NeuMF | iDCF | LCDR | CDR (CDR-src/CDR-KR) | ConAlign (ConAlign-src) |
| :-- | --: | --: | --: | --: | --: | --: |
| Coat | .5476 | .5230 | .5699 | .5629 | .6567 | .7016 |
| Yahoo!R3 | .5797 | .6506 | .6558 | .6569 | .6559 | .7690 |
| KuaiRand | .3772 | .4080 | .4053 | .4209 | .2740 | .5893 |

NeuMF thấp hơn MF trên Coat nhưng cao hơn trên Yahoo (+.071) và KuaiRand (+.031).

ConAlign đo theo metric của source, 3 seed ([chi tiết](benchmarks/lcdr_conalign_20261027.md#kết-quả-đầy-đủ-ba-dataset-2830102026)):

| Dataset | UAUC | UAUC paper | UNDCG | "NDCG@5" paper |
| :-- | --: | --: | --: | --: |
| Coat | .6838 ± .0077 | .6856 | .7078 ± .0171 | .7066 |
| Yahoo!R3 | .6771 ± .0077 | .6841 | .7783 ± .0055 | .7761 |
| KuaiRand | .6607 ± .0002 | .6372 | .6141 ± .0003 | .5656 |

### MRDR-CAL và CLEV-DR (protocol tác giả; MRDR-CAL chạy lại 07–08/11, CLEV-DR 04/11)

Cả hai dùng nền NCF/NeuMF, cài lại theo mã công khai (không chép file); nguồn và lựa chọn địa phương
ở `src/models/mrdr_cal/source.json`, `src/models/clev/source.json`.
[Script parity và chẩn đoán](archive/2026-11-04/mrdr_cal_clev/).

| MRDR-CAL | Seed | AUC | DCG@2 | Recall@2 | Bài báo (Bảng VI) |
| :-- | :-- | --: | --: | --: | :-- |
| Coat | 0–9 | .724 ± .008 | .597 ± .028 | .723 ± .036 | .7728 / .7648 / .8987 |
| Yahoo!R3 | 0–9 | .671 ± .009 | .440 ± .039 | .535 ± .041 | .6988 / .5623 / .6687 |
| KuaiRand | 0–2 | .574 ± .006 | .455 ± .021 | .554 ± .025 (đếm) | .6247 / .4928 / .5971 |

| MRDR-CAL, chỉ số @5 của đồ án (không có trong bài báo) | Seed | NDCG@5 | Recall@5 | Recall@5 bounded |
| :-- | :-- | --: | --: | --: |
| Coat | 0–9 | .446 ± .014 | .470 ± .016 | .520 ± .016 |
| Yahoo!R3 | 0–9 | .469 ± .023 | .645 ± .021 | .650 ± .021 |
| KuaiRand | 0–2 | .330 ± .014 | .295 ± .014 | .379 ± .016 |

NDCG@5/Recall@5 tính như H30 (IDCG trên min(5, số positive), macro theo user có positive) nhưng trên tập test
MRDR-CAL-src (toàn log ngẫu nhiên, nhãn rating > 3 hoặc is_click), nên không so trực tiếp với bảng H30.
Coat chạy lại khớp lượt 04/11 tuyệt đối ở mọi seed. Yahoo và KuaiRand lệch từng seed (tối đa .056) do tính toán số
thực trên CPU không tất định với dữ liệu lớn (tham số Platt đã khác ở chữ số thứ ba–tư); trung bình lệch dưới một độ
lệch chuẩn. Mọi số trong hai bảng trên lấy từ cùng lượt chạy lại.

| CLEV-DR (alpha tốt nhất, chọn trên test như script tác giả) | Seed | AUC | Recall@K | NDCG@K | Bài báo (Bảng 2, Ours-DR) |
| :-- | :-- | --: | --: | --: | :-- |
| Coat (alpha .8) | 0–4 | .750 ± .007 | .430 ± .012 | .613 ± .019 | .775 / .485 / .679 |
| Yahoo!R3 (alpha .4) | 0–2 | .672 ± .015 | .431 ± .039 | .660 ± .040 | .715 / .486 / .713 |
| KuaiRand-Pure (alpha .8) | 0–2 | .649 ± .001 | .218 ± .001 | .425 ± .001 | không có (bài báo dùng KuaiRec) |

- **CLEV-DR:** port khớp mã tác giả tuyệt đối trong phép thử ngắn (cùng seed, Coat, 2 epoch propensity + 3 epoch chính,
  chênh dự đoán 0). Thấp hơn bài báo trên Coat và Yahoo (NDCG −.05 đến −.07), và thấp hơn cả dòng NCF không khử thiên
  lệch của chính bài báo (NDCG@5 .623 Coat, .674 Yahoo). Yahoo chỉ 3 seed, độ lệch chuẩn .040. Repo tác giả thiếu
  `coat_test_dr.py` nên Coat-DR dùng cấu hình bản Naive; cấu hình này lấy 50 mẫu Monte Carlo, ngoài khoảng 100–500 mà
  bài báo ghi cho Coat. KuaiRand-Pure không có cấu hình của tác giả, dùng giá trị của `kuai_main.py`.
- **MRDR-CAL:** repo Hu không có mã MRDR, phần MRDR theo Guo et al. (MRDR-DL). NeuMF không khử thiên lệch
  theo script của Hu tái lập được dòng "Neumf base" của bài (Coat AUC .768, DCG@2 .765 so với .7604, .7478; chẩn đoán
  3 seed), nên khoảng cách nằm ở phần MRDR tự ghép. Hệ quả: MRDR-CAL của đồ án (Coat AUC .724) thấp hơn NeuMF không khử
  thiên lệch của chính đồ án trong cùng protocol, tức bản dựng lại chưa tái hiện được lợi ích của phương pháp. Chẩn đoán với loss dạng tổng và train tới khoảng epoch 150 đạt AUC .746, DCG@2 .670;
  cấu hình này chọn sau khi xem test nên không đưa vào bảng.
- **KuaiRand Recall:** mã Hu chuẩn hóa recall theo số positive (≤ 1), Bảng VI ghi giá trị > 1; dạng đếm của đồ án
  (.554 / 1.046 / 1.506) khớp thang của bài, nên bảng trên dùng dạng đếm.

Coat nhỏ nên phải đọc theo nhiều seed:

| Mô hình (Coat, H30) | Seed | Test NDCG@5 | Paper |
| :-- | :-- | --: | --: |
| iDCF | 42–51 | .5699 ± .0107 | .5744 ± .0122 (paper iDCF) |
| LCDR | 42–51 | .5713 ± .0114 | .5973 |
| MF | 42–51 | .5479 ± .0184 | .5524 ± .0144 (paper iDCF) |
| NeuMF (mã tác giả NCF) | 42–51 | .5340 ± .0194 | không có (paper NCF dùng ML-1M, Pinterest) |

iDCF và LCDR vượt MF có ý nghĩa (+.022, p ≈ .010; +.024, p ≈ .002); NeuMF thấp hơn MF −.014, không có ý nghĩa
(p ≈ .16). Chưa có mô hình nào trong nhóm H30 được chứng minh vượt iDCF trên Coat (LCDR so với iDCF: +.001).

iDCF 10 seed còn có Recall@5 .5537 ± .0110 và AUC .6865 ± .0114
([file](../results/idcf_coat_10seeds_windows_20261111.json); MF cùng lượt và kiểm định ở
[coat_seeds](../results/coat_seeds_4b77ed83d03fd5b3_20261111_163912_80b99b32.json)). Lượt chạy lại ngày 11/11 trùng
tuyệt đối trung bình của mốc 28/10. Một lượt iDCF chạy trên Linux
([file](../results/idcf_coat_10seeds_20261108.json)) ra .5651 ± .0209 vì lệch ở 6 seed (seed 45: .5110 so với .5726);
so với MF trên Windows thì p ≈ .064. MF, NeuMF và LCDR đều chạy trên Windows nên bảng trên dùng bản Windows.

## CF và học sâu (`cf-dl`)

Trên Coat, lượt `cf-dl` 10 seed còn có GMF .5185, MLP .5252, NeuMF-pre .5319
([file](../results/cf_dl_coat_20261103_200701_387e7f14.json)); MF vượt GMF 9/10 seed (p ≈ .010). Báo cáo chỉ dùng
MF và NeuMF; các dòng còn lại để tra cứu. File này còn dòng TopPop/ItemKNN của mã đã xóa ngày 07/11, không trích.
Yahoo và KuaiRand chỉ chạy NeuMF.

## Cấu hình mặc định

- **MF, iDCF, LCDR:** feedback MSE; chọn checkpoint bằng validation NDCG@5; seed 42.
- **NeuMF:** theo mã tác giả NCF `4aab159`: embedding 8, MLP [64, 32, 16, 8], BCE với 4 mẫu âm lấy đều
  từ item không dương mỗi epoch, Adam lr 1e-3, batch 256, đủ 100 epoch, chọn epoch bằng validation NDCG@5 (tác giả
  dùng HR@10 trên test). Mẫu dương là nhãn H30; lựa chọn địa phương ở `src/models/ncf/source.json`.
- **CDR:** bản released của tác giả, seed 2020, dim 4, trần 1000 epoch, dừng theo train loss, lấy trọng số cuối.
  Huấn luyện độc lập, không nạp checkpoint MF.
- **LCDR:** không có mã tác giả; cài đặt lại từ paper trên pipeline iDCF, lựa chọn địa phương ghi ở
  `src/models/lcdr/source.json`.
- **ConAlign:** port từ source `f6171bb`, seed tác giả là 0; KuaiRand mặc định cửa sổ train của paper vì loader source
  bỏ sót 01–05/05. `EarlyStopping` sao chép `best_state`, khác source trên CPU (source chỉ khôi phục đúng khi chạy GPU).
- **MRDR-CAL:** `run.py mrdr-cal`; NeuMF 64/[64, 32, 16], propensity NeuMF + Platt theo mã Hu, MRDR theo Guo.
- **CLEV-DR:** `run.py clev`; 4 tháp NCF 2k→k→k→1, siêu tham số theo script tác giả, quét `alpha` như file bash.
- **API:** phục vụ ConAlign (mặc định), MF và CDR released trên dữ liệu TopTop, user mới dùng popularity; yêu cầu
  `clev_dr` hoặc tên không tồn tại trả về mô hình thay thế kèm `fallback_reason`. Không có random log nên ConAlign và CDR dùng
  trọng số nghịch đảo tần suất video (kẹp .05–1, tối đa 20 lần) làm propensity proxy, ghi ở `training_stats.cdr`;
  số epoch cố định, không có tập validation online. Huấn luyện lại chạy nền, `/recommend` dùng mô hình cũ tới khi
  hoán đổi. Từ 06/11/2026 user_id lấy từ Firebase ID token và `/sync` cần `X-Admin-Key`
  ([hướng dẫn API](api/colab_api_guide.md#xác-thực)).

Tham số chi tiết: [config MF/CDR](../src/training/config.py), `IDCF_CONFIG` trong
[train_idcf.py](../src/models/idcf/train_idcf.py), `NCF_CONFIG` trong [train_ncf.py](../src/models/ncf/train_ncf.py),
[định nghĩa mô hình](benchmarks/paper_model_alignment.md).

## Kiểm chứng

**200 test: 199 đạt, 1 CUDA skip** ([log](archive/2026-11-08/mrdr_topk/tests.log)); smoke năm mô hình trên ba
dataset, `cf-dl` và `mrdr-cal` ([log](archive/2026-11-08/mrdr_topk/smoke.log)); CDR validation ba seed khớp chính xác mốc
trước ([validation](../results/mrdr_topk_validation_20261108.json)); `ruff check src experiments tests` sạch. `clev` không
đổi mã từ mốc 04/11 nên không chạy lại smoke. MRDR-CAL Coat chạy lại khớp tuyệt đối lượt 04/11. MF Coat trong `cf-dl` ra lại .5476 ở seed 42 (mốc 04/11); LCDR Coat 10 seed
([file](../results/lcdr_coat_20261104_001633_38fc69d6.json)) ra lại .5629 ở seed 42.

Môi trường: Python 3.12.10, PyTorch 2.14.1+cpu, NumPy 2.5.4, pandas 3.0.6, CPU.

## Giới hạn còn tồn tại

- **Không mô hình nào là tái lập paper.** Mọi số là kết quả của triển khai trong dự án.
- **Yahoo:** dự án giữ 15.400 user, paper iDCF chỉ giữ 5.400 user có survey; 10.000 user nhận category thiếu.
- **KuaiRand:** preprocessing và proxy địa phương; CDR dùng sampler có hoàn lại.
- **CDR source protocol** dùng nhãn tập chấm để hiệu chỉnh propensity, không phải held-out độc lập.
- **Bộ lọc phương sai của CDR gần như không hoạt động** với ngưỡng 10 của script: tỷ lệ giá trị điền khuyết bị loại là
  0 ở mọi epoch trên Coat, cao nhất .16% trên Yahoo và .0015% trên KuaiRand (`filtered_fraction` trong file kết quả).
  `observed_rows_dropped` (48 / 408 / 454) là số dòng lẻ của lô cuối bị bỏ, không phải số dòng bị lọc.
- **Bài báo và mã công bố lệch nhau ở CDR, ConAlign, CLEV-DR, MRDR-CAL, NeuMF;** đồ án theo mã. Danh sách ở
  [paper_model_alignment](benchmarks/paper_model_alignment.md#bài-báo-lệch-mã-công-bố).
- **MF/iDCF/CDR Yahoo và KuaiRand** thuộc lượt 20/10 (source `134b536cc623`); chỉ Coat được đối chiếu lại tensor ở các mốc sau.
- **ConAlign KuaiRand cao hơn paper** (+.024 UAUC); paper mô tả tập 1.000 user, khác log thật 27.285 user, nên hai bên không cùng dữ liệu.
- **NeuMF không tinh chỉnh:** dùng mặc định của mã tác giả, chạy đủ 100 epoch; trên Coat NeuMF-pre chọn epoch 0 ở 6/10 seed
  vì mã tác giả tiếp tục bằng Adam (paper dùng SGD sau pre-training). Yahoo và KuaiRand chỉ seed 42.
- **Lượt `cf-dl` Coat chạy ở source `1341c2ff1acb`,** trước khi sửa lỗi workflow ghi đè khóa `seeds`; số từng seed được
  chấm lại từ checkpoint và khớp trung bình gốc. Mã huấn luyện không đổi giữa `1341c2ff1acb` và mốc hiện hành.
- **Biến thể iDCF/LCDR nền NeuMF đã thử rồi bỏ** (03–04/11): kém bản nền MF trên Coat và Yahoo, người dùng chọn không giữ.
  Mã và kết quả nằm ngoài repo; mốc hiện hành trùng source của lượt NeuMF Yahoo/KuaiRand.
- **MRDR-CAL không phải mã của Hu et al.:** phần MRDR ghép từ Guo et al.; số epoch MRDR là ngân sách CPU địa phương
  (Coat 200, Yahoo 50, KuaiRand 20, chọn theo validation CE). Coat/Yahoo giữ 10% MNAR làm validation như bài viết.
- **CLEV-DR:** siêu tham số của tác giả được Optuna chọn trên test, và `alpha` chỉ chọn được bằng test; bài viết nhãn
  KuaiRec ngược với mã (mã: ratio ≥ 2 là dương). Lượt Coat/Yahoo chạy ở source `3bb669cc0d45`, trước khi thêm MRDR-CAL;
  lượt KuaiRand-Pure ở source `aaadb81eb5a6`.
- **CLEV-DR trên KuaiRec** (dataset của bài báo) từng chạy cục bộ ngày 04/11 nhưng file kết quả và dữ liệu không còn
  trong repo, nên không trích số. Lệnh `clev` hiện chạy Coat, Yahoo và KuaiRand-Pure.
- **CUDA chưa kiểm chứng.** Lỗi lệch thiết bị của ConAlign đã sửa, có unit test, nhưng chưa chạy thật trên GPU.
- **Đề cương `.docx` chính thức** (ngoài repo) vẫn ghi NCF và độ chính xác cao; `docs/de_cuong/` theo mã hiện hành và liệt kê
  [khác biệt](de_cuong/README.md#khác-biệt-với-bản-docx).
