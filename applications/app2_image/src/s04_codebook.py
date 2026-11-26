"""Bước 3: học codebook (từ điển từ thị giác) bằng k-means chỉ trên train, rồi gán từ cho mọi keypoint.

Chạy:  python src/s04_codebook.py [--force]
Kết quả:
  data/codebook_k100.npy, data/codebook_k300.npy   tâm cụm (k,128)
  data/words.npz     k100, k300: (N,) int16, từ (0..k-1) của từng keypoint, cùng thứ tự với data/sift.npz
  out/codebook_stats.csv   thống kê mỗi codebook (số mẫu, inertia, kích thước cụm)
Từ được đánh số 0..k-1; bước giao dịch (s05) mới đổi thành item SPMF bắt đầu từ 1.
"""
import hashlib
import sys

import numpy as np
import pandas as pd
from sklearn.cluster import MiniBatchKMeans

from config import (DATA_SIFT, DATA_SPLIT, DATA_WORDS, K_LIST, N_SAMPLE_DESC, OUT, SEED, codebook_path,
                    clear_step, mark_step_done, step_done)


def spec():
    outs = [DATA_WORDS, OUT / "codebook_stats.csv"] + [codebook_path(k) for k in K_LIST]
    return outs, [DATA_SIFT, DATA_SPLIT], {"K_LIST": K_LIST, "N_SAMPLE_DESC": N_SAMPLE_DESC, "SEED": SEED,
                                          "kmeans": "MiniBatchKMeans(n_init=3, batch_size=4096)"}


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
