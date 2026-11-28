"""Render a compact report figure from existing app2 results; does not rerun mining.

Run from the repository root with the app2 Python environment.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "applications/app2_image/src"))

import cv2
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from config import DATA_IMG, DATA_SIFT, DATA_SPLIT, DATA_WORDS, OUT, SEED, CLASSES, N_FIG_IMAGES
from s07_growth_viz import train_bitsets, images_of, image_contours, pattern_words


def main():
    split = pd.read_csv(DATA_SPLIT)
    z, words = np.load(DATA_SIFT), np.load(DATA_WORDS)
    top = pd.read_csv(OUT / "growth_top_k300.csv").groupby("class", sort=False).head(1).set_index("class")
    rows, bits, masks, full = train_bitsets(300)
    rng = np.random.default_rng(SEED)
    picks = {}
    # Match the original notebook figure selection, then retain its first two images.
    for c in CLASSES:
        b = full
        for it in top.loc[c, "items"].split():
            b &= bits[int(it)]
        imgs = images_of(b, masks[c], rows)
        picks[c] = sorted(rng.choice(imgs, size=min(N_FIG_IMAGES, len(imgs)), replace=False))[:2]
    plt.rcParams.update({"font.family": "serif", "font.serif": ["Times New Roman", "DejaVu Serif"]})
    fig, axes = plt.subplots(2, 3, figsize=(7.1, 3.6))
    for col, c in enumerate(["Leopards", "Faces_easy", "Motorbikes"]):
        pw = pattern_words(top.loc[c, "items"])
        cmap = plt.get_cmap("tab20", max(len(pw), 2))
        contours = image_contours(picks[c], split)
        for row, i in enumerate(picks[c]):
            ax = axes[row, col]
            img = cv2.imread(str(DATA_IMG.parent / split.loc[i, "path"]), cv2.IMREAD_GRAYSCALE)
            ax.imshow(img, cmap="gray")
            ct = contours[i]
            ax.plot(np.r_[ct[:, 0], ct[0, 0]], np.r_[ct[:, 1], ct[0, 1]], color="yellow", lw=0.7)
            sl = slice(z["offsets"][i], z["offsets"][i + 1])
            for j, word in enumerate(pw):
                sel = words['k300'][sl] == word
                ax.scatter(z['x'][sl][sel], z['y'][sl][sel], s=12, color=cmap(j), edgecolors='black', linewidths=0.3)
            ax.axis("off")
            if row == 0:
                ax.set_title(c, fontsize=11)
    fig.tight_layout(pad=0.3, h_pad=0.4, w_pad=0.6)
    dst = ROOT / 'docs/IEEE-conference-template-062824/figures/app2_patterns.png'
    dst.parent.mkdir(exist_ok=True)
    fig.savefig(dst, dpi=300, bbox_inches='tight')
    plt.close(fig)
    print(dst)


if __name__ == '__main__':
    main()
