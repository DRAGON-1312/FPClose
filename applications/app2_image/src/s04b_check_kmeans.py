"""Bước 3b: kiểm chứng k-means trên máy đang chạy (chỉ để so sánh, KHÔNG thay codebook dùng cho các bước sau).

Chạy:  python src/s04b_check_kmeans.py [--force]

Bước 3 mặc định dùng codebook đã lưu trong reference/ (bản dùng cho báo cáo), vì k-means cho kết quả khác nhau giữa
các nền tảng dù cùng code, seed và phiên bản thư viện. Bước này chạy lại ĐÚNG đoạn k-means của bước 3 (cùng mẫu
descriptor, cùng tham số, seed 42) trên máy hiện tại và so với codebook đã lưu bằng các tiêu chí không phụ thuộc cách
đánh số cụm (số thứ tự cụm là nhãn tùy ý):
  inertia_saved, inertia_relearned, inertia_diff_pct   tổng bình phương khoảng cách mẫu -> tâm gần nhất, trên CÙNG mẫu
  ari                                                  Adjusted Rand Index giữa hai cách gán cụm trên cùng mẫu (1 = như nhau)
  size_min/median/max_saved|relearned                  số descriptor mẫu mỗi cụm
  same_as_saved                                        hai codebook trùng từng byte không
Kết quả: out/kmeans_check.csv. Bảng này DỰ KIẾN khác giữa các máy (nó đo chính sự khác biệt đó).
"""
import sys

import numpy as np
import pandas as pd
from sklearn.cluster import MiniBatchKMeans
from sklearn.metrics import adjusted_rand_score

from config import (DATA_SIFT, DATA_SPLIT, K_LIST, N_SAMPLE_DESC, OUT, SEED, clear_step, codebook_path,
                    mark_step_done, step_done)
from s04_codebook import sample_even_per_image


def spec():
    params = {"K_LIST": K_LIST, "N_SAMPLE_DESC": N_SAMPLE_DESC, "SEED": SEED,
              "kmeans": "MiniBatchKMeans(n_init=3, batch_size=4096)"}
    return [OUT / "kmeans_check.csv"], [DATA_SIFT, DATA_SPLIT] + [codebook_path(k) for k in K_LIST], params


def nearest(X, c, block=50_000):
    """Nhãn tâm gần nhất và tổng bình phương khoảng cách (float64), tính theo khối để tiết kiệm bộ nhớ."""
    labels, total = np.empty(len(X), np.int64), 0.0
    cc = (c.astype(np.float64) ** 2).sum(1)
    for s in range(0, len(X), block):
        x = X[s:s + block].astype(np.float64)
        d = (x ** 2).sum(1)[:, None] - 2 * x @ c.T.astype(np.float64) + cc[None]
        labels[s:s + block] = d.argmin(1)
        total += float(np.maximum(d.min(1), 0).sum())
    return labels, total


def main(force: bool = False):
    outs, ins, params = spec()
    if not force and step_done("s04b", outs, ins, params):
        return
    clear_step("s04b")
    split = pd.read_csv(DATA_SPLIT)
    z = np.load(DATA_SIFT)
    idx, q = sample_even_per_image(z["offsets"], (split.split == "train").to_numpy(), N_SAMPLE_DESC,
                                   np.random.default_rng(SEED))
    X = z["desc"][idx].astype(np.float32)               # đúng mẫu mà bước 3 dùng để học codebook
    print(f"Mẫu: {len(X):,} descriptor train, tối đa {q}/ảnh (như bước 3)")
    rows = []
    for k in K_LIST:
        saved = np.load(codebook_path(k))
        new = MiniBatchKMeans(n_clusters=k, n_init=3, batch_size=4096, random_state=SEED).fit(X)
        new = new.cluster_centers_.astype(np.float32)
        lab_s, in_s = nearest(X, saved)
        lab_n, in_n = nearest(X, new)
        sz_s, sz_n = np.bincount(lab_s, minlength=k), np.bincount(lab_n, minlength=k)
        rows.append({"k": k, "same_as_saved": bool(np.array_equal(saved, new)),
                     "inertia_saved": round(in_s), "inertia_relearned": round(in_n),
                     "inertia_diff_pct": round(100 * (in_n - in_s) / in_s, 3),
                     "ari": round(adjusted_rand_score(lab_s, lab_n), 4),
                     "size_min_saved": int(sz_s.min()), "size_min_relearned": int(sz_n.min()),
                     "size_median_saved": int(np.median(sz_s)), "size_median_relearned": int(np.median(sz_n)),
                     "size_max_saved": int(sz_s.max()), "size_max_relearned": int(sz_n.max())})
        print(rows[-1], flush=True)
    OUT.mkdir(exist_ok=True)
    pd.DataFrame(rows).to_csv(OUT / "kmeans_check.csv", index=False)
    print("Đã ghi", OUT / "kmeans_check.csv", "(chỉ để so sánh; các bước sau vẫn dùng codebook đã lưu)")
    mark_step_done("s04b", ins, params)


if __name__ == "__main__":
    main("--force" in sys.argv)
