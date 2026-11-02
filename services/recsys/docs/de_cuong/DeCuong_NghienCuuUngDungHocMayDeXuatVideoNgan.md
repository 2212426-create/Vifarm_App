> **ĐỀ CƯƠNG, KHÔNG PHẢI BÁO CÁO KẾT QUẢ.** Cấu trúc bám bản `.docx` chính thức, phạm vi cập nhật theo mã hiện hành
> ([khác biệt](README.md#khác-biệt-với-bản-docx)). Điểm số và giới hạn: [CURRENT_STATE](../CURRENT_STATE.md).

# ĐỀ CƯƠNG THỰC HIỆN ĐỒ ÁN CHUYÊN NGÀNH

Trường Đại học Đà Lạt, Khoa Công nghệ Thông tin.

**Tên đề tài:** Nghiên cứu ứng dụng học máy trong phân tích hành vi người dùng và đề xuất video ngắn trên nền tảng
quảng bá sản phẩm nông nghiệp.

**Giáo viên hướng dẫn:** TS. Nguyễn Thị Lương

| STT | Họ và tên | MSSV | Lớp | Email | Trọng tâm |
| :-: | :-- | :-- | :-- | :-- | :-- |
| 1 | Vũ Thế Huỳnh | 2312639 | CTK47A | 2312639@dlu.edu.vn | [Phần 1: Lọc cộng tác](DeCuong_Phan1_LocCongTac_CF.md) |
| 2 | Phùng Nguyễn Hoài Bo | 2312585 | CTK47A | 2312585@dlu.edu.vn | [Phần 2: Học sâu](DeCuong_Phan2_HocSau_DeepLearning.md) |

## I. Mục tiêu đề tài

Video ngắn mang đến cơ hội để nông dân và doanh nghiệp quảng bá nông sản, quy trình nuôi trồng sạch và văn hóa địa
phương trực tiếp đến người tiêu dùng. Trước khối lượng nội dung lớn, người dùng dễ rơi vào tình trạng quá tải thông
tin, nên hệ thống gợi ý là thành phần cần thiết của nền tảng.

Dữ liệu tương tác chỉ phản ánh những video đã được hiển thị. Vì thế mô hình học trên dữ liệu quan sát dễ nhầm giữa
"được hiển thị nhiều" và "thật sự được yêu thích" (thiên lệch hiển thị, exposure bias). Đề tài tập trung vào nhóm
phương pháp khử thiên lệch.

Mục tiêu chi tiết:

- **Thu thập dữ liệu:** tìm hiểu, xử lý các bộ dữ liệu chuẩn mô tả hành vi người dùng (Coat, Yahoo! R3 và KuaiRand-Pure
  trên nền tảng video ngắn), có phần dữ liệu hiển thị ngẫu nhiên để đánh giá không thiên lệch.
- **Xây dựng mô hình học máy:** phân tích sở thích cá nhân, dự đoán mức độ quan tâm và đề xuất video phù hợp cho từng
  người dùng, đồng thời giảm thiên lệch hiển thị trong dữ liệu quan sát.
- **So sánh và đánh giá:** triển khai song song và đo lường hiệu quả giữa các thuật toán Lọc cộng tác (MF, DR-BIAS + CDR,
  ConAlign) và Học sâu (iDCF, IViDR, LCDR) theo từng giao thức đánh giá.

## II. Nội dung đề tài

**Chương I. Cơ sở lý thuyết**

1. Tổng quan về thuật toán Lọc cộng tác (Collaborative Filtering, CF).
2. Kiến trúc mạng nơ-ron trong hệ thống gợi ý: NCF, VAE và iVAE.
3. Thiên lệch hiển thị, biến nhiễu tiềm ẩn và các phương pháp khử thiên lệch.
4. Các chỉ số dùng để đánh giá độ chính xác: NDCG@5, Recall@5, Precision@5, HitRate@5, AUC.

**Chương II. Xây dựng mô hình và triển khai**

1. Thu thập và tiền xử lý dữ liệu.
2. Xây dựng mô hình phân tích sở thích người dùng dựa trên Lọc cộng tác: MF, DR-BIAS + CDR, ConAlign.
3. Xây dựng mô hình dự đoán mức độ quan tâm dựa trên Học sâu: iDCF, IViDR, LCDR.
4. Lập bảng so sánh hiệu quả giữa các mô hình trên từng giao thức đánh giá. Ba giao thức (H30, CDR source, ConAlign source)
   không so trực tiếp với nhau ([giao thức](../benchmarks/evaluation_protocol.md)).
5. Đóng gói mô hình thành API và tích hợp vào ứng dụng TopTop.

**Chương III. Kết luận và hướng phát triển**

1. Kết luận.
2. Hạn chế.
3. Hướng phát triển.

## III. Phần mềm và công cụ sử dụng

- Môi trường phát triển: Visual Studio Code, Google Colab.
- Xây dựng mô hình AI: Python, Pandas, NumPy, SciPy, PyTorch.
- Triển khai API: FastAPI, Uvicorn, Cloudflare Tunnel.
- Tích hợp: ứng dụng Flutter, Firebase Realtime Database.
- Quản lý mã nguồn: Git, GitHub.

## IV. Dự kiến kết quả đạt được

- Hoàn thiện hai nhóm mô hình học máy (CF và Deep Learning) có khả năng phân tích hành vi và đề xuất video, được đánh giá
  định lượng trên ba bộ dữ liệu chuẩn.
- Hệ thống API phục vụ các mô hình MF và DR-BIAS + CDR, tích hợp với ứng dụng di động.

## V. Kế hoạch thực hiện

| Từ ngày | Đến ngày | Nội dung | Phụ trách chính | Ghi chú |
| :-- | :-- | :-- | :-- | :-- |
| 03/08/2026 | 10/08/2026 | Làm đề cương chi tiết của đề tài. | Cả nhóm | Đã hoàn thành |
| 11/08/2026 | 20/08/2026 | Tìm hiểu tổng quan đề tài, nghiên cứu cơ sở lý thuyết Học máy. | Cả nhóm | Đã hoàn thành |
| 21/08/2026 | 01/09/2026 | Khảo sát, thu thập và tiền xử lý dữ liệu hành vi người dùng. | Cả nhóm | Đã hoàn thành |
| 02/09/2026 | 13/09/2026 | Xây dựng, huấn luyện và kiểm thử mô hình Lọc cộng tác. | Vũ Thế Huỳnh | Đã hoàn thành |
| 14/09/2026 | 20/09/2026 | Báo cáo tiến độ lần 1. | Cả nhóm | Đã hoàn thành |
| 21/09/2026 | 04/10/2026 | Tìm hiểu lý thuyết Học sâu, xây dựng và huấn luyện mô hình. | Phùng Nguyễn Hoài Bo | Đã hoàn thành |
| 05/10/2026 | 11/10/2026 | Thực nghiệm, so sánh và đánh giá giữa hai nhóm thuật toán. | Cả nhóm | Đã hoàn thành; thực nghiệm kéo dài đến 30/10 |
| 12/10/2026 | 18/10/2026 | Gửi kết quả đồ án cho GVPB. Báo cáo tiến độ lần 2. | Cả nhóm | Cần nhóm xác nhận |
| 19/10/2026 | 01/11/2026 | Đóng gói mô hình thành API, tích hợp luồng gọi API vào ứng dụng. | Cả nhóm | Đã hoàn thành |
| 02/11/2026 | 10/11/2026 | Tổng hợp số liệu thực nghiệm, viết và hoàn thiện báo cáo đồ án. | Cả nhóm | Đang thực hiện |
| 11/11/2026 | 16/11/2026 | Gửi kết quả đồ án cho GVHD và GVPB. | Cả nhóm | Sắp tới |
| 17/11/2026 | 22/11/2026 | Bảo vệ đồ án. Nộp báo cáo đồ án cho khoa theo lịch thi. | Cả nhóm | Sắp tới |

## VI. Tài liệu tham khảo

**Website**

1. FastAPI Documentation: <https://fastapi.tiangolo.com/>
2. PyTorch Documentation: <https://pytorch.org/docs/>
3. KuaiRand Dataset: <https://kuairand.com/>
4. CDR Official Repository: <https://github.com/CrazyDumpling/CDR_CIKM2023>
5. iDCF Official Repository: <https://github.com/BgmLover/iDCF>
6. ConAlign Official Repository: <https://github.com/JcZhangzz/ConAlign>

**Tài liệu**

1. Gao, C., Li, S., Zhang, Y., Chen, J., Li, B., Lei, W., Jiang, P., & He, X. (2022). KuaiRand: An Unbiased Sequential
   Recommendation Dataset with Randomly Exposed Videos. CIKM.
2. Hu, Y., Koren, Y., & Volinsky, C. (2008). Collaborative Filtering for Implicit Feedback Datasets. ICDM.
3. He, X., Liao, L., Zhang, H., Nie, L., Hu, X., & Chua, T. S. (2017). Neural Collaborative Filtering. WWW.
4. Aggarwal, C. C. (2016). Recommender Systems: The Textbook. Springer.
5. Steck, H. (2010). Training and Testing of Recommender Systems on Data Missing Not at Random. KDD.
6. Schnabel, T., Swaminathan, A., Singh, A., Chandak, N., & Joachims, T. (2016). Recommendations as Treatments: Debiasing
   Learning and Evaluation. ICML.
7. Marlin, B. M., & Zemel, R. S. (2009). Collaborative Prediction and Ranking with Non-Random Missing Data. RecSys.
8. Khemakhem, I., Kingma, D., Monti, R., & Hyvärinen, A. (2020). Variational Autoencoders and Nonlinear ICA: A Unifying
   Framework. AISTATS.
9. Song, Z., Chen, J., Zhou, S., Shi, Q., Feng, Y., Chen, C., & Wang, C. (2023). Conservative Doubly Robust Learning for
   Debiased Recommendation. CIKM.
10. Zhang, Q., Zhang, X., Liu, Y., Wang, H., Gao, M., Zhang, J., & Guo, R. (2023). Debiasing Recommendation by Learning
    Identifiable Latent Confounders. KDD.
11. Deng, J., Chen, Q., Cheng, D., Li, J., Liu, L., & Du, X. (2024). Mitigating Dual Latent Confounding Biases in
    Recommender Systems. arXiv:2410.12451.
12. Deng, J., Chen, Q., Cheng, D., Li, J., Liu, L., & Zhang, S. (2025). A Novel Generative Model with Causality Constraint
    for Mitigating Biases in Recommender Systems. arXiv:2505.16708.
13. Zhang, J., Wang, Y., Song, Q., & Hong, L. (2026). ConAlign: Conditional Alignment Framework for Balancing Biased and
    Unbiased Recommendation. RecSys.
