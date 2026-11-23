# Phân rã thời gian của FPClose (ours)

Cả ba phần lấy từ cùng một lần đo trong `results/runtime/grid_runtime.csv`, vì file này đã có cột tách riêng `read_s`, `mine_s` và `write_s` (xem `scripts/run_benchmark_grid.jl`). Trong đó `read_s` chỉ là `read_spmf` (đọc file); `mine_s` là toàn bộ lời gọi `fpclose`, gồm cả dựng FP-tree (`build_fptree`); `recover_s` (khôi phục mọi tập phổ biến, chỉ có ở chế độ all) không có cột riêng trong CSV. Đọc file (+ khôi phục nếu có) = read_s + max(time_no_write_s − read_s − mine_s, 0), trong đó phần dư là khôi phục, ≈ 0 ở chế độ closed. Dựng FP-tree + khai thác = mine_s. Ghi file = write_s. Mức minsup lấy theo `results/memory/basic_vs_optimized.csv`. Cột "mine_s (memory)" là `mine_s` đo riêng trong phần memory, để đối chiếu; nếu hai cột mine_s chênh nhau nhiều thì kết quả đo không ổn định.

Mỗi phần là trung vị riêng của các lần chạy OK, nên tổng ba phần có thể lệch nhẹ so với trung vị của `time_with_write_s`. Phần trăm được tính trên tổng ba phần. SPMF = `time_with_write_s` của SPMF (trung vị). Phương pháp: runtime: read_s, mine_s, write_s.

| Dataset | minsup (%) | Đọc file (+ khôi phục nếu có) (s) | Dựng FP-tree + khai thác (s) | Ghi file (s) | Tổng 3 phần (s) | Ours có ghi file (s) | SPMF (s) | % đọc file (+ khôi phục nếu có) | % dựng FP-tree + khai thác | % ghi file | mine_s (memory) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chess | 75 | 0,00909 | 0,07185 | 0,00864 | 0,08958 | 0,08955 | 0,185 | 10,1 | 80,2 | 9,6 | 0,0721 |
| mushrooms | 7 | 0,00986 | 0,1105 | 0,0066 | 0,127 | 0,1269 | 0,251 | 7,8 | 87 | 5,2 | 0,1089 |
| retail | 0,2 | 0,1086 | 0,4194 | 0,00249 | 0,5305 | 0,5305 | 0,459 | 20,5 | 79,1 | 0,5 | 0,3718 |
| T10I4D100K | 0,2 | 0,1062 | 1,026 | 0,01122 | 1,143 | 1,289 | 0,786 | 9,3 | 89,7 | 1 | 0,9676 |
| accidents | 70 | 1,152 | 0,9279 | 0,00106 | 2,081 | 2,077 | 0,901 | 55,4 | 44,6 | 0,1 | 0,8805 |
| connect | 85 | 0,2958 | 0,3641 | 0,00745 | 0,6674 | 0,6676 | 0,4 | 44,3 | 54,6 | 1,1 | 0,3558 |
| kosarak | 0,4 | 1,156 | 2,677 | 0,00252 | 3,836 | 3,836 | 2,146 | 30,1 | 69,8 | 0,1 | 2,632 |
| pumsb_star | 50 | 0,2488 | 0,2722 | 0,00089 | 0,5219 | 0,5214 | 0,349 | 47,7 | 52,1 | 0,2 | 0,2524 |
| T40I10D100K | 2 | 0,3981 | 6,298 | 0,00198 | 6,698 | 6,698 | 5,751 | 5,9 | 94 | 0 | 6,208 |
