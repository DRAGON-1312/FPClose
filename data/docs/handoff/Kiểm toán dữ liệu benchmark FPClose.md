# Dữ liệu đã sẵn sàng nhưng bàn giao chưa trọn

**Kết luận ngắn:** 9 tập benchmark đã chuẩn hóa, 5 Retail subsets và 6 tập synthetic đều nhất quán và đủ tin cậy để nhóm dùng làm đầu vào. Vì vậy phần dữ liệu đạt mức **"Ready with conditions"**. Toàn bộ workstream *chuẩn bị dữ liệu* theo checklist Chương 2 của nhóm thì **chưa xong**. Còn thiếu file header `results/benchmark.csv`, chưa có bằng chứng commit trên `feat/benchmark-data` kèm PR, smoke test và pilot mới chạy một phía (chỉ SPMF), và MANIFEST còn vài lỗ hổng tài liệu. Có hai rủi ro cấp dự án mà người chuẩn bị dữ liệu không tự giải quyết được nhưng phải nêu ngay khi bàn giao. Thứ nhất, đề bài yêu cầu xuất **tất cả frequent itemsets + support khớp SPMF**, trong khi FPClose chỉ sinh closed itemsets và pilot chỉ lưu số closed. Thứ hai, trang đề **có vẻ không liệt kê FPClose** trong nhóm thuật toán closed. Điểm này còn UNVERIFIED và cần người trong nhóm xem tận mắt hoặc có xác nhận của giảng viên. Kết quả 56 PASS của SPMF chỉ là dữ liệu tham chiếu và khả thi. Nó **không** chứng minh thuật toán của nhóm đúng. Độ tin cậy: **cao** với các CSV và metadata, **trung bình** với tính đúng byte-level của file lớn (dựa trên log của người dùng), **không có** với GitHub (chưa có URL).

---

## 1. Kết luận tổng quan

| Hạng mục | Kết luận |
|---|---|
| 9 tập normalized (đầu vào cho nhóm) | **Ready with conditions**: thống kê, SHA-256, số giao dịch và bản trên HF nhất quán. Điều kiện: sửa MANIFEST (HF URL, offset, ngày tải) |
| Dữ liệu dẫn xuất (Retail subsets, synthetic) | **Ready with conditions**: code generator và thống kê đúng đặc tả. Thiếu manifest hash công bố |
| Workstream chuẩn bị dữ liệu theo checklist guide (L177–197) | **Not ready**: thiếu mục 9 (`results/benchmark.csv` header) và mục 10 (`.gitignore`, commit, PR). Mục 3 và 6 mới làm một phía |
| Chương 2 đầy đủ (correctness, runtime, RAM, scalability, length, báo cáo) | **Chưa bắt đầu**: không thuộc phạm vi data-prep |
| Độ tin cậy audit | Cao (CSV, code cell, HF listing), trung bình (hash file lớn), không có (repo GitHub) |
| Phạm vi | Đọc CSV/MD nhỏ trên Drive, đọc *source* các cell NB01/NB02 (không đọc output), xem trang/tree/README của HF, đọc trang đề qua WebFetch (bản diễn giải của model, không phải nguyên văn). **Không** tải 9 file lớn, **không** chạy SPMF hay mining, **không** sửa gì trên Drive, HF hay repo |

---

## 2. Ma trận 11 đầu việc

Ký hiệu nguồn: [N1] [Notebook 01](https://colab.research.google.com/drive/17kcDkgBy61yCCT83Lg_7dFDMwwBZRBKt), [N2] [Notebook 02](https://colab.research.google.com/drive/1zXK8l9ORBa3aN6MOAx_VCWZvc3zXuz39), [M] [MANIFEST](https://drive.google.com/file/d/1FvI180i-lSv8IZikNRDDnt3rFLDjwl9q/view), [S] [dataset_statistics.csv](https://drive.google.com/file/d/1tUasiaEPBTEVIoOI-zO7MdvxYguM9XLn/view), [C] [benchmark_config.csv](https://drive.google.com/file/d/1qPQYBrh6Q33EOFLvqWTiSAj-ty4agPqp/view), [P] [minsup_pilot_all.csv](https://drive.google.com/file/d/1_lKLMa4myt26AUKW_5hZPkPLXEkvdJT-/view), [HF] [hytrang/fpclose-fim-benchmarks](https://huggingface.co/datasets/hytrang/fpclose-fim-benchmarks), [G] guide Chương 2 của nhóm (file local, số dòng L#). Chỉ số cell của NB01 đếm trên **tất cả cell**, của NB02 đếm trên code cell.

| # | Đầu việc | Trạng thái audit | Bằng chứng chính xác | Kiểm tra / điều kiện đóng |
|---|---|---|---|---|
| 1 | Tải 9 benchmark | **DONE** | [Thư mục benchmark](https://drive.google.com/drive/folders/1rEl-ywPlDaPKb6Yxeu4OrkZRjXaTydnN) có đúng 9 `.txt` + MANIFEST. [M] ghi URL nguồn: 6 từ SPMF, 3 từ FIMI | Lưu trên Drive/Colab thay vì `D:\FPClose\...` (G L177). Đây là khác biệt môi trường, vô hại |
| 2 | Chuẩn hóa SPMF | **PARTIAL** (dữ liệu đạt, tài liệu thiếu) | `normalize_spmf` ở N1 cell 8: lỗi khi gặp item ≤ 0, `sorted(set(...))`, bỏ dòng `#/@/%`. Phần mở rộng ở N1 cell 22: `offset = 1 if min_item_id == 0` | 5 tập đầu ghi `unknown_original_not_logged` trong [M] và [S]. Chưa thấy `.gitattributes eol=lf` trong repo (G L42) |
| 3 | Stats + SHA-256 | **DONE** (9 tập chính) | [S] 9 dòng khớp handoff. Density tính lại lệch ≤ 3e-6. 9 `clean_sha256` khớp [M], [inventory](https://drive.google.com/file/d/1BoEX6fbQUUEtpiaXaKHJ30ht5P7ixRrI/view), README và [HF] | Được tạo bằng notebook Python, không phải `scripts/dataset_stats.jl` (G L50). Hash của dữ liệu dẫn xuất chưa có trong MANIFEST |
| 4 | MANIFEST provenance | **PARTIAL** | [M] có raw/clean path, URL, raw/clean SHA. Dòng cuối: "Public Kaggle / Hugging Face dataset URL: TODO after publishing." | Còn thiếu: HF URL, **ngày tải** (G L117), offset của 5 tập đầu, ghi chú gzip của T40, tên giấy phép |
| 5 | Smoke test cả hai công cụ | **PARTIAL** | [spmf_initial_tests.csv](https://drive.google.com/file/d/1q2qRoQoIZAk4_Mq4qGRkJKu5sxA9AjJa/view): 9 PASS, số closed trùng dòng đầu của [C] | Guide yêu cầu `demo.jl` **và** SPMF ra cùng số dòng (G L48). Phía nhóm: **MISSING** (phụ thuộc người cài thuật toán) |
| 6 | Nested Retail subsets | **DONE** (sinh dữ liệu) | N1 cell 31: `SEED=2026`, shuffle một lần, `n*p//100`, assert `issubset` trên index, ghi LF. Kích thước file p100 = retail.txt = 4.080.775 B ([scalability](https://drive.google.com/drive/folders/1e54__DYqVAXkun2uqpNZz4e-myY-P5G_)) | Số dòng và hash của từng subset: UNVERIFIED (hash chỉ được in trong output notebook) |
| 7 | Synthetic lengths | **DONE** (sinh dữ liệu) | N1 cell 32 và [synthetic_statistics.csv](https://drive.google.com/file/d/1UTekFHgdGoN7HbdDMnu2Z-7CY9b7_bnh/view): 10.000 dòng / 500 item / seed 2026, avg đúng 5…30, có SHA từng file | Viết bằng Python thay vì `scripts/gen_synthetic.jl` (G L76). Phân phối độ dài hẹp, xem M8 |
| 8 | Minsup pilot | **PARTIAL** | [C] 56 dòng, đủ 9 tập, tất cả PASS. [P] 59 dòng = 56 PASS + 3 TIMEOUT. `minsup_count = ceil(n·pct/100)` đúng ở cả 59 dòng | Chỉ chạy SPMF, cutoff 300 s (G L100 quy định 10 phút), trên Colab, mỗi mức một lần. Không có #FI. Chưa chọn mức minsup "giữa" cho đo RAM |
| 9 | Public hosting + SHA | **DONE** (phần lõi) | [HF tree](https://huggingface.co/datasets/hytrang/fpclose-fim-benchmarks/tree/main): 9 `.txt` + README + MANIFEST, kích thước khớp Drive. SHA ghi trên card = inventory | Kết quả tải lại 9/9 PASS chỉ dựa trên log người dùng. Card còn câu hướng dẫn trước khi công bố, chưa có trường license |
| 10 | `results/benchmark.csv` | **MISSING** (header) | [results/](https://drive.google.com/drive/folders/1xbUTCmeFP-Ps_qMt014s5gYdfdoq8oSd) không có `benchmark.csv`. Tìm trên toàn Drive: 0 kết quả | Theo G L193, **tạo file với đúng các cột là việc của data-prep**. Điền số liệu là việc của evaluation |
| 11 | Scripts, README, `.gitignore`, PR | **UNVERIFIED** (repo) / **MISSING** (script độc lập) | Không có URL GitHub. Tìm `gen_synthetic` / `dataset_stats` trên Drive: 0 kết quả | G L195: commit trên `feat/benchmark-data` và mở PR. `.gitignore` cần thêm `data/scalability/` |

---

## 3. Vấn đề theo mức độ (kèm cách sửa nhỏ nhất)

### Critical: quyết định cấp dự án, phải nêu khi bàn giao

| ID | Vấn đề | Trạng thái | Cách sửa nhỏ nhất |
|---|---|---|---|
| C1 | **Closed và all-FI lệch nhau.** Theo bản đọc qua WebFetch, mức cơ bản của đề yêu cầu xuất mọi frequent itemset kèm support và khớp SPMF ([đề bài](https://hcmus-cs-ta.github.io/lab-book/data-mining/projects/itemset/)). FPClose chỉ trả closed itemsets. [C] chỉ có `reference_closed_itemsets`. Guide muốn so all-FI với FPGrowth ở các mức cao (G L104–106), nhưng chưa xác định mức nào và chưa có #FI | Xác nhận (khoảng trống trong kế hoạch, không phải lỗi dữ liệu) | Nhóm chọn một trong hai: (a) tái dựng all-FI từ closed và so với SPMF FPGrowth ở 1–2 mức cao mỗi tập; hoặc (b) xin giảng viên chấp thuận phạm vi chỉ so closed. Người chuẩn bị dữ liệu bổ sung cột `reference_all_fi` (ở các mức khả thi) hoặc ghi rõ "chưa đo" |
| C2 | **FPClose có thể không nằm trong danh sách thuật toán của đề.** Bản đọc WebFetch thấy họ "Closed" gồm Charm, LCM, DCI_Closed, Zart và không thấy FPClose. Thuật toán ngoài danh sách cần giảng viên duyệt ([đề bài](https://hcmus-cs-ta.github.io/lab-book/data-mining/projects/itemset/)) | **UNVERIFIED**: WebFetch là bản diễn giải, có thể sót | Một thành viên đọc trực tiếp trang đề. Nếu đúng là không có, lưu bằng chứng giảng viên đã duyệt (email hoặc Moodle) vào repo hay báo cáo |

### High

| ID | Vấn đề | Cách sửa nhỏ nhất |
|---|---|---|
| H1 | Chưa có `results/benchmark.csv` (checklist mục 9 của guide) | Tạo file chỉ có header: `dataset,n_transactions,minsup_pct,minsup_count,tool,mode,n_itemsets,time_s,peak_mem_mb,match_rate,machine`, rồi commit |
| H2 | Chưa có bằng chứng repo, nhánh hay PR. Code chuẩn bị chỉ nằm trong notebook trên Drive, không có script độc lập | Xuất code của N1 cell 8/22/31/32 ra `scripts/` (Python được chấp nhận vì đề cho phép code trong notebook hoặc helper). Thêm `.gitignore` (`data/benchmark/*.txt`, `data/synthetic/`, **`data/scalability/`**) và `.gitattributes` (`*.txt text eol=lf`). Commit trên `feat/benchmark-data` và mở PR. Không tự đặt ra link repo |
| H3 | Smoke test và pilot mới chạy một phía. Guide yêu cầu dừng khi **một trong hai** công cụ vượt ngưỡng (G L100). Các mức thấp, ví dụ Chess 60% (43,8 s, 98.392 closed), có thể không khả thi với bản Julia/Python của nhóm | Khi có implementation: chạy smoke test ở mức cao nhất cho 9 tập, so số dòng. Chạy lại riêng các mức thấp nhất, chỉnh lưới nếu bản của nhóm vượt ngưỡng. Ghi lại mức nào bị loại và lý do |
| H4 | Thiếu thông tin để lập kế hoạch: chưa chọn mức minsup "giữa" để đo RAM (G L84–94), chưa chọn minsup tương đối cố định cho Retail subsets (G L62) và synthetic (G L74), chưa chọn mức để so all-FI | Thêm vào `benchmark_config.csv` một cột `role` (`grid` / `memory_mid` / `scal_fixed` / `allfi_check`). Chỉ cần ghi lựa chọn, không phải chạy gì |

### Medium

| ID | Vấn đề | Cách sửa nhỏ nhất |
|---|---|---|
| M1 | Pilot dùng timeout **300 s**, guide quy định **10 phút**. Kosarak 0,15%/0,1% và T40 0,5% bị loại ở ngưỡng > 300 s, nên có thể vẫn khả thi trong 600 s | Ghi rõ độ lệch này trong MANIFEST, README và báo cáo. Nếu muốn, chạy lại riêng 3 mức đó với 600 s |
| M2 | Thời gian pilot là một lần chạy trên Colab, có khởi động JVM. Thời gian không đơn điệu theo minsup ở 6/9 tập, ví dụ chess 90%→85%: 1,216 s → 0,786 s | Chỉ dùng làm dữ liệu khả thi. Không đưa lên biểu đồ chính thức (G L161, L171) |
| M3 | MANIFEST: HF URL vẫn là `TODO`. Thiếu ngày tải. 5 tập ghi offset "unknown" | Điền `https://huggingface.co/datasets/hytrang/fpclose-fim-benchmarks` và ngày tải/công bố. Offset xem phát hiện tích cực bên dưới |
| M4 | Không có manifest hash cho dữ liệu dẫn xuất. Hash Retail subset chỉ được in ra trong output N1 | Ghi `derived_sha256.csv` (5 subset + 6 synthetic) và dẫn link từ MANIFEST |
| M5 | README dự án đã cũ: không có link HF, link notebook hay GitHub. Còn câu "Before publishing, verify…". Trỏ tới "generation scripts" không tồn tại. Không ghi phiên bản SPMF hay hash của jar | Thêm link HF và 2 link Colab, bỏ câu checklist, ghi phiên bản hoặc SHA của `spmf.jar` và Java 25 |
| M6 | HF card: không có trường `license`, không có khối citation. Còn câu "Upload this README.md to the root…". Front matter YAML có thể bị lỗi (`---\n---`): PLAUSIBLE, cần xem tận mắt | Sửa YAML, thêm `license: other` kèm ghi chú nguồn SPMF/FIMI, xóa câu hướng dẫn, đồng bộ MANIFEST bản mới lên HF |
| M7 | Mushrooms trong bản SPMF có 8.416 dòng, bảng của đề ghi 8.124. Retail 16.470 item | Thêm một câu trong báo cáo giải thích khác biệt phiên bản (G L36 cho phép dùng file thực tế) |
| M8 | **Rủi ro synthetic:** generator lấy prefix của master transaction 32 item, nên dễ nghi mọi giao dịch có cùng độ dài. **Kiểm tra cell cho thấy không phải vậy**: có offset cân bằng ±1/±2, min–max lần lượt 4–6, 8–12 … 28–32 ([synthetic_statistics.csv](https://drive.google.com/file/d/1UTekFHgdGoN7HbdDMnu2Z-7CY9b7_bnh/view)). Rủi ro còn lại là phương sai độ dài rất hẹp, khác phân phối kiểu Poisson của IBM Quest mà guide muốn mô phỏng (G L72). Ngoài ra lenK ⊂ lenK+5 theo từng giao dịch | Không cần sinh lại. Mô tả rõ thiết kế (prefix lồng nhau, độ dài trung bình ±2) trong MANIFEST và báo cáo |
| M9 | Kosarak có 27 dòng chứa item lặp | Dữ liệu giữ đủ 990.002 dòng, nên phép xử lý là **loại item trùng**, không xóa giao dịch. Ghi đúng như vậy trong MANIFEST |

### Low

| ID | Vấn đề | Cách sửa |
|---|---|---|
| L1 | `T40I10D100K.dat` có `gzip_detected: true` dù URL không có đuôi `.gz`. Raw SHA là hash của luồng gzip | Ghi chú trong MANIFEST |
| L2 | Handoff gọi "code index 30–32" cho N1, nhưng đó là chỉ số trên tất cả cell. Chỉ số code cell là 14–16 | Sửa cách gọi trong handoff |
| L3 | Density: `dataset_statistics` dùng **phần trăm**, `synthetic_statistics` dùng **tỉ lệ** (0,01–0,06) | Thống nhất một đơn vị hoặc ghi đơn vị vào tên cột |
| L4 | Kích thước subset dùng **floor** (22.040,5 → 22.040; 66.121,5 → 66.121) | Ghi quy tắc floor trong MANIFEST |
| L5 | `pilot_output_mb` / `output_mb` là **kích thước file kết quả, không phải peak RAM** | Đổi tên thành `output_file_mb`. Ở evaluation, đo `peak_mem_mb` từ "Max memory usage" của SPMF (G L159) |
| L6 | Ở dòng TIMEOUT, `n_closed_itemsets` để **trống (NaN), không phải 0**, còn `output_mb = 0.0`. Số đếm ở dòng PASS bị lưu dạng float ("498.0"). Thông báo lỗi không thống nhất ("300 seconds" và "300s") | Ghi trong README: TIMEOUT nghĩa là không biết, không phải 0 itemset. Đặt `output_mb` = NaN ở dòng TIMEOUT. Ép kiểu số đếm về Int |
| L7 | SPMF nhận minsup dạng `%`, không nhận count. Bước kiểm tra sau khi chạy chỉ bắt được trường hợp ngưỡng *thấp hơn* | Khi so với bản của nhóm, truyền `minsup_count` nguyên cho cả hai công cụ |
| L8 | HF card trỏ FIMI tới `fimi.uantwerpen.be`, MANIFEST dùng `cs.rpi.edu` | Thống nhất URL |

**Phát hiện tích cực (mới):** 5 tập có "unknown offset" **rất có thể có offset 0**. `normalize_spmf` (N1 cell 8) báo lỗi khi gặp item ≤ 0 và **không bao giờ dịch ID**. Nếu file gốc có ID 0, lần chạy đã bị dừng. Cách sửa: đổi nhãn thành `0 (normalizer rejects IDs ≤ 0; no shift applied)`. Nếu muốn chắc chắn hơn, so min ID giữa raw và clean, việc này rất rẻ. Chỉ nên đổi nhãn sau khi người thực hiện xác nhận.

---

## 4. Bằng chứng

| Loại | Nội dung |
|---|---|
| **Kiểm tra trực tiếp trong audit này** | [C] có 56 dòng, 9 tập, tất cả PASS, không trùng khóa. [P] có 59 dòng (56 + 3 TIMEOUT), khớp [C] ở mọi cột. Công thức `ceil` đúng ở 59/59 dòng (tính bằng Fraction và bằng double). Số closed không giảm khi minsup giảm. Giá trị max trong lưới khớp bảng handoff. [S] khớp. 9 SHA trùng nhau giữa 5 tài liệu. Kích thước trên Drive khớp inventory và HF. Code N1 cell 8/22/31/32 và N2 idx 6/21/25/28/29/33/35. Kích thước Retail subset và quy tắc floor. Thống kê synthetic. HF tree và card truy cập được không cần đăng nhập. Không có `benchmark.csv` và script độc lập trên Drive |
| **Chỉ dựa trên log của người dùng** | Tải lại 9/9 từ HF với SHA PASS (chỉ xác nhận được hash ghi trên card và kích thước). Hash thực tế của 9 file lớn (đối chiếu giữa các tài liệu, chưa hash lại). SPMF đã chạy thật trên Colab với Java 25 |
| **Chưa kiểm tra** | Repo GitHub, nhánh, PR, `.gitignore`, `.gitattributes` (không có URL, không tự đặt ra). Số dòng và hash thực của 5 subset và 6 synthetic. Định dạng từng dòng của 9 file (UTF-8, LF, số nguyên dương, đã sắp xếp). Quyền chia sẻ trên Drive. Cách làm tròn của SPMF trong source Java. FPClose có trong danh sách của đề hay không. Đã có giảng viên duyệt hay chưa. Front matter YAML trên HF. Ngày tải |

**Kiểm tra bổ sung rẻ nhất nếu cần:** tải `retail_p010` (0,4 MB) và `len05` (0,19 MB), đếm dòng và SHA, đọc từng dòng một lần để kiểm tra định dạng.

---

## 5. Phân tách việc còn lại

| Việc còn lại của **chuẩn bị dữ liệu** (chủ: sinh viên này) | Việc của **toàn Chương 2 benchmark/evaluation** (không đổ sang data-prep) |
|---|---|
| Sửa MANIFEST: HF URL, ngày tải, offset 5 tập, gzip T40, floor, cách xử lý item trùng ở Kosarak, timeout 300 s | Implementation FPClose của nhóm (base và opt) |
| `derived_sha256.csv` cho 11 file dẫn xuất | Correctness **từng itemset + support** so với SPMF, `match_rate`, phân tích các chỗ lệch |
| Tạo header `results/benchmark.csv` | Điền `benchmark.csv`: time_s là min của 3 lần chạy, cùng máy, có warm-up JIT, ghi cột `machine` |
| Xuất script ra `scripts/`, thêm `.gitignore` (gồm `data/scalability/`) và `.gitattributes`, commit trên `feat/benchmark-data`, mở PR | `peak_mem_mb` ở mức minsup giữa, so base với opt |
| Cập nhật README và HF card (link, license, YAML, bỏ câu checklist) | Biểu đồ output size (dense và sparse), scalability 10–100%, transaction length 5–30 |
| Ghi các lựa chọn `memory_mid` / `scal_fixed` / `allfi_check` vào config | Tái dựng all-FI và so với FPGrowth (nếu chọn phương án a ở C1) |
| Phối hợp với người cài thuật toán: smoke test hai phía, kiểm tra lại các mức minsup thấp nhất | Báo cáo: giải thích theo bài báo gốc, điểm mạnh/yếu so với SPMF, ít nhất 2 hướng tối ưu, giải thích khác biệt phiên bản dataset |
| Báo cho nhóm về C1 và C2 | Giảng viên duyệt FPClose (nếu C2 đúng) |

---

## 6. Đoạn bàn giao để gửi nhóm

> **Bàn giao dữ liệu benchmark (22/11/2026):** 9 tập SPMF đã chuẩn hóa nằm ở `data/benchmark/` và trên [Hugging Face](https://huggingface.co/datasets/hytrang/fpclose-fim-benchmarks). Thống kê và SHA-256 khớp nhau giữa MANIFEST, inventory và HF. Đi kèm 5 Retail subsets lồng nhau (seed 2026) và 6 tập synthetic dài 5–30 (10.000 dòng, 500 item). Mọi người dùng **đúng các file này** cho cả SPMF và bản của nhóm. `benchmark_config.csv` có 56 mức minsup PASS **chỉ với SPMF FPClose** (300 s, Colab, một lần chạy). Đây là số closed itemsets tham chiếu và dữ liệu khả thi, **không phải** kết quả benchmark và **không** chứng minh code của nhóm đúng. 3 mức TIMEOUT (Kosarak 0,15%/0,1%, T40 0,5%) nghĩa là **không biết**, không phải 0 itemset. Cột `output_mb` là kích thước file, không phải RAM. **Cần nhóm quyết định ngay:** (1) đề yêu cầu xuất *tất cả* frequent itemsets + support, còn FPClose cho ra closed: nhóm sẽ tái dựng all-FI hay xin chỉ so closed? (2) Cần một người đọc lại trang đề xem FPClose có trong danh sách không. Nếu không có, cần giảng viên duyệt. Phần mình còn làm trước khi đóng việc: sửa MANIFEST (link HF, ngày tải, offset, timeout), công bố hash dữ liệu dẫn xuất, tạo header `results/benchmark.csv`, đẩy script, `.gitignore` và `.gitattributes` lên `feat/benchmark-data` rồi mở PR. Khi có implementation, mình sẽ cùng người cài thuật toán chạy smoke test hai phía và kiểm tra lại các mức minsup thấp nhất.

## Kết luận

Chất lượng dữ liệu của sinh viên tốt hơn mức đề yêu cầu. Đề chỉ cần ít nhất 4 tập, ở đây có 9 tập, kèm hash kiểm tra chéo và pilot được ghi lịch sử minh bạch. Rủi ro thật nằm ở phần phía sau dữ liệu: phạm vi đầu ra (closed hay all-FI) và tính hợp lệ của việc chọn FPClose. Hai câu hỏi này có thể làm thay đổi lưới minsup và cách tính correctness. Vì vậy bàn giao nên đi kèm hai câu hỏi đó, thay vì chỉ thông báo "dữ liệu xong". Phần data-prep còn thiếu đều là việc tài liệu và repo trong vài giờ, **không cần chạy lại mining**. Ngoại lệ duy nhất là smoke test hai phía, việc này phải chờ implementation của nhóm.
