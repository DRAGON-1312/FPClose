# Fixture SPMF

Output NGUYÊN VĂN của SPMF trên các CSDL nhỏ của repo, dùng cho `test/test_spmf_fixtures.jl` (test không cần Java).
Sinh bằng `julia --project=. scripts/make_spmf_fixtures.jl`.

- Ngày sinh: 2026-11-23 (UTC)
- Java: openjdk version "25.0.5" 2026-10-20 LTS
- `spmf.jar` SHA-256: `2cc2d89e39909230ea0455da4a1c79b389dc98ca04b0670befb63e679b5e2ea0`
- Thuật toán: `FPClose` (chế độ `closed`) và `FPGrowth_itemsets` (chế độ `all`)
- Tên file: `<csdl>__<closed|all>__<minsup>.txt` (`7pct` là minsup `7%`)
- `manifest.csv`: CSDL, file đầu vào, SHA-256 của đầu vào, minsup, chế độ, file fixture, số itemset

Mỗi file có hai dòng metadata `@...` ở đầu, các dòng còn lại dạng `1 2 #SUP: 3`; item trong một itemset
không được SPMF sắp thứ tự. Nếu sửa file trong `data/toy/` thì phải sinh lại fixture (test kiểm SHA-256 đầu vào).
