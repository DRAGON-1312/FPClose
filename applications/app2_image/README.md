# Ứng dụng 2: khai thác mẫu trực quan trên ảnh (Caltech-101)

**Câu hỏi:** mỗi loại vật thể có những tổ hợp chi tiết hình ảnh (visual words) nào đặc trưng, và các tổ hợp đó có giúp
phân loại ảnh không? Mọi tập phổ biến đều do **FPClose của nhóm** (`demo.jl`) khai thác; không dùng thư viện FIM nào.
Trình bày đầy đủ ở Mục 3.2 của báo cáo (`docs/`).

| | Liên kết |
|---|---|
| Notebook (`notebooks/application_02.ipynb`) trên Colab | https://colab.research.google.com/github/DRAGON-1312/FPClose/blob/main/notebooks/application_02.ipynb |
| Dữ liệu trung gian (Hugging Face) | https://huggingface.co/datasets/nnkhlh376/fpclose-app2-caltech |
| Dữ liệu gốc | Caltech-101, CaltechDATA, doi: 10.22002/D1.20086 (CC BY 4.0), notebook tự tải |

## Quy trình

Notebook `notebooks/application_02.ipynb` (đặt cùng thư mục với notebook các phần khác) chỉ điều phối: mỗi bước là
một script trong `src/` của thư mục này, ghi kết quả trung gian ra `data/`
và `out/` (không commit). Mọi tham số nằm ở `src/config.py`, mọi bước ngẫu nhiên dùng seed 42.

| Bước | Script | Việc | Kết quả chính |
|---|---|---|---|
| 1 | `s01_prepare_data.py` | Tải Caltech-101, chọn 5 lớp × 200 ảnh, chia 70/30 theo lớp, ảnh xám, cạnh dài 400 px | `data/images/`, `data/split.csv` |
| 1b | `s02_sift_probe.py` | Chạy thử SIFT trên 10 ảnh/lớp | `out/sift_probe.*` |
| 2 | `s03_sift_extract.py` | SIFT (500 keypoint/ảnh) cho 1000 ảnh | `data/sift.npz` |
| 3 | `s04_codebook.py` | Codebook `MiniBatchKMeans` k = 100, 300, **chỉ học trên train**; gán từ cho mọi keypoint | `data/words.npz` |
| 4 | `s05_transactions.py` | Giao dịch SPMF: từ xuất hiện ≥ τ = 3 lần, bỏ từ có ở > 80% ảnh train; bảng nhạy cảm τ | `data/transactions/k{k}_word/` |
| 5 | `s06_mine.py` | Gọi FPClose theo từng lớp, quét minsup (k = 100 → 55%, k = 300 → 25%); kiểm tra độc lập support + tính đóng | `data/patterns/`, `out/mining_sweep.csv` |
| 6 | `s07_growth_viz.py` | Growth rate, top mẫu mỗi lớp, vẽ lên ảnh, tỉ lệ mẫu nằm trên vật thể (chú thích đường viền của Caltech-101) | `out/growth_*.csv`, `out/patterns_k{k}.png` |
| 7 | `s08_classify.py` | Phân loại A (BoVW) / B (top-20 mẫu mỗi lớp) / C (A + B) | `out/classification.csv` |

τ và minsup được chọn bằng tiêu chí **viết và commit trước khi chạy** (xem docstring của `s05`, `s06`). Lý do chọn
từng tham số có trong các ô markdown của notebook.

## Cài đặt và chạy

**Môi trường:** kết quả trong báo cáo được tạo bằng **Python 3.12** và đúng các phiên bản trong `requirements.txt`
(NumPy 1.26.4, scikit-learn 1.5.2, OpenCV 4.10.0). Trên cùng máy Windows, đã thử Python 3.13 + NumPy 2.4.6: SIFT và
codebook k = 100 giống hệt, nhưng codebook k = 300 khác. Số luồng CPU không ảnh hưởng.

**Đặc trưng đã lưu (mặc định):** ngay cả với cùng Python 3.12 và cùng phiên bản thư viện, chạy trên Colab (Linux) cho
**SIFT khác** (số keypoint và vị trí keypoint giống hệt, nhưng descriptor khác: chỉ 28,8% keypoint trùng descriptor theo
thứ tự; gán từ đã lưu cho SIFT tính lại chỉ trùng ~30%) và **k-means k = 300 khác** (với cùng đầu vào: inertia lệch +0,07%,
ARI 0,33; k = 100 thì trùng từng byte) so với máy Windows dùng làm báo cáo: thứ tự và tập lệnh tính số thực khác nhau
theo hệ điều hành/CPU. Vì vậy mặc định:
- bước 2 dùng **SIFT đã lưu** (`features/sift.npz` trên Hugging Face, commit cố định, kiểm tra SHA-256);
- bước 3 dùng **codebook và từ thị giác đã lưu** trong `reference/` (kiểm tra SHA-256).

Cả hai vẫn được **tính lại trên máy đang chạy để kiểm chứng** (bảng `out/sift_check.csv` và ô 3b, `out/kmeans_check.csv`)
nhưng không dùng cho các bước sau. Các bước sau (giao dịch, FPClose, growth rate, vẽ, phân loại) chạy lại bình thường.
Dùng kết quả tính lại trên máy đang chạy: đặt `APP2_RECOMPUTE_SIFT=1` và/hoặc `APP2_RELEARN_CODEBOOK=1`. Lần chạy lại
toàn bộ trên Colab (tính lại cả hai) cho số liệu khác (minsup k = 300 thành 20%, số tập đóng, accuracy lệch 0,3–3 điểm)
nhưng kết luận định tính giữ nguyên.

**Trên Colab:** mở link Colab ở trên, chọn *Runtime → Change runtime type → Python 3, CPU* (không cần GPU), rồi
*Runtime → Run all* (khoảng 15–25 phút). Colab dùng Python 3.13, nên ô thiết lập tạo một môi trường **Python 3.12
riêng bằng `uv`** (`/content/app2_py312`, khoảng 1 phút) và cài `requirements.txt` vào đó; mọi bước `src/sNN_*.py`
chạy bằng Python này, kernel Colab chỉ đọc và hiển thị CSV/ảnh. Ô thiết lập cũng clone/fetch đúng nhánh
`REPO_BRANCH`, in mã commit và phiên bản thư viện; Julia 1.13.4 được cài ở mục 5 của notebook.

**Đối chiếu kết quả giữa các máy:** ô cuối của notebook đóng gói 14 bảng `out/*.csv`, bản ghi từng bước
(`out/_steps/*.json`) và thông tin môi trường vào `app2_out.zip`. Cột `codebook_sha256` trong `codebook_stats.csv`
cho phép so nhanh ngay sau bước 3 (mốc trên máy dùng cho báo cáo: k = 100 `8bb871d5031ff0f7`, k = 300
`fbff0276c89d4e59`).

**Trên máy cá nhân** (Python 3.12, Julia 1.13.4):

```bash
# Julia (Windows): winget install Julialang.Juliaup; juliaup add 1.13.4; juliaup default 1.13.4
cd applications/app2_image
python -m venv .venv
source .venv/bin/activate            # Windows: .venv\Scripts\activate
pip install -r requirements.txt
# Windows: đặt PYTHONUTF8=1 để in tiếng Việt trên console
for s in s01_prepare_data s03_sift_extract s04_codebook s05_transactions s06_mine s07_growth_viz s08_classify; do
  python src/$s.py
done
```

Hoặc mở `notebooks/application_02.ipynb` (từ gốc repo) với kernel `applications/app2_image/.venv` và chạy hết; notebook tự
tìm thư mục `applications/app2_image/` và chạy các script trên.

Mỗi bước tự bỏ qua khi đã chạy với đúng tham số và đúng dữ liệu đầu vào (ghi nhận ở `out/_steps/`); đổi tham số
hoặc đầu vào thì bước đó và các bước sau tự chạy lại. Thêm `--force` để buộc chạy lại một bước.

## Ví dụ: khai thác trực tiếp từ dữ liệu trên Hugging Face

Không cần chạy lại SIFT và k-means. Từ thư mục gốc của repo:

```bash
pip install huggingface_hub
hf download nnkhlh376/fpclose-app2-caltech --repo-type dataset --local-dir app2_data
julia --project=. demo.jl --minsup 25% --output-closed leopards_closed.txt app2_data/transactions/k300_word/class_Leopards.txt
```

Trên Windows, đặt `--local-dir` ở đường dẫn ngắn: file tạm của `hf download` có tên dài, dễ vượt giới hạn 260 ký tự.
Mỗi dòng output dạng `156 263 #SUP: 100`: tập item (item = visual word + 1) và số ảnh train của lớp chứa nó.
Lớp Leopards ở k = 300, minsup 25% cho khoảng 2,6 triệu tập đóng; lớp nhỏ hơn để thử nhanh là
`class_airplanes.txt` (132 tập).

## Kết quả chính

- **Leopards:** mẫu có growth rate ∞ và nằm trên lông báo (tỉ lệ trên vật thể 0,95 so với mốc 0,76 ở k = 300).
- **Faces_easy, Motorbikes:** mẫu có growth rate cao nhưng nghiêng về nền hoặc góc ảnh; **airplanes** không có mẫu
  đặc trưng mạnh.
- **Phân loại** (300 ảnh test, accuracy): A 0,823 / 0,870; B 0,670 / 0,603; C 0,823 / 0,877 (k = 100 / 300). Mẫu có
  giá trị phân tích (chỉ ra chi tiết đặc trưng và thiên lệch nền) hơn là tăng accuracy so với BoVW.

## Thư viện

Tiền xử lý dùng thư viện hỗ trợ theo hướng dẫn của giảng viên (chi tiết ở ô "Thư viện sử dụng" trong notebook):
OpenCV (đọc ảnh, SIFT), NumPy, pandas, scikit-learn (chia tập, k-means, phân loại), SciPy (đọc chú thích `.mat`),
Matplotlib (vẽ). Phiên bản ghim trong `requirements.txt`. Khai thác tập phổ biến chỉ dùng FPClose của nhóm.

`hf_dataset_card.md` là mẫu của README trên Hugging Face (bản đã upload thay `{COMMIT}` bằng `6d81cb3`).
