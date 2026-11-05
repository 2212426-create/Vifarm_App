# IViDR: điểm paper, chẩn đoán và nguồn tham khảo

Đặc tả đang chạy: [ividr_reference](ividr_reference_20261022.md). Nguyên nhân khoảng cách với paper:
[ividr_root_cause](ividr_root_cause_20261027.md).

## Điểm mục tiêu

*Mitigating Dual Latent Confounding Biases in Recommender Systems*, arXiv 2410.12451v1, Table 3 (trang PDF 8), 10 trials [1].

| Dataset | NDCG@5 | RECALL@5 |
| :-- | --: | --: |
| Coat | .5903 ± .0101 | .5783 ± .0114 |
| Yahoo! R3 | .6602 ± .0038 | .7901 ± .0037 |
| KuaiRand | .4161 ± .0004 | .3549 ± .0006 |

Paper v1 không nêu đầy đủ công thức Recall, ngưỡng nhãn, cách chia random log và cách chọn checkpoint, và không
công bố danh sách seed. Evaluator theo iDCF là tham chiếu có cơ sở, **chưa đủ chứng nhận đúng protocol IViDR**.

## Chẩn đoán nhánh tái dựng, 23/10/2026

Trên checkpoint Coat bản theo paper, chỉ dùng biased exposure, không tính prediction trên test
([JSON](../../results/studies/ividr_research_diagnostics_20261023.json)):

| Phép đo | Kết quả |
| :-- | --: |
| ‖X_re − A‖F / ‖A‖F | .00298 |
| Cosine hai ma trận posterior mean | .99998778 |
| Gate fitted, trung bình | .0178 |
| Gate residual, trung bình | −.0034 |
| Rank instrument theo item | 4–11 trong không gian 32 chiều |

Nhánh tái dựng hoạt động yếu khiến hai posterior gần trùng. Ablation sau đó cho thấy đây không phải nguyên nhân chính
của khoảng cách với iDCF ([Eq. 10](ividr_eq10_ablation_20261027.md)).

Các khoảng trống đã xác nhận nhưng chưa xử lý: giai đoạn 1 kế thừa cấu hình iDCF, chưa quét riêng; Yahoo khác cohort
(15.400 so với 5.400 user); KuaiRand khác preprocessing và instrument.

## Mã nguồn liên quan

Đã khóa commit và đọc các file trong [manifest nguồn](../papers/ividr_reference_sources_20261023.json); chưa copy hoặc
chạy các model này. **Chưa xác minh được source tác giả IViDR v1.**

| Nguồn | Tham khảo cho | Giới hạn |
| :-- | :-- | :-- |
| [iDCF, KDD 2023](https://github.com/BgmLover/iDCF/tree/462014126f6e2fc33053341c1da250f9cf6f1fa0) [2] | ELBO, KL annealing, prior theo proxy, MF latent, split, evaluator | Không có learned IV |
| [iVAE, AISTATS 2020](https://github.com/ilkhem/iVAE/tree/cf6ff689f8ea957d70c54639132e3a875903a257) [3] | Prior/posterior, parameterization variance, ELBO | Không phải recommender; MIT |
| [IV4Rec, WWW 2022](https://github.com/Ethan00Si/Instrumental-variables-for-recommendation/tree/3bc141194dd36719ce86adb5d5c2bf93d4f4c4b3) [4] | Projector, MLP0, gate kết hợp embedding | IV là search query; không có dual iVAE |
| [DFIV, ICLR 2021](https://github.com/liyuan9988/DeepFeatureIV/tree/27442c3084196f352154e84504d37b0d94f9a289) [5] | Chẩn đoán IV hai giai đoạn | Estimator khác; MIT |

Hướng mở rộng, không đồng nhất với IViDR: **IDCIV-RS, IJCAI 2025** [6] học conditional IV từ interaction
([PDF](../papers/IDCIV_RS_IJCAI2025.pdf); chưa xác minh source chính thức). **DIVRS/DIVRS-GCN, Neural Networks 2026** [7]
học surrogate IV (mới kiểm tra metadata và abstract).

## Tài liệu trích dẫn

Truy cập nguồn ngoài ngày 23/10/2026.

[1] J. Deng et al., "Mitigating Dual Latent Confounding Biases in Recommender Systems," arXiv:2410.12451v1, 2024.
[arXiv](https://arxiv.org/abs/2410.12451v1), [PDF](../papers/IViDR.pdf).

[2] Q. Zhang et al., "Debiasing Recommendation by Learning Identifiable Latent Confounders," KDD 2023.
[Paper](https://reijz.github.io/papers/2023-debiasing-recommendation-by-learning-ide.pdf).

[3] I. Khemakhem et al., "Variational Autoencoders and Nonlinear ICA: A Unifying Framework," AISTATS 2020, PMLR 108, pp. 2207–2217.
[Publisher](https://proceedings.mlr.press/v108/khemakhem20a.html).

[4] Z. Si et al., "A Model-Agnostic Causal Learning Framework for Recommendation using Search Data," WWW 2022.
[arXiv](https://arxiv.org/abs/2202.04514).

[5] L. Xu et al., "Learning Deep Features in Instrumental Variable Regression," ICLR 2021.
[Paper](https://openreview.net/forum?id=sy4Kg_ZQmS7).

[6] Z. Huang et al., "Interaction-Data-guided Conditional Instrumental Variables for Debiasing Recommender Systems," IJCAI 2025, pp. 2955–2963.
[PDF](https://www.ijcai.org/proceedings/2025/0329.pdf).

[7] Z. Huang et al., "Learning instrumental variable representation for debiasing in recommender systems," Neural Networks, vol. 193, article 107977, 2026.
[Publisher](https://www.sciencedirect.com/science/article/pii/S0893608025008585).
