# IViDR: sửa nhánh Eq. (10) và ablation Table 4 — 27/10/2026

Tiếp nối [nghiên cứu 23/10](ividr_optimization_research_20261023.md), mục P0. Đặc tả mặc định
vẫn là [reference v2](ividr_reference_20261022.md); v3 và các ablation là **tùy chọn**.

## 1. Vấn đề và cách sửa thử

Chẩn đoán 23/10: phần cộng thêm của Eq. (10) chỉ bằng khoảng 0.3% chuẩn của $A$, hai posterior
gần trùng. Nguyên nhân về cơ chế: ở giai đoạn 1, gate $\alpha_1,\alpha_2$ chỉ được học qua ELBO
tái tạo $A$. Nhiễu đầu vào làm ELBO xấu đi, nên gate co phần cộng về gần 0.

Bản v3 (`eq10_bridge='tied_item_lift_rownorm'`) giữ phép cộng hệ số 1 của Eq. (10) nhưng chuẩn
hóa $P=(A\,T^{re})\,T_0^\top/\sqrt d$ theo từng user: $X^{re}_u=A_u+P_u\,\lVert A_u\rVert/\lVert P_u\rVert$.
Gate chỉ còn quyết định hướng, không xóa được phần cộng. Tùy chọn `reconstruction` chạy các
ablation của Table 4: `treatment` (IViDR-T), `fitted` (IViDR-F), `residual` (IViDR-R), `full`.
Mã: [ividr_reference.py](../../src/models/ividr/ividr_reference.py),
[train_ividr.py](../../src/models/ividr/train_ividr.py); test: `tests/test_ividr_v3.py`.

## 2. Thí nghiệm

Coat, seed 42/43/44; mỗi lượt huấn luyện MF treatment cùng seed, giai đoạn 1 tối đa 2000 epoch,
lưới feedback 10 cấu hình của paper. **Chọn biến thể chỉ bằng validation NDCG@5**; test chấm một lần.
[Script](../archive/2026-10-27/ividr_optimization/run_variant.py) · báo cáo
`results/ividr_opt_<bridge>_<reconstruction>_seed<seed>_20261027.json` · log cùng thư mục script.

| Biến thể | Val NDCG@5 (mean) | Test NDCG@5 mean ± std | Test Recall/all | Recall bounded | ‖X_re−A‖/‖A‖ | cos(μ₁, μ₂) |
| :-- | --: | --: | --: | --: | --: | --: |
| v2 full (mặc định) | .5707 | .5315 ± .0101 | .5409 | .5962 | .002–.006 | .99998–.99999 |
| v3 full | .5697 | .5362 ± .0040 | .5446 | .6005 | 1.0000 | .9990–.9994 |
| v3 fitted (IViDR-F) | .5775 | .5350 ± .0142 | .5398 | .5957 | 1.0000 | .9996–.9999 |
| v3 residual (IViDR-R) | .5701 | .5333 ± .0069 | .5442 | .5997 | 1.0000 | .9999 |
| v3 treatment (IViDR-T) | .5701 | .5342 ± .0036 | .5421 | .5975 | 1.0000 | .9994–.9999 |

Đối chứng cùng seed 42/43/44: iDCF test NDCG@5 .5755 ± .0072
([báo cáo LCDR/iDCF](../../results/lcdr_coat_20261027_220934_6395e1a8.json)). Paper IViDR Coat .5903 ± .0101.

## 3. Kết luận

1. v3 đã sửa đúng triệu chứng: phần cộng thêm tăng từ khoảng 0.3% lên 100% chuẩn của $A$.
2. Nhưng encoder học cách bỏ qua phần cộng: hai posterior mean vẫn gần trùng (cosine ≈ .999).
   Chênh lệch validation giữa các biến thể (≤ .007) nhỏ hơn dao động giữa seed (≈ .015–.018).
3. Không biến thể nào có bằng chứng tốt hơn v2 trên validation, nên **giữ v2 làm mặc định**.
   v3 fitted có validation cao nhất nhưng chênh lệch nằm trong nhiễu seed; không chọn nó.
4. Mọi biến thể IViDR vẫn thấp hơn iDCF cùng seed khoảng .04 NDCG. Như vậy nhánh IV của Eq. (10)
   **không phải nguyên nhân chính** của khoảng cách. Hướng cần kiểm tra tiếp là giai đoạn feedback:
   BCE với kỳ vọng xác suất (Eq. 25) so với MSE của iDCF, và việc gộp $C=\rho C_1+\tau C_2$ với
   $\rho=\tau=.9$ làm latent lớn gần gấp 1.8 lần. Đổi BCE là thay đổi so với paper, cần người dùng quyết định.
