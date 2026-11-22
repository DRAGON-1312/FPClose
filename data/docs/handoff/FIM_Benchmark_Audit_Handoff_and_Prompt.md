# FIM / FPClose — Benchmark Dataset Audit Handoff

> **Mục đích:** Tài liệu bàn giao đầy đủ để một AI agent độc lập kiểm toán lại chất lượng bộ benchmark, đối chiếu yêu cầu trong PDF/GitHub, xác định phần đã làm, phần còn thiếu và rủi ro. Có **prompt tiếng Anh** ở cuối nhưng **agent phải báo cáo hoàn toàn bằng tiếng Việt**.
>
> **Mốc tổng hợp:** 22/11/2026. **Phạm vi:** chuẩn bị 9 transaction databases, 5 Retail subsets, 6 synthetic datasets, minsup pilot bằng **SPMF FPClose**, manifest/checksum, công bố Hugging Face. **Không đánh đồng** với benchmark chính thức trên implementation tự viết của nhóm.
>
> **Chính sách tiết kiệm quota:** Đọc metadata, README, MANIFEST và các CSV nhỏ trước. Chỉ đọc những cell Notebook có liên quan. Không tự tải hoặc khai phá lại 9 tập dữ liệu lớn nếu chưa phát hiện vấn đề cụ thể. Mọi phát hiện phải được phân loại thành **đã có bằng chứng / chưa kiểm chứng / lỗi xác nhận**.

## 0. Tóm tắt cho agent — đọc phần này trước

- **Đã chuẩn bị:** 9/9 normalized SPMF datasets, 56/56 mức minsup đã chọn `PASS` qua SPMF FPClose, 3 ngưỡng `TIMEOUT` được giữ làm lịch sử, 5 nested Retail subsets, 6 synthetic datasets, README/MANIFEST và SHA-256.
- **Đã công bố:** [Hugging Face public dataset — hytrang/fpclose-fim-benchmarks](https://huggingface.co/datasets/hytrang/fpclose-fim-benchmarks); lần kiểm tra bằng `huggingface_hub` với `token=False` đã liệt kê đủ 9 `.txt`, `README.md`, `MANIFEST.md`; tải lại 9/9 file và so SHA-256 với Drive đều `PASS` (theo log người thực hiện).
- **Đã kiểm tra trên Drive:** 9/9 file tồn tại, số giao dịch khớp; 9/9 normalized SHA-256 khớp `MANIFEST.md`; README dự án và các CSV bàn giao có mặt.
- **Chưa thể kết luận:** correctness của thuật toán **nhóm tự cài đặt** so với SPMF; runtime/memory chính thức, scalability và transaction-length measurements, all frequent itemsets reconstruction, hoặc benchmark evaluation/report cuối cùng.
- **Những điểm phải rà soát:** 5 dataset ban đầu có `Item-ID offset: unknown_original_not_logged`; `MANIFEST.md` vẫn ghi public URL là `TODO`; README Drive còn vài câu mang tính checklist trước công bố; script/notebook và `results/benchmark.csv` đã commit lên GitHub nhóm hay chưa **chưa được xác minh**; quyền chia sẻ các file Drive không được mặc định là public.
- **Nguyên tắc:** `.txt` là transaction database; `benchmark_config.csv` là **cấu hình và số itemsets tham chiếu**, không phải database, cũng không phải kết quả benchmark chính thức.

## 1. Nguồn và liên kết xác thực

### 1.1. Notebook Google Colab — đã tìm đúng ID trong Drive

| Tài nguyên | Link thực tế | Phạm vi cần kiểm toán |
|---|---|---|
| **01_Data_Preparation.ipynb** | [Mở Notebook 01 trên Colab](https://colab.research.google.com/drive/17kcDkgBy61yCCT83Lg_7dFDMwwBZRBKt) | Tải và chuẩn hóa 5+4 nguồn, raw/normalized SHA, stats, MANIFEST, Retail subsets, synthetic datasets. **Đọc code ở các cell liên quan, không `Run all`.** |
| **02_Benchmark_FPClose.ipynb** | [Mở Notebook 02 trên Colab](https://colab.research.google.com/drive/1zXK8l9ORBa3aN6MOAx_VCWZvc3zXuz39) | Cài Java 25 và SPMF, smoke tests, minsup pilot, CSV tổng hợp, integrity checks, README, Hugging Face hash validation. **Không `Run all`.** |
| Thư mục chứa Notebook | [Colab Notebooks — Drive](https://drive.google.com/drive/folders/1Qe7ti6uqcX6qvRogGcegd-61w2su_1p4) | Mở hai file trên nếu cần xem metadata/outputs. |

**Các cell trọng tâm trong Notebook 01** (đếm từ 0 theo file `.ipynb`; nhãn hiển thị trên Colab có thể khác):

- Đầu Notebook: tải 5 benchmark đầu tiên từ SPMF, `normalize_spmf`, thống kê/SHA và MANIFEST sơ bộ.
- Giai đoạn mở rộng: thêm `connect`, `kosarak`, `pumsb_star`, `T40I10D100K` và MANIFEST đủ 9 tập.
- **Cell code index 30:** khôi phục đường dẫn Drive; có thể dùng `/content/fim_drive_new` nếu `/content/drive` bị xung đột.
- **Cell code index 31:** sinh Retail subsets lồng nhau với `random.Random(2026).shuffle(indices)`, lấy các prefix 10/25/50/75/100%, ghi file LF.
- **Cell code index 32:** sinh 6 tập synthetic, seed 2026; 10.000 transactions, 500 item, mean lengths 5/10/15/20/25/30; 200 mẫu đồng xuất hiện, dùng chung master transactions và kiểm tra tính lồng nhau.

**Các cell trọng tâm trong Notebook 02:**

- **Code index 0–4:** mount Drive, cài Java 25/SPMF, Chess smoke test, all-dataset smoke test.
- **Code index 5–27:** chọn minsup, `run_minsup_pilot`, `run_kosarak_safe`, `run_full_pilot` và các thí nghiệm pilot; có cả những cell cũ bị ghi đè CSV ở giai đoạn thử nghiệm; nên xem **CSV cuối** làm nguồn trạng thái.
- **Code index 28:** sửa schema của Retail pilot CSV bằng cách bổ sung `n_transactions`.
- **Code index 29:** tạo `benchmark_config.csv`, `minsup_pilot_all.csv`, `pilot_grid_summary.csv`.
- **Code index 30–31:** tạo `benchmark_inventory.csv`, đối chiếu normalized hashes với MANIFEST.
- **Code index 33–34:** tạo README dự án, kiểm tra file bàn giao và context của hash với tên dataset.
- **Code index 35:** tải lại từ HF theo `token=False` và so SHA-256 với `benchmark_inventory.csv`.

**Chú ý:** Đừng đánh giá Notebook qua sự hiện diện của các cell thử nghiệm thất bại/backup riêng lẻ. Nguồn đầu ra chuẩn là CSV tổng hợp cuối cùng; các cell cũ thể hiện lịch sử phát triển. Chỉ sửa/xóa cell khi chủ sở hữu yêu cầu.

### 1.2. Google Drive: đường dẫn thật (không suy đoán)

| Loại | Link |
|---|---|
| Project root `FIM_Project` | [Drive — FIM_Project](https://drive.google.com/drive/folders/1clzRNAL5cHWU5D1GEqFOk18k18_1GD99) |
| `data/` | [Drive — data](https://drive.google.com/drive/folders/1ccebh4PlUxNSkxoITmx6vr0Sskw9eGdv) |
| `data/benchmark/` (9 `.txt` + MANIFEST) | [Drive — benchmark](https://drive.google.com/drive/folders/1rEl-ywPlDaPKb6Yxeu4OrkZRjXaTydnN) |
| `data/raw/` (nguồn đầu vào) | [Drive — raw](https://drive.google.com/drive/folders/1MxjXOOpgR4jnm76xfdJHR6B-5D4dQWvX) |
| `data/scalability/` | [Drive — scalability](https://drive.google.com/drive/folders/1e54__DYqVAXkun2uqpNZz4e-myY-P5G_) |
| `data/synthetic/` | [Drive — synthetic](https://drive.google.com/drive/folders/16O9mQCw2w_-IV0f-ItKi1HSncK6uwMBh) |
| `results/` | [Drive — results](https://drive.google.com/drive/folders/1xbUTCmeFP-Ps_qMt014s5gYdfdoq8oSd) |
| `data/benchmark/MANIFEST.md` | [Mở MANIFEST](https://docs.google.com/document/d/1FvI180i-lSv8IZikNRDDnt3rFLDjwl9q/edit) |
| `FIM_Project/README.md` | [Mở Project README](https://docs.google.com/document/d/1bwMDX4PGKU7kdW8p6N_ni_oXGgIcCXO4/edit) |
| `results/dataset_statistics.csv` | [Drive — dataset_statistics.csv](https://drive.google.com/file/d/1tUasiaEPBTEVIoOI-zO7MdvxYguM9XLn/view) |
| `results/benchmark_inventory.csv` | [Drive — benchmark_inventory.csv](https://drive.google.com/file/d/1BoEX6fbQUUEtpiaXaKHJ30ht5P7ixRrI/view) |
| `results/benchmark_config.csv` | [Drive — benchmark_config.csv](https://drive.google.com/file/d/1qPQYBrh6Q33EOFLvqWTiSAj-ty4agPqp/view) |
| `results/minsup_pilot_all.csv` | [Drive — minsup_pilot_all.csv](https://drive.google.com/file/d/1_lKLMa4myt26AUKW_5hZPkPLXEkvdJT-/view) |
| `results/pilot_grid_summary.csv` | [Drive — pilot_grid_summary.csv](https://drive.google.com/file/d/1Q3lM-5wbQsYFVHh2OluFm96nk3Y7JDpn/view) |
| `results/spmf_initial_tests.csv` | [Drive — spmf_initial_tests.csv](https://drive.google.com/file/d/1q2qRoQoIZAk4_Mq4qGRkJKu5sxA9AjJa/view) |

**Đường dẫn Colab cũ:** `/content/drive/MyDrive/FIM_Project`; mount lại Google Drive trong phiên mới. Một lần Notebook 01 dùng `/content/fim_drive_new/MyDrive/FIM_Project` để tránh mount conflict. Đừng copy cứng đường dẫn mount khi đọc từ tài khoản khác: trên HF, chỉ cần file public; trên Drive, cần quyền xem được cấp.

### 1.3. Nguồn yêu cầu / phát hành

- **PDF/kế hoạch nhóm:** [Chương 2 hướng dẫn chuẩn bị dữ liệu benchmark — bản Google Docs](https://docs.google.com/document/d/1DkrBgkxiICy8tQtIXsSILGN3wARmyBVRj9oCfU7g4A8/edit), ngày 20/11/2026; có hướng dẫn 9 dataset, dữ liệu dẫn xuất, pilot, lưu trữ và `results/benchmark.csv`.
- **Đề bài môn học:** [HCMUS — Frequent Itemset Mining project](https://hcmus-cs-ta.github.io/lab-book/data-mining/projects/itemset/). Đề ít nhất 4 benchmark, kiểm tra correctness và đánh giá runtime/output/memory/scalability/transaction length.
- **Bản dữ liệu công khai:** [Hugging Face — hytrang/fpclose-fim-benchmarks](https://huggingface.co/datasets/hytrang/fpclose-fim-benchmarks). Có `.gitattributes`, `README.md`, `MANIFEST.md` và 9 file `.txt` ở thư mục gốc theo lần liệt kê công khai.
- **GitHub repository mã nguồn nhóm:** chưa có URL được xác thực trong phạm vi bàn giao này. **Không tự suy đoán repository**, phải xin URL hoặc tìm qua link chính thức nhóm cung cấp trước khi nhận xét commit/PR.

## 2. Kiến trúc bàn giao và ý nghĩa file

```text
FIM_Project/
├── README.md                          # README dự án (khác Dataset Card trên Hugging Face)
├── data/
│   ├── raw/                           # Bản gốc; không dùng trực tiếp cho benchmark so sánh
│   ├── benchmark/
│   │   ├── MANIFEST.md                # Provenance, preprocessing, stats, raw/clean SHA-256
│   │   ├── chess.txt
│   │   ├── mushrooms.txt
│   │   ├── retail.txt
│   │   ├── T10I4D100K.txt
│   │   ├── accidents.txt
│   │   ├── connect.txt
│   │   ├── kosarak.txt
│   │   ├── pumsb_star.txt
│   │   └── T40I10D100K.txt
│   ├── scalability/
│   │   ├── retail_p010.txt ... retail_p100.txt
│   └── synthetic/
│       ├── len05.txt ... len30.txt
│       └── synthetic_statistics.csv
└── results/
    ├── dataset_statistics.csv
    ├── spmf_initial_tests.csv
    ├── benchmark_inventory.csv
    ├── benchmark_config.csv           # 56 lựa chọn minsup + số CLOSED itemsets SPMF
    ├── pilot_grid_summary.csv
    ├── minsup_pilot_all.csv           # 59 thử nghiệm: 56 PASS + 3 TIMEOUT
    ├── minsup_pilot_<dataset>.csv     # 9 lịch sử riêng
    └── ...backup/intermediate files
```

**File chưa thấy qua lần liệt kê thư mục results:** `results/benchmark.csv` (file benchmark so sánh cuối cùng theo mẫu PDF); điều này **không đồng nghĩa dataset chuẩn hóa bị thiếu**. Script `gen_synthetic.jl`, `dataset_stats.jl` theo tên dự kiến trong PDF **không được xác nhận đã tồn tại/commit**; hiện logic sinh/kiểm tra đã hiện diện trong Notebook Python. Phải phân biệt “có notebook tái tạo được” và “đã có standalone Julia scripts đúng tên”.

## 3. Chuẩn hóa dữ liệu đã thực hiện

### 3.1. Nguồn và quy tắc

- 5 dataset đầu: `chess`, `mushrooms`, `retail`, `T10I4D100K`, `accidents` lấy từ nguồn SPMF (file `.txt`).
- 4 dataset bổ sung: `connect` từ SPMF; `kosarak.dat.gz`, `pumsb_star.dat.gz`, `T40I10D100K.dat` từ FIMI Repository.
- Bản raw giữ riêng; bản sạch thống nhất **UTF-8**, xuống dòng **LF**, một transaction mỗi dòng, item ID là số nguyên dương, **unique và sorted ascending**, ngăn bằng đúng một dấu cách; loại metadata `#/@/%`, blank/invalid transaction rows theo quy tắc Notebook; trường hợp ID có 0 thì offset +1 theo phép biến đổi một-một.
- Các phép thử phải dùng `data/benchmark/*.txt` **giống hệt nhau cho cả SPMF và implementation nhóm**, không dùng lại bản raw `.dat` hay tự chuẩn hóa khác đi.

### 3.2. Thống kê thực đo và normalized SHA-256

| Dataset | Transactions | Unique items | Avg len | Max len | Density (%) | SHA-256 normalized |
|---|---:|---:|---:|---:|---:|---|
| chess | 3,196 | 75 | 37.0000 | 37 | 49.333333 | `341d0ff8676e053dd3b417d61f84c732736154f987ce56975a099b07460957f5` |
| mushrooms | 8,416 | 119 | 23.0000 | 23 | 19.327731 | `37a11571574d74bd1659c830a1e30e120485c6994b79f32e3b6635621a229bf7` |
| retail | 88,162 | 16,470 | 10.3058 | 76 | 0.062573 | `417563fb5feb3711d4f761230ca78b76d100fe2ee0d3178fcc4fbb000d8d1c36` |
| T10I4D100K | 100,000 | 870 | 10.1023 | 29 | 1.161182 | `fb2dd118ff822ff88d724e47d5a4cea6531c0bd6294397db4d36890c1450f1a7` |
| accidents | 340,183 | 468 | 33.8079 | 51 | 7.223908 | `c2b3762e3f8f0ca241c35359b24e3015fd34ea241d09f94b42ae44ed42914726` |
| connect | 67,557 | 129 | 43.0000 | 43 | 33.333333 | `650a92d7803c465fb08fc0e58de087ceab84cd5f0de4c6816b523774dcd6a2c9` |
| kosarak | 990,002 | 41,270 | 8.1000 | 2,497 | 0.019627 | `cb4270629d786207143bb3c4002c36aedc3824f55294c7b3d5538c8023cec314` |
| pumsb_star | 49,046 | 2,088 | 50.4821 | 63 | 2.417727 | `a9ecd5c882ffff9e0042703253d0eef3453f747537e0027c9be275a8aaf38f2f` |
| T40I10D100K | 100,000 | 942 | 39.6051 | 77 | 4.204360 | `e3d86e8cf6eec0093528e238ab8a4ba10471375c00a9298144edb462caadb28c` |

Các số liệu trên được đối chiếu từ `dataset_statistics.csv` / `MANIFEST.md`; **không phải suy đoán từ tên dataset**. Có sự khác biệt giữa phiên bản nguồn, ví dụ Mushrooms 8.416 trong bản SPMF đang dùng thay vì 8.124 của một số tài liệu khác. Kosarak max len đã đo là 2.497, không lấy số xấp xỉ trong kế hoạch.

**Vấn đề provenance cần audit:** 5 dataset ban đầu ghi `Item-ID offset: unknown_original_not_logged`; không nên đổi thành `0` nếu chưa so sánh raw/clean. Bản raw và raw SHA được ghi trong MANIFEST nên có thể xác minh phép dịch ID nếu thực sự cần; xem xét tính tái lập quy tắc chuẩn hóa.

## 4. Dữ liệu dẫn xuất đã tạo

### 4.1. Retail subsets (scalability)

- Source: normalized `retail.txt`, **88.162** transactions.
- Seed: **2026**; tạo một permutation của chỉ số transaction, lấy các prefix lồng nhau; không lấy trực tiếp đầu file gốc theo thứ tự Retail.
- Đã xuất: `retail_p010.txt` (8.816), `retail_p025.txt` (22.040), `retail_p050.txt` (44.081), `retail_p075.txt` (66.121), `retail_p100.txt` (88.162).
- Quan hệ lồng nhau được **assert trên index**, không phải chỉ kiểm tra số dòng. Mỗi subset giữ nguyên nội dung từng transaction đã chuẩn hóa. SHA-256 từng subset đã in trong output Notebook; chưa xác nhận có một manifest riêng để công bố toàn bộ các hash này.
- **Chưa chạy** phép đo `runtime vs subset size` của implementation nhóm trong giai đoạn chuẩn bị.

### 4.2. Synthetic (transaction-length)

- `len05.txt`, `len10.txt`, `len15.txt`, `len20.txt`, `len25.txt`, `len30.txt`.
- Mỗi file: **10.000 transactions, 500 unique item IDs**, trung bình độ dài chính xác lần lượt 5/10/15/20/25/30; seed 2026.
- Generator ở Notebook 01 cell code index 32 tạo 200 mẫu itemset dài 4 với trọng số thiên lệch; master transaction 32 item rồi lấy prefix tương ứng; dùng chung master transactions cho thí nghiệm biến độ dài.
- Trong code có assertions về unique/sorted, trung bình, phủ đủ 500 item và quan hệ lồng nhau giữa các phiên bản theo transaction; thống kê + hash nằm trong `data/synthetic/synthetic_statistics.csv`.
- Đây là **synthetic có cấu trúc đồng xuất hiện**, không phải dữ liệu ngoài đời. Kết quả hiệu năng phải được diễn giải dưới giả định generator này.
- **Chưa chạy** phần đo thuật toán nhóm trên sáu dataset và ghi/đánh giá đồ thị.

## 5. SPMF smoke test và MinSup pilot — hiện trạng chính xác

- SPMF chạy trên Colab bằng Java 25 vì một bản `spmf.jar` mới không tương thích Java 21; code gọi `str(JAVA25)` trong subprocess.
- Smoke tests tại mức minsup cao đã được thực hiện trên 9 dataset bằng **SPMF**; log ở `results/spmf_initial_tests.csv`. Việc cả thuật toán nhóm đọc được file và khớp kết quả **chưa có bằng chứng trong gói dữ liệu này**.
- Pilot: **56 cấu hình được chọn PASS**, **3 cấu hình TIMEOUT** trong lịch sử, tổng **59 bản ghi** (`results/minsup_pilot_all.csv`). `benchmark_config.csv` chỉ chứa 56 mức được chọn PASS.
- Pilot kiểm tra file output SPMF có các dòng `#SUP:`, support nằm trong ngưỡng, đếm số frequent **closed** itemsets. Đây là kiểm tra format/đủ điều kiện tối thiểu, **không tự chứng minh mọi itemset đều đúng hoặc closed**, không kiểm tra full equality với bản nhóm.
- Thời gian pilot là một phép đo đơn lẻ/cấu hình, có khởi động JVM và biến động Colab; **không phải official runtime benchmark**. `output_mb` là kích thước file kết quả, **không phải peak RAM**. Output tạm được xóa sau khi xử lý; không còn toàn bộ danh sách itemsets tham chiếu ở mỗi minsup.
- Timeout 300 giây ở giai đoạn pilot; PDF kế hoạch có hướng dẫn dừng ở 10 phút nhưng trong các thử nghiệm Colab đã chọn ngưỡng **5 phút**. Nếu đánh giá tuân thủ tuyệt đối phải ghi rõ sự khác biệt này, không đánh tráo thành 10 phút.
- Một số hàm chỉ kiểm tra kích thước output **sau khi SPMF kết thúc**, không khống chế file size/RAM ngay lúc chạy. Không nên mô tả là có hard quota về disk hoặc RAM.

| Dataset | Các minsup (%) **đã chọn** | PASS | Max reference closed count trong lưới |
|---|---|---:|---:|
| chess | 90, 85, 80, 75, 70, 65, 60 | 7 | 98,392 |
| mushrooms | 20, 15, 10, 7, 5, 3, 2 | 7 | 31,416 |
| retail | 1, 0.5, 0.2, 0.1, 0.05, 0.02 | 6 | 65,301 |
| T10I4D100K | 1, 0.5, 0.2, 0.1, 0.05, 0.02 | 6 | 107,822 |
| accidents | 90, 80, 70, 60, 50, 40 | 6 | 32,528 |
| connect | 95, 90, 85, 80, 75, 70 | 6 | 35,875 |
| kosarak | 1, 0.5, 0.4, 0.3, 0.25, 0.2 | 6 | 35,864 |
| pumsb_star | 70, 60, 50, 45, 40, 35 | 6 | 6,129 |
| T40I10D100K | 5, 3, 2, 1.5, 1.25, 1 | 6 | 65,236 |

**TIMEOUT có chủ đích giữ trong lịch sử, không đưa vào lưới chính thức:** Kosarak 0,15% và 0,1% (mỗi mức >300 giây); T40I10D100K 0,5% (>300 giây). Với Kosarak đã bổ sung 0,4% và 0,25%; với T40 đã bổ sung 1,25%. Đừng hiểu `NaN`/`0` khi timeout là không có closed itemsets.

**Các ví dụ để thẩm tra nhận xét:**

- Kosarak 0,25%: 8.770 closed itemsets, 12,413s; 0,2%: 35.864, 18,435s; 0,15% timeout >300s.
- T40I10D100K 1,25%: 13.460 closed itemsets, 27,445s; 1%: 65.236, 35,049s; 0,5% timeout >300s.
- Chess 90%: 498; 60%: 98.392 closed itemsets, 43,773s.

## 6. Công bố Hugging Face và đối chiếu dữ liệu

1. Repository: [hytrang/fpclose-fim-benchmarks](https://huggingface.co/datasets/hytrang/fpclose-fim-benchmarks).
2. Theo output xác minh của chủ dự án, gọi `HfApi().list_repo_files(repo_type="dataset", token=False)` đã liệt kê `.gitattributes`, `MANIFEST.md`, `README.md` và đúng 9 `.txt` ở root.
3. Dùng `hf_hub_download(..., token=False)` để tải từng `.txt` về Colab, tính SHA-256, so với `benchmark_inventory.csv`: **9/9 PASS**. Đây là bằng chứng rằng các file public trùng byte với bản normalized đã kiểm tra tại thời điểm thử; việc repository còn Public / content không bị sửa **có thể kiểm tra lại metadata nhẹ** nếu cần.
4. Cảnh báo `unauthenticated requests / HF_TOKEN` chỉ nói về giới hạn tốc độ, **không phải lỗi**; auth không cần thiết để xác minh public dataset.
5. **Chưa xác nhận** dữ liệu dẫn xuất `scalability/` hoặc `synthetic/` được upload lên Hugging Face; hiện chúng đã có trong Drive. PDF cho phép commit script tái tạo thay vì commit dữ liệu dẫn xuất, nhưng việc này cần đối chiếu GitHub nhóm.
6. **Còn việc tài liệu:** `MANIFEST.md` trên Drive vẫn kết thúc bằng `Public Kaggle / Hugging Face dataset URL: TODO after publishing.`; nên cập nhật thành link thật và đồng bộ Dataset Card nếu có liên kết đến các file khác.

## 7. Checklist 11 việc gốc — tình trạng hiện tại

| # | Công việc | Tình trạng | Bằng chứng / điều kiện đóng |
|---|---|---|---|
| 1 | Tải 9 benchmark | **DONE** | 9 raw/normalized files và URLs/hashes trong MANIFEST. |
| 2 | Chuẩn hóa SPMF | **DONE, cần audit provenance** | 9 clean `.txt`, count/hash; xét lại ID-offset không rõ của 5 bộ đầu. |
| 3 | Dataset stats + SHA-256 | **DONE** | `dataset_statistics.csv`, `benchmark_inventory.csv`. |
| 4 | MANIFEST provenance | **MOSTLY DONE** | Có nguồn, raw/clean hashes, stats; thiếu cập nhật public URL, lịch sử offset chưa đầy đủ. |
| 5 | Smoke test cả nhóm + SPMF | **PARTIAL** | SPMF 9/9; chưa có bằng chứng chạy/đối chiếu output bản nhóm. |
| 6 | Nested Retail subsets | **DONE — data generation** | 5 files, seed 2026, nested indices; thí nghiệm scaling chưa chạy. |
| 7 | Synthetic lengths | **DONE — data generation** | 6 files, seed 2026, `synthetic_statistics.csv`; experiment chưa chạy. |
| 8 | Chọn minsup pilot | **DONE FOR SPMF** | 56 PASS + 3 TIMEOUT; chưa chứng minh mọi level đều feasible trên implementation nhóm. |
| 9 | Public hosting, SHA-256 | **DONE for 9 main datasets** | HF public listing, download public 9/9 PASS; sửa link TODO MANIFEST. |
| 10 | `results/benchmark.csv` so sánh chính thức | **NOT DONE / NOT VERIFIED** | Chưa thấy CSV kết quả chung gồm `tool/mode/peak_mem_mb/match_rate/machine`; `benchmark_config.csv` không thay thế. |
| 11 | Commit scripts, README, `.gitignore`, PR | **NOT VERIFIED** | Chưa có GitHub repo nhóm trong handoff; cần kiểm tra đường dẫn, scripts, seed, history, `.gitignore`, PR. |

**Phân công:** Nếu nhiệm vụ chỉ là *benchmark data preparation*, phần dữ liệu cơ bản đã xong; còn provenance/doc cleanup và chuyển giao repo. Nếu người này chịu trách nhiệm **toàn Chương 2** thì correctness và đánh giá hiệu năng chưa xong.

## 8. Yêu cầu Chương 2 không được nhầm với phần chuẩn bị

Theo đề/PDF cần đánh giá: correctness từng itemset + support, so runtime theo minsup (cùng máy/cùng file), output size, peak memory ở minsup giữa và so bản base/opt, scalability Retail 10/25/50/75/100, experiment transaction length 5/10/15/20/25/30, biểu đồ và giải thích theo Original Paper, phân tích điểm mạnh/yếu và ít nhất 2 hướng tối ưu. PDF đề nghị `results/benchmark.csv` với các cột:

```text
dataset,n_transactions,minsup_pct,minsup_count,tool,mode,n_itemsets,time_s,peak_mem_mb,match_rate,machine
```

Giá trị `tool`: `ours_base`, `ours_opt`, `spmf`; `mode`: `closed`, `all_fi` nếu nhóm hỗ trợ. Phải phân biệt **closed itemsets** và **all frequent itemsets**. Ngay từ yêu cầu ban đầu có nguy cơ lệch: FPClose trực tiếp trả closed itemsets còn đề có hạng mục trả all frequent itemsets + support; cần nhóm thống nhất reconstruction hoặc phạm vi so sánh.

**Quy tắc đo trong PDF:** chạy 3 lần, so trên cùng máy, warm-up JIT (nếu Julia). Dùng kết quả pilot hiện tại làm *feasibility/reference-count planning*, không coi thời gian pilot Colab là kết quả đo chính thức. Đặc biệt đánh giá `peak_mem_mb` và `match_rate` chưa có bằng chứng.

## 9. Ưu tiên kiểm toán dataset — đánh giá độc lập nhưng không chạy lại nặng

### Tier 0 — Metadata-only (rẻ nhất; bắt buộc)

1. Đọc **tài liệu này**, sau đó MANIFEST và `dataset_statistics.csv`.
2. Đọc `benchmark_config.csv`, `minsup_pilot_all.csv`, `pilot_grid_summary.csv`, `benchmark_inventory.csv` (tất cả file CSV nhỏ). Check 9 unique datasets, 56 selected PASS, 59 records = 56 PASS + 3 TIMEOUT, 9 normalized SHA, support count = `ceil(n * minsup_pct / 100)`.
3. Đọc README dự án, Dataset Card/HF file listing **metadata**, xác nhận tên 9 file, nguồn và public URL, chỉ ra `TODO` còn tồn tại.
4. Kiểm tra tiêu chí trong PDF, lập bảng **Done / Partial / Missing / Unverified** với bằng chứng file+cell+link.
5. Ghi riêng những gì **chưa thể tự xác minh** (repo mã nguồn nhóm, script commit, full correctness, performance experiment).

### Tier 1 — Light code review (chỉ khi Tier 0 cần)

- Mở Notebook 01 **các cell đã chỉ ở §1.1** để kiểm tra normalization (ID positivity, duplicate handling, LF, metadata), random seed/nested Retail, synthetic correlated patterns.
- Mở Notebook 02 **các cell đã chỉ** để kiểm tra lệnh gọi SPMF, output parser, timeout/checkpoint, schema và hash checking.
- Kiểm tra nguy cơ: 5 `id_offset` unknown; synthetic length là nested; 27 giao dịch Kosarak có duplicated item IDs trong raw được loại; schema Retail từng thiếu `n_transactions` nhưng đã vá trong CSV cuối; 2 functions đời đầu có thể overwrite kết quả nhưng bản consolidated hiện có 56 PASS; `output_mb` không phải `peak_mem_mb`.
- **Không** phân tích output HTML khổng lồ của Colab khi chỉ cần code cell và CSV.

### Tier 2 — Lightweight empirical checks (chỉ khi cần chứng cứ mạnh hơn)

- Nếu được cấp quyền đọc Drive / tải HF, kiểm tra **1–2 sample files trước**, không tải cả 9 file theo mặc định vì người dùng đã có log 9/9 verified. Nếu nghi hash sai hoặc cần tái kiểm độc lập, tải 9 file **một lần** theo streaming và so local/remote SHA-256; không xử lý nhiều bản sao thừa.
- Nếu cần kiểm tra toàn bộ định dạng thì **stream each line once**: non-empty, integer >0, ascending sorted, no duplicates, no metadata, newline `LF`, counts/hashes. Không load toàn bộ Kosarak vào memory.
- Kiểm tra `retail_p010 ⊆ retail_p025 ⊆ ...` dựa trên **multiset/order indices**, không chỉ `set(lines)` bởi duplicate transactions có thể lặp; tốt nhất kiểm tra đối chiếu generator seed.
- Kiểm tra synthetic hash/stats + positive/sorted + 10.000 rows + 500 items + avg lengths; kiểm tra nested relation **theo transaction index** nếu cần.
- **Không chạy lại FPClose 56 cấu hình, không benchmark Java/Julia/Python**, trừ khi có lỗi cụ thể, người dùng yêu cầu hoặc không còn chứng cứ nào khác. Nếu cần spot-run, dùng 1 dataset nhỏ và minsup cao, kèm timeout.

### Tier 3 — Chỉ làm sau khi dữ liệu qua audit và có repo thuật toán nhóm

- Full correctness trên mỗi cấu hình cần đối chiếu itemsets + support, không chỉ counts.
- Official benchmark nhiều lần/cùng môi trường; đo runtime, memory, speedup, scaling, length; xuất `results/benchmark.csv`; viết đánh giá/đề xuất tối ưu.
- Hoàn chỉnh GitHub README, code/reproduction, public HF link, notebook public access và PR. Đừng tự chuyển sang tier này trong một **data-only audit**.

## 10. Mẫu đánh giá cuối cùng agent phải cung cấp

Trả lời **bằng tiếng Việt**, ngắn gọn nhưng có lý do và bằng chứng:

1. **Kết luận tổng quan:** bộ chuẩn hóa có *ready for benchmarking* hay không; điểm tin cậy; giới hạn phạm vi.
2. **Ma trận 11 bước:** Status + evidence URL/file/cell + câu kiểm tra ngắn cho từng bước.
3. **Phát hiện theo mức độ:** Critical / High / Medium / Low. Không ghi là lỗi nếu chỉ chưa xác minh.
4. **Những điều đã kiểm chứng trực tiếp trong audit này** vs **dựa trên log người dùng** vs **chưa kiểm tra**.
5. **Việc cần sửa trước khi bàn giao** (đầu ra nhỏ, ưu tiên): cập nhật link HF trong MANIFEST/README; làm rõ 5 offset; xác minh public GitHub scripts/PR; bổ sung provenance và versioning nếu cần.
6. **Việc thuộc benchmark chính thức, không đổ sang data prep:** `benchmark.csv`, correctness, time/RAM/scalability/length/evaluation.
7. **Không tự nhận đã sửa/chạy bất kỳ thứ gì nếu chưa thực hiện; không tự mutate repo/Drive/HF**.

---

## 11. READY-TO-PASTE AGENT PROMPT (ENGLISH; OUTPUT MUST BE VIETNAMESE)

> **Chỉ sao chép phần bên dưới vào agent khác nếu muốn tiết kiệm token.** Gửi kèm file tài liệu này nếu agent cần chi tiết. Có thể dùng riêng prompt ngắn trong file `FIM_Benchmark_Audit_Prompt_EN.md` đi kèm.

```text
You are an independent, evidence-driven auditor for a university Frequent Itemset Mining (FIM) / FPClose benchmark-dataset preparation workstream.

IMPORTANT LANGUAGE REQUIREMENT: Respond entirely in VIETNAMESE. Technical names (FPClose, SPMF, SHA-256, minsup, Hugging Face, Colab, etc.) may remain in English. Do not write the final report in English.

GOAL: Determine exactly what has been completed, what is partially done, what is missing, and whether the nine normalized datasets are ready for reproducible benchmarks. Cross-check the team's Chapter 2 preparation guide and the official assignment. Evaluate dataset preparation first; do NOT silently expand into running official algorithm performance experiments.

SOURCE LINKS (verified; use targeted reads):
- Preparation notebook: https://colab.research.google.com/drive/17kcDkgBy61yCCT83Lg_7dFDMwwBZRBKt
- SPMF benchmark notebook: https://colab.research.google.com/drive/1zXK8l9ORBa3aN6MOAx_VCWZvc3zXuz39
- Drive project: https://drive.google.com/drive/folders/1clzRNAL5cHWU5D1GEqFOk18k18_1GD99
- Drive benchmark datasets and MANIFEST: https://drive.google.com/drive/folders/1rEl-ywPlDaPKb6Yxeu4OrkZRjXaTydnN
- Drive results folder: https://drive.google.com/drive/folders/1xbUTCmeFP-Ps_qMt014s5gYdfdoq8oSd
- Benchmark config CSV: https://drive.google.com/file/d/1qPQYBrh6Q33EOFLvqWTiSAj-ty4agPqp/view
- All pilot history: https://drive.google.com/file/d/1_lKLMa4myt26AUKW_5hZPkPLXEkvdJT-/view
- Inventory hashes: https://drive.google.com/file/d/1BoEX6fbQUUEtpiaXaKHJ30ht5P7ixRrI/view
- Dataset statistics: https://drive.google.com/file/d/1tUasiaEPBTEVIoOI-zO7MdvxYguM9XLn/view
- Team preparation guideline: https://docs.google.com/document/d/1DkrBgkxiICy8tQtIXsSILGN3wARmyBVRj9oCfU7g4A8/edit
- Official assignment: https://hcmus-cs-ta.github.io/lab-book/data-mining/projects/itemset/
- Public dataset repository: https://huggingface.co/datasets/hytrang/fpclose-fim-benchmarks
- GitHub code repository for the group: NOT VERIFIED. Do not invent its URL; explicitly mark GitHub-specific checks as pending until an authoritative repo URL is provided.

KNOWN PRIOR EVIDENCE (claims to assess, not automatically accept as newly verified):
- Nine SPMF-compatible normalized datasets, all nine present on Drive with measured transaction counts and matching SHA-256 values in MANIFEST.
- A public Hugging Face repository with README, MANIFEST and nine .txt files. An earlier unauthenticated download/hash check reported 9/9 PASS.
- 56 selected minsup configurations passed SPMF FPClose pilot: 7 levels for chess, 7 for mushrooms, 6 each for the other seven datasets. Three additional TIMEOUT records: kosarak at 0.15% and 0.1%, T40I10D100K at 0.5%; threshold 300 sec.
- Five fixed-seed nested Retail subsets (10/25/50/75/100%) and six 10,000-transaction, 500-item synthetic datasets (average lengths 5/10/15/20/25/30).
- Project README, MANIFEST, dataset statistics, benchmark inventory, benchmark config and pilot CSVs exist.
- SPMF pilot does NOT validate the group's own FPClose implementation; neither closed-itemset equality nor all-frequent-itemset reconstruction, peak memory, official runtime, scalability, or final report have been established.

QUOTA-OPTIMIZED WORKFLOW (MANDATORY):
1. First inspect only small metadata/text files: requirements, MANIFEST, README, dataset_statistics.csv, benchmark_inventory.csv, benchmark_config.csv, minsup_pilot_all.csv, pilot_grid_summary.csv.
2. Check consistency by reading these small CSVs, not by re-running mining: 9 datasets, 56 unique selected dataset/minsup pairs all PASS, 59 total pilot records = 56 PASS + 3 TIMEOUT, support threshold ceil(n_transactions * minsup_pct / 100), and 9 source-to-normalized hashes.
3. Inspect only the relevant notebook code cells: preparation normalization, Retail generator, synthetic generator; benchmark SPMF runner, final CSV consolidation, SHA checks and public HF check. Avoid rendering or analyzing large notebook output blobs.
4. Do not install Java/SPMF, do not use 'Run all', do not recompute all minsup thresholds, and do not download large datasets unless concrete inconsistencies warrant it. If necessary, first inspect a small file or metadata, then propose the minimum additional verification and its cost.
5. Do not modify any files, repositories, Hugging Face content or permissions without explicit approval. If access fails, record 'not verified' and identify an exact link/file needed. NEVER invent evidence.

AUDIT QUESTIONS:
A) Dataset provenance and format: raw sources; item ID normalization (especially 'unknown_original_not_logged' in the five initial datasets); positive unique sorted IDs, LF, no metadata/blank rows, counts and SHA; source version limitations.
B) Derived data: seeded nested Retail 10/25/50/75/100%; synthetic length sweep 5..30, 10k rows, 500 items, correlated patterns, generators and reproducibility. Verify source code, not just filenames.
C) MinSup pilot: correct closed-itemset terminology, chosen grids, timeout history, parser/threshold, SPMF-only nature, no inflated correctness/performance claims, and the 300-sec-vs-guide's-10-min discrepancy.
D) Publication: public HF file listing, README/dataset card, MANIFEST, source licensing/attribution, comparison with local checksum evidence; note outdated 'TODO' link in Drive MANIFEST.
E) Requirements gap: group algorithm comparison, peak memory, runtime charts, scalability, length experiment, all frequent itemsets vs closed, consolidated results/benchmark.csv, report, scripts/commit/PR (only if GitHub repo can be verified).
F) Distinguish what is required for DATA PREPARATION from what belongs to the FULL CHAPTER 2 EXPERIMENTAL EVALUATION.

REQUIRED ANSWER FORMAT (VIETNAMESE ONLY):
1. Executive verdict (ready / ready with conditions / not ready; confidence and scope).
2. Compact 11-step checklist with DONE/PARTIAL/MISSING/UNVERIFIED, cited evidence per row.
3. Prioritized issues (Critical/High/Medium/Low), with why they matter and the smallest fix.
4. An 'evidence classification' section: verified yourself vs prior logs vs not verified.
5. Next actions split into (i) data-preparation closure and (ii) official FPClose benchmarking/reporting. Estimate which checks can be completed WITHOUT running mining.
6. A concise final handoff verdict suitable for the team.

Do not claim that 56 SPMF PASS results prove correctness or speed of the group's implementation. Do not count TIMEOUT as zero itemsets. Do not present output file MB as peak memory MB. Do not guess the GitHub repository. Finish after the audit; do not proceed to implementation or benchmarking without being asked.
```

## 12. Những nội dung nên sửa sau khi agent audit xong (không tự sửa trước khi xét bằng chứng)

- **MANIFEST:** cập nhật dòng `TODO` thành `https://huggingface.co/datasets/hytrang/fpclose-fim-benchmarks`; ghi ngày công bố/đối chiếu, giữ nguyên raw/clean hashes.
- **README project:** thêm link public HF và hai Notebook Colab; bỏ câu lệnh cũ mang tính “before publishing” nếu đã qua xác minh; tách `pilot` và `official benchmark`.
- **Provenance:** truy lại ID-offset 5 file gốc từ raw-clean nếu cần reproducibility chặt chẽ, hoặc mô tả hạn chế thay vì đoán.
- **GitHub:** cung cấp đúng URL repo cho auditor; kiểm tra notebook/script generator, `.gitignore` loại file lớn, seed, kết quả `.csv`, README, PR/commit history.
- **Chương 2:** theo trách nhiệm được giao, chuẩn bị `results/benchmark.csv`, chạy implementation nhóm, so correctness support từng itemset, đo time/memory/scaling/length và viết phân tích dựa trên Original Paper (không thay thế bằng pilot).

---

### Hạn chế và mức độ xác minh của tài liệu này

Tài liệu biên soạn dựa trên: nội dung trực tiếp của 2 `.ipynb` trong Google Drive, MANIFEST, `dataset_statistics.csv`, tên các file kết quả/trong các thư mục Drive, PDF kế hoạch nhóm và **logs người dùng đã cung cấp** về 56 PASS/3 TIMEOUT và Hugging Face 9/9. Công cụ truy cập web trực tiếp không đọc được trang Hugging Face mới trong lần thử; trạng thái Public 9/9 được xác nhận dựa trên log truy cập **unauthenticated** của người dùng, không phải re-download độc lập ở lần soạn này. Chưa có repo mã nguồn nhóm hợp lệ để đánh giá triển khai thực tế. Các link Drive có thể đòi hỏi được chia sẻ quyền trước khi agent khác truy cập.
