"""Bước 1: tải Caltech-101, chọn 5 lớp x 200 ảnh, chia train/test 70/30, chuyển xám + resize.

Chạy:  python src/s01_prepare_data.py
Kết quả: data/images/<lớp>/<file>.png  và  data/split.csv (path, label, split, src)
Chạy lại an toàn: bỏ qua bước tải/giải nén nếu đã có.
"""
import csv
import tarfile
import urllib.request
import zipfile
from pathlib import Path

import cv2
from sklearn.model_selection import train_test_split

from config import (CALTECH_URL, CLASSES, DATA_IMG, DATA_RAW, DATA_SPLIT,
                    MAX_SIDE, N_PER_CLASS, SEED, TEST_SIZE)


def safe_extract_tar(tar: tarfile.TarFile, dest: Path):
    """Giải nén tar nhưng chặn đường dẫn thoát ra ngoài dest (path traversal)."""
    dest = dest.resolve()
    for m in tar.getmembers():
        target = (dest / m.name).resolve()
        if dest not in target.parents and target != dest:
            raise RuntimeError(f"đường dẫn đáng ngờ trong tar: {m.name}")
        if not (m.isfile() or m.isdir()):
            raise RuntimeError(f"tar chứa link/thiết bị: {m.name}")
    tar.extractall(dest)


def download_caltech() -> Path:
    """Trả về thư mục 101_ObjectCategories."""
    DATA_RAW.mkdir(parents=True, exist_ok=True)
    cat_dir = DATA_RAW / "101_ObjectCategories"
    if cat_dir.is_dir():
        return cat_dir
    zip_path = DATA_RAW / "caltech-101.zip"
    if not zip_path.exists():
        print("Đang tải", CALTECH_URL)
        req = urllib.request.Request(CALTECH_URL, headers={"User-Agent": "Mozilla/5.0"})
        tmp = zip_path.with_suffix(".part")
        with urllib.request.urlopen(req) as r, open(tmp, "wb") as fh:
            while chunk := r.read(1 << 20):
                fh.write(chunk)
        tmp.rename(zip_path)          # chỉ đổi tên khi tải xong, tránh zip dở dang
    tgz_path = DATA_RAW / "101_ObjectCategories.tar.gz"
    if not tgz_path.exists():
        with zipfile.ZipFile(zip_path) as z:
            name = next(n for n in z.namelist() if n.endswith("101_ObjectCategories.tar.gz"))
            tgz_path.write_bytes(z.read(name))
    with tarfile.open(tgz_path) as t:
        safe_extract_tar(t, DATA_RAW)
    return cat_dir


def to_gray_resized(src: Path):
    img = cv2.imread(str(src), cv2.IMREAD_GRAYSCALE)
    if img is None:
        raise RuntimeError(f"không đọc được ảnh {src}")
    h, w = img.shape
    s = MAX_SIDE / max(h, w)
    # INTER_AREA khi thu nhỏ (ít răng cưa), INTER_CUBIC khi phóng to
    interp = cv2.INTER_AREA if s < 1 else cv2.INTER_CUBIC
    return cv2.resize(img, (round(w * s), round(h * s)), interpolation=interp)


def main():
    cat_dir = download_caltech()
    rows = []
    for label in CLASSES:
        files = sorted((cat_dir / label).glob("*.jpg"))   # sort trước để kết quả không phụ thuộc hệ điều hành
        assert len(files) >= N_PER_CLASS, f"{label} chỉ có {len(files)} ảnh"
        chosen, _ = (train_test_split(files, train_size=N_PER_CLASS, random_state=SEED)
                     if len(files) > N_PER_CLASS else (files, None))
        tr, te = train_test_split(sorted(chosen), test_size=TEST_SIZE, random_state=SEED)
        for split, group in (("train", tr), ("test", te)):
            for f in sorted(group):
                out = DATA_IMG / label / (f.stem + ".png")       # PNG: không nén mất mát lần 2
                if not out.exists():
                    out.parent.mkdir(parents=True, exist_ok=True)
                    cv2.imwrite(str(out), to_gray_resized(f))
                rows.append({"path": out.relative_to(DATA_IMG.parent).as_posix(),
                             "label": label, "split": split, "src": f.name})
        print(f"{label:12s} có {len(files):4d} ảnh -> chọn {len(chosen)} ({len(tr)} train / {len(te)} test)")

    with open(DATA_SPLIT, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["path", "label", "split", "src"])
        w.writeheader()
        w.writerows(rows)
    print("Đã ghi", DATA_SPLIT, f"({len(rows)} ảnh)")


if __name__ == "__main__":
    main()
