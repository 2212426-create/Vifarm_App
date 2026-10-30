> **LƯU TRỮ — KHÔNG PHẢI TRẠNG THÁI HIỆN HÀNH.** Chụp trước đợt dọn 20/10/2026. Nội dung có nhận định đã bị thay thế; xem [CURRENT_STATE](../../../CURRENT_STATE.md). Bản nguyên byte nằm trong ZIP và được kiểm tra bằng checksum; bản đọc này chỉ thêm nhãn và sửa đường dẫn.

# Trạng thái mô hình và nguyên nhân chênh lệch kết quả

Cập nhật 20/10/2026. Cấu hình MF/CDR dùng chung ở
[`src/training/config.py`](../../../../src/training/config.py); iDCF/IViDR ở
[`src/causal/idcf/train_idcf.py`](../../../../src/causal/idcf/train_idcf.py).
Xem [giao thức](../../../benchmarks/evaluation_protocol.md) và [review, trạng thái sửa R1–R7](review_2026-10-19.md).

**Cập nhật theo yêu cầu dùng mô hình đúng bài báo:** MF/iDCF dùng khởi tạo uniform,
CDR huấn luyện từ đầu với backbone không bias; đã bỏ MF-MSE warm-start khỏi benchmark,
tuning và seed workflow. IViDR-approx bị loại khỏi bộ mặc định vì chưa đúng các MLP
và loss BCE của paper. [Đối chiếu chi tiết](../../../benchmarks/paper_model_alignment.md).
Các số warm-start/ablation bên dưới là lịch sử, không dùng để đánh giá CDR nguyên bản.

Kiểm chứng cấu hình mới: 97 test, 96 đạt và một CUDA test bỏ qua; smoke MF/iDCF/CDR
trên Coat và KuaiRand 64 user đều chạy thành công. CDR Coat huấn luyện từ đầu với
cấu hình cố định, ba seed 42/43/44 chọn epoch 6/7/17, Val NDCG@5 lần lượt
.425608/.417528/.453052; loss hữu hạn. Đây là kiểm tra vận hành của cấu hình chưa
tuning, không phải tái lập số paper và chưa chấm held-out test cho ba lượt này.
[Artifact có cấu hình, source hash và lịch sử training](../../../../results/cdr_paper_method_validation_37b126f2c13fcea9.json).

## MF

Benchmark và tuning dùng Adam + MSE trên điểm thô, decay mọi tham số, không scheduler,
global intercept cố định 0. Coat: dim 64, LR 5e-4, wd 1e-6, batch 512;
KuaiRand: dim 64, LR 5e-5, wd 1e-6, batch 2048. Trần 100 epoch, patience 5.
Khởi tạo mặc định Uniform(-0.01,0.01) cho cả embedding và bias theo mã tác giả iDCF.
`--init-scheme normal` chỉ dùng cho ablation; metadata phân biệt hai lựa chọn.

Kết quả **lịch sử**, không phải lượt chạy lại sau sửa 19/10:

| Thí nghiệm | NDCG@5 | Artifact |
| :-- | --: | :-- |
| Coat MF-MSE, 10 seed | 0.5402 ± 0.0118 | `coat_seeds_c25da453e8909e5b` |
| KuaiRand MF-MSE, seed 42 | 0.3744 | `benchmark_kuairand_all_32e6ded9ad_v4` |

Các lượt BCE cũ cho điểm thấp hơn; không quy toàn bộ chênh lệch cho optimizer.
MSE không có gradient bị chặn theo định nghĩa; giải thích điều chuẩn ngầm trước đây
chỉ là giả thuyết.

## iDCF và IViDR

Pipeline hiện tại có hai giai đoạn: iVAE trên exposure và proxy user, sau đó MF cộng
thành phần latent với MSE. iVAE chọn checkpoint bằng MC ELBO với nhiều mẫu, cùng bộ nhiễu
validation mỗi epoch và RNG riêng. Cả hai giai đoạn hỗ trợ CPU/CUDA; cấu hình thực thi
được ghi trong artifact.

IViDR thêm nhánh treatment từ MF và hồi quy theo biến công cụ; đây vẫn là biến thể
địa phương có giả định về T, Z và cách ghép hai posterior. Chưa khẳng định tái lập nguyên bản IViDR.

Coat có artifact `coat_seeds_7d37e1975c96a410`: iDCF 0.5704 ± 0.0124,
IViDR-staged 0.5712 ± 0.0129. **IViDR trong artifact này dùng alpha_residual=1**,
nên fitted + residual trả về treatment gốc. Source hiện tại dùng alpha_residual=0;
không gán lại số cũ cho bản đã sửa. Cần lượt chạy mới nhiều seed cho cả hai mô hình
sau thay đổi cách chọn checkpoint iVAE ngày 19/10.

IViDR joint 0.3630 trên KuaiRand trong artifact cũ thuộc kiến trúc đã gỡ.
Chưa có số chất lượng đầy đủ của bản staged hiện hành trên KuaiRand.

## DR-BIAS + CDR

### Ablation Eq. (7) với warm-start — trước khi bỏ mô hình ghép

Mặc định đã chuyển sang `ips_weighting=paper`, `filter_mode=cv`, eta=0.1,
MC dropout 10 mẫu và objective revision `cdr_eq7_bce_v1`.
Các test quần thể nhỏ kiểm tra imputation hoàn hảo, propensity đúng theo kỳ vọng,
tương đương full/complement pool, bất biến theo tỷ lệ batch và luồng gradient.
Suite hiện có 90 test: 89 đạt, một test CUDA bỏ qua trên môi trường CPU.

Thử nghiệm validation sau sửa, cấu hình cố định (Coat dim 32, LR 0.005, CV eta 0.1,
trần 25 epoch, patience 7), không chấm test:

| Seed | MF warm-start Val NDCG@5 | CDR được chọn | Best epoch | Filter observed / direct |
| --: | --: | --: | --: | :-- |
| 42 | 0.616085 | 0.616085 | 0 | 39.73% / 40.73% |
| 43 | 0.601381 | 0.601381 | 0 | 36.87% / 37.59% |
| 44 | 0.605417 | 0.605417 | 0 | 38.79% / 39.66% |

Loss đều hữu hạn, mỗi lượt dừng sau 7 epoch cập nhật; cả ba vẫn chọn MF epoch 0.
Điều này xác nhận sửa bộ lọc đã có tác dụng, **chưa xác nhận fine-tune CDR cải thiện
chất lượng ranking**. Tỷ lệ lọc là tỷ lệ loại imputation, không phải tỷ lệ poisonous
imputation được xác định bằng ground truth.
Artifact: [`cdr_eq7_validation_6346597634257fd0.json`](../../../../results/cdr_eq7_validation_6346597634257fd0.json).

Môi trường `venv` trong workspace bị Windows Application Control chặn DLL NumPy.
Đã chạy kiểm chứng bằng Python 3.12 ở môi trường thử nghiệm riêng, dùng NumPy 2.5.2,
PyTorch 2.14.1+cpu và pandas 3.0.6. Không dùng số test ngày trước thay cho bản mới.

Trainer chuẩn hóa theo số cặp observed duy nhất, gộp nhãn train lặp bằng mean
(BCE kỳ vọng thực nghiệm của cặp), còn ranking validation/test vẫn giữ any-positive.
Hai bước dùng cùng định nghĩa BCE(logits rec, xác suất nhãn giả), dừng gradient ở
phía không được cập nhật. Metadata/checkpoint ghi objective revision, policy dữ liệu,
ESS propensity, lựa chọn epoch 0 và tỷ lệ filter observed/direct.

Các bất nhất ở mục 3–5 bên dưới mô tả **bản trước sửa**, được giữ làm bằng chứng
điều tra. Đúng estimator không bảo đảm tăng NDCG; cần xem thử nghiệm validation mới
và benchmark nhiều seed trên test khóa trước khi kết luận mô hình tốt hơn.

Đối chiếu sâu ngày 19/10/2026 với [bản chép paper](../../../paper_summaries/CDR.md),
[PDF gốc](https://jiawei-chen.github.io/paper/CIKM23-CDR.pdf), mã tác giả và source trước sửa.
Các sửa R1–R7 là sửa pipeline; không đồng nghĩa đã kiểm chứng loss đúng Eq. (7).
Kết luận trước đây rằng CDR thấp chỉ do giao thức/BCE và không do cài đặt là quá mạnh.

### 1. Cùng một checkpoint: 0.6685 xuống 0.4832 chỉ khi đổi cách chấm

Tái chạy port mã Coat của tác giả với seed 2020, dim 4, LR 0.05, wd 1e-3,
batch 128, G=4; dừng theo train loss ở epoch 27. Giữ nguyên trọng số rồi chấm:

| Nhãn / user / metric | NDCG@5 | Recall@5 |
| :-- | --: | --: |
| Rating ≥3, toàn 290 user, user không dương tính 1, bounded Recall | 0.668550 | 0.676494 |
| Rating ≥3, toàn bộ user có dương, Recall chia tổng positive | 0.657934 | 0.486103 |
| Rating ≥4, toàn bộ user có dương, Recall chia tổng positive | 0.495449 | 0.519721 |
| Rating ≥4, 203 user test của dự án, loại user không dương | 0.483192 | 0.505899 |

Đây là **rescore một mô hình cố định**, không phải bốn lượt tối ưu độc lập. Checkpoint
được train bằng nhãn ≥3 và dùng 5% nhãn random test cho propensity theo script tác giả;
thử nghiệm chỉ đối chiếu giao thức, không phải đánh giá trên test chưa đụng tới.
Trong chuỗi rescore này, bỏ quy ước empty=1 đổi NDCG −0.010616; đổi nhãn ≥3 sang ≥4
đổi −0.162485; chuyển tập user test đổi −0.012257. Đây là phân rã có điều kiện theo
thứ tự trên, không phải mức đóng góp độc lập của từng yếu tố cho mọi mô hình.

Trên Coat, ≥3 làm tỷ lệ dương random log thành 40.13%, ≥4 chỉ còn 18.53%.
Random expected NDCG theo mã tác giả là 0.460389, theo test dự án là 0.298575.
Không thể lấy khoảng cách giữa 0.65 và 0.50 làm bằng chứng riêng cho chất lượng thuật toán.

### 2. Paper, mã công bố và benchmark là ba đối tượng khác nhau

| Thành phần | Paper | Mã công bố Coat | Benchmark dự án hiện tại |
| :-- | :-- | :-- | :-- |
| Nhãn | §4.1 nói rating >3 | `binarize(thres=3)` dùng ≥3 | ≥4 |
| Validation/test | 10/90 random data | Chấm toàn random log; dừng theo train loss | 30/70 theo user, chọn bằng validation |
| Propensity | Cần phân biệt quy trình ước lượng khi tái lập | Naive Bayes từ 5% nhãn test | File Coat, inverse clip 20 |
| Bộ lọc | §3.1: std/mean < eta | variance < un_thres | variance <10 trên Coat |
| Hệ số trừ imputation trên observed, khi direct lấy toàn D | Eq. (7): inverse propensity | 1 | 1 ở `ips_weighting=author` |

Nguồn hành vi mã công bố:
[`utils.py`](https://github.com/CrazyDumpling/CDR_CIKM2023/blob/main/CDR/utils.py),
[`mf_cdr_bias_coat.py`](https://github.com/CrazyDumpling/CDR_CIKM2023/blob/main/CDR/mf_cdr_bias_coat.py),
[`MF_mcdropout.py`](https://github.com/CrazyDumpling/CDR_CIKM2023/blob/main/CDR/MF_mcdropout.py).
Port đạt 0.6660 ± 0.0060 trong artifact cũ và 0.66855 ở lượt kiểm chứng mới cho thấy
có thể tái tạo mức điểm của **script công bố**. Chưa chứng minh đã tái lập đúng giao thức
paper mô tả hoặc đúng mọi điều kiện tạo Table 2.

### 3. Loss trước sửa không phải Eq. (7) khi direct pool là toàn D

Khai triển Eq. (7), với gamma là cờ giữ imputation, cho mục tiêu:

```text
L_paper = [sum_O w * (e - gamma*h) + sum_D gamma*h] / |D|,
w = 1 / propensity, h = imputed error.
```

Phiên bản trước sửa của [`dr_bias_loss.py`](../../../../src/causal/cdr/dr_bias_loss.py) trừ `gamma*h` khi
`ips_weighting=author`; nhánh `dr` trừ `(w-1)*gamma*h`. Với direct pool toàn D, cả hai
đều khác hệ số `w` của Eq. (7). Hệ số `w-1` chỉ phù hợp cách tách observed/unobserved
khi direct sum chỉ trên D\O và chuẩn hóa đúng; không áp dụng nguyên xi cho toàn D.

Probe số học: D có 4 cặp, O có 2 cặp, e_D=[0.2,0.8,0.3,0.7], w_O=[2,4],
imputation hoàn hảo h=e và giữ mọi cặp. Eq. (7) trả đúng mean(e_D)=0.5;
nhánh author hiện tại trả 1.15, nhánh dr với direct pool toàn D trả 0.75.
Probe chứng minh khác mục tiêu, **chưa định lượng phần giảm NDCG do sai khác này**.

Mini-batch cũng cần chuẩn hóa đúng. Với B observed lấy đều từ O, M cặp lấy đều từ D:

```text
L_hat = (|O| / |D|) * mean_B[w*(e-gamma*h)] + mean_M[gamma*h].
```

Coat có |O|/|D|=6960/87000=0.08. Code mặc định dùng M=4B rồi chia chung cho M,
cho hệ số observed 0.25 thay vì 0.08: chênh tương đối 3.125 lần.
`population_counterfactual_weight=True` có thể sửa tỷ lệ direct/observed tới một hằng
số nhân chung, nhưng không sửa được hệ số trừ imputation sai; hằng số còn tác động
độ mạnh regularization. Không chỉ đổi một flag rồi coi loss đã đúng paper.

### 4. Bộ lọc cũ không hoạt động trong lượt kiểm chứng

Chạy cấu hình Coat trước sửa, seed 42, warm-start MF-MSE dim 32, CDR LR 0.002,
trần 100 epoch/patience 7: cả 385 batch đều có `filtered_ratio=0`.
Best validation=0.616085 tại **epoch 0**; model được trả về là warm-start MF,
test NDCG=0.522627, Recall=0.505512. Đây là một seed, không thay báo cáo nhiều seed.

Với score s, BCE(sigmoid(s), m)=softplus(s)-m*s, nên phương sai MC error bằng
s² Var(m). Khi score MSE warm-start còn nhỏ, variance error nhỏ; ngưỡng variance 10
có thể giữ toàn bộ imputation dù nhãn giả chưa đáng tin. Cờ giữ tất cả làm bộ lọc
CDR không đóng góp trong lượt này; chưa chứng minh mọi imputation được giữ đều độc hại.

Ngoài ra, bước rec dùng h=BCE(p,q), còn bước imp tối ưu BCE(q,p) ở
[`cdr_model.py`](../../../../src/causal/cdr/cdr_model.py). Hai hàm không đối xứng, ví dụ
p=0.8,q=0.6 cho 0.777661 và 0.591919. Với p=0.8,y=1, e=0.223144 nhưng
min_q BCE(q,p)=H(p)=0.500402: mục tiêu error này không thể khớp chính xác.
Đảo chiều BCE cũng có trong mã công bố; đây là bất nhất cần kiểm tra khi dựng bản
theo công thức, không phải bằng chứng riêng rằng port địa phương sai với script.

### 5. Cấu hình và phạm vi kết luận

Paper §2.1 cho phép cả squared error và BCE; **CDR không bắt buộc là khung BCE**.
Hai triển khai đang dùng BCE không chứng minh mọi biến thể CDR đều chịu cùng hạn chế.
Nếu thử squared error, cần suy ra đồng bộ loss rec, imputation, uncertainty và estimator.

Grid LR paper {0.005,0.01,0.05,0.1}, trong khi mặc định Coat trước sửa là 0.002 và grid
tuning 0.001/0.002. Còn khác backbone có bias, khởi tạo, dropout có/không co giãn,
warm-start và lịch cập nhật rec/imp. Đây là các biến cần ablation sau khi chốt estimator;
chưa có bằng chứng tách riêng mức tác động mỗi biến. Clip inverse 20 chạm 11.82% mẫu
observed; DR-BIAS khuếch đại trọng số imputation tới 7220 ở w=20, cần theo dõi gradient.

Coat trong Table 2 là DR-BIAS+CDR NDCG=0.6567; KuaiRand cùng biến thể là 0.3098,
không phải 0.6567. Số KuaiRand dự án cũ 0.3459 không thấp hơn 0.3098 về mặt số học,
nhưng vẫn không so trực tiếp được do dữ liệu/giao thức khác.

Thứ tự xử lý tiếp: tách tên bản theo script và bản theo Eq. (7); kiểm thử estimator
trên quần thể nhỏ với imputation hoàn hảo/propensity đúng; thống nhất BCE của hai bước;
ghi tỷ lệ filter và tune CV/eta bằng validation; sau đó mới chạy nhiều seed với test khóa.
Đợt điều tra 19/10 chưa thay đổi thuật toán; trạng thái triển khai ngày 20/10 ở đầu mục CDR.

Toàn bộ số đo mới và hash source/data:
[`cdr_audit_2026-10-19_evidence.json`](../../../benchmarks/cdr_audit_2026-10-19_evidence.json).

## Việc tiếp theo

1. Chạy lại Coat nhiều seed, khóa config trước khi chấm test.
2. Chạy iDCF rồi IViDR staged trên toàn KuaiRand; smoke chỉ xác minh vận hành.
3. Ablation alpha_residual và cách ghép latent, so với iDCF cùng ngân sách/tham số.
4. Thêm đánh giá theo thời gian trên TopTop để kiểm tra mô hình phục vụ ứng dụng.

Các artifact lịch sử được giữ nguyên ở [results](../../../../results/README.md).
Tham chiếu bên ngoài nằm ở [bảng paper](paper_reference_comparison.md).
