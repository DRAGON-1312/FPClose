"""Bước 1b: chạy thử SIFT trên vài ảnh mỗi lớp để xem số keypoint trung bình.

Chạy:  python src/s02_sift_probe.py [số_ảnh_mỗi_lớp=10]
Kết quả: in bảng thống kê, ghi out/sift_probe.csv và out/sift_probe.png (keypoint vẽ trên 1 ảnh/lớp).
"""
import sys

import cv2
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

from config import CLASSES, DATA_IMG, DATA_SPLIT, OUT, SEED, SIFT_NFEATURES


def main(n_per_class: int = 10):
    OUT.mkdir(exist_ok=True)
    split = pd.read_csv(DATA_SPLIT)
    sample = (split[split.split == "train"].groupby("label", group_keys=False)
              .apply(lambda g: g.sample(n=min(n_per_class, len(g)), random_state=SEED)))
    sift = cv2.SIFT_create(nfeatures=SIFT_NFEATURES)

    stats, examples = [], {}
    for r in sample.itertuples():
        img = cv2.imread(str(DATA_IMG.parent / r.path), cv2.IMREAD_GRAYSCALE)
        kps, desc = sift.detectAndCompute(img, None)
        stats.append({"label": r.label, "path": r.path, "h": img.shape[0], "w": img.shape[1],
                      "n_kp": len(kps), "desc_dim": None if desc is None else desc.shape[1]})
        examples.setdefault(r.label, (img, kps))

    df = pd.DataFrame(stats)
    df.to_csv(OUT / "sift_probe.csv", index=False)
    print(df.groupby("label").n_kp.agg(["count", "mean", "min", "max"]).round(1))
    print("Trung bình toàn bộ:", round(df.n_kp.mean(), 1), "keypoint/ảnh; descriptor dim =", df.desc_dim.iloc[0])

    fig, axes = plt.subplots(1, len(CLASSES), figsize=(4 * len(CLASSES), 4))
    for ax, label in zip(axes, CLASSES):
        img, kps = examples[label]
        vis = cv2.drawKeypoints(img, kps, None, flags=cv2.DRAW_MATCHES_FLAGS_DRAW_RICH_KEYPOINTS)
        ax.imshow(vis[..., ::-1]); ax.set_title(f"{label} ({len(kps)} kp)"); ax.axis("off")
    fig.tight_layout(); fig.savefig(OUT / "sift_probe.png", dpi=110)
    print("Đã ghi", OUT / "sift_probe.png")


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 10)
