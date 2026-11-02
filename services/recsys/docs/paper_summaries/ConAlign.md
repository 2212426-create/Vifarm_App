# ConAlign: Conditional Alignment for Biased and Unbiased Recommendation

**Bản tổng hợp có dẫn nguồn**, lập ngày 27/10/2026 từ [PDF](../papers/ConAlign_RecSys2026.pdf)
arXiv v1 và source tác giả khóa commit. Không phải bản chép nguyên văn.

## 1. Thông tin tài liệu

- *ConAlign: Conditional Alignment Framework for Balancing Biased and Unbiased Recommendation*.
- Jingcheng Zhang, Yihan Wang, Qi Song, Liyin Hong.
- **RecSys 2026** (Minneapolis, 27/09–02/10/2026); DOI
  [10.1145/3773078.3831873](https://doi.org/10.1145/3773078.3831873);
  arXiv [2607.24092v1](https://arxiv.org/abs/2607.24092).
- Source: [JcZhangzz/ConAlign](https://github.com/JcZhangzz/ConAlign), commit
  `f6171bb5871025be2a77a37c4c9ab151cbaaab6f`, lưu đúng byte tại
  [third_party/conalign](../../third_party/conalign/upstream_manifest.json).
  **Repo không có file LICENSE**: chỉ dùng để học tập/đối chiếu, giữ attribution.

## 2. Ý tưởng

Hệ gợi ý công nghiệp có nhiều dữ liệu biased và rất ít dữ liệu unbiased (random traffic).
Huấn luyện chỉ trên unbiased thì thiếu dữ liệu; chỉ trên biased thì lệch. ConAlign dùng
**hai tháp MF**: tháp biased học từ dữ liệu biased, tháp unbiased học từ dữ liệu unbiased và
nhận kiến thức từ tháp biased qua **alignment có cổng rời rạc**. Tháp unbiased cho gợi ý cuối.

## 3. Thuật toán theo source

1. Pretrain tháp biased: BCE trên dữ liệu biased + L2 embedding, SGD; early stop theo AUC
   validation biased.
2. Chép trọng số tháp biased sang tháp unbiased, đóng băng tháp biased.
3. Fine-tune tháp unbiased trên hỗn hợp biased + unbiased đã xáo trộn:
   - BCE chỉ tính trên mẫu unbiased;
   - alignment (độ lệch tuyệt đối giữa embedding/bias hai tháp, tháp biased detach)
     **chỉ bật cho mẫu có BCE tháp unbiased > BCE tháp biased**: đây là cổng rời rạc;
   - L2 embedding tháp unbiased; early stop theo AUC validation unbiased.

Cấu hình source: dim 10; Coat lr 0.01/0.001, wd 0.01/0.01, alignment 0.2;
Yahoo lr 0.001/0.01, wd 1e-6/0.1, alignment 0.18; KuaiRand lr 0.01/0.01, wd 0.001, alignment 0.2;
patience 60, tối đa 500 + 500 epoch; seed mặc định 0.

## 4. Thực nghiệm của paper

- Backbone MF; baseline: MF, MF-IPS, MF-DR, CausE, KD-label, AutoDebias, InterD, KD-Debias
  (đều có trong source `baselines/`).
- Coat/Yahoo: rating > 3 là positive; biased chia 70/10/20, unbiased 50/10/40.
- Đánh giá UAUC và NDCG@5 trên cả môi trường biased và unbiased.

Số **thuộc paper** (UAUC / NDCG@5):

| Dataset | Môi trường | ConAlign | Baseline tốt nhất |
| :-- | :-- | :-- | :-- |
| Coat | Biased | .6954 / .7746 | KD-label .6903 / .7692 |
| Coat | Unbiased | .6856 / .7066 | MF-DR .6836 / .6970 |
| Yahoo!R3 | Biased | .6535 / .7898 | InterD .6622 / .7938 |
| Yahoo!R3 | Unbiased | .6841 / .7761 | InterD .6787 / .7713 |
| KuaiRand-Pure | Biased | .6145 / .8039 | InterD .6190 / .8057 |
| KuaiRand-Pure | Unbiased | .6372 / .5656 | InterD .6251 / .5544 |

ConAlign dẫn đầu môi trường unbiased ở cả ba dataset; môi trường biased chỉ dẫn ở Coat.
Paper có A/B test trực tuyến trên Kuaishou với backbone DNN công nghiệp.

## 5. Khác biệt paper và source

- Paper (Sec. 4.1) dùng log KuaiRand **22/04–08/05 (17 ngày)**: train hai tuần đầu (22/04–05/05),
  validation ngày 15 (06/05), test hai ngày cuối (07–08/05).
  Source `utils/load_kuairand.py` ghi trong docstring là train 28 ngày 08/04–05/05, nhưng tạo ngày bằng
  `20220408 + i` (i < 28). Sau 20220430 các giá trị là 20220431…20220435, không phải ngày thật, nên
  **01–05/05 không vào train**. Validation và test trùng paper.
- Từ 30/10/2026 project mặc định cửa sổ của paper; `kuairand_window='source'` giữ đúng loader gốc.
  Đính chính ghi chú 27/10 ("Project theo source"): xem
  [hướng dẫn, mục cửa sổ KuaiRand](../benchmarks/lcdr_conalign_20261027.md).
- Paper ghi KuaiRand-Pure có 1.000 user và 7.388 video; log Pure 22/04–08/05 thực tế có 27.285 user
  và 7.583 video. Paper không mô tả tập con nào khác.
- Paper ghi "NDCG@5" nhưng source in cả `UNDCG` (user có positive) và `NDCG` (user có cả hai nhãn);
  artifact giữ cả hai tên source. Bảng benchmark chung hiển thị `NDCG` ở cột NDCG@5 và in UAUC/UNDCG
  dưới bảng. KuaiRand cửa sổ paper: UNDCG .5650 gần "NDCG@5" .5656 của paper, nhưng Coat/Yahoo không cho
  thấy rõ paper dùng metric nào.

## 6. Cài đặt trong project

Xem [giao thức và cách chạy](../benchmarks/lcdr_conalign_20261027.md) và
[hồ sơ nguồn](../../src/models/conalign/source.json).
