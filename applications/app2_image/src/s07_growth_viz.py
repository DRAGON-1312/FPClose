"""Bước 6: growth rate của các mẫu, top mẫu mỗi lớp, vẽ mẫu lên ảnh, đo mẫu nằm trên vật thể hay nền.

Chạy:  python src/s07_growth_viz.py [--force]

Input: data/patterns/k{k}_word_closed.csv (tập đóng do FPClose của nhóm khai thác ở bước 5, CHỈ trên train),
       data/transactions/k{k}_word/all_train.txt + transactions_index.csv, data/sift.npz, data/words.npz,
       chú thích đường viền vật thể Annotations.tar (giải nén tự động từ caltech-101.zip).

Growth rate (emerging pattern, Dong & Li 1999), mọi số đếm chỉ trên train:
    GR(X, c) = supp_c(X) / supp_ngoài(X)
    supp_c(X)     = số ảnh lớp c chứa X / số ảnh lớp c       (140)
    supp_ngoài(X) = số ảnh các lớp khác chứa X / số ảnh các lớp khác  (560)
  supp_ngoài = 0 -> GR = vô cực. Xếp hạng (đã thống nhất trước khi chạy): GR giảm dần (vô cực đứng đầu), rồi
  support trong lớp giảm dần, rồi độ dài giảm dần, rồi chuỗi item (để thứ tự xác định).
  Chỉ xét mẫu dài >= 2 (tổ hợp). Support trong lớp tính lại bằng bitset và phải khớp #SUP của FPClose.

Vật thể hay nền: với mỗi mẫu top-TOP_TABLE, trên mọi ảnh train của lớp chứa mẫu, lấy các keypoint có từ thuộc mẫu,
  đo tỉ lệ nằm TRONG đường viền vật thể (on_object). Mốc so sánh (baseline): tỉ lệ MỌI keypoint của cùng các
  ảnh đó nằm trong đường viền. on_object < baseline nghĩa là mẫu nghiêng về nền hơn một keypoint bất kỳ.

Kết quả:
  out/growth_summary.csv      mỗi (k, lớp): số mẫu dài >= 2, số mẫu GR vô cực, GR / support của top-10
  out/growth_top_k{k}.csv     top-10 mỗi lớp: từ, độ dài, support trong/ngoài, GR, on_object, baseline
  data/patterns/k{k}_word_top.csv   top-TOP_KEEP mỗi lớp (cho bước phân loại)
  out/patterns_k{k}.png       mẫu top-1 mỗi lớp vẽ trên N_FIG_IMAGES ảnh train (kèm đường viền vật thể)
"""
import io
import sys
import tarfile
import zipfile

import cv2
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import scipy.io as sio
from matplotlib.path import Path as MplPath

from config import (ANN_DIR, ANN_DIRS, CLASSES, DATA_IMG, DATA_PATTERNS, DATA_RAW, DATA_SIFT, DATA_SPLIT, DATA_TX,
                    DATA_WORDS, K_LIST, MIN_PATTERN_LEN, N_FIG_IMAGES, OUT, SEED, TOP_KEEP, TOP_TABLE,
                    clear_step, mark_step_done, step_done)
from s01_prepare_data import safe_extract_tar

VARIANT = "word"


def spec():
    outs = [OUT / "growth_summary.csv"]
    ins = [DATA_SPLIT, DATA_SIFT, DATA_WORDS]
    for k in K_LIST:
        outs += [OUT / f"growth_top_k{k}.csv", OUT / f"patterns_k{k}.png", DATA_PATTERNS / f"k{k}_{VARIANT}_top.csv"]
        d = DATA_TX / f"k{k}_{VARIANT}"
        ins += [DATA_PATTERNS / f"k{k}_{VARIANT}_closed.csv", d / "all_train.txt", d / "transactions_index.csv"]
    params = {"K_LIST": K_LIST, "MIN_PATTERN_LEN": MIN_PATTERN_LEN, "TOP_TABLE": TOP_TABLE, "TOP_KEEP": TOP_KEEP,
              "N_FIG_IMAGES": N_FIG_IMAGES, "ANN_DIRS": ANN_DIRS, "SEED": SEED}
    return outs, ins, params


def ensure_annotations():
    if (ANN_DIR / "Leopards").is_dir():
        return
    z = zipfile.ZipFile(DATA_RAW / "caltech-101.zip")
    name = next(n for n in z.namelist() if n.endswith("Annotations.tar"))
    with tarfile.open(fileobj=io.BytesIO(z.read(name))) as t:
        safe_extract_tar(t, DATA_RAW)


def train_bitsets(k):
    """Bitset trên các giao dịch train (thứ tự dòng của all_train.txt): item -> bitmask; lớp -> bitmask."""
    d = DATA_TX / f"k{k}_{VARIANT}"
    idx = pd.read_csv(d / "transactions_index.csv")
    tr = idx[(idx.split == "train") & ~idx["empty"]].sort_values("line_common")
    lines = [l for l in (d / "all_train.txt").read_text(encoding="utf-8").splitlines() if l.strip()]
    assert len(lines) == len(tr) and (tr.line_common.to_numpy() == np.arange(1, len(tr) + 1)).all()
    bits = {}
    for pos, l in enumerate(lines):
        for it in map(int, l.split()):
            bits[it] = bits.get(it, 0) | (1 << pos)
    # int(p): p là int64 của NumPy, `1 << p` sẽ tràn khi p >= 64; phải dùng số nguyên Python (không giới hạn bit)
    masks = {c: sum(1 << int(p) for p in np.flatnonzero(tr.label.to_numpy() == c)) for c in CLASSES}
    assert all(m.bit_count() == (tr.label == c).sum() for c, m in masks.items())
    return tr.index.to_numpy(), bits, masks, (1 << len(tr)) - 1     # tr.index = số dòng ảnh trong split.csv


def growth_table(k, bits, masks, full):
    pats = pd.read_csv(DATA_PATTERNS / f"k{k}_{VARIANT}_closed.csv")
    pats = pats[pats.length >= MIN_PATTERN_LEN].reset_index(drop=True)
    out = []
    for c in CLASSES:
        g = pats[pats["class"] == c].reset_index(drop=True)
        m_in, m_out = masks[c], full & ~masks[c]
        n_in, n_out = m_in.bit_count(), m_out.bit_count()
        s_in = np.empty(len(g), np.int64); s_out = np.empty(len(g), np.int64)
        for i, items in enumerate(g["items"]):
            b = full
            for it in items.split():
                b &= bits[int(it)]
            s_in[i], s_out[i] = (b & m_in).bit_count(), (b & m_out).bit_count()
        assert (s_in == g.sup.to_numpy()).all(), f"{c}: support trong lớp khác #SUP của FPClose"
        r_in, r_out = s_in / n_in, s_out / n_out
        with np.errstate(divide="ignore"):
            gr = np.where(s_out == 0, np.inf, r_in / np.where(s_out == 0, 1, r_out))
        g = g.assign(sup_in=s_in, sup_in_rel=r_in.round(4), sup_out=s_out, sup_out_rel=r_out.round(4), growth=gr)
        out.append(g.sort_values(["growth", "sup_in", "length", "items"], ascending=[False, False, False, True]))
    return out


def image_contours(rows, split):
    """Đường viền vật thể (tọa độ ảnh ĐÃ resize) cho các ảnh trong rows (số dòng split.csv)."""
    res = {}
    for i in rows:
        r = split.loc[i]
        mat = sio.loadmat(ANN_DIR / ANN_DIRS[r.label] / r.src.replace("image_", "annotation_").replace(".jpg", ".mat"))
        y1, _, x1, _ = mat["box_coord"].ravel().astype(float)
        cx, cy = mat["obj_contour"].astype(float)
        h0, w0 = cv2.imread(str(DATA_RAW / "101_ObjectCategories" / r.label / r.src), cv2.IMREAD_GRAYSCALE).shape
        h1, w1 = cv2.imread(str(DATA_IMG.parent / r.path), cv2.IMREAD_GRAYSCALE).shape
        res[i] = np.c_[(cx + x1) * w1 / w0, (cy + y1) * h1 / h0]
    return res


def images_of(b, mask, tr_rows):
    bb = b & mask
    return [tr_rows[p] for p in range(bb.bit_length()) if bb >> p & 1]


def pattern_words(items):
    return [int(it) - 1 for it in items.split()]           # item SPMF = từ + 1 (s05)


def on_object(top, k, bits, masks, full, tr_rows, split, z, words, contours):
    """Thêm cột on_object, baseline, n_images cho các mẫu top."""
    offs, x, y = z["offsets"], z["x"], z["y"]
    w = words[f"k{k}"]
    vals = []
    for _, p in top.iterrows():
        b = full
        for it in p["items"].split():
            b &= bits[int(it)]
        imgs = images_of(b, masks[p["class"]], tr_rows)
        ws = set(pattern_words(p["items"]))
        n_pat = in_pat = n_all = in_all = 0
        for i in imgs:
            if i not in contours:
                contours.update(image_contours([i], split))
            sl = slice(offs[i], offs[i + 1])
            inside = MplPath(contours[i]).contains_points(np.c_[x[sl], y[sl]])
            sel = np.isin(w[sl], list(ws))
            n_pat += sel.sum(); in_pat += inside[sel].sum(); n_all += len(inside); in_all += inside.sum()
        vals.append({"n_images": len(imgs), "on_object": round(in_pat / n_pat, 3),
                     "baseline": round(in_all / n_all, 3)})
    return pd.concat([top.reset_index(drop=True), pd.DataFrame(vals)], axis=1)


def draw(k, tops, bits, masks, full, tr_rows, split, z, words, contours):
    offs, x, y = z["offsets"], z["x"], z["y"]
    w = words[f"k{k}"]
    rng = np.random.default_rng(SEED)
    fig, axes = plt.subplots(len(CLASSES), N_FIG_IMAGES, figsize=(3.3 * N_FIG_IMAGES, 3.3 * len(CLASSES)))
    for row, c in zip(axes, CLASSES):
        p = tops[c].iloc[0]
        b = full
        for it in p["items"].split():
            b &= bits[int(it)]
        imgs = images_of(b, masks[c], tr_rows)
        pick = sorted(rng.choice(imgs, size=min(N_FIG_IMAGES, len(imgs)), replace=False))
        pw = pattern_words(p["items"])
        cmap = plt.get_cmap("tab20", max(len(pw), 2))
        for ax, i in zip(row, pick):
            img = cv2.imread(str(DATA_IMG.parent / split.loc[i, "path"]), cv2.IMREAD_GRAYSCALE)
            ax.imshow(img, cmap="gray"); ax.axis("off")
            if i not in contours:
                contours.update(image_contours([i], split))
            ct = contours[i]
            ax.plot(np.r_[ct[:, 0], ct[0, 0]], np.r_[ct[:, 1], ct[0, 1]], color="yellow", lw=1)
            sl = slice(offs[i], offs[i + 1])
            for j, word in enumerate(pw):
                s = w[sl] == word
                ax.scatter(x[sl][s], y[sl][s], s=28, color=cmap(j), edgecolors="black", linewidths=0.5)
        gr = "∞" if np.isinf(p["growth"]) else f"{p['growth']:.1f}"
        row[0].set_title(f"{c}: {p['length']} từ, GR={gr}, sup={p['sup_in']}/140\n"
                         f"trên vật thể {p['on_object']:.0%} (mốc {p['baseline']:.0%})", fontsize=9, loc="left")
    fig.suptitle(f"k = {k}: mẫu top-1 mỗi lớp (chấm màu = keypoint thuộc mẫu, viền vàng = vật thể)", fontsize=11)
    fig.tight_layout()
    fig.savefig(OUT / f"patterns_k{k}.png", dpi=110)
    plt.close(fig)


def main(force: bool = False):
    outs, ins, params = spec()
    if not force and step_done("s07", outs, ins, params):
        return
    clear_step("s07")                   # chạy lại: bỏ dấu hoàn tất cũ ngay từ đầu
    ensure_annotations()
    split = pd.read_csv(DATA_SPLIT)
    z, words = np.load(DATA_SIFT), np.load(DATA_WORDS)
    contours, summary = {}, []
    for k in K_LIST:
        tr_rows, bits, masks, full = train_bitsets(k)
        tables = growth_table(k, bits, masks, full)
        tops, keep = {}, []
        for c, g in zip(CLASSES, tables):
            keep.append(g.head(TOP_KEEP))
            tops[c] = on_object(g.head(TOP_TABLE), k, bits, masks, full, tr_rows, split, z, words, contours)
            fin = g.growth[np.isfinite(g.growth)]
            summary.append({"k": k, "class": c, "minsup_pct": int(g.minsup_pct.iloc[0]), "n_len2": len(g),
                            "n_growth_inf": int(np.isinf(g.growth).sum()),
                            "max_finite_growth": round(float(fin.max()), 2) if len(fin) else None,
                            "top10_growth_min": tops[c].growth.min(), "top10_sup_in_median": tops[c].sup_in.median(),
                            "top10_on_object_mean": tops[c].on_object.mean().round(3),
                            "top10_baseline_mean": tops[c].baseline.mean().round(3)})
            print(summary[-1], flush=True)
        pd.concat(keep).to_csv(DATA_PATTERNS / f"k{k}_{VARIANT}_top.csv", index=False)
        top = pd.concat(tops.values())
        top.insert(top.columns.get_loc("items") + 1, "words",
                   top["items"].map(lambda s: " ".join(f"w{v}" for v in pattern_words(s))))
        top.drop(columns=["minsup_pct", "sup", "sup_rel"]).to_csv(OUT / f"growth_top_k{k}.csv", index=False)
        draw(k, tops, bits, masks, full, tr_rows, split, z, words, contours)
        print("Đã ghi", OUT / f"patterns_k{k}.png", flush=True)
    pd.DataFrame(summary).to_csv(OUT / "growth_summary.csv", index=False)
    print(pd.DataFrame(summary).to_string(index=False))
    mark_step_done("s07", ins, params)


if __name__ == "__main__":
    main("--force" in sys.argv)
