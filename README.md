# FPClose

Cài đặt lại bằng Julia thuật toán **FPClose** — khai thác các *closed frequent itemsets* (tập mục thường xuyên đóng) bằng FP-tree — cho đồ án môn học.

Thuật toán được trình bày trong bài báo:

> G. Grahne và J. Zhu, "Fast Algorithms for Frequent Itemset Mining Using FP-Trees",
> *IEEE Transactions on Knowledge and Data Engineering*, 17(10), 2005.
> DOI: [10.1109/TKDE.2005.166](https://doi.org/10.1109/TKDE.2005.166)

## Thành viên nhóm

TODO

## Cấu trúc thư mục

```
FPClose/
├── Project.toml
├── Manifest.toml
├── demo.jl
├── src/
│   ├── FPClose.jl
│   ├── structures.jl
│   ├── utils.jl
│   └── algorithm/
│       ├── fptree.jl
│       ├── fparray.jl
│       ├── cfitree.jl
│       └── fpclose.jl
├── test/
├── notebooks/
│   └── demo.ipynb
├── docs/
└── data/
    ├── toy/
    └── benchmark/
```

| Đường dẫn | Vai trò |
|---|---|
| `Project.toml`, `Manifest.toml` | Khai báo gói và cố định phiên bản phụ thuộc để tái lập môi trường (`Manifest.toml` được commit). |
| `src/FPClose.jl` | Module gốc `FPClose`, `include` các file còn lại trong `src/`. |
| `src/structures.jl` | Định nghĩa cấu trúc dữ liệu: FP-tree và CFI-tree. |
| `src/utils.jl` | Đọc/ghi định dạng SPMF và xử lý tham số dòng lệnh. |
| `src/algorithm/fptree.jl` | Section 2.1 của bài báo: xây dựng FP-tree và conditional FP-tree. |
| `src/algorithm/fparray.jl` | Section 2.2–2.3: FP-array. |
| `src/algorithm/cfitree.jl` | Section 4.1: CFI-tree và `closed_checking`. |
| `src/algorithm/fpclose.jl` | Fig. 8: thủ tục `FPclose`. |
| `test/` | Các bài test (`runtests.jl` là điểm vào; `test_correctness.jl`, `test_benchmark.jl`). |
| `notebooks/demo.ipynb` | Notebook demo (để chạy trên Google Colab). |
| `docs/` | Tài liệu, báo cáo (`docs/Report.pdf` là file PDF duy nhất được commit). |
| `demo.jl` | Script chạy thuật toán từ dòng lệnh. |
| `data/toy/` | Dữ liệu nhỏ để kiểm thử và demo. Hiện chưa có file nào. |
| `data/benchmark/` | Dữ liệu cỡ lớn để đo hiệu năng. Hiện chưa có file nào. |

> Phần `data/` do thành viên khác phụ trách; README chỉ liệt kê những gì đang có trong thư mục.

## Cài đặt môi trường

Yêu cầu: Julia ≥ 1.9.

```
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

## Cách chạy

> **Dự kiến, chưa cài xong.** `demo.jl` hiện chưa có nội dung.

```
julia --project=. demo.jl --minsup 0.2 data/toy/<tên file trong data/toy>
```

(Hiện `data/toy/` chưa có file nào, nên chưa có tên file cụ thể để điền.)

## Chạy test

```
julia --project test/runtests.jl
```

Output lần chạy test cuối: TODO

## Định dạng input/output (SPMF)

**Input**: mỗi dòng là một giao dịch; các item là số nguyên, cách nhau bằng dấu cách. Ví dụ minh họa về định dạng (không phải file dữ liệu của repo):

```
1 2 3
1 2
2 3
```

**Output**: mỗi dòng là một closed frequent itemset, theo sau là độ hỗ trợ (support) sau `#SUP:`. Ví dụ minh họa về định dạng:

```
1 2 #SUP: 3
```

## Liên kết

- Google Colab: TODO
- Dataset (Hugging Face/Kaggle): TODO
