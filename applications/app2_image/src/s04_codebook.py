"""Bước 3: học codebook (từ điển từ thị giác) bằng k-means chỉ trên train, rồi gán từ cho mọi keypoint.

Chạy:  python src/s04_codebook.py [--force]
Kết quả:
  data/codebook_k100.npy, data/codebook_k300.npy   tâm cụm (k,128)
  data/words.npz     k100, k300: (N,) int16, từ (0..k-1) của từng keypoint, cùng thứ tự với data/sift.npz
  out/codebook_stats.csv   thống kê mỗi codebook (số mẫu, inertia, kích thước cụm)
Từ được đánh số 0..k-1; bước giao dịch (s05) mới đổi thành item SPMF bắt đầu từ 1.

Mặc định (USE_SAVED_CODEBOOK = True trong config.py) KHÔNG học lại mà dùng codebook + từ thị giác đã lưu trong
reference/ (bản đã dùng cho báo cáo, kiểm tra SHA-256), vì k-means ra khác nhau giữa các nền tảng dù cùng phiên bản
thư viện và cùng seed. Code học k-means vẫn giữ nguyên bên dưới (đặt APP2_RELEARN_CODEBOOK=1 để chạy).
"""
import hashlib
import os
import shutil
import sys

import numpy as np
import pandas as pd
from sklearn.cluster import MiniBatchKMeans

from config import (DATA_SIFT, DATA_SPLIT, DATA_WORDS, K_LIST, N_SAMPLE_DESC, OUT, REF_DIR, SEED, USE_SAVED_CODEBOOK,
                    codebook_path, clear_step, mark_step_done, step_done)

REF_FILES = [f"codebook_k{k}.npy" for k in K_LIST] + ["words.npz", "codebook_stats.csv"]


def spec():
    outs = [DATA_WORDS, OUT / "codebook_stats.csv"] + [codebook_path(k) for k in K_LIST]
    params = {"K_LIST": K_LIST, "N_SAMPLE_DESC": N_SAMPLE_DESC, "SEED": SEED,
              "kmeans": "MiniBatchKMeans(n_init=3, batch_size=4096)", "USE_SAVED_CODEBOOK": USE_SAVED_CODEBOOK}
    ins = [DATA_SIFT, DATA_SPLIT] + ([REF_DIR / f for f in REF_FILES] if USE_SAVED_CODEBOOK else [])
    return outs, ins, params


def use_saved():
    """Chép codebook + từ thị giác đã lưu từ reference/ (kiểm tra SHA-256 và khớp với sift.npz của máy này)."""
    want = {}
    for line in (REF_DIR / "SHA256SUMS.txt").read_text(encoding="utf-8").splitlines():
        if line.strip():
            digest, name = line.split(maxsplit=1)
            want[name.lstrip("*")] = digest                 # sha256sum ghi '*tên' ở chế độ nhị phân
    for f in REF_FILES:
        got = hashlib.sha256((REF_DIR / f).read_bytes()).hexdigest()
        assert want.get(f) == got, f"SHA-256 của reference/{f} không khớp SHA256SUMS.txt"
    z, words = np.load(DATA_SIFT), np.load(REF_DIR / "words.npz")
    desc = z["desc"].astype(np.float32)
    for k in K_LIST:
        w = words[f"k{k}"]
        assert len(w) == len(desc), "words.npz đã lưu không khớp sift.npz của máy này (SIFT khác?)"
        # Chẩn đoán: gán lại bằng codebook đã lưu trên máy này, đếm keypoint ra cùng từ (chỉ in, không dùng).
        c = np.load(REF_DIR / f"codebook_k{k}.npy")
        same = 0
        for s in range(0, len(desc), 50_000):              # theo khối để không tốn hàng trăm MB bộ nhớ
            x = desc[s:s + 50_000]
            d = (x ** 2).sum(1)[:, None] - 2 * x @ c.T + (c ** 2).sum(1)[None]
            same += int((d.argmin(1) == w[s:s + 50_000]).sum())
        print(f"k={k}: gán lại trên máy này trùng {same / len(desc):.4%} keypoint với words.npz đã lưu")
        shutil.copy(REF_DIR / f"codebook_k{k}.npy", codebook_path(k))
    shutil.copy(REF_DIR / "words.npz", DATA_WORDS)
    OUT.mkdir(exist_ok=True)
    shutil.copy(REF_DIR / "codebook_stats.csv", OUT / "codebook_stats.csv")
    print(pd.read_csv(OUT / "codebook_stats.csv").to_string(index=False))
    print("Đã dùng codebook đã lưu trong", REF_DIR, "(đặt APP2_RELEARN_CODEBOOK=1 để học lại)")


def sample_even_per_image(offsets, train_mask, total, rng):
    """Lấy ~total descriptor từ các ảnh train, mỗi ảnh tối đa q cái (q chung, tìm bằng chia đôi).

    Ảnh ít keypoint hơn q thì lấy hết. Nhờ vậy ảnh nhiều keypoint (Motorbikes, Leopards...) không
    áp đảo codebook so với airplanes (~280 keypoint/ảnh)."""
    sizes = np.diff(offsets)
    idx_img = np.flatnonzero(train_mask)
    lo, hi = 1, int(sizes[idx_img].max())
    while lo < hi:                                      # q nhỏ nhất sao cho sum(min(n_i, q)) >= total
        mid = (lo + hi) // 2
        if np.minimum(sizes[idx_img], mid).sum() >= total:
            hi = mid
        else:
            lo = mid + 1
    q = lo
    picked = []
    for i in idx_img:
        n = sizes[i]
        local = np.arange(n) if n <= q else rng.choice(n, size=q, replace=False)
        picked.append(offsets[i] + local)
    return np.concatenate(picked), q


def main(force: bool = False):
    outs, ins, params = spec()
    if not force and step_done("s04", outs, ins, params):
        return
    clear_step("s04")                   # chạy lại: bỏ dấu hoàn tất cũ ngay từ đầu
    if USE_SAVED_CODEBOOK:
        use_saved()
        mark_step_done("s04", ins, params)
        return
    split = pd.read_csv(DATA_SPLIT)
    z = np.load(DATA_SIFT)
    desc, offsets = z["desc"], z["offsets"]
    train_mask = (split.split == "train").to_numpy()

    rng = np.random.default_rng(SEED)
    idx, q = sample_even_per_image(offsets, train_mask, N_SAMPLE_DESC, rng)
    img_of_kp = np.repeat(np.arange(len(split)), np.diff(offsets))
    assert train_mask[img_of_kp[idx]].all(), "codebook chỉ được học từ ảnh train"
    sample = desc[idx].astype(np.float32)
    print(f"Mẫu: {len(sample):,} descriptor từ {train_mask.sum()} ảnh train, tối đa {q}/ảnh")

    words, rows = {}, []
    for k in K_LIST:
        km = MiniBatchKMeans(n_clusters=k, n_init=3, batch_size=4096, random_state=SEED).fit(sample)
        np.save(codebook_path(k), km.cluster_centers_.astype(np.float32))
        w = km.predict(desc.astype(np.float32)).astype(np.int16)    # mọi keypoint: train và test
        words[f"k{k}"] = w
        size = np.bincount(w[train_mask[img_of_kp]], minlength=k)   # số keypoint train mỗi từ
        rows.append({"k": k, "n_sample": len(sample), "inertia": round(km.inertia_, 0), "n_iter": km.n_iter_,
                     "word_size_min": size.min(), "word_size_median": int(np.median(size)),
                     "word_size_max": size.max(), "unused_words_train": int((size == 0).sum()),
                     # SHA-256 file tâm cụm: đối chiếu nhanh giữa các máy (Colab vs máy cá nhân) ngay sau bước 3
                     "codebook_sha256": hashlib.sha256(codebook_path(k).read_bytes()).hexdigest()[:16]})
        print(rows[-1])
    np.savez_compressed(DATA_WORDS, **words)
    OUT.mkdir(exist_ok=True)
    pd.DataFrame(rows).to_csv(OUT / "codebook_stats.csv", index=False)
    print("Đã ghi", DATA_WORDS)
    mark_step_done("s04", ins, params)


if __name__ == "__main__":
    main("--force" in sys.argv)
