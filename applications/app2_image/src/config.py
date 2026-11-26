"""Tham số dùng chung cho Ứng dụng 2. Mọi bước ngẫu nhiên đều dùng SEED."""
import os
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]          # applications/app2_image/
REPO = ROOT.parents[1]                              # gốc repo FPClose (chứa demo.jl, Project.toml)
FPCLOSE_DEMO = REPO / "demo.jl"                     # CLI FPClose của nhóm, dùng ở bước khai thác
DATA_RAW = ROOT / "data" / "raw"                    # file tải về + giải nén (dữ liệu không tin cậy)
DATA_IMG = ROOT / "data" / "images"                 # ảnh đã chọn, xám, resize
DATA_SPLIT = ROOT / "data" / "split.csv"            # danh sách ảnh + lớp + train/test
DATA_SIFT = ROOT / "data" / "sift.npz"              # descriptor + tọa độ keypoint của mọi ảnh (bước 2)
OUT = ROOT / "out"

SEED = 42
CLASSES = ["airplanes", "Motorbikes", "Faces_easy", "watch", "Leopards"]
N_PER_CLASS = 200          # Leopards chỉ có 200 ảnh, watch 239: 200 là mức cân bằng lớn nhất
TEST_SIZE = 0.30           # 70/30, stratify theo lớp -> 140 train / 60 test mỗi lớp
MAX_SIDE = 400             # cạnh dài 400 px: đủ chi tiết cho SIFT, giữ số keypoint giữa các ảnh tương đương
SIFT_NFEATURES = 500

CALTECH_URL = "https://data.caltech.edu/records/mzrjq-6wc02/files/caltech-101.zip?download=1"

K_LIST = [100, 300]        # kích thước codebook thử
N_SAMPLE_DESC = 150_000    # số descriptor train lấy mẫu để học codebook (~48% của ~316k)
DATA_WORDS = ROOT / "data" / "words.npz"            # từ thị giác của mọi keypoint, k100 / k300 (bước 3)


def codebook_path(k: int) -> Path:
    return ROOT / "data" / f"codebook_k{k}.npy"     # tâm cụm (k, 128) float32


# --- Bước 4: giao dịch ---
TAU = 3                    # giữ từ xuất hiện >= TAU lần trong ảnh. Mặc định ban đầu là 2; đổi sang 3 theo
                           # tiêu chí đặt trước (docstring s05, commit a541b25) cho cả k=100 và k=300 chế độ word
WRITE_VARIANTS = ["word"]  # chế độ được ghi file giao dịch và khai thác bằng FPClose
SENS_VARIANTS = ["word", "grid"]  # chế độ có trong bảng nhạy cảm; grid chỉ dừng ở đây (đề không yêu cầu vị trí)
STOP_DF = 0.80             # bỏ item có mặt trong > 80% ảnh train
GRID = 2                   # biến thể lưới GRID x GRID (2x2 -> 4 vùng)
TAU_GRID = [1, 2, 3]       # bảng nhạy cảm: các giá trị tau thử
STOP_GRID = [0.6, 0.7, 0.8, 0.9]
CV_FOLDS = 5
CV_TOL = 0.01              # tiêu chí chọn tau (xem docstring s05): sai khác accuracy CV tối đa 1 điểm %
DATA_TX = ROOT / "data" / "transactions"            # data/transactions/k{k}_word/

# --- Bước 5: khai thác bằng FPClose (Julia) của nhóm ---
JULIA = os.environ.get("JULIA") or shutil.which("julia") or "julia"
MINSUP_GRID = {                                     # % , quét giảm dần (xem tiêu chí trong docstring s06)
    100: [90, 85, 80, 75, 70, 65, 60, 55, 50],      # k=100 dày (mật độ 0,58): bắt đầu cao
    300: [60, 55, 50, 45, 40, 35, 30, 25, 20, 15, 10],  # k=300 thưa (0,19); 10% = 14 ảnh/lớp là mức thấp nhất
}
MIN_PATTERNS = 50          # tiêu chí: mỗi lớp cần >= 50 tập đóng có độ dài >= MIN_PATTERN_LEN
MIN_PATTERN_LEN = 2        # "tổ hợp" chi tiết: ít nhất 2 từ
MINE_TIMEOUT = 300         # giây cho một lần gọi demo.jl; quá thì coi như mức minsup đó không chạy được
N_JOBS = max(1, min(len(CLASSES), os.cpu_count() or 1))  # số lần gọi FPClose chạy song song (5 lớp)
CLOSED_CHECK_SAMPLE = 5000  # kiểm tra tính đóng trên tối đa chừng này mẫu mỗi lớp (seed 42); support kiểm tra hết
DATA_PATTERNS = ROOT / "data" / "patterns"          # output thô của FPClose + bảng mẫu đã chọn
