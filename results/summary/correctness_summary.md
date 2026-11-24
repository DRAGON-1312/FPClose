# Tổng hợp tính đúng đắn

Nguồn: `results/correctness/grid_correctness.csv`, `results/correctness/toy_vs_spmf.csv`, `results/reference/spmf_check.csv`. Một cấu hình **khớp** khi status = OK và không có itemset chỉ một bên có (`only_ours = only_spmf = 0`) và không có itemset lệch support (`n_diff_support = 0`). Với toy: `n_ours = n_spmf = n_match`. Với spmf_check: cột `match` (chỉ so số lượng). Tổng số itemset = tổng `n_ours` (hoặc `n_closed_itemsets`) trên các cấu hình.

| Nguồn so sánh | Dataset | Chế độ | Số cấu hình | Tổng số itemset | Số cấu hình khớp | Tỷ lệ khớp (%) | Ghi chú |
|---|---|---|---:|---:|---:|---:|---|
| nhóm vs SPMF (từng itemset) | chess | tập đóng | 7 | 190309 | 7 | 100 |  |
| nhóm vs SPMF (từng itemset) | mushrooms | tập đóng | 7 | 83281 | 7 | 100 |  |
| nhóm vs SPMF (từng itemset) | retail | tập đóng | 6 | 95417 | 6 | 100 |  |
| nhóm vs SPMF (từng itemset) | T10I4D100K | tập đóng | 6 | 196186 | 6 | 100 |  |
| nhóm vs SPMF (từng itemset) | accidents | tập đóng | 6 | 43368 | 6 | 100 |  |
| nhóm vs SPMF (từng itemset) | connect | tập đóng | 6 | 87877 | 6 | 100 |  |
| nhóm vs SPMF (từng itemset) | kosarak | tập đóng | 6 | 54138 | 6 | 100 |  |
| nhóm vs SPMF (từng itemset) | pumsb_star | tập đóng | 6 | 9785 | 6 | 100 |  |
| nhóm vs SPMF (từng itemset) | T40I10D100K | tập đóng | 6 | 88637 | 6 | 100 |  |
| nhóm vs SPMF (từng itemset) | TỔNG | tập đóng | 56 | 848998 | 56 | 100 |  |
| nhóm vs SPMF (từng itemset) | chess | mọi tập phổ biến | 1 | 622 | 1 | 100 |  |
| nhóm vs SPMF (từng itemset) | mushrooms | mọi tập phổ biến | 1 | 53583 | 1 | 100 |  |
| nhóm vs SPMF (từng itemset) | retail | mọi tập phổ biến | 1 | 159 | 1 | 100 |  |
| nhóm vs SPMF (từng itemset) | T10I4D100K | mọi tập phổ biến | 1 | 385 | 1 | 100 |  |
| nhóm vs SPMF (từng itemset) | accidents | mọi tập phổ biến | 1 | 31 | 1 | 100 |  |
| nhóm vs SPMF (từng itemset) | connect | mọi tập phổ biến | 1 | 2201 | 1 | 100 |  |
| nhóm vs SPMF (từng itemset) | kosarak | mọi tập phổ biến | 1 | 383 | 1 | 100 |  |
| nhóm vs SPMF (từng itemset) | pumsb_star | mọi tập phổ biến | 1 | 29 | 1 | 100 |  |
| nhóm vs SPMF (từng itemset) | T40I10D100K | mọi tập phổ biến | 1 | 316 | 1 | 100 |  |
| nhóm vs SPMF (từng itemset) | TỔNG | mọi tập phổ biến | 9 | 57709 | 9 | 100 |  |
| toy: nhóm vs SPMF (từng itemset) | toy (6 CSDL) | tập đóng | 18 | 516 | 18 | 100 |  |
| toy: nhóm vs SPMF (từng itemset) | toy (6 CSDL) | mọi tập phổ biến | 18 | 667 | 18 | 100 |  |
| SPMF vs số tham chiếu (chỉ số lượng) | chess | tập đóng | 7 | 190309 | 7 | 100 | so số lượng tập đóng của SPMF với số tham chiếu, không so từng itemset |
| SPMF vs số tham chiếu (chỉ số lượng) | mushrooms | tập đóng | 7 | 83281 | 7 | 100 | so số lượng tập đóng của SPMF với số tham chiếu, không so từng itemset |
| SPMF vs số tham chiếu (chỉ số lượng) | retail | tập đóng | 6 | 95417 | 6 | 100 | so số lượng tập đóng của SPMF với số tham chiếu, không so từng itemset |
| SPMF vs số tham chiếu (chỉ số lượng) | T10I4D100K | tập đóng | 6 | 196186 | 6 | 100 | so số lượng tập đóng của SPMF với số tham chiếu, không so từng itemset |
| SPMF vs số tham chiếu (chỉ số lượng) | accidents | tập đóng | 6 | 43368 | 6 | 100 | so số lượng tập đóng của SPMF với số tham chiếu, không so từng itemset |
| SPMF vs số tham chiếu (chỉ số lượng) | connect | tập đóng | 6 | 87877 | 6 | 100 | so số lượng tập đóng của SPMF với số tham chiếu, không so từng itemset |
| SPMF vs số tham chiếu (chỉ số lượng) | kosarak | tập đóng | 6 | 54138 | 6 | 100 | so số lượng tập đóng của SPMF với số tham chiếu, không so từng itemset |
| SPMF vs số tham chiếu (chỉ số lượng) | pumsb_star | tập đóng | 6 | 9785 | 6 | 100 | so số lượng tập đóng của SPMF với số tham chiếu, không so từng itemset |
| SPMF vs số tham chiếu (chỉ số lượng) | T40I10D100K | tập đóng | 6 | 88637 | 6 | 100 | so số lượng tập đóng của SPMF với số tham chiếu, không so từng itemset |
| SPMF vs số tham chiếu (chỉ số lượng) | TỔNG | tập đóng | 56 | 848998 | 56 | 100 |  |
