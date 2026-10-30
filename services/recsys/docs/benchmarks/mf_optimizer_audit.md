# MF, loss và bộ tối ưu

**Hiện hành về lựa chọn objective/optimizer.** Kết quả thực nghiệm thuộc từng
artifact, không suy ra từ ví dụ lệnh. [CURRENT_STATE](../CURRENT_STATE.md).

Cập nhật 20/10/2026. MF tính `p_u · q_i + b_u + b_i + mu`.
Adam/SGD là cách cập nhật tham số; thay optimizer không tự tạo một kiến trúc mới.

| Đầu chạy | Mục tiêu mặc định |
| :-- | :-- |
| `benchmark`, `tune`, `tune-kr`, `coat-seeds` | MF-MSE, decay mọi tham số, không scheduler, mu=0 |
| `mf` và API TopTop | MSE, decay mọi tham số, mu=0, khởi tạo uniform như iDCF |
| `optimizers` | So Adam/SGD với cùng objective; CLI mặc định BCE, có thể chọn MSE |

MSE dùng score thô, BCE dùng `BCEWithLogitsLoss`. Adam weight decay ở đây ghép L2
vào gradient, không phải AdamW. Khởi tạo mặc định là Uniform(-.01,.01) cho embedding và bias;
`mf --init-scheme normal` là lựa chọn ablation cũ.
Cấu hình này cũng có ở `benchmark`, và được lưu trong model kwargs của checkpoint.

Ví dụ từ thư mục `services/recsys`:

```powershell
.\venv\Scripts\python.exe experiments\run.py benchmark --dataset coat --model mf
.\venv\Scripts\python.exe experiments\run.py mf --dataset coat --loss mse --decay-scope all --scheduler none --init-scheme author_uniform --lr 0.0005 --weight-decay 0.000001 --epochs 100 --dim 64
.\venv\Scripts\python.exe experiments\run.py optimizers --dataset coat --loss mse --decay-scope all
```

`optimizers` tune từng optimizer trên validation, khóa cấu hình rồi chấm test và
lặp seed. Cần giữ cùng loss, initialization, dim, batch, split và ngân sách khi so sánh;
ngân sách epoch bằng nhau không bảo đảm cùng thời gian hay cùng mức hội tụ.

ALS cổ điển tối ưu mục tiêu bình phương khác và cần baseline riêng; không phải phép
thay trực tiếp cho Adam trong BCE. Không có bằng chứng một optimizer tốt nhất cho mọi dữ liệu.

[Mã MF tác giả iDCF](https://github.com/BgmLover/iDCF/blob/main/MF.py) dùng MSE + Adam;
[kiến trúc tác giả](https://github.com/BgmLover/iDCF/blob/main/models/mf.py) dùng uniform.
Điều kiện đối chiếu điểm xem [giao thức đánh giá](evaluation_protocol.md).
