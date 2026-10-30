# IViDR: đối chiếu điểm paper và hướng tối ưu — 23/10/2026

Đây là nghiên cứu nguồn và chẩn đoán checkpoint, **chưa triển khai biến thể hoặc
huấn luyện lại**. Đặc tả đang chạy vẫn ở [IViDR reference v2](ividr_reference_20261022.md),
trạng thái triển khai ở [CURRENT_STATE](../CURRENT_STATE.md).
Áp dụng cách trình bày của skill academic-thesis-writer; số liệu lấy từ PDF và artifact.

## 1. Mục tiêu tái lập đúng phiên bản

Nguồn đối chiếu là *Mitigating Dual Latent Confounding Biases in Recommender Systems*,
arXiv **2410.12451v1**, ngày 16/10/2024 [1]. Table 3 ở **trang PDF 8** báo cáo:

| Dataset | IViDR NDCG@5, mean ± std | IViDR RECALL@5, mean ± std |
| :-- | --: | --: |
| Coat | 0.5903 ± 0.0101 | 0.5783 ± 0.0114 |
| Yahoo! R3 | 0.6602 ± 0.0038 | 0.7901 ± 0.0037 |
| KuaiRand | 0.4161 ± 0.0004 | 0.3549 ± 0.0006 |

Paper ghi **10 trials**, không công bố danh sách seed tại §5.1. Đây là các số paper,
không phải mục tiêu được phép chọn checkpoint bằng test. Không dùng bảng của một
phiên bản xuất bản khác thay cho v1 mà không đối chiếu lại toàn văn và phương pháp.

Paper v1 không nêu đầy đủ công thức Recall, ngưỡng nhãn, cách chia random log và
cách chọn checkpoint trong §5.1/Appendix E.1. Vì vậy, evaluator theo iDCF là một
tham chiếu có cơ sở, **chưa đủ chứng nhận đúng protocol IViDR**.
Recall/all positives ở bảng tiếp theo là định nghĩa hiện có của dự án; không khẳng
định đây chắc chắn là mẫu số mà tác giả IViDR đã dùng. Bounded Recall có mẫu số
khác, không dùng để suy ra đã vượt RECALL của paper.

## 2. Khoảng cách hiện tại trên Coat

Nguồn local là [benchmark seed 42](../../results/benchmark_coat_all_02b9e8eb46_20261022_073711_146173c9_v4.json),
training source `dd068e23091a263bd967f9cc776d3352082b46842d27f9cc51e02a3d54ce2556`.
Các điểm cùng giao thức local, một seed:

| Mô hình | NDCG@5 local | Recall/all positives local | Recall bounded local | NDCG paper, mean |
| :-- | --: | --: | --: | --: |
| MF | 0.547612 | 0.529536 | 0.584032 | 0.5590 |
| iDCF | 0.569884 | 0.551969 | 0.602295 | 0.5638 |
| IViDR reference v2 | 0.541201 | 0.558345 | 0.613273 | 0.5903 |

IViDR thiếu **0.049099 NDCG** so với trung bình paper; một seed không cho phép kết
luận ý nghĩa thống kê. MF/iDCF local gần mức paper hơn là một dấu hiệu để ưu tiên
rà nhánh tái dựng IViDR, không chứng minh mọi tiền xử lý và metric đều đã khớp.
CDR source dùng protocol khác, không dùng làm đối chứng trực tiếp trong bảng này.

## 3. Phát hiện mới từ checkpoint, không dùng test để lựa chọn

Đã nạp stage1 Coat được chọn ở epoch 463 và tính trên **biased exposure**.
[JSON chẩn đoán](../../results/ividr_research_diagnostics_20261023.json) ghi checksum,
shape và phép đo; [script](../archive/2026-10-23/ividr_research/diagnose_checkpoint.py)
không retrain hoặc tính prediction trên test.

| Phép đo | Kết quả | Ý nghĩa trong checkpoint này |
| :-- | --: | :-- |
| \|X_re − A\|F / \|A\|F | 0.00298415 | Tái dựng chỉ thay đổi khoảng **0.2984%** theo chuẩn Frobenius |
| Cosine giữa hai ma trận posterior mean, sau flatten | 0.99998778 | Hai nhánh cho biểu diễn gần cùng hướng |
| \|mu_re − mu_original\|F / \|mu_original\|F | 0.00681583 | Mean của hai nhánh chỉ khác khoảng 0.6816% theo chuẩn |
| Gate fitted: mean, min → max | 0.017821; −0.027343 → 0.050739 | Hệ số fitted nhỏ; gate không bị chặn dương |
| Gate residual: mean, min → max | −0.003434; −0.008555 → 0.005392 | Hệ số residual gần 0 |
| Rank instrument theo item | 4–11, trong không gian 32 chiều | Không phải mọi projector đều bằng identity hoặc zero |
| Mean/std xuất lại so với cache | Khớp từng phần tử | Không phát hiện lỗi nạp/cached latent ở lượt kiểm tra này |

Checksum checkpoint trước/sau giống nhau. Dấu hiệu mạnh nhất là nhánh tái dựng
**hoạt động yếu**, khiến hai posterior gần trùng. Đây là giả thuyết về chất lượng,
chưa phải chứng minh rằng tăng biên độ input hoặc đổi gate sẽ tăng NDCG.
Cosine đo toàn ma trận không đồng nghĩa mọi user có latent giống hệt nhau.

## 4. Những khác biệt cần xử lý trước khi tăng ngân sách training

| Ưu tiên | Bằng chứng đã kiểm tra | Hành động cần làm tiếp | Mức chắc chắn |
| :-- | :-- | :-- | :-- |
| P0: Eq. (10) và nhánh IV | Paper cộng X + T_re nhưng thiếu phép đổi kích thước; local dùng `A + (A @ T_re) @ T0.T / sqrt(d)`; perturbation rất nhỏ | Xác minh biểu diễn X/T và phép gom history/target; thiết kế đối chứng T, fitted-only, residual-only, full trên validation | Khác biệt đã xác nhận; tác động NDCG cần thí nghiệm |
| P1: Hai posterior dùng chung mạng | Local chia sẻ encoder/prior/decoder; paper chưa định nghĩa đầy đủ parameter sharing | So sánh shared và separate encoder với cùng dữ liệu/ngân sách; giữ tên biến thể riêng | Lựa chọn local, không gọi một phía là tác giả nếu thiếu source |
| P2: Stage1 kế thừa cấu hình iDCF | `fit_ividr_pipeline` copy `IDCF_CONFIG`; Coat latent16/hidden32/layers3, LR5e-4 | Quét stage1, không chỉ quét feedback; chọn bằng validation với ngân sách công bố | Khoảng trống tuning đã xác nhận |
| P3: Yahoo khác cohort | Dự án 15.400 user/311.704 biased ratings; paper 5.400/129.179 | Profile riêng lọc user có survey, assert lại ID/count và rebuild exposure/proxy | Khác dữ liệu rõ ràng; chưa triển khai profile mới |
| P3: KuaiRand khác preprocessing/IV | Dự án dùng proxy user và tab-exposure làm instrument | Đối chiếu đúng processed IDs, số dòng, loại interaction, feature và split | Chưa đủ thông tin để khẳng định tương đương |
| P4: Thống kê nhiều seed | Một full run reference v2 không phải 10 trials | Khóa profile rồi chạy 10 seed; xuất mean/std, cả hai Recall, protocol và cấu hình | Cần để đánh giá độ ổn định, không tự tăng mean |

Đường dẫn thực thi:
[tái dựng, posterior và scorer](../../src/models/ividr/ividr_reference.py),
[stage1 và grid feedback](../../src/models/ividr/train_ividr.py),
[config iDCF dùng chung](../../src/models/idcf/train_idcf.py),
[giao thức local](evaluation_protocol.md).

Eq. (25) xác định **BCE** [1]; giữ objective này. Treatment/user-feature embedding
32/96/128 khác **latent confounder dimension** 16/32. Đổi `--latent-dim 32` không
phải tự động sửa treatment dimension cho đúng paper.
Feedback đã quét đủ **5 LR × 2 WD** của §5.1, chọn LR .001/WD 1e-6 bằng validation.
Không có căn cứ gọi việc lặp lại grid feedback hiện có là một tối ưu mới.

## 5. Mã nguồn có thể tham khảo và dùng vào phần nào

Đã truy cập repository, khóa commit và đọc các file ghi trong
[manifest nguồn](../papers/ividr_reference_sources_20261023.json).
Chỉ lưu metadata/hash/đoạn dòng liên quan; **chưa copy hoặc thực thi các model này**.
Không đưa lại nguồn mà người dùng đã yêu cầu loại khỏi đồ án.
Trong phạm vi tìm kiếm này chưa xác minh được source tác giả khớp đầy đủ IViDR v1.

| Nguồn | File/commit đã kiểm tra | Tham khảo cho IViDR | Giới hạn |
| :-- | :-- | :-- | :-- |
| [iDCF, KDD 2023](https://github.com/BgmLover/iDCF/tree/462014126f6e2fc33053341c1da250f9cf6f1fa0) [2] | `ivae_exposure.py`, `models/vae.py`, `iDCF.py`, `utils.py`; `462014126f6e` | ELBO/KL annealing, prior theo proxy, MF latent, dữ liệu Yahoo/split/evaluator | Là iDCF, không có toàn bộ learned IV của IViDR; API không ghi license |
| [iVAE, AISTATS 2020](https://github.com/ilkhem/iVAE/tree/cf6ff689f8ea957d70c54639132e3a875903a257) [3] | `models/nets.py`; `cf6ff689f8ea` | Prior/posterior, parameterization variance và ELBO | Nền tảng iVAE, không phải recommender IViDR; MIT |
| [IV4Rec, WWW 2022](https://github.com/Ethan00Si/Instrumental-variables-for-recommendation/tree/3bc141194dd36719ce86adb5d5c2bf93d4f4c4b3) [4] | `models/IV_DIN.py`, `IV_NRHUB.py`, `modules/phi.py`; `3bc141194dd3` | Projector, MLP0 và cách gate kết hợp embedding | Dùng search queries làm IV; không có dual iVAE; API không ghi license |
| [DFIV, ICLR 2021](https://github.com/liyuan9988/DeepFeatureIV/tree/27442c3084196f352154e84504d37b0d94f9a289) [5] | `src/models/DFIV/model.py`, `src/utils/pytorch_linear_reg_utils.py`; `27442c308419` | Chẩn đoán và tối ưu hai giai đoạn IV, least squares/regularization | Khác estimator; không chép ridge vào Eq. (6) rồi gọi nguyên bản IViDR; MIT |

Đối chiếu quan trọng ở IV4Rec: source dùng sigmoid cho gate và kết hợp **photo gốc
+ phần projected**, không phải nguyên văn `alpha*fitted + beta*residual` của IViDR.
Đổi sang gate sigmoid là một **ablation lấy cảm hứng từ nguồn liên quan**, không
phải lỗi IViDR đã được xác nhận. Source DFIV hiện dùng explicit inverse trong
linear regression; không sao chép nguyên mẫu đó thay QR hiện hành để “ổn định số”.
[Biên bản đọc IV4Rec](../archive/2026-10-23/ividr_research/iv4rec_source_inspection.json)
giữ số dòng và hash để đối chiếu lần sau.

Hai tài liệu gần đây có ích cho hướng mở rộng, **không đồng nhất với IViDR**:

- **IDCIV-RS, IJCAI 2025** [6]: học conditional IV và conditioning set từ interaction.
  [PDF chính thức đã lưu](../papers/IDCIV_RS_IJCAI2025.pdf). arXiv 2408.09651v1 gọi
  CIV4Rec; v2 đổi thành IDCIV-RS. Chưa xác minh được source chính thức trong các
  nguồn đã kiểm tra; không suy repo từ tên gần giống. Dữ liệu paper là phim.
- **DIVRS/DIVRS-GCN, Neural Networks 193, January 2026**, article107977 [7]: học
  surrogate IV, có OPR cho GCN. Metadata/abstract publisher đã kiểm tra; chưa xác
  minh toàn văn/source. Là phương pháp khác, không thay IViDR trong bộ benchmark.

Đã lưu thêm [iVAE PDF](../papers/iVAE_AISTATS2020.pdf) và
[IV4Rec arXiv v1 PDF](../papers/IV4Rec_WWW2022.pdf). Manifest ghi URL, tiêu đề đã
kiểm tra, số trang và SHA-256; không ghi nhận đã chạy lại các source tham khảo.

## 6. Kế hoạch đối chứng có thể thực hiện

1. **Đóng băng baseline** reference v2, split1234, nhãn và metric local; lưu manifest
   dữ liệu. Dùng Coat trước vì nhỏ và MF/iDCF đã có mốc đối chiếu.
2. **Gắn chẩn đoán theo epoch**: train/validation reconstruction BCE, KL từng nhánh,
   norm X_re−A, rank/condition instrument, gate histogram, posterior similarity,
   gradient norm của MLP0/feature embedding/gate. Dùng biased data, không xem test.
3. **Ablation theo Table 4**: T / fitted / residual / full; định nghĩa rõ cùng
   coordinate adapter và scale. Trước khi dùng kết quả, phải kiểm tra shape và phép
   cộng input. Thay adapter/gate/sharing mang tên mới và ghi khác biệt với paper.
4. **Tuning stage1 trên validation**: bắt đầu LR {1e-3,5e-4,1e-4}, WD {1e-5,1e-6};
   giữ treatment dim32, rho=tau=.9, phi=lambda=1, BCE. Sáu cấu hình này là kế hoạch
   địa phương nằm trong grid LR/WD paper, không phải config tối ưu tác giả công bố.
   Với mỗi latent cache, giữ cùng feedback grid10; ghi chi phí toàn bộ60 trial.
   ELBO thấp không đảm bảo ranking tốt: selection cuối dựa **validation NDCG**,
   dùng cùng selection rule cho mọi cấu hình và không thay rule sau khi thấy test.
5. **Khóa cấu hình bằng validation** ở seed42/43/44, sau đó báo cáo10seed42–51.
   Ba seed sàng lọc có thể nằm trong10seed cuối vì không dùng test; ghi rõ quá trình
   tuning đã diễn ra. Ghi mean, sample std `ddof=1`, không chọn seed đẹp nhất.
6. **Yahoo/KuaiRand** chỉ chạy đối chiếu paper khi có profile dữ liệu tương ứng;
   nếu chưa đủ thông tin, tiếp tục gắn nhãn adaptation. Không đổi ngưỡng/candidate
   pool hoặc bỏ user khó để ép tăng chỉ số.

Đây là kế hoạch, chưa có bằng chứng cấu hình nào ở trên làm tăng điểm. Tăng epoch
đơn thuần không xử lý việc checkpoint đã early-stop và nhánh IV đang gần triệt tiêu.
Không coi khoảng mean ± std của paper là tiêu chí duy nhất: cần đúng phiên bản,
dữ liệu, selection, metric và kết quả lặp ổn định.

Các lệnh **hiện có** để chạy baseline, từ `services/recsys`:

```powershell
# Một seed, cấu hình IViDR hiện hành; tự huấn luyện MF treatment nếu cần.
.\venv\Scripts\python.exe experiments\run.py benchmark --dataset coat --model ividr --device cpu --threads 2

# 10 seed baseline, chưa phải runner của kế hoạch ablation/tuning stage1 ở trên.
.\venv\Scripts\python.exe experiments\run.py coat-seeds --models IViDR --seeds 42 43 44 45 46 47 48 49 50 51 --threads 2
```

Không thêm `--lr` khi muốn giữ grid feedback tự động. `--ivae-lr` chỉ chỉnh LR
stage1; CLI benchmark chưa có runner quét stage1 validation-only. Không chạy hàng
loạt benchmark có test để chọn hyperparameter từ các bảng kết quả đó.

## 7. Nguồn tham khảo

[1] J. Deng et al., “Mitigating Dual Latent Confounding Biases in Recommender Systems,”
arXiv:2410.12451v1, 2024. [arXiv](https://arxiv.org/abs/2410.12451v1),
[PDF đang lưu](../papers/IViDR.pdf), §4.3–4.6, §5.1, Tables2–4, Algorithm1.

[2] Q. Zhang et al., “Debiasing Recommendation by Learning Identifiable Latent
Confounders,” KDD2023. [Paper tác giả](https://reijz.github.io/papers/2023-debiasing-recommendation-by-learning-ide.pdf),
[repo tác giả](https://github.com/BgmLover/iDCF).

[3] I. Khemakhem et al., “Variational Autoencoders and Nonlinear ICA: A Unifying
Framework,” AISTATS2020, PMLR108, pp.2207–2217.
[Publisher](https://proceedings.mlr.press/v108/khemakhem20a.html).

[4] Z. Si et al., “A Model-Agnostic Causal Learning Framework for Recommendation
using Search Data,” WWW2022. [arXiv](https://arxiv.org/abs/2202.04514).

[5] L. Xu et al., “Learning Deep Features in Instrumental Variable Regression,”
ICLR2021. [Paper](https://openreview.net/forum?id=sy4Kg_ZQmS7).

[6] Z. Huang et al., “Interaction-Data-guided Conditional Instrumental Variables
for Debiasing Recommender Systems,” IJCAI2025, pp.2955–2963.
[Publisher PDF](https://www.ijcai.org/proceedings/2025/0329.pdf),
[arXiv v2](https://arxiv.org/abs/2408.09651v2).

[7] Z. Huang et al., “Learning instrumental variable representation for debiasing
in recommender systems,” Neural Networks, vol.193, article107977, 2026.
[Publisher](https://www.sciencedirect.com/science/article/pii/S0893608025008585).

Ngày truy cập nguồn ngoài: 23/10/2026. Đợt này không chứng nhận source chính thức
IViDR v1, không sửa BCE, không đưa nguồn đã loại vào project, không công bố điểm mới.
