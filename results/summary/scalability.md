# Khả năng mở rộng theo kích thước dữ liệu

Nguồn: `results/scalability/scalability.csv`. Thời gian: trung vị các lần chạy OK (thường 3 lần), cột `time_with_write_s` = đọc + khai thác + GHI file output cho cả hai công cụ (SPMF luôn ghi file). `t_ours_nowrite` = nhóm không tính ghi file (SPMF không tách được). Tỷ số = SPMF / ours (> 1 nghĩa là ours nhanh hơn).

| minsup (%) | % giao dịch | Dataset | Số giao dịch | Số closed itemset | Ours (s) | Ours không ghi file (s) | SPMF (s) | SPMF / ours |
|---:|---:|---|---:|---:|---:|---:|---:|---:|
| 0,1 | 10 | retail_p010 | 8816 | 8394 | 0,07464 | 0,07035 | 0,161 | 2,16 |
| 0,1 | 25 | retail_p025 | 22040 | 7585 | 0,1405 | 0,1349 | 0,23 | 1,64 |
| 0,1 | 50 | retail_p050 | 44081 | 7601 | 0,2787 | 0,2744 | 0,432 | 1,55 |
| 0,1 | 75 | retail_p075 | 66121 | 7590 | 0,5173 | 0,513 | 0,469 | 0,91 |
| 0,1 | 100 | retail_p100 | 88162 | 7572 | 0,7549 | 0,7508 | 0,561 | 0,74 |
| 0,05 | 10 | retail_p010 | 8816 | 19579 | 0,1237 | 0,1135 | 0,22 | 1,78 |
| 0,05 | 25 | retail_p025 | 22040 | 18925 | 0,2296 | 0,2196 | 0,297 | 1,29 |
| 0,05 | 50 | retail_p050 | 44081 | 19216 | 0,4253 | 0,4146 | 0,453 | 1,07 |
| 0,05 | 75 | retail_p075 | 66121 | 19119 | 0,6931 | 0,6819 | 0,611 | 0,88 |
| 0,05 | 100 | retail_p100 | 88162 | 19114 | 0,9001 | 0,8882 | 0,761 | 0,85 |
