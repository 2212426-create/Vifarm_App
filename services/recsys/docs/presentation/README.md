# Slide và kịch bản thuyết trình

**Chưa có bộ slide hoặc kịch bản nào trong thư mục này được kiểm chứng với trạng thái hiện tại.**
Soạn từ [CURRENT_STATE](../CURRENT_STATE.md), [giao thức](../benchmarks/evaluation_protocol.md) và
[catalog kết quả](../../results/CATALOG.md); tách kế hoạch khỏi kết quả đã thực hiện.

Các nhận định đã thu hồi, không dùng lại:

| Nhận định cũ | Cách trình bày đúng |
| :-- | :-- |
| CDR/IViDR vượt MF trên mọi chỉ số | Chỉ so trong cùng protocol; trên Coat, IViDR không khác biệt có ý nghĩa với iDCF |
| IViDR chỉ giữ Z, bỏ hoàn toàn C hoặc khử 100% confounding | Không có bảo đảm thực nghiệm như vậy |
| MF API dùng BCE, CDR mặc định warm-start MF | MF dùng MSE; CDR dùng BCE và huấn luyện độc lập |
| Adam luôn vượt SGD | Phải đọc thí nghiệm cùng objective/config; không khái quát cho mọi dữ liệu |
| API 150–250 ms, đã triển khai mô hình tốt nhất | Chưa có phép đo độ trễ làm căn cứ; API chỉ phục vụ MF và CDR |
