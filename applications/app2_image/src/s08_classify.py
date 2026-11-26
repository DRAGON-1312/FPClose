"""Bước 7: dùng mẫu trực quan để phân loại ảnh, so 3 cấu hình đặc trưng.

Chạy:  python src/s08_classify.py [--force]

Cùng LogisticRegression(random_state=42) (sau StandardScaler học trên train), cùng cách chia train/test (bước 1):
  A) histogram BoVW: số keypoint mỗi từ / tổng keypoint của ảnh (k chiều). Chuẩn hóa vì airplanes ít keypoint.
  B) vector 0/1: ảnh có chứa TRỌN mẫu hay không, với top-TOP_N_CLF mẫu mỗi lớp theo growth rate (bước 6) -> 100 chiều.
     Mẫu CHỈ khai thác trên train (bước 5); ảnh test chỉ được kiểm tra có chứa mẫu hay không. Giao dịch của ảnh
     lấy từ file SPMF (sau tau + stop word); ảnh rỗng = tập rỗng.
  C) nối A + B.
Báo cáo accuracy (kèm khoảng tin cậy 95% xấp xỉ chuẩn, n = 300 ảnh test), macro-F1, confusion matrix.

Kết quả: out/classification.csv, out/confusion_matrices.png, out/classification_per_class.csv (recall từng lớp).
"""
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import ConfusionMatrixDisplay, accuracy_score, confusion_matrix, f1_score, recall_score
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

from config import (CLASSES, DATA_PATTERNS, DATA_SIFT, DATA_SPLIT, DATA_TX, DATA_WORDS, K_LIST, OUT, SEED, TOP_N_CLF,
                    clear_step, mark_step_done, step_done)

VARIANT = "word"


def spec():
    outs = [OUT / f for f in ("classification.csv", "classification_per_class.csv", "confusion_matrices.png")]
    ins = [DATA_SPLIT, DATA_SIFT, DATA_WORDS]
    for k in K_LIST:
        d = DATA_TX / f"k{k}_{VARIANT}"
        ins += [DATA_PATTERNS / f"k{k}_{VARIANT}_top.csv", d / "all_train.txt", d / "test.txt",
                d / "transactions_index.csv"]
    params = {"K_LIST": K_LIST, "TOP_N_CLF": TOP_N_CLF, "SEED": SEED,
              "model": "StandardScaler + LogisticRegression(max_iter=5000)"}
    return outs, ins, params


def bovw(k, offsets, w):
    H = np.zeros((len(offsets) - 1, k))
    for i in range(len(offsets) - 1):
        H[i] = np.bincount(w[offsets[i]:offsets[i + 1]], minlength=k)
    return H / H.sum(1, keepdims=True)


def transactions(k, n_img):
    """Tập item của mọi ảnh (thứ tự split.csv), đọc lại từ file SPMF của bước 4."""
    d = DATA_TX / f"k{k}_{VARIANT}"
    idx = pd.read_csv(d / "transactions_index.csv")
    files = {s: [set(map(int, l.split())) for l in (d / f).read_text(encoding="utf-8").splitlines() if l.strip()]
             for s, f in [("train", "all_train.txt"), ("test", "test.txt")]}
    tx = [set() for _ in range(n_img)]
    for i, r in idx.iterrows():
        if not r["empty"]:
            tx[i] = files[r.split][int(r.line_common) - 1]
    return tx


def pattern_features(k, tx):
    top = pd.read_csv(DATA_PATTERNS / f"k{k}_{VARIANT}_top.csv")
    top = top.groupby("class", sort=False).head(TOP_N_CLF)        # file đã xếp theo growth rate trong từng lớp
    pats = [set(map(int, s.split())) for s in top["items"]]
    return np.array([[p <= t for p in pats] for t in tx], dtype=float), len(pats)


def main(force: bool = False):
    outs, ins, params = spec()
    if not force and step_done("s08", outs, ins, params):
        return
    clear_step("s08")                   # chạy lại: bỏ dấu hoàn tất cũ ngay từ đầu
    split = pd.read_csv(DATA_SPLIT)
    offsets = np.load(DATA_SIFT)["offsets"]
    words = np.load(DATA_WORDS)
    tr, te = (split.split == "train").to_numpy(), (split.split == "test").to_numpy()
    y = split.label.to_numpy()
    rows, per_class, cms = [], [], []
    for k in K_LIST:
        A = bovw(k, offsets, words[f"k{k}"])
        B, n_pat = pattern_features(k, transactions(k, len(split)))
        for name, X in [("A: BoVW", A), ("B: mẫu", B), ("C: A + B", np.hstack([A, B]))]:
            clf = make_pipeline(StandardScaler(), LogisticRegression(max_iter=5000, random_state=SEED))
            pred = clf.fit(X[tr], y[tr]).predict(X[te])
            acc = accuracy_score(y[te], pred)
            rows.append({"k": k, "config": name, "n_features": X.shape[1], "accuracy": round(acc, 4),
                         "acc_ci95": round(1.96 * np.sqrt(acc * (1 - acc) / te.sum()), 4),
                         "macro_f1": round(f1_score(y[te], pred, average="macro"), 4)})
            rec = recall_score(y[te], pred, labels=CLASSES, average=None)
            per_class.append({"k": k, "config": name, **dict(zip(CLASSES, rec.round(3)))})
            cms.append((k, name, confusion_matrix(y[te], pred, labels=CLASSES)))
            print(rows[-1], flush=True)
        print(f"k={k}: B dùng {n_pat} mẫu; ảnh test chứa >= 1 mẫu: {(B[te].sum(1) > 0).mean():.0%}", flush=True)
    res = pd.DataFrame(rows)
    res.to_csv(OUT / "classification.csv", index=False)
    pd.DataFrame(per_class).to_csv(OUT / "classification_per_class.csv", index=False)

    fig, axes = plt.subplots(len(K_LIST), 3, figsize=(15, 5 * len(K_LIST)))
    for ax, (k, name, cm) in zip(axes.ravel(), cms):
        ConfusionMatrixDisplay(cm, display_labels=CLASSES).plot(ax=ax, colorbar=False, xticks_rotation=45)
        ax.set_title(f"k = {k}, {name}")
    fig.tight_layout()
    fig.savefig(OUT / "confusion_matrices.png", dpi=100)
    print(res.to_string(index=False))
    print(pd.DataFrame(per_class).to_string(index=False))
    mark_step_done("s08", ins, params)


if __name__ == "__main__":
    main("--force" in sys.argv)
