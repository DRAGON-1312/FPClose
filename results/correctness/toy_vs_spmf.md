# Cài đặt của nhóm so với SPMF trên CSDL nhỏ

So từng itemset và support (bản mặc định của `fpclose`; `all` = `recover_all_frequent` so với SPMF `FPGrowth_itemsets`, `closed` so với SPMF `FPClose`). `match_rate` = số dòng khớp hoàn toàn / số dòng của hợp hai bên. Fixture: `test/fixtures/spmf/`, sinh bằng `scripts/make_spmf_fixtures.jl`.

| CSDL | minsup | ngưỡng (giao dịch) | chế độ | n_ours | n_spmf | n_match | match_rate |
|---|---|---:|---|---:|---:|---:|---:|
| pasquier99 | 60% | 3 | closed | 4 | 4 | 4 | 100.0% |
| pasquier99 | 60% | 3 | all | 9 | 9 | 9 | 100.0% |
| pasquier99 | 40% | 2 | closed | 5 | 5 | 5 | 100.0% |
| pasquier99 | 40% | 2 | all | 15 | 15 | 15 | 100.0% |
| pasquier99 | 20% | 1 | closed | 6 | 6 | 6 | 100.0% |
| pasquier99 | 20% | 1 | all | 19 | 19 | 19 | 100.0% |
| pasquier99 | 7% | 1 | closed | 6 | 6 | 6 | 100.0% |
| pasquier99 | 7% | 1 | all | 19 | 19 | 19 | 100.0% |
| rounding_test | 40% | 40 | closed | 1 | 1 | 1 | 100.0% |
| rounding_test | 40% | 40 | all | 1 | 1 | 1 | 100.0% |
| rounding_test | 20% | 20 | closed | 1 | 1 | 1 | 100.0% |
| rounding_test | 20% | 20 | all | 1 | 1 | 1 | 100.0% |
| rounding_test | 7% | 8 | closed | 2 | 2 | 2 | 100.0% |
| rounding_test | 7% | 8 | all | 3 | 3 | 3 | 100.0% |
| ex5 | 60% | 3 | closed | 4 | 4 | 4 | 100.0% |
| ex5 | 60% | 3 | all | 5 | 5 | 5 | 100.0% |
| ex5 | 40% | 2 | closed | 7 | 7 | 7 | 100.0% |
| ex5 | 40% | 2 | all | 12 | 12 | 12 | 100.0% |
| ex5 | 20% | 1 | closed | 10 | 10 | 10 | 100.0% |
| ex5 | 20% | 1 | all | 21 | 21 | 21 | 100.0% |
| fig1 | 40% | 3 | closed | 9 | 9 | 9 | 100.0% |
| fig1 | 40% | 3 | all | 9 | 9 | 9 | 100.0% |
| fig1 | 20% | 2 | closed | 14 | 14 | 14 | 100.0% |
| fig1 | 20% | 2 | all | 19 | 19 | 19 | 100.0% |
| fig1 | 10% | 1 | closed | 21 | 21 | 21 | 100.0% |
| fig1 | 10% | 1 | all | 102 | 102 | 102 | 100.0% |
| random200 | 20% | 40 | closed | 12 | 12 | 12 | 100.0% |
| random200 | 20% | 40 | all | 12 | 12 | 12 | 100.0% |
| random200 | 7% | 15 | closed | 75 | 75 | 75 | 100.0% |
| random200 | 7% | 15 | all | 75 | 75 | 75 | 100.0% |
| random200 | 2% | 4 | closed | 326 | 326 | 326 | 100.0% |
| random200 | 2% | 4 | all | 329 | 329 | 329 | 100.0% |
| item0 | 60% | 4 | closed | 3 | 3 | 3 | 100.0% |
| item0 | 60% | 4 | all | 3 | 3 | 3 | 100.0% |
| item0 | 30% | 2 | closed | 10 | 10 | 10 | 100.0% |
| item0 | 30% | 2 | all | 13 | 13 | 13 | 100.0% |

Tổng: 36/36 fixture khớp hoàn toàn (trên 6 CSDL, 36 cặp CSDL × minsup × chế độ). Bản tắt mọi tối ưu (`prune_line8`, `fparray`, `early_termination`, `exact_count`, `reduced_cfitree` đều tắt): 36/36 fixture khớp hoàn toàn.
