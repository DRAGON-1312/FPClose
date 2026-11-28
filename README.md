# FPClose

Cài đặt lại bằng Julia thuật toán **FPClose** — khai thác các *closed frequent itemsets* (tập mục thường xuyên đóng) bằng FP-tree — cho đồ án môn học.

Thuật toán được trình bày trong bài báo:

> G. Grahne và J. Zhu, "Fast Algorithms for Frequent Itemset Mining Using FP-Trees",
> *IEEE Transactions on Knowledge and Data Engineering*, 17(10), 2005.
> DOI: [10.1109/TKDE.2005.166](https://doi.org/10.1109/TKDE.2005.166)

## Thành viên nhóm

TODO

## Cấu trúc thư mục

```
FPClose/
├── Project.toml
├── Manifest.toml
├── demo.jl
├── scripts/
│   ├── data_setup.jl
│   ├── reference_check.jl
│   ├── make_spmf_fixtures.jl
│   ├── compare_spmf.jl
│   └── benchmark.jl
├── src/
│   ├── FPClose.jl
│   ├── structures.jl
│   ├── utils.jl
│   ├── recovery.jl
│   ├── rules.jl
│   └── algorithm/
│       ├── fptree.jl
│       ├── fparray.jl
│       ├── cfitree.jl
│       └── fpclose.jl
├── test/
│   ├── runtests.jl
│   ├── test_correctness.jl
│   ├── test_optimizations.jl
│   ├── test_recovery.jl
│   ├── test_spmf_fixtures.jl
│   ├── test_benchmark.jl
│   ├── brute_force.jl
│   ├── mutation_record_x.jl
│   └── fixtures/spmf/          # output SPMF đã lưu, test so từng itemset (không cần Java)
├── data/                       # CHỈ dữ liệu đầu vào
│   ├── README.md               # nguồn, SHA-256, thống kê, cách tái tạo 9 dataset benchmark
│   ├── meta/                   # cấu hình dữ liệu: dataset_statistics, benchmark_config, benchmark_inventory,
│   │                           #   derived_hashes, synthetic_statistics (CSV)
│   ├── toy/                    # CSDL nhỏ để test; toy/extra/ có thêm 3 CSDL nhỏ
│   ├── benchmark/              # 9 dataset benchmark (.txt bị .gitignore, chỉ giữ .gitkeep)
│   ├── scalability/            # Retail subsets (sinh ra, bị .gitignore)
│   ├── synthetic/              # CSDL tổng hợp theo độ dài giao dịch (sinh ra, bị .gitignore)
│   └── raw/                    # file gốc tải về (bị .gitignore)
├── results/                    # mọi kết quả, được commit
│   ├── reference/              # SPMF và FIMI kiểm dữ liệu (reference_check.jl)
│   ├── correctness/            # so cài đặt của nhóm với SPMF (compare_spmf.jl)
│   ├── optimization/           # số đo các tối ưu của Chương 1
│   ├── pilot/                  # chạy thử lưới minsup bằng SPMF
│   └── runtime/ memory/ scalability/ txlen/ figures/   # dành cho Chương 2
├── notebooks/
│   ├── demo.ipynb
│   ├── application_01.ipynb    # Ứng dụng 1 (giỏ hàng)
│   └── application_02.ipynb    # Ứng dụng 2 (ảnh), code ở applications/app2_image/
└── docs/
    └── DEVIATIONS.md
```

| Đường dẫn | Vai trò |
|---|---|
| `Project.toml`, `Manifest.toml` | Khai báo gói và cố định phiên bản phụ thuộc để tái lập môi trường (`Manifest.toml` được commit). |
| `src/FPClose.jl` | Module gốc `FPClose`, `include` các file còn lại trong `src/`. |
| `src/structures.jl` | Định nghĩa cấu trúc dữ liệu: FP-tree và CFI-tree. |
| `src/utils.jl` | Đọc/ghi định dạng SPMF và xử lý tham số dòng lệnh. |
| `src/recovery.jl` | Khôi phục MỌI frequent itemset (kèm support) từ các closed itemset. Phần nhóm bổ sung, không thuộc bài báo. |
| `src/rules.jl` | Sinh luật kết hợp (support, confidence, lift), xếp hạng theo lift, top-k. Phần nhóm bổ sung. |
| `src/algorithm/fptree.jl` | Section 2.1 của bài báo: xây dựng FP-tree và conditional FP-tree. |
| `src/algorithm/fparray.jl` | Section 2.2–2.3: FP-array. |
| `src/algorithm/cfitree.jl` | Section 4.1: CFI-tree và `closed_checking`. |
| `src/algorithm/fpclose.jl` | Fig. 8: thủ tục `FPclose`. |
| `test/` | Các bài test: `runtests.jl` là điểm vào; `test_correctness.jl`, `test_optimizations.jl` (mọi tổ hợp bật/tắt tối ưu so với bản cơ bản và vét cạn), `test_recovery.jl` (recovery, luật kết hợp, CLI), `test_spmf_fixtures.jl` (so từng itemset với output SPMF đã lưu, không cần Java), `test_benchmark.jl`; `brute_force.jl` là bộ đáp án vét cạn; `mutation_record_x.jl` là test đột biến chạy riêng (không nằm trong `runtests.jl`). |
| `scripts/data_setup.jl` | Tải và chuẩn hóa 9 dataset benchmark, sinh Retail subsets và synthetic, kiểm SHA-256 (xem mục "Chuẩn bị dữ liệu"). |
| `scripts/reference_check.jl` | Kiểm dữ liệu bằng SPMF FPClose và FPclose gốc của FIMI, ghi vào `results/reference/`. |
| `scripts/make_spmf_fixtures.jl` | Sinh fixture từ SPMF cho `test/fixtures/spmf/` và lập bảng `results/correctness/toy_vs_spmf.*` (xem mục "So sánh với SPMF"). |
| `scripts/compare_spmf.jl` | Chạy SPMF và bản của nhóm trên cùng input rồi so kết quả (xem mục "So sánh với SPMF"). |
| `scripts/benchmark.jl` | Đo thời gian và bộ nhớ đỉnh khi bật/tắt từng tối ưu, xuất CSV vào `out/` (xem mục "Đo hiệu năng"). |
| `tools/`, `out/` | Không commit (nằm trong `.gitignore`): `tools/` chứa `spmf.jar` và FIMI, `out/` chứa output tạm. Kết quả cần giữ được chuyển vào `results/`. |
| `notebooks/demo.ipynb` | Notebook demo (để chạy trên Google Colab). |
| `applications/app2_image/` | Ứng dụng 2: khai thác mẫu trực quan trên ảnh Caltech-101 (script `src/`, hướng dẫn trong `README.md` của thư mục; notebook ở `notebooks/application_02.ipynb`). |
| `docs/` | Tài liệu, báo cáo (`docs/Report.pdf` là file PDF duy nhất được commit). `docs/DEVIATIONS.md` liệt kê mọi chỗ code khác hoặc bổ sung so với bài báo, kèm lý do. |
| `demo.jl` | Script chạy thuật toán từ dòng lệnh. |
| `data/README.md` | Nguồn, SHA-256, thống kê và cách tái tạo 9 dataset benchmark; bản sao công khai trên Hugging Face. |
| `data/meta/` | Cấu hình dữ liệu dạng CSV; `scripts/data_setup.jl` và `scripts/reference_check.jl` đọc từ đây, không chép cứng. |
| `data/toy/` | Dữ liệu nhỏ để kiểm thử và demo (`pasquier99.txt`, `rounding_test.txt`; thêm `extra/`). Test đọc thư mục này. |
| `data/benchmark/`, `data/scalability/`, `data/synthetic/`, `data/raw/` | Dữ liệu cỡ lớn, không commit (chỉ có `.gitkeep`); tạo bằng `scripts/data_setup.jl`. |
| `results/` | Kết quả chạy được commit, chia theo loại (xem cây thư mục). |

## Cài đặt môi trường

Yêu cầu: Julia ≥ 1.9.

```
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

## Chuẩn bị dữ liệu benchmark

Dữ liệu benchmark lớn không nằm trong repo. Tạo chúng bằng script (chỉ dùng thư viện chuẩn của Julia), mọi
cấu hình và SHA-256 đọc từ `data/meta/*.csv`:

```
julia --project=. scripts/data_setup.jl                          # tải 9 dataset đã chuẩn hóa từ Hugging Face (mặc định)
julia --project=. scripts/data_setup.jl --from-source            # tải từ SPMF/FIMI rồi chuẩn hóa
julia --project=. scripts/data_setup.jl --from-source --only mushrooms,chess
julia --project=. scripts/reference_check.jl --datasets chess    # kiểm dữ liệu bằng SPMF và FIMI, ghi results/reference/
```

`data_setup.jl` luôn sinh thêm 5 Retail subsets (`data/scalability/`) và 6 synthetic (`data/synthetic/`) rồi so hash.
Với `--from-source`, nếu URL chính lỗi (ví dụ `cs.rpi.edu` bị từ chối chứng chỉ trên Windows) thì script thử
`fallback_url` trong `data/meta/dataset_statistics.csv`. Mã thoát khác 0 nếu có bước lệch hash. Chi tiết nguồn, hash và
thống kê: `data/README.md`. Item trong mọi file là số nguyên không âm; file benchmark chuẩn hóa chỉ có item ≥ 1.

## Cách chạy

```
# Chỉ closed frequent itemsets (in ra màn hình nếu không có tham số ghi file)
julia --project=. demo.jl --minsup 0.4 data/toy/pasquier99.txt
julia --project=. demo.jl --minsup 40% --output-closed out/closed.txt data/toy/pasquier99.txt
julia --project=. demo.jl --minsup-count 2 data/toy/pasquier99.txt

# Thêm MỌI frequent itemset (chạy bước recovery)
julia --project=. demo.jl --minsup 40% --output-closed out/closed.txt --output-all out/all.txt data/toy/pasquier99.txt

# Thêm luật kết hợp: confidence >= 0.6, giữ 10 luật lift cao nhất
julia --project=. demo.jl --minsup 40% --rules out/rules.txt --minconf 0.6 --top 10 data/toy/pasquier99.txt
```

- `--minsup`: ngưỡng tương đối, viết `0.4` hoặc `40%` (như SPMF). Số giao dịch tối thiểu là
  `ceil(minsup × số giao dịch)`, làm tròn lên thuần, không dung sai. Quy ước này đã kiểm với SPMF
  (`data/toy/rounding_test.txt` ở 7%: 0.07 × 100 = 7.000000000000001 nên ngưỡng là 8, cả hai cùng cho đúng
  2 itemset; xem `docs/DEVIATIONS.md`).
- `--minsup-count`: ngưỡng tuyệt đối, số giao dịch (số nguyên ≥ 1).
- Phải có đúng một trong hai; thiếu, có cả hai hoặc giá trị ngoài miền thì báo lỗi.
- `--output-closed <file>`: ghi closed frequent itemsets, định dạng SPMF `1 2 #SUP: 3`. `--output` là tên cũ,
  tương đương `--output-closed` (dùng cả hai thì báo lỗi). Không có tham số ghi file nào thì in closed
  itemsets ra màn hình.
- `--output-all <file>`: ghi MỌI frequent itemset cùng định dạng. Chỉ khi có tham số này (hoặc `--rules`) mới
  chạy recovery. Số frequent itemset có thể lớn hơn số closed itemset theo cấp số mũ: chỉ dùng ở minsup đủ
  cao với dữ liệu dày.
- `--rules <file> --minconf <0..1> [--top <k>]`: ghi luật kết hợp (cũng chạy recovery vì cần support của mọi
  tập con). Mỗi dòng `X ==> Y #SUP: <support tương đối> #CONF: <confidence> #LIFT: <lift> #COUNT: <số giao dịch>`,
  xếp theo lift giảm dần. `--minconf` là bắt buộc khi có `--rules`; `--top` phải là số nguyên dương.
- Thời gian của từng giai đoạn (mining, recovery, rules) và số CFI, số FI, số luật được in riêng ra stderr.
- File không tồn tại, tham số ngoài miền hoặc sai kiểu cho thông báo `Lỗi: ...` và mã thoát 2.

## So sánh với SPMF

SPMF chỉ dùng để đối chiếu kết quả, mã của nhóm không tham khảo nó. Tải `spmf.jar` về `tools/`
(cần Java 25; đã thử với Temurin 25.0.5):

```
mkdir tools
curl -L -o tools/spmf.jar https://www.philippe-fournier-viger.com/spmf/spmf.jar
```

Chạy so sánh trên một file với một ngưỡng (dạng SPMF, ví dụ `40%`):

```
julia --project scripts/compare_spmf.jl data/toy/pasquier99.txt 40%                  # closed (mặc định)
julia --project scripts/compare_spmf.jl --mode all data/toy/pasquier99.txt 40%       # mọi frequent itemset
julia --project scripts/compare_spmf.jl --mode both --baseline data/toy/rounding_test.txt 7%
julia --project scripts/compare_spmf.jl --table                                       # bảng cho mọi data/toy/*.txt
julia --project scripts/compare_spmf.jl --table --dir data/toy/extra --minsups 60%,20%,2%
```

- Chế độ `closed`: FPClose của nhóm so với SPMF `FPClose` (`java -jar tools/spmf.jar run FPClose ...`).
- Chế độ `all`: recovery (`src/recovery.jl`) so với SPMF **`FPGrowth_itemsets`** (thuật toán FP-Growth xuất mọi
  frequent itemset của SPMF; `java -jar tools/spmf.jar run FPGrowth_itemsets <input> <output> 40%`).
- Output của hai phía được chuẩn hóa (bỏ dòng metadata `@...`, sắp item trong từng itemset, so theo tập
  `(itemset, support)`), rồi in số dòng khớp, các dòng chỉ có ở một phía và các dòng khác support. Mã thoát
  là 0 khi khớp hoàn toàn, 1 khi có lệch, 2 khi SPMF lỗi hoặc tham số sai.
- `--table` in bảng markdown (file, minsup, số giao dịch, số closed FI, số khớp, tỉ lệ khớp, số all-FI, số khớp,
  tỉ lệ khớp) và ghi `out/compare_table.csv`. Tỉ lệ khớp = số dòng khớp hoàn toàn / số dòng của hợp hai bên.
  Các bảng đã chạy và dùng trong báo cáo được lưu ở `results/correctness/compare_table*.csv|md`.
- `--baseline` chạy FPClose bản cơ bản (không FP-array, không kết thúc sớm); `--jar` đổi đường dẫn jar.
- Output thô nằm ở `out/spmf_<chế độ>_<tên>_<minsup>.txt` và `out/ours_<chế độ>_<tên>_<minsup>.txt`.

**Fixture cho unit test (không cần Java khi chạy test).** `scripts/make_spmf_fixtures.jl` chạy SPMF `FPClose` và
`FPGrowth_itemsets` trên 6 CSDL nhỏ của `data/toy/` và `data/toy/extra/` (mỗi CSDL 2 đến 4 mức minsup, gồm các mức
làm tròn kiểu 7% và một CSDL có item 0), lưu NGUYÊN output vào `test/fixtures/spmf/` (36 file kèm `manifest.csv`).
`test/test_spmf_fixtures.jl` so từng itemset và support của `fpclose` (bản mặc định và bản tắt mọi tối ưu) và của
`recover_all_frequent` với các file đó. Cần Java 25 và `tools/spmf.jar` chỉ khi sinh lại fixture:

```
julia --project=. scripts/make_spmf_fixtures.jl                 # sinh lại fixture bằng SPMF, rồi lập bảng
julia --project=. scripts/make_spmf_fixtures.jl --report-only   # chỉ lập bảng từ fixture đã lưu (không cần Java)
```

Bảng `results/correctness/toy_vs_spmf.csv|md` (CSDL, minsup, chế độ, `n_ours`, `n_spmf`, `n_match`, `match_rate`):
36/36 cặp CSDL × minsup × chế độ khớp hoàn toàn (tỉ lệ khớp 100%), cả với bản mặc định lẫn bản tắt mọi tối ưu.

## Đo hiệu năng

```
julia --project scripts/benchmark.jl --minsups 0.05,0.02,0.01 data/benchmark/<file>.txt
julia --project scripts/benchmark.jl --synthetic --minsups 0.05,0.02,0.01 --reps 3
```

Mỗi (minsup, tổ hợp bật/tắt của `prune_line8`, `fparray`, `early_termination`) chạy trong một
tiến trình Julia riêng, có warm-up để loại thời gian biên dịch, lấy thời gian nhỏ nhất của
`--reps` lần chạy và RSS đỉnh của tiến trình. Kết quả ghi vào `out/benchmark_<tên>.csv`.
`--synthetic` dùng CSDL tổng hợp cố định (seed 2026). `--combos ablation` chỉ chạy 4 tổ hợp:
bản cơ bản, +FP-array, +kết thúc sớm, +cả hai.

`--recovery` đo thêm bước recovery tách khỏi mining (tiến trình riêng, đọc tập đóng từ file) và ghi CSV thứ hai
`out/benchmark_<tên>_recovery.csv` (số CFI, số FI, thời gian, bộ nhớ cấp phát, RSS đỉnh của recovery, kèm thời
gian mining để so). `--max-fi N` (mặc định 5.000.000) dừng recovery khi số FI vượt `N` và ghi `status = LIMIT`.

Các công tắc cũng có sẵn trong API: `fpclose(db, minsup; fparray = false, early_termination = false,
prune_line8 = true, exact_count = true, reduced_cfitree = true)`. Mặc định bật hết; `benchmark.jl` chỉ
bật/tắt ba công tắc đầu, hai công tắc sau (`exact_count`, `reduced_cfitree`) luôn ở giá trị mặc định.

## Chạy lưới benchmark (Chương 2)

`scripts/run_benchmark_grid.jl` chạy cả lưới đo của Chương 2 (không vẽ biểu đồ). Cần Java và `tools/spmf.jar`,
dữ liệu đã tạo bằng `scripts/data_setup.jl`.

```
julia --project=. scripts/run_benchmark_grid.jl                      # cả 5 phần, 56 cấu hình, 3 lần, timeout 600 s/lần
julia --project=. scripts/run_benchmark_grid.jl --quick              # bản rút gọn (chess + mushrooms), vài phút, file có đuôi _quick
julia --project=. scripts/run_benchmark_grid.jl --datasets chess --only runtime,correctness
julia --project=. scripts/run_benchmark_grid.jl --runs 1 --timeout 120
```

| Tham số | Ý nghĩa |
|---|---|
| `--only` | Chọn phần, cách nhau bằng dấu phẩy: `correctness`, `runtime`, `memory`, `scalability`, `txlen` (mặc định: cả 5). `txlen_pilot` chạy thử các mức minsup của txlen. |
| `--datasets` | Giới hạn dataset của `correctness`, `runtime`, `memory` (`scalability` và `txlen` dùng dữ liệu cố định, bỏ qua tham số này). |
| `--runs`, `--timeout` | Số lần đo (mặc định 3) và timeout mỗi lần chạy, tính bằng giây (mặc định 600). Quá hạn thì ghi `TIMEOUT` và chạy tiếp. |
| `--quick` | chess + mushrooms, 2–3 mức minsup, 1 lần đo. File kết quả có hậu tố `_quick`. |
| `--suffix`, `--machine` | Hậu tố tên file kết quả; tên máy ghi vào cột `machine` (mặc định tên máy hoặc biến `FPCLOSE_MACHINE`). |
| `--fi-limit`, `--txlen-minsups`, `--scal-minsups` | Giới hạn số FI khi so mọi FI (mặc định 2.000.000), các mức minsup (%) của txlen (mặc định 0.5,0.2) và của scalability (mặc định 0.1,0.05). |
| `--no-skip-after-timeout` | Không bỏ qua các minsup thấp hơn sau khi một công cụ đã TIMEOUT ở minsup cao hơn của cùng dataset. |

Chạy tiếp được: dòng đã có trạng thái `OK`, `TIMEOUT` hoặc `SKIPPED` trong file CSV không bị chạy lại, dòng `FAILED` được
chạy lại. Log ở `out/grid.log`; cấu hình máy ở `results/ENVIRONMENT.md`.

| Phần | Nội dung | Kết quả |
|---|---|---|
| `correctness` | So từng itemset và support của `fpclose` với SPMF FPClose trên 56 cấu hình; kiểm thêm mọi FI (`recover_all_frequent` so với SPMF FPGrowth) ở minsup cao nhất của mỗi dataset, `SKIPPED` kèm lý do nếu vượt `--fi-limit`. | `results/correctness/grid_correctness.csv` |
| `runtime` | Thời gian và bộ nhớ của nhóm (tùy chọn mặc định) và SPMF trên 56 cấu hình. | `results/runtime/grid_runtime.csv` (+ `README.md` giải thích cột) |
| `memory` | Ở minsup giữa của mỗi dataset: bản cơ bản (tắt hết), bản theo bài báo (chỉ `prune_line8`), bản tối ưu (mặc định) và bản tắt riêng từng tối ưu; mọi bộ đếm `FPCloseStats`; kiểm mọi biến thể ra cùng tập đóng. | `results/memory/basic_vs_optimized.csv` |
| `scalability` | Retail con 10%…100%, hai mức minsup tương đối. | `results/scalability/scalability.csv` |
| `txlen` | CSDL tổng hợp theo độ dài giao dịch 5…30. | `results/txlen/txlen.csv` (+ `README.md` giải thích cách chọn minsup) |

**Cách đo.** Mỗi lần đo của nhóm chạy trong một tiến trình Julia riêng, đã warm-up trên dữ liệu nhỏ để loại thời gian biên dịch.
Đồng hồ chỉ bắt đầu sau warm-up và tách `read_s` (đọc), `mine_s` (khai thác), `write_s` (`write_spmf`).
`time_with_write_s` GỒM bước ghi file (dùng để so với SPMF, vì "Total time" của SPMF đã gồm ghi output);
`time_no_write_s` KHÔNG gồm ghi file (SPMF để trống). Việc đọc lại hai file output và so từng itemset làm sau khi dừng
đồng hồ, không tính vào thời gian.

**Bộ nhớ.** Nhóm: `Sys.maxrss()` (RSS đỉnh) của tiến trình riêng, kèm số đo nền (`baseline_mem_mb`, tiến trình chỉ warm-up)
và `mem_delta_mb = peak − baseline`. Lưu ý: (1) nền khoảng 290 MB nên với cấu hình nhỏ mức tăng chỉ vài chục MB, `maxrss` là
đỉnh nên không phân biệt được các biến thể gần nhau, hãy dùng thêm cột `alloc_mb` (tổng bộ nhớ cấp phát) và các bộ đếm;
(2) SPMF báo "Max memory usage" của heap JVM, KHÔNG phải RSS, nên không so trực tiếp với số của nhóm.

## Chạy test

```
julia --project test/runtests.jl
```

Các test so với SPMF dùng output đã lưu trong `test/fixtures/spmf/` nên không cần Java.

Output lần chạy test cuối: TODO

## Định dạng input/output (SPMF)

**Input**: mỗi dòng là một giao dịch; các item là số nguyên không âm (item 0 hợp lệ), cách nhau bằng dấu cách.
Item âm hoặc không phải số nguyên bị từ chối với thông báo nêu số dòng.

**Output**: mỗi dòng là một closed frequent itemset, theo sau là độ hỗ trợ (support) sau `#SUP:`.

Ví dụ: CSDL `contextPasquier99` của SPMF (5 giao dịch), `--minsup 40%`.

```
1 3 4
2 3 5
1 2 3 5
2 5
1 2 3 5
```

Kết quả (đã kiểm bằng `demo.jl` và bằng test `Ví dụ chính thức của SPMF`):

```
3 #SUP: 4
1 3 #SUP: 3
2 5 #SUP: 4
2 3 5 #SUP: 3
1 2 3 5 #SUP: 2
```

## Ứng dụng (Chương 3) và thư viện Python

Theo hướng dẫn của giảng viên, phần ứng dụng được viết bằng Python và được dùng thư viện hỗ trợ. **Mọi itemset và
luật kết hợp đều do FPClose của nhóm sinh ra** (`demo.jl` hoặc các hàm trong `src/`); không dùng mlxtend,
efficient-apriori, SPMF hay thư viện khai thác tập phổ biến (FIM) nào khác. Mỗi notebook có ghi chú thư viện nào
dùng để làm gì.

| | Ứng dụng 1: giỏ hàng (UCI Online Retail) | Ứng dụng 2: mẫu trực quan trên ảnh (Caltech-101) |
|---|---|---|
| Notebook | `notebooks/application_01.ipynb` | `notebooks/application_02.ipynb` (ô "Thư viện sử dụng") |
| Code, hướng dẫn | `applications/application_01/` | `applications/app2_image/` (phiên bản ghim trong `requirements.txt`) |

**Ứng dụng 1:** `pandas`, `openpyxl`, `matplotlib`, chỉ dùng để đọc dữ liệu, biến đổi thành giao dịch và trình bày
kết quả (chi tiết ở `applications/application_01/README.md`).

**Ứng dụng 2:**

| Thư viện | Dùng để làm gì |
|---|---|
| OpenCV | Đọc ảnh, chuyển xám, resize; trích đặc trưng SIFT |
| NumPy | Mảng descriptor, tọa độ keypoint, histogram |
| scikit-learn | Chia train/test theo lớp; k-means (`MiniBatchKMeans`) tạo codebook từ thị giác; chọn τ bằng accuracy CV; chuẩn hóa (`StandardScaler`) và phân loại (`LogisticRegression`), accuracy, macro-F1, confusion matrix; ARI ở ô kiểm chứng k-means |
| pandas | Danh sách ảnh, bảng thống kê, bảng mẫu và growth rate |
| Matplotlib | Vẽ keypoint của mẫu lên ảnh; kiểm tra keypoint nằm trong đường viền vật thể |
| SciPy | Đọc file đường viền vật thể `.mat` của Caltech-101 |

Khai thác tập phổ biến đóng ở Ứng dụng 2 dùng `demo.jl` của nhóm (gọi qua `subprocess`); file giao dịch theo định
dạng SPMF chỉ là định dạng dữ liệu, không chạy SPMF.

## Liên kết

- Google Colab: TODO
- Dataset (Hugging Face): https://huggingface.co/datasets/hytrang/fpclose-fim-benchmarks (9 dataset benchmark đã chuẩn hóa; nguồn, SHA-256 và thống kê ở `data/README.md`)
- Ứng dụng 2 (ảnh), Colab: https://colab.research.google.com/github/DRAGON-1312/FPClose/blob/main/notebooks/application_02.ipynb
- Ứng dụng 2 (ảnh), dữ liệu trung gian (Hugging Face): https://huggingface.co/datasets/nnkhlh376/fpclose-app2-caltech
