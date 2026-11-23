# Thời gian chạy và bộ nhớ trên lưới 56 cấu hình

Sinh bởi `scripts/run_benchmark_grid.jl --only runtime` (cùng cách đo dùng cho `results/scalability/` và `results/txlen/`).

- `grid_runtime.csv`: MỖI DÒNG MỘT LẦN ĐO (dataset × minsup × công cụ × lần). Nhóm và SPMF chạy xen kẽ trên cùng file,
  cùng minsup, cùng máy.
- `grid_runtime_summary.csv`: tổng hợp theo (dataset, minsup, công cụ): thời gian nhỏ nhất của các lần OK, bộ nhớ của lần
  nhanh nhất, `match_rate` lấy từ `results/correctness/grid_correctness.csv`, số lần OK.

## Công cụ (cột `tool`)

| tool | Ý nghĩa |
|---|---|
| `ours_opt` | `fpclose` của nhóm với tùy chọn mặc định (mọi tối ưu bật) |
| `spmf` | SPMF `FPClose` (`java -Xmx4g -jar spmf.jar run FPClose ...`) |

## Cột nào GỒM ghi file, cột nào KHÔNG

| Cột | Gồm ghi output ra file? | Ghi chú |
|---|---|---|
| `time_with_write_s` | **CÓ** | Nhóm: `read_s + mine_s + write_s` (`write_spmf`, không sắp xếp kết quả). SPMF: "Total time" do SPMF tự in, đã gồm đọc và ghi output. Dùng cột này để so nhóm với SPMF. |
| `time_no_write_s` | KHÔNG | Nhóm: `read_s + mine_s`. SPMF không tách được nên để trống. |
| `read_s` | không | `read_spmf` (chỉ nhóm) |
| `mine_s` | không | `fpclose` (chỉ nhóm) |
| `write_s` | có | `write_spmf` (chỉ nhóm) |
| `process_wall_s` | có | Thời gian cả tiến trình. SPMF: gồm khởi động JVM. Nhóm: gồm khởi động Julia, nạp gói và warm-up, KHÔNG dùng để so sánh. |

Việc đọc lại hai file output và so từng itemset làm SAU khi đã dừng đồng hồ, không tính vào bất kỳ cột thời gian nào.

## Bộ nhớ

| Cột | Nghĩa |
|---|---|
| `peak_mem_mb` | Nhóm: `Sys.maxrss()` (RSS đỉnh của tiến trình) sau lần đo. SPMF: "Max memory usage" do SPMF tự in (heap JVM, **không phải RSS**, nên không so trực tiếp với số của nhóm). |
| `baseline_mem_mb` | Nhóm: `Sys.maxrss()` ngay sau warm-up, trước khi đọc dữ liệu (số đo nền: Julia, gói và mã đã biên dịch). |
| `mem_delta_mb` | Nhóm: `max(peak - baseline, 0)`, phần bộ nhớ tăng thêm do dữ liệu và khai thác. Bằng 0 nghĩa là mức tăng nhỏ hơn đỉnh nền (không phân biệt được). |
| `mem_source` | `rss_maxrss` hoặc `spmf_memorylogger` |

Mỗi lần đo của nhóm chạy trong tiến trình Julia riêng nên `Sys.maxrss` không lẫn giữa các lần đo.

## Trạng thái (cột `status`)

`OK`, `TIMEOUT` (quá `--timeout`, mặc định 600 s), `SKIPPED` (bỏ qua vì công cụ đó đã TIMEOUT ở minsup cao hơn của cùng dataset),
`FAILED` (lỗi; được chạy lại khi chạy tiếp).
