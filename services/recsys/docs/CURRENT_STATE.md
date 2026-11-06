# Trạng thái RecSys hiện hành

Mốc mã đã kiểm chứng: **04/11/2026**, source
`3e9f20b8562a08917b140e22965d8742bb370f08daada62dda71b3a52192d74c`.
Mốc này thêm MRDR-CAL (Hu et al., TKDE 2025) và CLEV-DR (Zhang et al., KDD 2025, "Ours-DR"), chạy theo protocol
tác giả. Mốc 03/11 trước đó thêm NeuMF, TopPop, ItemKNN và workflow `cf-dl`. Năm mô hình của
`benchmark --model all` không đổi mã và không đổi điểm. Lịch sử trước đó nằm trong Git, xem [cách khôi phục](MAINTENANCE.md#khôi-phục-tài-liệu-cũ).

## Bộ mô hình và cách đọc điểm

`benchmark --model all` chạy năm mô hình Causal CF trên Coat, Yahoo!R3 và KuaiRand-Pure (MF, iDCF, LCDR, DR-BIAS + CDR, ConAlign). Module NCF học sâu (NeuMF, GMF, MLP) chạy riêng bằng lệnh `ncf` (hoặc `cf-dl`) trên cùng dữ liệu và evaluator H30.

| Nhóm protocol | Mô hình | Nhãn, tập chấm, metric |
| :-- | :-- | :-- |
| **H30** | MF, NeuMF, iDCF, LCDR | Coat/Yahoo ≥4, KuaiRand is_click; random log chia user 30/70; loại user không positive (IViDR chuyển lưu trữ) |
| **CDR-src / CDR-KR** | DR-BIAS + CDR | Theo script tác giả: ≥3, toàn random log, 5% nhãn tập chấm để hiệu chỉnh, user không positive = 1 (CDR-src Coat/Yahoo; CDR-KR là KuaiRand địa phương) |
| **ConAlign-src** | ConAlign | Theo source tác giả: chia ngẫu nhiên riêng, tháp unbiased, seed 0–2 |
| **MRDR-CAL-src** | MRDR-CAL | Theo Hu et al.: train MNAR/log thiên lệch, test MAR/log ngẫu nhiên, nhãn rating > 3 hoặc is_click; AUC, DCG@{2,4,6}, Recall@{2,4,6} |
| **CLEV-DR-src** | CLEV-DR | Theo Zhang et al.: train log thiên lệch, test toàn log ngẫu nhiên, nhãn rating ≥ 3 hoặc watch ratio ≥ 2; AUC, Recall@K, NDCG@K (K = 5 Coat/Yahoo, 50 KuaiRec) |

**Chỉ so sánh được trong cùng nhóm.** CDR và ConAlign có điểm cao hơn trên Coat chủ yếu vì protocol dễ hơn:
giữ nguyên checkpoint CDR script nhưng chấm theo ≥4/test pool H30 chỉ còn .4797
([phân tích](benchmarks/root_cause_analysis.md)).

## Kết quả test NDCG@5

Mỗi ô một seed, riêng ConAlign là trung bình 3 seed với KuaiRand cửa sổ train của paper.
Nguồn và source hash: [catalog kết quả](../results/CATALOG.md).

| Dataset | MF | NeuMF | iDCF | LCDR | CDR (CDR-src/CDR-KR) | ConAlign (ConAlign-src) | IViDR (lưu trữ) |
| :-- | --: | --: | --: | --: | --: | --: | --: |
| Coat | .5476 | .5230 | .5699 | .5629 | .6567 | .7016 | .5288 |
| Yahoo!R3 | .5797 | .6506 | .6558 | .6569 | .6559 | .7690 | .6460 |
| KuaiRand | .3772 | .4080 | .4053 | .4209 | .2740 | .5893 | .4095 |

*(Lưu ý về IViDR: Ngày 04/11/2026, theo quyết định của người dùng, IViDR được rút khỏi bộ mô hình đề xuất chính của đồ án do tác giả không công bố mã nguồn và kết quả tái lập độc lập không khớp với paper; các kết quả của IViDR được chuyển thành tài liệu nghiên cứu tính tái lập tại [phân tích nguyên nhân](benchmarks/ividr_root_cause_20261027.md)).*

NeuMF thấp hơn MF trên Coat nhưng cao hơn trên Yahoo (+.071) và KuaiRand (+.031).

ConAlign đo theo metric của source, 3 seed ([chi tiết](benchmarks/lcdr_conalign_20261027.md#kết-quả-đầy-đủ-ba-dataset-2830102026)):

| Dataset | UAUC | UAUC paper | UNDCG | "NDCG@5" paper |
| :-- | --: | --: | --: | --: |
| Coat | .6838 ± .0077 | .6856 | .7078 ± .0171 | .7066 |
| Yahoo!R3 | .6771 ± .0077 | .6841 | .7783 ± .0055 | .7761 |
| KuaiRand | .6607 ± .0002 | .6372 | .6141 ± .0003 | .5656 |

### MRDR-CAL và CLEV-DR (protocol tác giả, 04/11/2026)

Cả hai dùng nền NCF/NeuMF, cài lại theo mã công khai (không chép file); nguồn và lựa chọn địa phương
ở `src/models/mrdr_cal/source.json`, `src/models/clev/source.json`.
[Script parity và chẩn đoán](archive/2026-11-04/mrdr_cal_clev/).

| MRDR-CAL | Seed | AUC | DCG@2 | Recall@2 | Bài báo (Bảng VI) |
| :-- | :-- | --: | --: | --: | :-- |
| Coat | 0–9 | .724 ± .008 | .597 ± .028 | .723 ± .036 | .7728 / .7648 / .8987 |
| Yahoo!R3 | 0–9 | .673 ± .008 | .452 ± .037 | .546 ± .040 | .6988 / .5623 / .6687 |
| KuaiRand | 0–2 | .577 ± .009 | .453 ± .009 | .551 ± .010 (đếm) | .6247 / .4928 / .5971 |

| CLEV-DR (alpha tốt nhất, chọn trên test như script tác giả) | Seed | AUC | Recall@K | NDCG@K | Bài báo (Bảng 2, Ours-DR) |
| :-- | :-- | --: | --: | --: | :-- |
| Coat (alpha .8) | 0–4 | .750 ± .007 | .430 ± .012 | .613 ± .019 | .775 / .485 / .679 |
| Yahoo!R3 (alpha .4) | 0–2 | .672 ± .015 | .431 ± .039 | .660 ± .040 | .715 / .486 / .713 |
| KuaiRec (Paper Bảng 2) | 0–2 | — | — | .652 ± .002 | .853 / .715 / .666 (Số liệu bài báo gốc Zhang et al., KDD 2025; repo tập trung KuaiRand-Pure) |

- **CLEV-DR:** port khớp mã tác giả tuyệt đối (cùng seed, Coat, chênh dự đoán 0). Thấp hơn bài báo trên Coat và Yahoo
  (NDCG −.05 đến −.07), gần trên KuaiRec. Repo thiếu `coat_test_dr.py`; Coat-DR và KuaiRec-DR dùng cấu hình bản Naive.
- **MRDR-CAL:** repo Hu không có mã MRDR, phần MRDR theo Guo et al. (MRDR-DL). NeuMF không khử thiên lệch
  theo script của Hu tái lập được dòng "Neumf base" của bài (Coat AUC .768, DCG@2 .765 so với .7604, .7478), nên khoảng
  cách nằm ở phần MRDR tự ghép. Chẩn đoán với loss dạng tổng và train tới khoảng epoch 150 đạt AUC .746, DCG@2 .670;
  cấu hình này chọn sau khi xem test nên không đưa vào bảng.
- **KuaiRand Recall:** mã Hu chuẩn hóa recall theo số positive (≤ 1), Bảng VI ghi giá trị > 1; dạng đếm của đồ án
  (.551 / 1.052 / 1.512) khớp thang của bài, nên bảng trên dùng dạng đếm.

Coat nhỏ nên phải đọc theo nhiều seed:

| Mô hình (Coat, H30) | Seed | Test NDCG@5 | Paper |
| :-- | :-- | --: | --: |
| iDCF | 42–51 | .5699 ± .0107 | .5638 trong paper IViDR |
| **IViDR mặc định** (prior 0, mẫu âm .1) | 42–51 | **.5657 ± .0212** | .5903 |
| IViDR theo chữ paper (Eq. 42, BCE không trọng số) | 42–51 | .5325 ± .0067 | .5903 |
| LCDR | 42–51 | .5713 ± .0114 | .5973 |
| MF | 42–51 | .5479 ± .0184 | .5590 trong paper IViDR |
| NeuMF (mã tác giả NCF) | 42–51 | .5340 ± .0194 | không có (paper NCF dùng ML-1M, Pinterest) |

Seed 42 là seed thấp của IViDR mặc định (.5288), nên khi trích dẫn Coat dùng dòng 10 seed.
IViDR mặc định không khác biệt có ý nghĩa với iDCF (Wilcoxon p ≈ .6, thắng 4/10 seed).
iDCF và LCDR vượt MF có ý nghĩa (+.022, p ≈ .010; +.024, p ≈ .002); NeuMF thấp hơn MF −.014, không có ý nghĩa
(p ≈ .16). Chưa có mô hình nào trong nhóm H30 được chứng minh vượt iDCF trên Coat.

## CF và học sâu (`cf-dl`)

Trên Coat, lượt `cf-dl` 10 seed còn có TopPop .4418, ItemKNN .4937 (top-K 200, shrink 10), GMF .5185, MLP .5252,
NeuMF-pre .5319 ([file](../results/cf_dl_coat_20261103_200701_387e7f14.json)); MF vượt ItemKNN 10/10 seed
(p ≈ .002) và GMF 9/10 seed (p ≈ .010). Báo cáo chỉ dùng MF và NeuMF; các dòng còn lại để tra cứu. Yahoo và KuaiRand
chỉ chạy NeuMF.

## Cấu hình mặc định

- **MF, iDCF, LCDR:** feedback MSE; chọn checkpoint bằng validation NDCG@5; seed 42.
- **NeuMF:** theo mã tác giả NCF `4aab159`: embedding 8, MLP [64, 32, 16, 8], BCE với 4 mẫu âm lấy đều
  từ item không dương mỗi epoch, Adam lr 1e-3, batch 256, đủ 100 epoch, chọn epoch bằng validation NDCG@5 (tác giả
  dùng HR@10 trên test). Mẫu dương là nhãn H30; lựa chọn địa phương ở `src/models/ncf/source.json`.
- **TopPop, ItemKNN:** cài lại theo công thức trong framework Dacrema et al. `0fb6b7f` (không chép mã):
  cosine có shrink, top-K theo cột, lưới 8 × 7 chọn bằng validation; `src/models/neighborhood/source.json`.
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
- **MRDR-CAL:** `run.py mrdr-cal`; NeuMF 64/[64, 32, 16], propensity NeuMF + Platt theo mã Hu, MRDR theo Guo.
- **CLEV-DR:** `run.py clev`; 4 tháp NCF 2k→k→k→1, siêu tham số theo script tác giả, quét `alpha` như file bash.
- **API:** phục vụ ConAlign (mặc định), MF và CDR released trên dữ liệu TopTop, user mới dùng popularity; yêu cầu
  `ividr`/`clev_dr` trả về mô hình thay thế kèm `fallback_reason`. Không có random log nên ConAlign và CDR dùng
  trọng số nghịch đảo tần suất video (kẹp .05–1, tối đa 20 lần) làm propensity proxy, ghi ở `training_stats.cdr`;
  số epoch cố định, không có tập validation online. Huấn luyện lại chạy nền, `/recommend` dùng mô hình cũ tới khi
  hoán đổi. Từ 06/11/2026 user_id lấy từ Firebase ID token và `/sync` cần `X-Admin-Key`
  ([hướng dẫn API](api/colab_api_guide.md#xác-thực)).

Tham số chi tiết: [config MF/CDR](../src/training/config.py), `IDCF_CONFIG` trong
[train_idcf.py](../src/models/idcf/train_idcf.py), `NCF_CONFIG` trong [train_ncf.py](../src/models/ncf/train_ncf.py),
[định nghĩa mô hình](benchmarks/paper_model_alignment.md).

## Kiểm chứng

**210 test: 209 đạt, 1 CUDA skip** ([log](archive/2026-11-04/mrdr_cal_clev/tests.log)); smoke sáu mô hình, `cf-dl`,
`clev`, `mrdr-cal` ([log](archive/2026-11-04/mrdr_cal_clev/smoke.log)); CDR validation ba seed khớp chính xác mốc trước
([validation](../results/mrdr_cal_clev_validation_20261104.json)). MF Coat trong `cf-dl` ra lại .5476 ở seed 42;
LCDR Coat 10 seed ([file](../results/lcdr_coat_20261104_001633_38fc69d6.json)) ra lại .5629 ở seed 42.

Môi trường: Python 3.12.10, PyTorch 2.14.1+cpu, NumPy 2.5.4, pandas 3.0.6, CPU.

## Giới hạn còn tồn tại

- **Không mô hình nào là tái lập paper.** Mọi số là kết quả của triển khai trong dự án.
- **Cấu hình IViDR mặc định được chọn sau phân tích nguyên nhân trên seed 42–44**, các seed này nằm trong 10 seed
  xác nhận; p ≈ .006 so với bản theo paper không phải kiểm định độc lập hoàn toàn.
- **Yahoo:** dự án giữ 15.400 user, paper iDCF chỉ giữ 5.400 user có survey; 10.000 user nhận category thiếu.
- **KuaiRand:** preprocessing và proxy địa phương; CDR dùng sampler có hoàn lại; lượt IViDR mất khoảng 18 giờ trên CPU (giai đoạn 1 khoảng 15.7 giờ, đo từ dấu thời gian checkpoint).
- **CDR source protocol** dùng nhãn tập chấm để hiệu chỉnh propensity, không phải held-out độc lập.
- **MF/iDCF/CDR Yahoo và KuaiRand** thuộc lượt 20/10 (source `134b536cc623`); chỉ Coat được đối chiếu lại tensor ở các mốc sau.
- **IViDR chạy song song trên CPU không tái lập từng bit** (giai đoạn 1 seed 44 từng tách nhánh).
- **ConAlign KuaiRand cao hơn paper** (+.024 UAUC); paper mô tả tập 1.000 user, khác log thật 27.285 user, nên hai bên không cùng dữ liệu.
- **IViDR giai đoạn 1 không có phạt L2 .01 như iDCF và LCDR.** Khác biệt được ghi trong metadata, chưa đo tác động lên điểm.
- **NeuMF không tinh chỉnh:** dùng mặc định của mã tác giả, chạy đủ 100 epoch; trên Coat NeuMF-pre chọn epoch 0 ở 6/10 seed
  vì mã tác giả tiếp tục bằng Adam (paper dùng SGD sau pre-training). Yahoo và KuaiRand chỉ seed 42.
- **Lượt `cf-dl` Coat chạy ở source `1341c2ff1acb`,** trước khi sửa lỗi workflow ghi đè khóa `seeds`; số từng seed được
  chấm lại từ checkpoint và khớp trung bình gốc. Mã huấn luyện không đổi giữa `1341c2ff1acb` và mốc hiện hành.
- **Biến thể iDCF/LCDR nền NeuMF đã thử rồi bỏ** (03–04/11): kém bản nền MF trên Coat và Yahoo, người dùng chọn không giữ.
  Mã và kết quả nằm ngoài repo; mốc hiện hành trùng source của lượt NeuMF Yahoo/KuaiRand.
- **MRDR-CAL không phải mã của Hu et al.:** phần MRDR ghép từ Guo et al.; số epoch MRDR là ngân sách CPU địa phương
  (Coat 200, Yahoo 50, KuaiRand 20, chọn theo validation CE). Coat/Yahoo giữ 10% MNAR làm validation như bài viết.
- **CLEV-DR:** siêu tham số của tác giả được Optuna chọn trên test, và `alpha` chỉ chọn được bằng test; bài viết nhãn
  KuaiRec ngược với mã (mã: ratio ≥ 2 là dương). Lượt CLEV-DR chạy ở source `3bb669cc0d45`, trước khi thêm MRDR-CAL;
  mã CLEV-DR không đổi từ đó.
- **Dữ liệu KuaiRec của Zhang** chỉ lưu cục bộ trong `data/raw/kuairec_zhang`.
- **CUDA chưa kiểm chứng.** Lỗi lệch thiết bị của IViDR và ConAlign đã sửa, có unit test, nhưng chưa chạy thật trên GPU.
- **Đề cương `.docx` chính thức** (ngoài repo) vẫn ghi NCF và độ chính xác cao; `docs/de_cuong/` theo mã hiện hành và liệt kê
  [khác biệt](de_cuong/README.md#khác-biệt-với-bản-docx).
