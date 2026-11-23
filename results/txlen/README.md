# Thí nghiệm ảnh hưởng của độ dài giao dịch (txlen)

Dữ liệu: `data/synthetic/len05.txt` … `len30.txt` (10.000 giao dịch, 500 item, độ dài trung bình 5, 10, 15, 20, 25, 30,
nhận ra theo các mức lồng nhau; xem `data/README.md`). Kết quả: `txlen.csv` (từng lần đo) và `txlen_summary.csv`
(nhỏ nhất của các lần). Cột thời gian và bộ nhớ có cùng nghĩa như `results/runtime/` (xem `results/runtime/README.md`).

## Chọn mức minsup

Một minsup tương đối dùng chung cho cả sáu độ dài. Chạy thử bằng
`julia --project=. scripts/run_benchmark_grid.jl --only txlen_pilot --txlen-minsups 5,2,1,0.5,0.2 --timeout 90`
(mỗi ô một lần, nhóm và SPMF; kết quả ở `pilot.csv`). Số closed itemsets (và thời gian nhóm, giây):

| minsup | len05 | len10 | len15 | len20 | len25 | len30 |
|---|---:|---:|---:|---:|---:|---:|
| 5% | 18 (0,02) | 43 (0,05) | 69 (0,05) | 96 (0,09) | 163 (0,12) | 476 (0,41) |
| 2% | 68 (0,02) | 208 (0,04) | 546 (0,15) | 645 (0,30) | 698 (0,36) | 750 (0,56) |
| 1% | 174 (0,03) | 713 (0,12) | 868 (0,21) | 1.144 (0,33) | 1.689 (0,34) | 4.020 (0,57) |
| 0,5% | 470 (0,03) | 1.244 (0,08) | 2.134 (0,20) | 5.177 (0,36) | 9.135 (0,51) | 18.038 (0,91) |
| 0,2% | 914 (0,04) | 3.720 (0,17) | 9.556 (0,32) | 26.428 (0,69) | 81.828 (1,71) | 146.134 (3,04) |

**Chọn 0,5% và 0,2%.**
- Mọi ô của cả hai công cụ chạy xong rất nhanh (nhóm tối đa 3,0 s, SPMF tối đa 3,4 s ở len30, 0,2%), còn dư xa so với
  timeout 600 s, nên không bị TIMEOUT làm mất điểm trên đường cong.
- Ở 0,5% và 0,2% số tập đóng tăng mạnh theo độ dài (0,5%: 470 → 18.038; 0,2%: 914 → 146.134), nên ảnh hưởng của độ dài
  giao dịch hiện rõ; ở 5% và 2% số tập đóng gần như không đổi (hoặc rất nhỏ) nên đường cong gần phẳng và ít thông tin.
- Hai mức cho hai "độ khó" khác nhau để xem xu hướng có bền theo minsup hay không.
- 1% cũng chạy được nhưng nằm giữa hai nhóm trên, không thêm thông tin; các mức thấp hơn 0,2% chưa thử.

Đổi mức bằng `--txlen-minsups` (ví dụ `--txlen-minsups 1,0.5`).
