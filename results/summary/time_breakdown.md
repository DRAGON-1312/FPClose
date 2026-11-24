# Phân rã thời gian của FPClose (ours)

Cả ba phần lấy từ cùng một lần đo trong `results/runtime/grid_runtime.csv`, vì file này đã có cột tách riêng `read_s`, `mine_s` và `write_s` (xem `scripts/run_benchmark_grid.jl`). Trong đó `read_s` chỉ là `read_spmf` (đọc file); `mine_s` là toàn bộ lời gọi `fpclose`, gồm cả dựng FP-tree (`build_fptree`); `recover_s` (khôi phục mọi tập phổ biến, chỉ có ở chế độ all) không có cột riêng trong CSV. Đọc file (+ khôi phục nếu có) = read_s + max(time_no_write_s − read_s − mine_s, 0), trong đó phần dư là khôi phục, ≈ 0 ở chế độ closed. Dựng FP-tree + khai thác = mine_s. Ghi file = write_s. Mức minsup lấy theo `results/memory/basic_vs_optimized.csv`. Cột "mine_s (memory)" là `mine_s` đo riêng trong phần memory, để đối chiếu; nếu hai cột mine_s chênh nhau nhiều thì kết quả đo không ổn định.

Mỗi phần là trung vị riêng của các lần chạy OK, nên tổng ba phần có thể lệch nhẹ so với trung vị của `time_with_write_s`. Phần trăm được tính trên tổng ba phần. SPMF = `time_with_write_s` của SPMF (trung vị). Phương pháp: runtime: read_s, mine_s, write_s.

| Dataset | minsup (%) | Đọc file (+ khôi phục nếu có) (s) | Dựng FP-tree + khai thác (s) | Ghi file (s) | Tổng 3 phần (s) | Ours có ghi file (s) | SPMF (s) | % đọc file (+ khôi phục nếu có) | % dựng FP-tree + khai thác | % ghi file | mine_s (memory) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chess | 75 | 0,00074 | 0,06825 | 0,00827 | 0,07726 | 0,07722 | 0,182 | 1 | 88,3 | 10,7 | 0,07131 |
| mushrooms | 7 | 0,00118 | 0,08282 | 0,00674 | 0,09074 | 0,09074 | 0,284 | 1,3 | 91,3 | 7,4 | 0,08358 |
| retail | 0,2 | 0,01014 | 0,2863 | 0,002 | 0,2984 | 0,2985 | 0,441 | 3,4 | 95,9 | 0,7 | 0,3019 |
| T10I4D100K | 0,2 | 0,01109 | 0,8409 | 0,00985 | 0,8618 | 0,8618 | 0,799 | 1,3 | 97,6 | 1,1 | 0,8813 |
| accidents | 70 | 0,1267 | 0,4905 | 0,00099 | 0,6182 | 0,6183 | 0,932 | 20,5 | 79,3 | 0,2 | 0,456 |
| connect | 85 | 0,01549 | 0,2149 | 0,00666 | 0,237 | 0,2366 | 0,414 | 6,5 | 90,7 | 2,8 | 0,2305 |
| kosarak | 0,4 | 0,1252 | 1,86 | 0,00241 | 1,988 | 1,987 | 2,027 | 6,3 | 93,6 | 0,1 | 1,779 |
| pumsb_star | 50 | 0,01618 | 0,1436 | 0,00086 | 0,1606 | 0,1606 | 0,346 | 10,1 | 89,4 | 0,5 | 0,1424 |
| T40I10D100K | 2 | 0,02833 | 4,445 | 0,00185 | 4,475 | 4,475 | 5,345 | 0,6 | 99,3 | 0 | 4,822 |
