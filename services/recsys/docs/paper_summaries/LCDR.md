# LCDR: Latent Causality Constraints for Debiasing Recommendation

**Bản tổng hợp có dẫn nguồn**, lập ngày 27/10/2026 từ [PDF](../papers/LCDR.pdf) và
[mã LaTeX](../papers/LCDR_arxiv_v1_source.tex) arXiv v1. Không phải bản chép nguyên văn.

## 1. Thông tin tài liệu

- *A Novel Generative Model with Causality Constraint for Mitigating Biases in Recommender Systems*.
- Jianfeng Deng, Qingfeng Chen, Debo Cheng, Jiuyong Li, Lin Liu, Shichao Zhang
  (cùng nhóm tác giả với IViDR).
- arXiv [2505.16708v1](https://arxiv.org/abs/2505.16708), 22/05/2025, 11 trang; chưa ghi nơi xuất bản.
- **Không có mã nguồn công khai**: abstract, HTML và LaTeX không có link; tìm GitHub theo tên
  không thấy; repo `hfutmars/ACD` xuất hiện trong kết quả tìm kiếm là dự án khác.
  [Manifest tải và SHA-256](../papers/lcdr_conalign_downloads_20261027.json).

## 2. Ý tưởng

iDCF cần proxy W tương quan mạnh với biến nhiễu ẩn. LCDR cho rằng proxy thực tế yếu/nhiễu, nên
không suy ra biến nhiễu trực tiếp từ W. Thay vào đó:

- iVAE học $Z$ từ $q(Z\mid A,W)$ với prior $p(Z\mid W)=N(\mu_w(W),v_w(W))$, như iDCF.
- Một VAE chuẩn (LCVAE) học $Z_{lc}$ chỉ từ exposure $A$, prior $N(0,I)$.
- $Z$ của iVAE làm **ràng buộc** kéo $Z_{lc}$ lại gần; W chỉ tác động gián tiếp lên $Z_{lc}$ qua $Z$.
- $Z_{lc}$ được đưa vào mô hình gợi ý MF.

## 3. Công thức theo paper

Eq. (6), ELBO của LCVAE, với $\lambda$ trọng số ràng buộc và chuẩn L2 **không bình phương**:

$$\mathcal L=E_{q(Z_{lc}\mid A)}[\log p(A\mid Z_{lc})]-KL(q(Z_{lc}\mid A)\,\|\,N(0,I))
-\lambda\lVert Z_{lc}-Z\rVert_2 .$$

$\log p(A\mid Z_{lc})$ là Bernoulli trên từng item. MF: $P_u^\top Q_i+B_u+B_i$ (Eq. 17).
Eq. (18) viết $f(u,i,Z_{lc})=\mathcal L_{LCVAE}+\mathcal L_{MF}$; Eq. (12) định nghĩa
$\mathcal L_{LCVAE}$ bị cụt trong bản v1.

Algorithm 1: mỗi batch tính iVAE(A, W) và LCVAE(A), lấy mẫu $Z$, $Z_{lc}$ bằng
reparameterization, cập nhật theo $-\mathcal L$; sau đó huấn luyện mô hình gợi ý trên $Z_{lc}$.
Phần độ phức tạp ghi iVAE và LCVAE "chạy song song" trong bước 1.

## 4. Thực nghiệm của paper

- Dữ liệu và split "Following iDCF": toàn bộ biased để train, 30% unbiased làm validation,
  phần còn lại làm test; Coat/Yahoo rating ≥ 4, KuaiRand `IsClick=1`.
  Thống kê dataset trùng bảng của iDCF (KuaiRand 23.533 user, 6.712 video).
- Adam; lưới lr {1e-3, 5e-4, 1e-4, 5e-5, 1e-5}, weight decay {1e-5, 1e-6};
  $\lambda$ = 0.9 Coat, 0.1 Yahoo!R3, 0.9 KuaiRand; 10 lần chạy.

Số **thuộc paper**, NDCG@5 / Recall@5 (trung bình ± std):

| Dataset | LCDR | iDCF (paper LCDR chạy lại) |
| :-- | :-- | :-- |
| Coat | .5973 ± .0101 / .5878 ± .0119 | .5643 ± .0114 / .5498 ± .0129 |
| Yahoo!R3 | .6631 ± .0033 / .7928 ± .0034 | .6421 ± .0027 / .7806 ± .0041 |
| KuaiRand | .4176 ± .0008 / .3575 ± .0011 | .4084 ± .0005 / .3485 ± .0007 |

## 5. Thiếu sót của paper

Không công bố: số lớp/độ rộng mạng, số chiều latent, lr/wd được chọn, batch, số epoch,
điều kiện dừng, seed; không nói proxy W của Yahoo/KuaiRand; Eq. (18) và Eq. (12) không đủ
để biết cách đưa $Z_{lc}$ vào MF; không ghi iVAE có tối ưu ELBO riêng trong bước 1 hay không.
Vì vậy một bản cài đặt lại **không thể** xem là tái lập chính xác.

## 6. Cài đặt trong project

Xem [giao thức và cách chạy](../benchmarks/lcdr_conalign_20261027.md) và
[hồ sơ nguồn](../../src/models/lcdr/source.json). Tóm tắt lựa chọn địa phương: dùng lại iVAE,
proxy và cấu hình mạng của iDCF; iVAE giữ ELBO riêng, $Z$ được detach trong ràng buộc;
Eq. (18) đọc theo dạng MFMF của iDCF $MF(u,i)+\langle e_i,Z_{lc,u}\rangle$, loss MSE.
