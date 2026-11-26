---
license: cc-by-4.0
pretty_name: FPClose – Ứng dụng 2 – giao dịch visual words từ Caltech-101
language:
- vi
tags:
- frequent-itemset-mining
- closed-itemsets
- bag-of-visual-words
- caltech-101
size_categories:
- n<1K
---

# Giao dịch visual words từ Caltech-101 (Ứng dụng 2 của đồ án FPClose)

Dữ liệu trung gian của **Ứng dụng 2: khai thác mẫu trực quan trên ảnh** trong đồ án cài đặt thuật toán FPClose
(môn Khai thác dữ liệu, Khoa CNTT, ĐH KHTN – ĐHQG-HCM). Code sinh ra dữ liệu: repo `DRAGON-1312/FPClose`, thư mục
`applications/app2_image/`, commit `{COMMIT}`. Notebook chạy lại toàn bộ: `applications/app2_image/app2_image.ipynb`.

## Nguồn
Caltech-101 (Fei-Fei, Fergus, Perona), CaltechDATA, doi: 10.22002/D1.20086, giấy phép CC BY 4.0.
Dùng 5 lớp `airplanes`, `Motorbikes`, `Faces_easy`, `watch`, `Leopards`, 200 ảnh mỗi lớp (seed 42), chia train/test
70/30 theo lớp (140/60). Ảnh gốc **không** đưa lên đây: notebook tự tải từ CaltechDATA.

## Quy trình tạo
1. Ảnh xám, resize cạnh dài 400 px.
2. SIFT (OpenCV, `nfeatures=500`) cho cả 1000 ảnh.
3. Codebook `MiniBatchKMeans` (k = 100 và 300, seed 42), **chỉ học trên train** (~150 000 descriptor, tối đa 221/ảnh);
   mọi keypoint (train và test) được gán từ của tâm gần nhất (khoảng cách Euclid).
4. Giao dịch của ảnh = các từ xuất hiện ≥ τ = 3 lần trong ảnh, bỏ từ có mặt trong hơn 80% ảnh train.
   Item = từ + 1 (SPMF cần số nguyên dương).

## Cấu trúc
| Đường dẫn | Nội dung |
|---|---|
| `split.csv` | 1000 ảnh: `path`, `label`, `split` (train/test), `src` (tên file gốc trong Caltech-101) |
| `transactions/k{100,300}_word/class_<lớp>.txt` | Giao dịch **train** của từng lớp, định dạng SPMF (mỗi dòng một ảnh, item tăng dần, cách nhau dấu cách) — đầu vào cho FPClose |
| `transactions/k{100,300}_word/all_train.txt` | Toàn bộ 700 giao dịch train (để tính support ở các lớp khác cho growth rate) |
| `transactions/k{100,300}_word/test.txt` | 300 giao dịch test (chỉ để kiểm tra ảnh có chứa mẫu hay không) |
| `transactions/k{100,300}_word/transactions_index.csv` | Ảnh ↔ dòng trong các file trên (`line_common`, `line_class`), số item, cờ `empty` (ảnh rỗng bị loại khỏi file .txt) |
| `transactions/k{100,300}_word/items.csv` | Item ↔ từ, số ảnh train chứa item, có là stop word không |
| `features/sift.npz` | `desc` (N×128, uint8), `x`, `y`, `size`, `angle`, `offsets` (keypoint của ảnh i nằm ở `[offsets[i], offsets[i+1])`, thứ tự ảnh = `split.csv`) |
| `features/words.npz` | `k100`, `k300`: từ (0..k−1) của từng keypoint, cùng thứ tự với `sift.npz` |
| `features/codebook_k{100,300}.npy` | Tâm cụm (k×128, float32) |
| `SHA256SUMS.txt` | Mã SHA-256 của từng file |

## Ví dụ: khai thác bằng FPClose của nhóm
```
julia --project=. demo.jl --minsup 25% --output-closed closed.txt transactions/k300_word/class_Leopards.txt
```
Output mỗi dòng dạng `156 263 #SUP: 100` (`#SUP` là số giao dịch chứa tập).
