# Môi trường chạy thực nghiệm

Ghi tự động bởi `scripts/run_benchmark_grid.jl` ở lần chạy gần nhất (mỗi dòng của các CSV có cột `machine`).

| Mục | Giá trị |
|---|---|
| Cập nhật lúc (UTC) | 2026-11-24 03:07:09 |
| Nhãn máy | HYT |
| Hệ điều hành | NT (x86_64-w64-mingw32) |
| CPU | 13th Gen Intel(R) Core(TM) i5-13500H |
| Số luồng logic | 16 |
| RAM | 15.7 GiB |
| Julia | 1.13.4 |
| Java | openjdk version "25.0.5.1" 2026-11-17 LTS |
| spmf.jar SHA-256 | `bb371b99b3bfd58fbce6b92e0ea3ccda5f9d1fd173bfe8e40f177672117159ba` |
| JVM heap (-Xmx) | 4g |
| Commit | 2735ca6 (có thay đổi chưa commit) |
| Số lần đo mỗi cấu hình | 3 (tổng hợp lấy nhỏ nhất) |
| Timeout mỗi lần chạy | 600 s |
| Chế độ | đầy đủ |

Chưa ghi tự động (cần ghi tay trước khi chạy chính thức): chế độ nguồn/hiệu năng của máy, ứng dụng nền đang mở,
nhiệt độ. Mọi số liệu trên cùng một biểu đồ phải đo trên cùng máy.

**Ghi chú.** File này ghi môi trường của lần chạy ngày 2026-11-24 trên máy HYT. Kết quả từ máy này còn được dùng trong
báo cáo là `correctness/grid_correctness_fi_all_levels.csv` (so mọi frequent itemset với SPMF). Mã nguồn `src/` không
thay đổi từ commit 5434a47 (lần đo hiệu năng trên máy MSI) đến commit 5c51a8e. Mọi số liệu thời gian và bộ nhớ trong
báo cáo được đo trên máy MSI (`results/ENVIRONMENT.md`).
