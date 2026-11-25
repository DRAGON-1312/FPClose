"""Tham số dùng chung cho Ứng dụng 2. Mọi bước ngẫu nhiên đều dùng SEED."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]          # applications/app2_image/
REPO = ROOT.parents[1]                              # gốc repo FPClose (chứa demo.jl, Project.toml)
FPCLOSE_DEMO = REPO / "demo.jl"                     # CLI FPClose của nhóm, dùng ở bước khai thác
DATA_RAW = ROOT / "data" / "raw"                    # file tải về + giải nén (dữ liệu không tin cậy)
DATA_IMG = ROOT / "data" / "images"                 # ảnh đã chọn, xám, resize
DATA_SPLIT = ROOT / "data" / "split.csv"            # danh sách ảnh + lớp + train/test
OUT = ROOT / "out"

SEED = 42
CLASSES = ["airplanes", "Motorbikes", "Faces_easy", "watch", "Leopards"]
N_PER_CLASS = 200          # Leopards chỉ có 200 ảnh, watch 239: 200 là mức cân bằng lớn nhất
TEST_SIZE = 0.30           # 70/30, stratify theo lớp -> 140 train / 60 test mỗi lớp
MAX_SIDE = 400             # cạnh dài 400 px: đủ chi tiết cho SIFT, giữ số keypoint giữa các ảnh tương đương
SIFT_NFEATURES = 500

CALTECH_URL = "https://data.caltech.edu/records/mzrjq-6wc02/files/caltech-101.zip?download=1"
