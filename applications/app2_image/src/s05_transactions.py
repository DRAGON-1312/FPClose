"""Bước 4: biến mỗi ảnh thành một giao dịch (tập item), xuất file SPMF và bảng thống kê.

Chạy:  python src/s05_transactions.py [--force]

Hai biến thể (thư mục riêng), mỗi biến thể với k = 100 và 300:
  word : item = từ thị giác + 1                        (MẶC ĐỊNH, dùng cho khai thác chính)
  grid : item = (từ * 4 + vùng 2x2) + 1                (tùy chọn). Ở đây tau áp lên (từ, vùng), không phải từ,
         nên là một chế độ khác với word: cùng tau nhưng giữ ít item hơn. Báo cáo phải ghi rõ.
Item bắt đầu từ 1 (SPMF cần số dương). Id ổn định, không đánh số lại sau khi lọc.

Mỗi thư mục data/transactions/k{k}_{variant}/ gồm:
  class_<lớp>.txt   giao dịch train của từng lớp       all_train.txt  toàn bộ train (file chung)
  test.txt          giao dịch test (chỉ để kiểm tra ảnh có chứa mẫu hay không)
  transactions_index.csv   mỗi ảnh: path, label, split, n_items, empty, line_common, line_class
  items.csv         mỗi item: từ, vùng, số ảnh train chứa nó, có bị loại như stop word không
Ảnh có giao dịch RỖNG (sau khi lọc tau + stop word) bị LOẠI khỏi các file .txt vì read_spmf của FPClose bỏ dòng
trống (số dòng sẽ lệch so với thứ tự ảnh). Chúng được đánh dấu empty=True trong transactions_index.csv, line_*
để trống. Số giao dịch n để tính minsup (ceil(minsup * n)) là số dòng KHÔNG rỗng của file.

Ghi thêm: out/transaction_stats.csv (số giao dịch, số item, độ dài TB, mật độ),
          out/tau_sensitivity.csv (tau x ngưỡng stop word: độ dài, mật độ, accuracy CV),
          out/tau_recommendation.csv (tau theo tiêu chí dưới đây).

TIÊU CHÍ CHỌN tau (viết TRƯỚC khi xem kết quả CV; không đổi sau khi xem):
  Với từng (k, biến thể), cố định ngưỡng stop word 80%. Gọi A* là accuracy CV 5-fold (trên train) cao nhất
  trong tau thuộc {1, 2, 3}. Chọn tau LỚN NHẤT có accuracy >= A* - 0,01.
  Lý do: tau lớn hơn cho giao dịch ngắn và thưa hơn, nên FPClose nhanh hơn và bớt nhiễu; một điểm % nằm trong
  sai số của CV với 700 ảnh (độ lệch chuẩn của accuracy ~1,1%), nên không có lý do chọn tau nhỏ hơn chỉ vì
  hơn kém dưới ngưỡng đó. Accuracy dùng LogisticRegression(random_state=42) trên vector 0/1 có/không có item.
  Nếu tau được chọn khác TAU trong config.py (hoặc nằm ở biên 1 hay 3) thì chỉ báo, KHÔNG tự đổi cấu hình.
  Giới hạn: ngưỡng stop word tính trên toàn bộ train rồi mới chia fold (không dùng nhãn nên không rò nhãn,
  nhưng không lồng trong fold).
"""
import sys

import cv2
import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import StratifiedKFold, cross_val_score

from config import (CLASSES, CV_FOLDS, CV_TOL, DATA_IMG, DATA_SIFT, DATA_SPLIT, DATA_TX, DATA_WORDS, GRID,
                    K_LIST, OUT, SEED, STOP_DF, STOP_GRID, TAU, TAU_GRID)

VARIANTS = ["word", "grid"]
N_REGION = GRID * GRID


def load_inputs():
    split = pd.read_csv(DATA_SPLIT)
    z = np.load(DATA_SIFT)
    words = np.load(DATA_WORDS)
    sizes = []                                          # (w, h) ảnh đã resize, để chia vùng lưới
    for p in split.path:
        h, w = cv2.imread(str(DATA_IMG.parent / p), cv2.IMREAD_GRAYSCALE).shape
        sizes.append((w, h))
    n_kp = np.diff(z["offsets"])
    img_of_kp = np.repeat(np.arange(len(split)), n_kp)
    wh = np.asarray(sizes, dtype=np.float32)[img_of_kp]
    region = (z["y"] >= wh[:, 1] / 2).astype(np.int64) * GRID + (z["x"] >= wh[:, 0] / 2).astype(np.int64)
    return split, words, img_of_kp, region


def count_matrix(words_k, img_of_kp, region, k, variant, n_img):
    """C[i, j] = số lần item j (0-based) xuất hiện trong ảnh i."""
    if variant == "word":
        item, n_total = words_k.astype(np.int64), k
    else:
        item, n_total = words_k.astype(np.int64) * N_REGION + region, k * N_REGION
    return np.bincount(img_of_kp * n_total + item, minlength=n_img * n_total).reshape(n_img, n_total)


def presence(C, train_mask, tau, stop):
    """Ma trận có/không sau khi lọc tau và stop word (stop word tính chỉ trên train). Trả (P, df_count, is_stop)."""
    P = C >= tau
    df_count = P[train_mask].sum(0)
    is_stop = df_count > stop * train_mask.sum() + 1e-9           # "> 80%": đúng 80% thì giữ
    return P & ~is_stop, df_count, is_stop


def write_variant(split, P, df_count, is_stop, k, variant):
    d = DATA_TX / f"k{k}_{variant}"
    d.mkdir(parents=True, exist_ok=True)
    lens = P.sum(1)
    empty = lens == 0
    idx = split[["path", "label", "split"]].copy()
    idx["n_items"], idx["empty"] = lens, empty
    idx["line_common"] = pd.array([pd.NA] * len(idx), dtype="Int64")
    idx["line_class"] = pd.array([pd.NA] * len(idx), dtype="Int64")

    def dump(name, rows, col):
        with open(d / name, "w", encoding="utf-8", newline="\n") as f:
            for n, i in enumerate(rows, start=1):
                f.write(" ".join(map(str, np.flatnonzero(P[i]) + 1)) + "\n")
                idx.loc[i, col] = n

    ok = ~empty
    train, test = (split.split == "train").to_numpy(), (split.split == "test").to_numpy()
    dump("all_train.txt", np.flatnonzero(train & ok), "line_common")
    dump("test.txt", np.flatnonzero(test & ok), "line_common")
    for c in CLASSES:
        dump(f"class_{c}.txt", np.flatnonzero(train & ok & (split.label == c).to_numpy()), "line_class")
    idx.to_csv(d / "transactions_index.csv", index=False)

    j = np.arange(len(df_count))
    pd.DataFrame({"item": j + 1, "word": j // N_REGION if variant == "grid" else j,
                  "region": j % N_REGION if variant == "grid" else -1,
                  "df_train": df_count, "stop": is_stop}).to_csv(d / "items.csv", index=False)


def group_stats(split, P, k, variant):
    rows = []
    groups = {c: ((split.split == "train") & (split.label == c)).to_numpy() for c in CLASSES}
    groups["all_train"] = (split.split == "train").to_numpy()
    groups["test"] = (split.split == "test").to_numpy()
    for g, m in groups.items():
        Pg = P[m]
        lens = Pg.sum(1)
        used = Pg.any(0).sum()
        ne = lens > 0
        rows.append({"k": k, "variant": variant, "tau": TAU, "stop": STOP_DF, "group": g,
                     "n_images": int(m.sum()), "n_empty": int((~ne).sum()), "n_transactions": int(ne.sum()),
                     "n_items": int(used), "avg_len": round(float(lens[ne].mean()), 1),
                     "min_len": int(lens[ne].min()), "max_len": int(lens[ne].max()),
                     "density": round(float(lens[ne].mean() / used), 3)})
    return rows


def sensitivity(split, C, train_mask, k, variant):
    y = split.label[train_mask].to_numpy()
    cv = StratifiedKFold(CV_FOLDS, shuffle=True, random_state=SEED)
    rows = []
    for tau in TAU_GRID:
        for stop in STOP_GRID:
            P, _, is_stop = presence(C, train_mask, tau, stop)
            Pt = P[train_mask]
            lens = Pt.sum(1)
            used = Pt.any(0).sum()
            acc = cross_val_score(LogisticRegression(max_iter=1000, random_state=SEED),
                                  Pt.astype(np.float32), y, cv=cv, scoring="accuracy")
            rows.append({"k": k, "variant": variant, "tau": tau, "stop": stop, "n_stop_items": int(is_stop.sum()),
                         "n_items": int(used), "avg_len": round(float(lens.mean()), 1),
                         "n_empty_train": int((lens == 0).sum()),
                         "density": round(float(lens.mean() / max(used, 1)), 3),
                         "cv_acc": round(float(acc.mean()), 4), "cv_std": round(float(acc.std()), 4)})
            print(rows[-1], flush=True)
    return rows


def recommend(sens):
    """Áp tiêu chí ở docstring: stop = STOP_DF, tau lớn nhất có cv_acc >= max - CV_TOL."""
    out = []
    for (k, variant), g in sens[np.isclose(sens.stop, STOP_DF)].groupby(["k", "variant"]):
        best = g.cv_acc.max()
        ok = g[g.cv_acc >= best - CV_TOL - 1e-9]
        tau = int(ok.tau.max())
        out.append({"k": k, "variant": variant, "best_acc": best, "tau_chosen": tau,
                    "acc_at_chosen": float(ok[ok.tau == tau].cv_acc.iloc[0]), "tau_config": TAU})
    return pd.DataFrame(out)


def main(force: bool = False):
    if (OUT / "transaction_stats.csv").exists() and not force:
        print("Đã có out/transaction_stats.csv - bỏ qua (dùng --force để chạy lại)")
        return
    OUT.mkdir(exist_ok=True)
    split, words, img_of_kp, region = load_inputs()
    train_mask = (split.split == "train").to_numpy()
    stats, sens = [], []
    for k in K_LIST:
        for variant in VARIANTS:
            C = count_matrix(words[f"k{k}"], img_of_kp, region, k, variant, len(split))
            P, df_count, is_stop = presence(C, train_mask, TAU, STOP_DF)
            write_variant(split, P, df_count, is_stop, k, variant)
            stats += group_stats(split, P, k, variant)
            sens += sensitivity(split, C, train_mask, k, variant)
    stats = pd.DataFrame(stats)
    stats.to_csv(OUT / "transaction_stats.csv", index=False)
    sens = pd.DataFrame(sens)
    sens.to_csv(OUT / "tau_sensitivity.csv", index=False)
    rec = recommend(sens)
    rec.to_csv(OUT / "tau_recommendation.csv", index=False)
    print(stats.to_string(index=False))
    print(rec.to_string(index=False))


if __name__ == "__main__":
    main("--force" in sys.argv)
