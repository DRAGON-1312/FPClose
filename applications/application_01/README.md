# Ứng dụng 1 — Phân tích giỏ hàng (Market Basket Analysis)

Ứng dụng thuộc Chương 3 của đồ án. Mục tiêu là tìm các nhóm sản phẩm thường được mua cùng nhau trong một cửa hàng bán
lẻ trực tuyến, rồi sinh luật kết hợp (association rules) X → Y. Luật được giữ khi support của X đạt ngưỡng minsup và
confidence của luật đạt ngưỡng minconf. Báo cáo trình bày top-10 luật theo lift và giải thích ý nghĩa kinh doanh.

Mọi tập phổ biến và luật kết hợp đều được sinh bằng **chính cài đặt FPClose của nhóm**, qua CLI `demo.jl` hoặc các
hàm trong `src/`. Nhóm không dùng mlxtend hay bất kỳ thư viện khai thác tập phổ biến (FIM) nào khác. Phía Python
(pandas, openpyxl, matplotlib) chỉ dùng để đọc dữ liệu, biến đổi thành giao dịch và trình bày kết quả.

## Dữ liệu

| Mục | Giá trị |
|---|---|
| Bộ dữ liệu | UCI Online Retail (id 352) |
| Nguồn | https://archive.ics.uci.edu/dataset/352/online+retail (file tải: `https://archive.ics.uci.edu/static/public/352/online+retail.zip`) |
| Giấy phép | CC BY 4.0 |
| File gốc | `data/raw/Online Retail.xlsx` |
| SHA-256 | `43465A06F2CCF7C8B5BD2892BC7DEFB52F97487934FE93B16AE4C3936424676D` |
| Cột | InvoiceNo, StockCode, Description, Quantity, InvoiceDate, UnitPrice, CustomerID, Country |

Trích dẫn: Chen, D. (2015). *Online Retail* [Dataset]. UCI Machine Learning Repository.
https://doi.org/10.24432/C5BW33

## Các quyết định biến đổi dữ liệu thành giao dịch

Phần lý do của từng quyết định sẽ được điền sau khi phân tích kết quả chẩn đoán dữ liệu.

| # | Quyết định | Lý do |
|---|---|---|
| 1 | Một giao dịch là một hóa đơn (InvoiceNo); item là StockCode | (điền sau) |
| 2 | Bỏ Quantity: giao dịch là **tập** mã sản phẩm phân biệt, nên các dòng trùng mã trong một hóa đơn được gộp | (điền sau) |
| 3 | Giữ các hóa đơn chỉ có 1 sản phẩm | (điền sau) |
| 4 | Bỏ hóa đơn hủy (InvoiceNo bắt đầu bằng 'C' hoặc 'c'), Quantity ≤ 0, UnitPrice ≤ 0, Description rỗng, InvoiceNo/StockCode thiếu | (điền sau) |
| 5 | Bỏ mã không phải sản phẩm: `NON_PRODUCT` (POST, DOT, M, D, C2, CRUK, PADS, S, B, BANK CHARGES, AMAZONFEE) và tiền tố `GIFT_`, `DCGS`. Các mã lệch mẫu `^\d{5}[A-Z]{0,2}$` còn lại chỉ được thống kê, không bị loại | (điền sau) |
| 6 | Không loại dòng thiếu CustomerID (khách vãng lai vẫn là hóa đơn hợp lệ), chỉ thống kê | (điền sau) |
| 7 | Chuẩn hóa: StockCode `strip().upper()` trước mọi phép đối chiếu; Description `strip` và gộp khoảng trắng | (điền sau) |
| 8 | Id item liên tục từ 1 theo thứ tự StockCode tăng dần (`read_spmf` nhận id ≥ 0; chọn 1 để khớp quy ước SPMF). Tên hiển thị là Description phổ biến nhất của mã, hòa thì lấy chuỗi nhỏ nhất theo thứ tự từ điển | (điền sau) |

Quy ước tái lập:
- Hóa đơn được sắp theo InvoiceNo (so như chuỗi), item trong mỗi giao dịch sắp tăng dần.
- Mọi tham số ảnh hưởng đến kết quả đều khai báo ở ô cấu hình của notebook.
- Cache `data/online_retail.pkl` gắn với SHA-256 của file gốc (lưu ở `data/online_retail.pkl.sha256`). Nếu SHA không
  khớp, dữ liệu được đọc lại từ file xlsx.

## Cấu trúc thư mục

```
applications/application_01/
├── README.md
├── market_basket.py          # tiền xử lý, gọi demo.jl, đọc và kiểm tra chéo kết quả (thuần / tác dụng phụ tách riêng)
├── data/                     # KHÔNG commit (.gitignore): sinh lại được từ notebook
│   ├── raw/Online Retail.xlsx
│   ├── online_retail.pkl (+ .sha256)
│   ├── transactions.txt      # giao dịch định dạng SPMF, đầu vào của demo.jl
│   ├── transactions_lt<t>.txt # mục 5.1: giao dịch sau khi bỏ hóa đơn có >= t sản phẩm (cùng id item)
│   └── item_map.csv          # id, stock_code, description, n_transactions, support_pct
├── out/                      # KHÔNG commit (.gitignore): output thô của FPClose (closed_*, all_*, rules_*_all)
└── results/                  # commit: bảng và hình dùng trong báo cáo
    ├── cleaning_steps.csv                 # mục 3.3: các bước làm sạch
    ├── transaction_stats.csv              # mục 3.5: thống kê giao dịch
    ├── minsup_survey.csv                  # mục 5: khảo sát minsup (số tập đóng, mọi tập phổ biến, tỷ lệ nén, thời gian)
    ├── long_invoice_check.csv             # mục 5.1: số tập đóng / tập phổ biến khi bỏ hóa đơn >= 500, >= 200 sản phẩm
    ├── long_invoice_rules_check.csv       # mục 5.1: top-10 theo lift (gốc) đối chiếu luật khi bỏ hóa đơn >= 200 sản phẩm
    ├── all_rules.csv                      # mục 6: toàn bộ luật ở MINSUP, MINCONF
    ├── top10_rules.csv                    # mục 7.1: top-10 theo lift (10 dòng đầu của all_rules)
    ├── rule_verification.csv              # mục 7.1: kiểm tra chéo toàn bộ luật ở MINSUP bằng phép đếm trực tiếp
    ├── top10_rules_diverse.csv            # mục 7.2: top-10, mỗi sản phẩm xuất hiện tối đa một lần
    ├── long_invoice_diverse_check.csv     # mục 7.2: top-10 đa dạng đối chiếu luật khi bỏ hóa đơn >= 200 sản phẩm
    ├── top10_rules_diverse_ms0.02.csv     # mục 7.3: top-10 đa dạng ở MINSUP_SENS = 2%
    ├── sensitivity_minsup.csv             # mục 7.3: top-10 đa dạng ở 1% đối chiếu với toàn bộ luật ở 2%
    ├── rule_verification_ms0.02.csv       # mục 7.3: kiểm tra chéo toàn bộ luật ở MINSUP_SENS
    └── figures/
        ├── basket_length.png              # mục 3.5: phân bố độ dài giỏ hàng
        └── minsup_survey.png              # mục 5: số itemset và tỷ lệ nén theo minsup
```

## Cách chạy

- **Bản chi tiết:** `notebooks/application_01.ipynb` (kernel Python 3, chạy trên Colab hoặc local; cần lệnh `julia`
  cho các mục 4–7). Notebook đi qua từng bước: tải dữ liệu, chẩn đoán, làm sạch, tạo giao dịch, thống kê, khai thác
  tập đóng, khảo sát minsup, sinh luật, top-10 theo lift, top-10 đa dạng và độ nhạy theo minsup. Phần diễn giải ý
  nghĩa kinh doanh sẽ được bổ sung sau.
- **Bản rút gọn:** mục 7.1 của `notebooks/demo.ipynb` (sẽ bổ sung) gọi `market_basket.run_preprocessing(...)` rồi chạy
  FPClose của nhóm trên `data/transactions.txt`.
- **Chạy riêng phần tiền xử lý** (local, từ gốc repo): `python applications/application_01/market_basket.py`.

Thư viện Python cần có: `pandas`, `openpyxl`, `matplotlib` (Colab có sẵn).
Cài local: `pip install pandas openpyxl matplotlib`.
