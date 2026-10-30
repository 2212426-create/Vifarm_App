# Tình trạng tài liệu thuyết trình

**Chưa có bộ slide/kịch bản hiện hành đã kiểm chứng toàn bộ nội dung.** Hai bản cũ
đã chuyển vào archive; đường dẫn cũ giữ thông báo để tránh người đọc dùng nhầm.

Các nhận định bị thu hồi khỏi tài liệu hiện hành:

| Nhận định cũ | Cách trình bày được phép ở mốc hiện tại |
| :-- | :-- |
| CDR/IViDR vượt MF trên mọi chỉ số | Chưa có benchmark test nhiều seed của bộ mô hình hiện tại |
| IViDR chỉ giữ Z, bỏ hoàn toàn C hoặc khử 100% confounding | IViDR-approx chưa đúng paper; không có bảo đảm thực nghiệm như vậy |
| MF API dùng BCE, CDR mặc định warm-start MF | MF dùng MSE; CDR dùng BCE và huấn luyện độc lập |
| Adam luôn vượt SGD | Phải đọc thí nghiệm cùng objective/config; không khái quát cho mọi dữ liệu |
| API 150–250 ms / đã triển khai mô hình tốt nhất | Chưa có phép đo độ trễ/benchmark triển khai làm căn cứ ở mốc này |

Nguồn để soạn lại: [CURRENT_STATE](../CURRENT_STATE.md),
[giao thức](../benchmarks/evaluation_protocol.md), [catalog kết quả](../../results/CATALOG.md).
Giữ mô tả đề tài và kế hoạch tách khỏi kết quả đã thực hiện.

Bản cũ: [slide](../archive/2026-10-20/presentation/presentation_slides.md),
[kịch bản](../archive/2026-10-20/presentation/presentation_script.md).
File [PPTX lịch sử](../archive/2026-10-20/presentation/Slide_33_NghienCuuUngDungHocMayDeXuatVideoNgan.pptx)
cũng đã chuyển vào archive, giữ nguyên byte và có checksum; chưa được sửa thành
bộ trình chiếu dùng cho trạng thái hiện tại.
