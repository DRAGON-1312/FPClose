# Khả năng mở rộng theo kích thước dữ liệu

Nguồn: `results/scalability/scalability.csv`. Thời gian: trung vị các lần chạy OK (thường 3 lần), cột `time_with_write_s` = đọc + khai thác + GHI file output cho cả hai công cụ (SPMF luôn ghi file). `t_ours_nowrite` = nhóm không tính ghi file (SPMF không tách được). Tỷ số = SPMF / ours (> 1 nghĩa là ours nhanh hơn).

| minsup (%) | % giao dịch | Dataset | Số giao dịch | Số closed itemset | Ours (s) | Ours không ghi file (s) | SPMF (s) | SPMF / ours |
|---:|---:|---|---:|---:|---:|---:|---:|---:|
| 0,1 | 10 | retail_p010 | 8816 | 8394 | 0,07016 | 0,06547 | 0,168 | 2,39 |
| 0,1 | 25 | retail_p025 | 22040 | 7585 | 0,1499 | 0,1457 | 0,236 | 1,57 |
| 0,1 | 50 | retail_p050 | 44081 | 7601 | 0,2753 | 0,2705 | 0,437 | 1,59 |
| 0,1 | 75 | retail_p075 | 66121 | 7590 | 0,4284 | 0,424 | 0,5 | 1,17 |
| 0,1 | 100 | retail_p100 | 88162 | 7572 | 0,469 | 0,4645 | 0,574 | 1,22 |
| 0,05 | 10 | retail_p010 | 8816 | 19579 | 0,1771 | 0,1669 | 0,231 | 1,3 |
| 0,05 | 25 | retail_p025 | 22040 | 18925 | 0,2914 | 0,2811 | 0,299 | 1,03 |
| 0,05 | 50 | retail_p050 | 44081 | 19216 | 0,455 | 0,4452 | 0,455 | 1 |
| 0,05 | 75 | retail_p075 | 66121 | 19119 | 0,6658 | 0,6544 | 0,618 | 0,93 |
| 0,05 | 100 | retail_p100 | 88162 | 19114 | 0,9615 | 0,9513 | 0,757 | 0,79 |
