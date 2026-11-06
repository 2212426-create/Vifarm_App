# Đề cương nghiên cứu

- [Đề cương tổng hợp](DeCuong_NghienCuuUngDungHocMayDeXuatVideoNgan.md).
- [Phần 1: Lọc cộng tác](DeCuong_Phan1_LocCongTac_CF.md).
- [Phần 2: Học sâu](DeCuong_Phan2_HocSau_DeepLearning.md).

Bản chính thức là file `.docx` của nhóm, nằm ngoài repo. Các file ở đây lấy cấu trúc từ bản đó và mô tả phạm vi theo mã
hiện hành. Đề cương mô tả kế hoạch, không chứng nhận kết quả; điểm số ở [CURRENT_STATE](../CURRENT_STATE.md).

## Khác biệt với bản `.docx`

| Bản `.docx` | Các file trong repo, theo mã hiện hành |
| :-- | :-- |
| Học sâu là NCF | NeuMF là mô hình học sâu đối chứng với MF (`cf-dl`); mô hình khử thiên lệch chính là iDCF, LCDR, CLEV-DR, MRDR-CAL |
| Lọc cộng tác không nêu tên mô hình | MF, DR-BIAS + CDR, ConAlign |
| Hai mô hình, "độ chính xác cao" | Hai nhóm mô hình, đánh giá định lượng trên ba bộ dữ liệu chuẩn |
| TensorFlow, thư viện `implicit`, Postman | Dự án dùng PyTorch; không dùng `implicit`; Postman không có trong repo |
| API tích hợp web/mobile | API phục vụ MF và DR-BIAS + CDR, tích hợp ứng dụng di động |
| Không có mục thiên lệch hiển thị | Thêm vào Mục tiêu và Chương I |
