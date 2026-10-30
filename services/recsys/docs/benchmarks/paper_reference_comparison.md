# Tham chiếu bài báo: giữ đúng nguồn và biến thể

Đây là chỉ dẫn nguồn nghiên cứu bên ngoài. Kết quả dự án nằm ở
[results/CATALOG.md](../../results/CATALOG.md); trạng thái ở [CURRENT_STATE](../CURRENT_STATE.md).
Không ghép các dòng từ nhiều paper thành bảng xếp hạng có điều kiện thực nghiệm giống nhau.

| Nguồn | Nội dung cần đọc | Phân biệt với dự án |
| :-- | :-- | :-- |
| [iDCF PDF](../papers/iDCF.pdf), [bản chép](../paper_summaries/iDCF.md) | Phương pháp, preprocessing, bảng so sánh và thống kê nhiều seed của iDCF | Không dùng số iDCF được chạy lại trong paper IViDR thay cho số paper iDCF gốc |
| [CDR PDF](../papers/CDR.pdf), [bản chép](../paper_summaries/CDR.md) | Eq. (7), CV filter, giao thức 10/90, từng biến thể DR+CDR | Script công bố và paper có khác biệt; benchmark dự án dùng giao thức chung 30/70 |
| [IViDR PDF](../papers/IViDR.pdf), [bản chép](../paper_summaries/IViDR.md) | MLP/treatment reconstruction và loss BCE | Dự án hiện có IViDR-approx; chưa được dùng số paper làm bằng chứng triển khai |
| [ReCRec bản chép](../paper_summaries/ReCRec.md) | Nghiên cứu bổ sung và giao thức riêng | Không có pipeline ReCRec trong bộ chạy mặc định |

Riêng CDR, các số hay bị dùng nhầm trong tài liệu cũ:

| Nguồn Table 2 CDR | Dataset | Biến thể | NDCG@5 / Recall@5 |
| :-- | :-- | :-- | :-- |
| CDR paper | Coat | DR-BIAS+CDR | .6567 / .6678 |
| CDR paper | Yahoo! R3 | DR-BIAS+CDR | .6565 / .7323 |
| CDR paper | KuaiRand | DR-BIAS+CDR | .3098 / .3048 |
| CDR paper | KuaiRand | MRDR+CDR | .3167 / .3078 |

Không gọi dòng “CDR tốt nhất theo từng dataset” là một mô hình duy nhất.
Bảng ghép cũ được giữ làm dấu vết ở [archive](../archive/2026-10-20/benchmarks/paper_reference_comparison.md),
không dùng lại để kết luận mô hình dự án thấp/cao hơn paper.
Khi trích thêm số: ghi paper/phiên bản, bảng, dataset, biến thể, metric, split,
backbone, seed và độ bất định; đối chiếu PDF vì bản chép chưa được kiểm tra toàn văn.
