# Toy datasets

CSDL rất nhỏ để thử nhanh `demo.jl` và chạy unit test (`test/`). Định dạng SPMF: mỗi dòng một giao dịch,
item là số nguyên không âm (item 0 hợp lệ) cách nhau dấu cách, xuống dòng LF.

| File | Giao dịch | Dùng để kiểm tra |
|---|---|---|
| `pasquier99.txt` | 5 | Ví dụ kinh điển của Pasquier et al. (1999), giống `contextPasquier99.txt` trong ví dụ của SPMF. Ở minsup 40% (2 giao dịch) có 5 closed itemsets và 15 frequent itemsets. |
| `rounding_test.txt` | 100 | Cách làm tròn minsup: 7 × `1 2`, 8 × `2 3`, 85 × `2`. Ở 7%, `0.07 × 100 = 7.000000000000001` nên ngưỡng là `ceil` = 8 giao dịch: chỉ có `{2}:100` và `{2,3}:8` là closed; `{1,2}:7` không đạt ngưỡng. |

Thư mục `extra/` có thêm bốn CSDL nhỏ. Cùng với hai file ở trên, chúng là đầu vào của các fixture SPMF trong
`test/fixtures/spmf/` (`test/test_spmf_fixtures.jl`, bảng `results/correctness/toy_vs_spmf.*`) và của bảng
`results/correctness/compare_table_extra.*`. Test `data/toy/*.txt` của `test_optimizations.jl` chỉ đọc hai file
ở thư mục cha. Sửa bất kỳ file nào ở đây thì phải sinh lại fixture bằng `scripts/make_spmf_fixtures.jl`.

| File | Giao dịch | Nội dung |
|---|---|---|
| `extra/ex5.txt` | 5 | Bài tập 5 giao dịch (a=1, b=2, c=3, d=4, e=5; minsup 2 cho 7 closed itemsets). |
| `extra/fig1.txt` | 7 | CSDL Fig. 1 của bài báo Grahne & Zhu (a=1, b=2, ..., k=11; minsup 20% cho 14 closed, 19 frequent itemsets). |
| `extra/random200.txt` | 200 | 200 giao dịch ngẫu nhiên trên 12 item (seed 2026), độ dài 1 đến 8 sau khi bỏ item trùng. Ở 7%, `0,07 × 200 = 14,000000000000002` nên ngưỡng là 15. |
| `extra/item0.txt` | 6 | Có item 0 (item 0 là item thật, không được nhầm với nút gốc của cây): items 0 đến 3. |

Kết quả mong đợi (SPMF FPClose, Java 25):

```
pasquier99.txt, 40%          rounding_test.txt, 7%
3 #SUP: 4                    2 #SUP: 100
1 3 #SUP: 3                  2 3 #SUP: 8
2 5 #SUP: 4
2 3 5 #SUP: 3
1 2 3 5 #SUP: 2
```
