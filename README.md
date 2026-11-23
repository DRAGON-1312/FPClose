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
│   ├── test_benchmark.jl
│   ├── brute_force.jl
│   └── mutation_record_x.jl
├── notebooks/
│   └── demo.ipynb
├── docs/
│   └── DEVIATIONS.md
└── data/
    ├── toy/
    └── benchmark/
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
| `test/` | Các bài test: `runtests.jl` là điểm vào; `test_correctness.jl`, `test_optimizations.jl` (mọi tổ hợp bật/tắt tối ưu so với bản cơ bản và vét cạn), `test_recovery.jl` (recovery, luật kết hợp, CLI), `test_benchmark.jl`; `brute_force.jl` là bộ đáp án vét cạn; `mutation_record_x.jl` là test đột biến chạy riêng (không nằm trong `runtests.jl`). |
| `scripts/compare_spmf.jl` | Chạy SPMF và bản của nhóm trên cùng input rồi so kết quả (xem mục "So sánh với SPMF"). |
| `scripts/benchmark.jl` | Đo thời gian và bộ nhớ đỉnh khi bật/tắt từng tối ưu, xuất CSV vào `out/` (xem mục "Đo hiệu năng"). |
| `tools/`, `out/` | Không commit (nằm trong `.gitignore`): `tools/spmf.jar` do người dùng tải về, `out/` chứa output tạm và CSV benchmark. |
| `notebooks/demo.ipynb` | Notebook demo (để chạy trên Google Colab). |
| `docs/` | Tài liệu, báo cáo (`docs/Report.pdf` là file PDF duy nhất được commit). `docs/DEVIATIONS.md` liệt kê mọi chỗ code khác hoặc bổ sung so với bài báo, kèm lý do. |
| `demo.jl` | Script chạy thuật toán từ dòng lệnh. |
| `data/toy/` | Dữ liệu nhỏ để kiểm thử và demo (`pasquier99.txt`, `rounding_test.txt`). |
| `data/benchmark/` | Dữ liệu cỡ lớn để đo hiệu năng. Hiện chưa có file nào. |

> Phần `data/` do thành viên khác phụ trách; README chỉ liệt kê những gì đang có trong thư mục.
> Hiện `data/toy/` có `pasquier99.txt` và `rounding_test.txt`.

## Cài đặt môi trường

Yêu cầu: Julia ≥ 1.9.

```
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

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
julia --project scripts/compare_spmf.jl --table --dir out/extra_toy --minsups 60%,20%,2%
```

- Chế độ `closed`: FPClose của nhóm so với SPMF `FPClose` (`java -jar tools/spmf.jar run FPClose ...`).
- Chế độ `all`: recovery (`src/recovery.jl`) so với SPMF **`FPGrowth_itemsets`** (thuật toán FP-Growth xuất mọi
  frequent itemset của SPMF; `java -jar tools/spmf.jar run FPGrowth_itemsets <input> <output> 40%`).
- Output của hai phía được chuẩn hóa (bỏ dòng metadata `@...`, sắp item trong từng itemset, so theo tập
  `(itemset, support)`), rồi in số dòng khớp, các dòng chỉ có ở một phía và các dòng khác support. Mã thoát
  là 0 khi khớp hoàn toàn, 1 khi có lệch, 2 khi SPMF lỗi hoặc tham số sai.
- `--table` in bảng markdown (file, minsup, số giao dịch, số closed FI, số khớp, tỉ lệ khớp, số all-FI, số khớp,
  tỉ lệ khớp) và ghi `out/compare_table.csv`. Tỉ lệ khớp = số dòng khớp hoàn toàn / số dòng của hợp hai bên.
- `--baseline` chạy FPClose bản cơ bản (không FP-array, không kết thúc sớm); `--jar` đổi đường dẫn jar.
- Output thô nằm ở `out/spmf_<chế độ>_<tên>_<minsup>.txt` và `out/ours_<chế độ>_<tên>_<minsup>.txt`.

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

## Chạy test

```
julia --project test/runtests.jl
```

Output lần chạy test cuối: TODO

## Định dạng input/output (SPMF)

**Input**: mỗi dòng là một giao dịch; các item là số nguyên, cách nhau bằng dấu cách.

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

## Liên kết

- Google Colab: TODO
- Dataset (Hugging Face/Kaggle): TODO
