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

# --- Bước 6: growth rate + vẽ mẫu ---
TOP_TABLE = 10             # số mẫu mỗi lớp trong bảng báo cáo
TOP_KEEP = MIN_PATTERNS    # số mẫu mỗi lớp lưu cho bước phân loại (s08 dùng top-N <= 20 trong số này)
N_FIG_IMAGES = 3           # số ảnh minh họa cho mẫu top-1 của mỗi lớp
ANN_DIR = DATA_RAW / "Annotations"                  # giải nén từ Annotations.tar trong caltech-101.zip
ANN_DIRS = {"airplanes": "Airplanes_Side_2", "Motorbikes": "Motorbikes_16", "Faces_easy": "Faces_3",
            "watch": "watch", "Leopards": "Leopards"}
TOP_N_CLF = 20             # bước 7: số mẫu mỗi lớp làm đặc trưng cấu hình B (5 lớp -> 100 đặc trưng)
# Faces_easy -> Faces_3 (không phải Faces_2): hộp của Faces_2 vượt khung ảnh Faces_easy ở 40/40 ảnh thử,
# Faces_3 thì 0/40. annotation_XXXX.mat <-> image_XXXX.jpg; box_coord = [y1 y2 x1 x2],
# obj_contour (2, N) = (x, y) tính từ góc (x1, y1) của hộp, theo tọa độ ảnh GỐC.


# --- Bỏ qua bước đã chạy: chỉ khi đủ output VÀ tham số + đầu vào không đổi ---
import hashlib
import json

STEP_DIR = OUT / "_steps"   # out/_steps/<bước>.json, ghi SAU CÙNG khi bước chạy xong và mọi kiểm tra đã qua


def file_sig(path) -> str:
    """SHA-1 nội dung file (đọc từng khối 1 MB)."""
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _step_record(inputs, params) -> dict:
    rec = {"params": params, "inputs": {Path(os.path.relpath(p, REPO)).as_posix(): file_sig(p) for p in inputs}}
    return json.loads(json.dumps(rec, sort_keys=True, default=str))   # chuẩn hóa (tuple -> list, khóa -> str)


def step_done(name: str, outputs, inputs, params) -> bool:
    """True nếu bước `name` đã chạy xong với đúng tham số và đầu vào này, và còn đủ mọi output."""
    f = STEP_DIR / f"{name}.json"
    if not f.exists():
        return False
    missing = [Path(o).name for o in outputs if not Path(o).exists()]
    if missing:
        print(f"{name}: thiếu output {missing[:3]} -> chạy lại")
        return False
    if json.loads(f.read_text(encoding="utf-8")) != _step_record(inputs, params):
        print(f"{name}: tham số hoặc dữ liệu đầu vào đã đổi so với lần chạy trước -> chạy lại")
        return False
    print(f"{name}: đã chạy với đúng tham số và đầu vào này, đủ output -> bỏ qua (dùng --force để chạy lại)")
    return True


def mark_step_done(name: str, inputs, params) -> None:
    STEP_DIR.mkdir(parents=True, exist_ok=True)
    (STEP_DIR / f"{name}.json").write_text(json.dumps(_step_record(inputs, params), indent=1, sort_keys=True),
                                          encoding="utf-8")


def clear_step(name: str) -> None:
    """Gọi NGAY khi bắt đầu chạy (kể cả --force): xóa dấu hoàn tất cũ, để nếu lần chạy này thất bại giữa chừng
    thì lần sau không bỏ qua bước với output dở dang."""
    (STEP_DIR / f"{name}.json").unlink(missing_ok=True)
