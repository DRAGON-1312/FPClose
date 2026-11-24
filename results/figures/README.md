# Biểu đồ Chương 2

Sinh bởi `scripts/plot_results.jl` từ các CSV trong `results/`, không đo lại. Mỗi hình có hai bản: `.png` (300 dpi) và
`.pdf` (dạng vector, nên dùng cho LaTeX). Kích thước: hình một cột rộng khoảng 3,5 in, hình lưới hoặc hình rộng khoảng 7 in
(khổ hai cột IEEE).

Tất cả số liệu được đo trên cùng một máy, nhãn **MSI** (xem `results/ENVIRONMENT.md`: CPU, RAM, phiên bản Julia/Java,
SHA của spmf.jar, timeout 600 s, 3 lần đo cho mỗi cấu hình). Cột `machine` trong mọi CSV đều là MSI.

## Quy ước chung

- **Trung vị**: mỗi điểm là trung vị của các lần đo có `status = OK` (thường 3 lần). Script tự tính từ CSV từng lần đo.
  Lưu ý: các file `*_summary.csv` do `run_benchmark_grid.jl` sinh ra lấy giá trị **nhỏ nhất**, nên số trên hình có thể hơi
  khác số trong các file đó.
- **TIMEOUT/SKIPPED/FAILED**: một cấu hình không có lần OK nào sẽ không được vẽ, và script in cảnh báo ra console.
- **Ghi file**: mọi hình so sánh với SPMF dùng `time_with_write_s` cho cả hai bên (đọc + khai thác + ghi output). SPMF
  luôn ghi file, và giá trị của nó là "Total time" do SPMF tự in.
- **Màu và marker cố định**: FPClose (nhóm) màu xanh với marker tròn ●; SPMF màu cam với marker tam giác ▲.
- **Trục minsup của các hình runtime** đặt các điểm **cách đều nhau** theo thứ tự 1..k, không tỷ lệ với giá trị minsup.
  Nhãn trục là các mức minsup đã đo, giảm dần từ trái sang phải. Cách này tránh đè chữ khi các mức sát nhau, ví dụ
  0,3 / 0,25 / 0,2 hoặc 1,5 / 1,25 / 1. Vì vậy khoảng cách ngang giữa hai điểm không phản ánh độ chênh của minsup.
  Riêng hình `itemsets_vs_minsup` vẫn dùng trục minsup thang log, vì đó là trục chung cho mọi dataset.
- **Trục y thang log**: mốc theo dãy 1–2–5 (…; 0,02; 0,05; 0,1; 0,2; 0,5; 1; 2; 5; 10; …) trong khoảng dữ liệu, nhãn là
  số thập phân thường, không dùng dạng 10^x. Nếu dải dữ liệu cho ra hơn 8 mốc thì chỉ giữ các mốc 1, 10, 100…
- **Dấu thập phân** là dấu phẩy ở mọi nhãn trục x và y, kể cả trục tuyến tính (ví dụ "0,8", "12,5").

## Danh sách hình

| File (`.png` + `.pdf`) | CSV nguồn | Cột dùng | Trục hoành | Trục tung | Cách tính |
|---|---|---|---|---|---|
| `runtime_<dataset>` (mỗi dataset một hình) | `runtime/grid_runtime.csv` | `time_with_write_s` (nhóm và SPMF), `minsup_pct`, `tool`, `status` | minsup (%), **trục thứ tự**: các mức đặt cách đều 1..k, nhãn là giá trị minsup giảm dần | Thời gian (s), **thang log**, mốc 1–2–5 | Trung vị theo (dataset, minsup, tool). Hai đường: FPClose (nhóm) và SPMF |
| `runtime_grid` | như trên | như trên | như trên (mỗi ô một dataset) | như trên | Lưới 3 cột gồm mọi dataset. Chú giải chỉ ở ô đầu tiên |
| `itemsets_vs_minsup` | `runtime/grid_runtime.csv` | `n_itemsets` (của nhóm, thiếu thì lấy của SPMF) | minsup (%), **thang log**, giảm dần, mốc 1–2–5 | Số tập phổ biến đóng, **thang log** | Tiêu đề "Số tập phổ biến đóng theo minsup". Mỗi dataset một đường |
| `memory_variants_grid` | `memory/basic_vs_optimized.csv` | `mem_delta_mb`, `variant` | Biến thể (**trục phân loại**) | Bộ nhớ thực dùng (MB), **tuyến tính** từ 0 | Trung vị theo (dataset, variant), đo tại minsup giữa lưới (ghi trong tiêu đề ô) |
| `time_variants_grid` | `memory/basic_vs_optimized.csv` | `mine_s` | Biến thể (**trục phân loại**) | Thời gian khai thác (s), **tuyến tính** từ 0 | Trung vị. Chỉ tính thời gian khai thác, không gồm đọc/ghi |
| `ablation_time_relative` | `memory/basic_vs_optimized.csv` | `mine_s` | Biến thể (**trục phân loại**) | Thời gian / optimized, **tuyến tính** từ 0 | Với mỗi biến thể, lấy `mine_s / mine_s(optimized)` trên từng dataset rồi tính trung bình nhân qua các dataset. Đường nét đứt ở mức 1 |
| `scalability_time` | `scalability/scalability.csv` | `fraction_pct`, `minsup_pct`, `time_with_write_s` | Phần trăm giao dịch của Retail (%), **tuyến tính**, mốc tại các mức đã đo | Thời gian (s), **tuyến tính** từ 0 | Trung vị. Mỗi minsup một cặp đường nhóm/SPMF |
| `txlen_time` | `txlen/txlen.csv` | `avg_length`, `minsup_pct`, `time_with_write_s` | Độ dài giao dịch trung bình, **tuyến tính**, mốc tại các mức đã đo | Thời gian (s), **thang log**, mốc 1–2–5 | Trung vị. Mỗi minsup một cặp đường nhóm/SPMF |
| `txlen_itemsets` | `txlen/txlen.csv` | `avg_length`, `minsup_pct`, `n_itemsets` | Độ dài giao dịch trung bình, **tuyến tính** | Số tập phổ biến đóng, **thang log**, mốc 1–2–5 | Nhóm vẽ thành đường; SPMF chỉ vẽ marker rỗng (hai bên trùng nhau nếu kết quả khớp) |
| `time_breakdown` | `runtime/grid_runtime.csv`, `memory/basic_vs_optimized.csv` | `read_s`, `mine_s`, `write_s`, `time_no_write_s` (runtime, `ours_opt`); `minsup_pct` (memory, `optimized`) | Dataset kèm minsup (**trục phân loại**) | Tỷ lệ thời gian (%), **tuyến tính** 0–100 | Cột chồng 100% cho mỗi dataset, đo tại minsup của memory CSV. Xem mục bên dưới |

`ours_opt` là giá trị của cột `tool` trong CSV (mã của cài đặt nhóm), không phải nhãn hiển thị trên hình.

### Phân rã thời gian (`time_breakdown`)

- Mức minsup của mỗi dataset lấy theo `memory/basic_vs_optimized.csv` (biến thể `optimized`, minsup giữa lưới). Thời gian
  lấy từ dòng `ours_opt` cùng dataset và minsup trong `runtime/grid_runtime.csv`. Nếu minsup đó không có trong runtime CSV
  thì dataset bị bỏ và script in cảnh báo.
- Ý nghĩa các cột (theo `scripts/run_benchmark_grid.jl`): `read_s` chỉ gồm `read_spmf` (đọc file). `mine_s` là toàn bộ
  lời gọi `fpclose`, **gồm cả dựng FP-tree** (`build_fptree`). `recover_s` là thời gian khôi phục mọi tập phổ biến, chỉ
  có ở chế độ all, và không có cột riêng trong CSV.
- `grid_runtime.csv` đã có cột tách riêng, nên cả ba phần đều lấy từ cùng một lần đo runtime:
  - **dựng FP-tree + khai thác** = `mine_s`;
  - **đọc file (+ khôi phục nếu có)** = `read_s` + max(`time_no_write_s` − `read_s` − `mine_s`, 0). Phần dư là thời gian
    khôi phục, xấp xỉ 0 ở chế độ closed;
  - **ghi file** = `write_s`.

  Mỗi phần là trung vị riêng của các lần chạy OK.
- Nếu một CSV runtime không có các cột tách này, script chuyển sang **ước lượng ghép từ hai lần đo riêng**:
  dựng FP-tree + khai thác = `mine_s` lấy từ memory CSV; đọc file (+ khôi phục nếu có) = max(`time_no_write_s` − `mine_s`, 0);
  ghi file = `time_with_write_s` − `time_no_write_s`. Bảng `results/summary/time_breakdown.md` ghi rõ đã dùng cách nào.
- Hình vẽ tỷ lệ % trên tổng ba phần, vì thời gian tuyệt đối giữa các dataset chênh nhau nhiều bậc. Số giây tuyệt đối và
  thời gian của SPMF (`time_with_write_s`) nằm trong `results/summary/time_breakdown.(csv|md)`.

Trong các hình lưới, ô thứ k ứng với dataset thứ k theo thứ tự xuất hiện trong CSV. Tên dataset không được hard-code trong
script.

### Biến thể trong hình memory/ablation

| Nhãn trên trục | `variant` trong CSV | Ý nghĩa |
|---|---|---|
| basic | `basic` | Tắt mọi tối ưu |
| paper | `paper` | Chỉ giữ cắt nhánh dòng 8 như trong bài báo |
| optimized | `optimized` | Mặc định của `fpclose` (bật mọi tối ưu), dùng làm mốc so sánh |
| −cắt dòng 8 | `opt_no_prune_line8` | optimized nhưng tắt cắt nhánh dòng 8 |
| −FP-array | `opt_no_fparray` | optimized nhưng tắt FP-array |
| −dừng sớm | `opt_no_early_termination` | optimized nhưng tắt dừng sớm |
| −đếm chính xác | `opt_no_exact_count` | optimized nhưng tắt đếm chính xác |
| −CFI-tree rút gọn | `opt_no_reduced_cfitree` | optimized nhưng tắt CFI-tree rút gọn |

Màu cột: optimized màu xanh (cùng màu của nhóm), các biến thể ablation màu xanh nhạt, basic/paper màu xám.

## Bộ nhớ: đọc thế nào, và vì sao không so với SPMF

- Hình bộ nhớ vẽ **bộ nhớ thuật toán thực dùng** `mem_delta_mb = max(peak RSS − baseline RSS, 0)`, không vẽ RSS thô.
  RSS thô (`peak_mem_mb`, khoảng 285 MB) phần lớn là nền của tiến trình Julia: runtime, các gói và mã đã biên dịch.
  Baseline được đo ngay sau bước warm-up, trước khi đọc dữ liệu. Mỗi lần đo chạy trong một tiến trình riêng.
- Giá trị 0 (hoặc cột không nhìn thấy) nghĩa là phần tăng thêm nhỏ hơn mức đỉnh của nền, nên không phân biệt được. Giá trị
  này không có nghĩa là thuật toán không dùng bộ nhớ.
- **Số bộ nhớ của SPMF không được đưa vào các hình này.** Cột `peak_mem_mb` của SPMF là "Max memory usage" do SPMF tự đo
  (heap JVM qua MemoryLogger). Đây không phải RSS và cũng không trừ nền, nên hai con số khác bản chất và không so trực tiếp
  được. Nếu cần nêu bộ nhớ SPMF trong báo cáo, hãy để ở bảng riêng và ghi rõ là heap JVM.

## Tái tạo

Cài môi trường một lần:

```
julia --project=scripts/plot -e "using Pkg; Pkg.add([\"CSV\",\"DataFrames\",\"Plots\"])"
```

Sau đó chạy:

```
julia --project=scripts/plot scripts/plot_results.jl                      # mọi hình → results/figures/
julia --project=scripts/plot scripts/plot_results.jl --only runtime,txlen # chỉ một số nhóm
julia --project=scripts/plot scripts/summarize_results.jl                 # bảng → results/summary/
```

Các tùy chọn: `--only runtime,itemsets,memory,scalability,txlen,breakdown`, `--results <thư mục>`, `--outdir <thư mục>`.
Code dùng chung cho hai script nằm ở `scripts/plot/results_common.jl`.
