"""Bước 2: trích SIFT cho toàn bộ ảnh (train + test), lưu descriptor và tọa độ keypoint.

Chạy:  python src/s03_sift_extract.py [--force]
Kết quả:
  data/sift.npz       desc (N,128) uint8, x, y, size, angle (N,) float32 (N = tổng keypoint),
                      offsets (n_ảnh+1,) int64: keypoint của ảnh i nằm ở [offsets[i], offsets[i+1]),
                      thứ tự ảnh = thứ tự dòng trong data/split.csv.
  out/sift_stats.csv  số keypoint mỗi ảnh (kèm label, split).
Đã có data/sift.npz thì bỏ qua (dùng --force để chạy lại).
"""
import sys

import cv2
import numpy as np
import pandas as pd

from config import CLASSES, DATA_IMG, DATA_SPLIT, DATA_SIFT, OUT, SIFT_NFEATURES


def main(force: bool = False):
    if DATA_SIFT.exists() and not force:
        print("Đã có", DATA_SIFT, "- bỏ qua (dùng --force để chạy lại)")
        return
    OUT.mkdir(exist_ok=True)
    split = pd.read_csv(DATA_SPLIT)
    sift = cv2.SIFT_create(nfeatures=SIFT_NFEATURES)      # SIFT xác định (không ngẫu nhiên) nên không cần seed

    descs, xs, ys, sizes, angles, counts = [], [], [], [], [], []
    for r in split.itertuples():
        img = cv2.imread(str(DATA_IMG.parent / r.path), cv2.IMREAD_GRAYSCALE)
        assert img is not None, f"Không đọc được {r.path}"
        kps, desc = sift.detectAndCompute(img, None)
        if desc is None:                                  # ảnh không có keypoint nào
            desc, kps = np.zeros((0, 128), np.float32), []
        # Descriptor OpenCV là số nguyên 0..255 lưu dạng float32 -> uint8 không mất thông tin, nhỏ hơn 4 lần.
        assert np.array_equal(desc, desc.astype(np.uint8)), "descriptor không phải số nguyên 0..255"
        descs.append(desc.astype(np.uint8))
        xs.append([k.pt[0] for k in kps]); ys.append([k.pt[1] for k in kps])
        sizes.append([k.size for k in kps]); angles.append([k.angle for k in kps])
        counts.append(len(kps))

    offsets = np.concatenate([[0], np.cumsum(counts)]).astype(np.int64)
    flat = lambda a: np.concatenate([np.asarray(v, np.float32) for v in a])
    np.savez_compressed(DATA_SIFT, desc=np.concatenate(descs), x=flat(xs), y=flat(ys),
                        size=flat(sizes), angle=flat(angles), offsets=offsets)

    stats = split[["path", "label", "split"]].assign(n_kp=counts)
    stats.to_csv(OUT / "sift_stats.csv", index=False)
    print(f"{len(split)} ảnh, {offsets[-1]} keypoint, {(np.array(counts) == 0).sum()} ảnh không có keypoint")
    print(stats.groupby(["label", "split"]).n_kp.agg(["count", "mean", "min", "max"]).round(1)
          .reindex(CLASSES, level=0))
    print("Đã ghi", DATA_SIFT, f"({DATA_SIFT.stat().st_size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main("--force" in sys.argv)
