# Bộ bàn giao mỹ thuật Đế Đạo

## Đọc theo thứ tự
1. AGENTS.md: quy định workspace; Unity là engine đang dùng.
2. docs/art/GAME_ART_DIRECTION.md: định hướng xuyên asset, mẫu tham chiếu, phạm vi duyệt.
3. docs/art/ASSET_FAILURE_LOG.md: lỗi nhân vật, phương pháp đã thất bại và các lượt thử. Đọc cả các mục mới; đừng chỉ lấy phần đầu file.
4. docs/art/ENVIRONMENT_FAILURE_LOG.md: lỗi môi trường.
5. docs/art/ANIMATION_DEVELOPMENT_BASELINE.md: phương pháp animation đã chọn, giới hạn còn mở.
6. .agents/rules/art_and_asset_standards.md: quy trình chi tiết, có nội dung lịch sử đã bị thay thế.
7. docs/GDD_THIET_KE_TONG_THE.md và Unity/README.md: bối cảnh thiết kế và tích hợp.

## Lưu ý mâu thuẫn và phạm vi
- Yêu cầu trực tiếp mới nhất của người dùng ưu tiên. GAME_ART_DIRECTION là chuẩn xuyên asset khi quy tắc cũ mâu thuẫn.
- Không áp chibi 2,5 đầu hoặc một canvas cố định lên tất cả asset.
- Phần đầu ASSET_FAILURE_LOG còn ghi thử nghiệm 128×128; baseline animation 2026-10-25 ghi 96×96, neo (48,92). Đây là các thử nghiệm khác nhau, không tự trộn neo hoặc đổi kích thước.
- Baseline animation được chọn về PHƯƠNG PHÁP, chưa đồng nghĩa mọi pose được duyệt hoặc được đưa vào production.
- 1,5× không phải scale nguyên. Giảm ảnh và quantize không tự chứng minh đạt pixel art.
- Sau hai lần thất bại cùng lỗi/cùng phương pháp, đổi cách kiểm soát; chỉ đổi prompt hoặc provider không đặt lại bộ đếm.
- Duyệt một hướng/action trước khi mở rộng. Giữ nguồn gốc, PNG native, file chỉnh sửa, prompt và ảnh kiểm tra thực tế.

## Skill
- .agents/skills/generate2dmap: nền, tile, map, props môi trường.
- .agents/skills/generate2dsprite: nhân vật, vật phẩm, icon, FX và đóng gói sprite.
- .agents/skills/video2dsprite: animation từ ảnh master hoặc video.
- .agents/skills/generate2dmedia: chọn đường API/CLI, sinh media, ledger.
- .agents/skills/codeart2d: vẽ bằng code; chỉ dùng trong phạm vi người dùng cho phép, không thay tranh sinh ảnh âm thầm.
- external-skills/imagegen: tài liệu skill tạo ảnh tổng quát của Codex; scripts của skill hệ thống này không nằm trong gói.
Các skill Forge được giữ cùng cấu trúc thư mục để không mất liên kết tương đối. Phụ thuộc runtime/API cần cấu hình riêng.

## Phạm vi gói
Đây là bản chụp tài liệu và bộ skill, không phải một dự án game chạy độc lập. Các PNG/Aseprite/reference được nhắc trong tài liệu vẫn nằm ở đường dẫn gốc, không được đóng kèm. Không kèm tài khoản, token, config riêng hoặc toàn bộ thư mục tools. manifest.json ghi hash các file nguồn đã sao chép. Các tài liệu gốc không bị sửa.

## Prompt bàn giao gợi ý
Đọc README và các tài liệu theo thứ tự. Xác định asset, mẫu đang áp dụng, canvas/neo, phương pháp và lỗi cần sửa trước khi làm. Không suy ra một kết quả được duyệt chỉ từ PASS kỹ thuật. Dùng đúng provider người dùng yêu cầu; không bịa ảnh khi API thất bại. Giữ output mới riêng và trình duyệt trước khi tích hợp game.
