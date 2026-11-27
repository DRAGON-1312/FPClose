"""Bước 2: trích SIFT cho toàn bộ ảnh (train + test), lưu descriptor và tọa độ keypoint.

Chạy:  python src/s03_sift_extract.py [--force]
Kết quả:
  data/sift.npz       desc (N,128) uint8, x, y, size, angle (N,) float32 (N = tổng keypoint),
                      offsets (n_ảnh+1,) int64: keypoint của ảnh i nằm ở [offsets[i], offsets[i+1]),
                      thứ tự ảnh = thứ tự dòng trong data/split.csv.
  out/sift_stats.csv  số keypoint mỗi ảnh (kèm label, split).
  out/sift_check.csv  so SIFT tính trên máy này với SIFT đã lưu (chỉ để kiểm chứng, DỰ KIẾN khác giữa các máy).

SIFT luôn được TÍNH trên máy đang chạy. Mặc định (USE_SAVED_SIFT trong config.py) data/sift.npz là bản ĐÃ LƯU của lần
chạy dùng cho báo cáo (tải từ Hugging Face theo commit cố định, kiểm tra SHA-256), vì SIFT của OpenCV cho kết quả khác
nhau giữa các nền tảng: trên Colab số keypoint mỗi ảnh giống hệt nhưng nội dung keypoint khác. Bản tính lại chỉ dùng
để so sánh. APP2_RECOMPUTE_SIFT=1 để dùng SIFT tính trên máy này cho các bước sau.
Bỏ qua khi đã chạy với đúng tham số và đúng nội dung ảnh (out/_steps/s03.json); --force để chạy lại.
"""
import hashlib
import sys
import urllib.request

import cv2
import numpy as np
import pandas as pd

from config import (CLASSES, DATA_IMG, DATA_SPLIT, DATA_SIFT, HF_DATASET, HF_REVISION, MAX_SIDE, OUT, SIFT_NFEATURES,
                    SIFT_SHA256, USE_SAVED_SIFT, clear_step, mark_step_done, step_done)


def spec():
    """(output, đầu vào, tham số) của bước: dùng để quyết định có bỏ qua được không.
    Đầu vào gồm NỘI DUNG mọi ảnh trong split.csv: ảnh được resize lại (bước 1) thì bước này chạy lại."""
    imgs = [DATA_IMG.parent / p for p in pd.read_csv(DATA_SPLIT).path]
    params = {"SIFT_NFEATURES": SIFT_NFEATURES, "MAX_SIDE": MAX_SIDE, "USE_SAVED_SIFT": USE_SAVED_SIFT}
    if USE_SAVED_SIFT:
        params.update({"HF_DATASET": HF_DATASET, "HF_REVISION": HF_REVISION, "SIFT_SHA256": SIFT_SHA256})
    return [DATA_SIFT, OUT / "sift_stats.csv", OUT / "sift_check.csv"], [DATA_SPLIT] + imgs, params


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def compute_sift(split):
    """SIFT trên máy đang chạy -> dict mảng giống định dạng data/sift.npz."""
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
    flat = lambda a: np.concatenate([np.asarray(v, np.float32) for v in a])
    return {"desc": np.concatenate(descs), "x": flat(xs), "y": flat(ys), "size": flat(sizes), "angle": flat(angles),
            "offsets": np.concatenate([[0], np.cumsum(counts)]).astype(np.int64)}


def fetch_saved():
    """Tải features/sift.npz đã lưu (Hugging Face, commit cố định) vào data/sift.npz, kiểm tra SHA-256."""
    if DATA_SIFT.exists() and sha256(DATA_SIFT) == SIFT_SHA256:
        print("data/sift.npz đã là bản đã lưu (SHA-256 khớp)")
        return
    url = f"https://huggingface.co/datasets/{HF_DATASET}/resolve/{HF_REVISION}/features/sift.npz"
    tmp = DATA_SIFT.with_suffix(".download")
    print("Tải", url)
    urllib.request.urlretrieve(url, tmp)
    got = sha256(tmp)
    if got != SIFT_SHA256:
        tmp.unlink()
        raise RuntimeError(f"SHA-256 của sift.npz tải về không khớp: {got}")
    tmp.replace(DATA_SIFT)


def compare(split, saved, new):
    """So SIFT đã lưu với SIFT tính lại, theo từng lớp và toàn bộ (không phụ thuộc thứ tự keypoint cho vị trí)."""
    rows = []
    so, no = saved["offsets"], new["offsets"]
    per = []
    for i in range(len(split)):
        a, b = slice(so[i], so[i + 1]), slice(no[i], no[i + 1])
        n_a, n_b = a.stop - a.start, b.stop - b.start
        same_n = n_a == n_b
        same_desc = int((saved["desc"][a] == new["desc"][b]).all(1).sum()) if same_n else 0
        pos = 0
        if n_a and n_b:                                   # keypoint đã lưu có keypoint tính lại cách <= 0,5 px
            dx = saved["x"][a][:, None] - new["x"][b][None]
            dy = saved["y"][a][:, None] - new["y"][b][None]
            pos = int(((dx * dx + dy * dy).min(1) <= 0.25).sum())
        per.append((split.label[i], same_n, n_a, same_desc, pos))
    df = pd.DataFrame(per, columns=["label", "same_n", "n_kp", "same_desc", "pos_match"])
    for g, d in [(c, df[df.label == c]) for c in CLASSES] + [("all", df)]:
        rows.append({"group": g, "images": len(d), "images_same_n_kp": int(d.same_n.sum()),
                     "kp_saved": int(d.n_kp.sum()),
                     "kp_same_desc_same_index_pct": round(100 * d.same_desc.sum() / max(d.n_kp.sum(), 1), 2),
                     "kp_position_match_pct": round(100 * d.pos_match.sum() / max(d.n_kp.sum(), 1), 2)})
    return pd.DataFrame(rows)


def main(force: bool = False):
    outs, ins, params = spec()
    if not force and step_done("s03", outs, ins, params):
        return
    clear_step("s03")                   # chạy lại: bỏ dấu hoàn tất cũ ngay từ đầu
    OUT.mkdir(exist_ok=True)
    split = pd.read_csv(DATA_SPLIT)
    new = compute_sift(split)
    if USE_SAVED_SIFT:
        fetch_saved()
        saved = dict(np.load(DATA_SIFT))
    else:
        np.savez_compressed(DATA_SIFT, **new)
        saved = new
    check = compare(split, saved, new)
    check.to_csv(OUT / "sift_check.csv", index=False)
    print("So SIFT tính trên máy này với SIFT dùng cho các bước sau (chỉ để kiểm chứng):")
    print(check.to_string(index=False))

    counts = np.diff(saved["offsets"])
    stats = split[["path", "label", "split"]].assign(n_kp=counts)
    stats.to_csv(OUT / "sift_stats.csv", index=False)
    print(f"{len(split)} ảnh, {saved['offsets'][-1]} keypoint, {(counts == 0).sum()} ảnh không có keypoint")
    print(stats.groupby(["label", "split"]).n_kp.agg(["count", "mean", "min", "max"]).round(1)
          .reindex(CLASSES, level=0))
    print("Dùng cho các bước sau:", "SIFT ĐÃ LƯU (bản dùng cho báo cáo)" if USE_SAVED_SIFT else "SIFT tính trên máy này",
          f"-> {DATA_SIFT} ({DATA_SIFT.stat().st_size / 1e6:.1f} MB)")
    mark_step_done("s03", ins, params)


if __name__ == "__main__":
    main("--force" in sys.argv)
