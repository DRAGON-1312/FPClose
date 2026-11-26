"""Bước 5: khai thác tập phổ biến đóng theo từng lớp bằng FPClose (Julia) của nhóm.

Chạy:  python src/s06_mine.py [--force]

Mỗi lần gọi `demo.jl` của nhóm cho 1 file + 1 minsup (dạng %, ngưỡng = ceil(minsup * n), n = số giao dịch):
    julia --project=<repo> demo.jl --minsup 60% --output-closed <out> <in>
Input: data/transactions/k{k}_word/class_<lớp>.txt (CHỈ train). Output thô mỗi lần gọi:
    data/patterns/k{k}_word/ms{minsup}/class_<lớp>.txt   dạng "1 2 3 #SUP: 5" (#SUP là số đếm)
    data/patterns/k{k}_word/ms{minsup}/class_<lớp>.err   stderr của demo.jl (+ dòng wall_seconds)
Dùng lại một lần gọi CHỈ KHI cache_key khớp (hash file giao dịch + hash code FPClose + phiên bản Julia); --force để chạy lại hết.

Kết quả:
    out/mining_sweep.csv     mỗi (k, lớp, minsup): số tập đóng, số tập dài >= 2, độ dài lớn nhất, thời gian
    out/minsup_choice.csv    minsup được chọn cho mỗi k theo tiêu chí dưới đây
    out/fpclose_check.csv    kiểm tra độc lập bằng Python trên output đã chọn (support, tính đóng)
    data/patterns/k{k}_word_closed.csv   mọi tập đóng ở minsup đã chọn: class, items, length, sup, sup_rel

TIÊU CHÍ CHỌN minsup (viết TRƯỚC khi chạy quét; không đổi sau khi xem):
  Với mỗi k, quét minsup giảm dần theo MINSUP_GRID[k] (config.py). Ở mỗi mức chạy FPClose cho cả 5 lớp.
  Chọn minsup CAO NHẤT mà MỌI lớp đều có >= 50 tập phổ biến đóng dài >= 2 item. Dùng chung một minsup cho
  5 lớp của cùng một k. Dừng quét ngay khi đạt (không chạy các mức thấp hơn).
  Nếu tới mức thấp nhất của lưới mà vẫn chưa đạt, hoặc một lần gọi vượt MINE_TIMEOUT: lấy mức thấp nhất
  đã chạy được trọn 5 lớp và ghi rõ là KHÔNG đạt tiêu chí (cột met = False).
  Lý do:
  - minsup cao: mẫu có mặt ở nhiều ảnh của lớp nên đại diện cho lớp, ít do ngẫu nhiên; ít mẫu hơn nên bảng
    growth rate và hình vẽ dễ đọc; growth rate của mẫu support thấp rất dao động.
  - >= 50 mẫu dài >= 2 mỗi lớp: bước 6 cần top-10 mỗi lớp, bước 7 cần top-N (<= 20) mỗi lớp xếp theo growth
    rate, nên cần nhóm ứng viên lớn hơn vài lần để việc xếp hạng có ý nghĩa. Dài >= 2 vì câu hỏi là về TỔ HỢP
    chi tiết; mẫu 1 item chỉ là một từ phổ biến.
  - Chung một minsup cho 5 lớp: cùng ngưỡng tương đối nên mẫu giữa các lớp so sánh được; lớp có giao dịch
    ngắn nhất (dự kiến airplanes) sẽ là lớp quyết định, và báo cáo phải nói điều đó.
  Công khai: trước khi viết tiêu chí đã chạy thử minsup 60% trên 3 file để chọn lưới quét (k=300 airplanes:
  3 tập đóng, Motorbikes: 5; k=100 Motorbikes: 22.947). Chưa xem kết quả ở mức nào khác.

Kiểm tra độc lập (không thay cho unit test của FPClose): đếm lại support của MỌI tập đóng trên file giao dịch
bằng bitset Python, và kiểm tra tính đóng (thêm bất kỳ item nào cũng làm support giảm) trên tối đa
CLOSED_CHECK_SAMPLE tập mỗi lớp. Không kiểm tra được tính đầy đủ (cần khai thác lại).
"""
import random
import hashlib
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

import pandas as pd

from config import (CLASSES, CLOSED_CHECK_SAMPLE, DATA_PATTERNS, DATA_TX, FPCLOSE_DEMO, JULIA, K_LIST,
                    MIN_PATTERN_LEN, MIN_PATTERNS, MINE_TIMEOUT, MINSUP_GRID, N_JOBS, OUT, REPO, SEED, file_sig,
                    clear_step, mark_step_done, step_done)

VARIANT = "word"
KV = re.compile(r"(\w+)\s*=\s*([0-9.]+)")
CACHE_KEY = re.compile(r"^cache_key = (\S+)$", re.M)


def code_files():
    """Code FPClose được gọi: demo.jl + src/**/*.jl. Đổi code thì cache phải hết hiệu lực."""
    return [FPCLOSE_DEMO] + sorted((REPO / "src").rglob("*.jl"))


def code_signature(julia_version):
    h = hashlib.sha1(julia_version.encode())
    for f in code_files():
        h.update(file_sig(f).encode())
    return h.hexdigest()


def spec(julia_version):
    outs = [OUT / f for f in ("mining_sweep.csv", "minsup_choice.csv", "fpclose_check.csv")]
    outs += [DATA_PATTERNS / f"k{k}_{VARIANT}_closed.csv" for k in K_LIST]
    ins = [DATA_TX / f"k{k}_{VARIANT}" / f"class_{c}.txt" for k in K_LIST for c in CLASSES] + code_files()
    params = {"K_LIST": K_LIST, "MINSUP_GRID": {str(k): v for k, v in MINSUP_GRID.items()},
              "MIN_PATTERNS": MIN_PATTERNS, "MIN_PATTERN_LEN": MIN_PATTERN_LEN, "MINE_TIMEOUT": MINE_TIMEOUT,
              "CLOSED_CHECK_SAMPLE": CLOSED_CHECK_SAMPLE, "SEED": SEED, "julia": julia_version}
    return outs, ins, params


def read_patterns(path):
    """Đọc output FPClose: mỗi dòng 'i1 i2 ... #SUP: s' -> list (tuple item, support)."""
    pats = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            items, sup = line.split("#SUP:")
            pats.append((tuple(sorted(map(int, items.split()))), int(sup)))
    return pats


def read_transactions(path):
    return [list(map(int, l.split())) for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]


def run_fpclose(in_path, minsup, out_path, force, code_sig):
    """Một lần gọi demo.jl. Trả dict số liệu (từ stderr của demo.jl + thời gian).

    Dùng lại kết quả đã có CHỈ KHI cache_key (hash file giao dịch + hash code FPClose + phiên bản Julia) khớp:
    đổi tau, codebook, chia tập... (file giao dịch đổi) hoặc đổi code FPClose thì tự chạy lại."""
    err_path = out_path.with_suffix(".err")
    key = f"{file_sig(in_path)}-{code_sig}"
    cached = (out_path.exists() and err_path.exists()
              and CACHE_KEY.findall(err_path.read_text(encoding="utf-8")) == [key])
    if force or not cached:
        out_path.parent.mkdir(parents=True, exist_ok=True)
        t0 = time.perf_counter()
        try:
            r = subprocess.run([JULIA, f"--project={REPO}", str(FPCLOSE_DEMO), "--minsup", f"{minsup}%",
                                "--output-closed", str(out_path), str(in_path)],
                               capture_output=True, text=True, encoding="utf-8", timeout=MINE_TIMEOUT)
        except subprocess.TimeoutExpired:
            out_path.unlink(missing_ok=True)
            return {"status": "timeout", "wall_seconds": float(MINE_TIMEOUT)}
        if r.returncode != 0:
            raise RuntimeError(f"demo.jl lỗi ({r.returncode}) trên {in_path}:\n{r.stderr}")
        err_path.write_text(r.stderr + f"\nwall_seconds = {time.perf_counter() - t0:.3f}\ncache_key = {key}\n",
                            encoding="utf-8")
        status = "ran"
    else:
        status = "cached"
    info = {k: float(v) for k, v in KV.findall(err_path.read_text(encoding="utf-8"))}
    pats = read_patterns(out_path)
    assert int(info["closed_itemsets"]) == len(pats), f"số dòng output khác số tập đóng báo ở stderr: {out_path}"
    lens = [len(p) for p, _ in pats]
    return {"status": status, "n_transactions": int(info["transactions"]), "minsup_count": int(info["minsup_count"]),
            "n_closed": len(pats), "n_len2": sum(l >= MIN_PATTERN_LEN for l in lens), "max_len": max(lens, default=0),
            "mining_seconds": info.get("mining_seconds"), "wall_seconds": info.get("wall_seconds")}


def sweep(k, force, code_sig):
    """Quét minsup giảm dần cho một k; dừng khi mọi lớp có >= MIN_PATTERNS tập dài >= 2. Trả (rows, choice)."""
    rows, last_ok = [], None
    tx_dir, pat_dir = DATA_TX / f"k{k}_{VARIANT}", DATA_PATTERNS / f"k{k}_{VARIANT}"
    for m in MINSUP_GRID[k]:
        jobs = [(tx_dir / f"class_{c}.txt", m, pat_dir / f"ms{m:02d}" / f"class_{c}.txt") for c in CLASSES]
        with ThreadPoolExecutor(N_JOBS) as ex:
            res = list(ex.map(lambda j: run_fpclose(*j, force, code_sig), jobs))
        for c, r in zip(CLASSES, res):
            rows.append({"k": k, "class": c, "minsup_pct": m, **r})
            print(rows[-1], flush=True)
        if any(r["status"] == "timeout" for r in res):
            note = f"vượt {MINE_TIMEOUT}s ở minsup {m}%"
            break
        last_ok = m
        weakest = min(zip(res, CLASSES), key=lambda t: t[0]["n_len2"])
        if weakest[0]["n_len2"] >= MIN_PATTERNS:
            return rows, {"k": k, "minsup_pct": m, "met": True, "weakest_class": weakest[1],
                          "weakest_n_len2": weakest[0]["n_len2"], "note": "đạt tiêu chí"}
    else:
        note = "hết lưới minsup mà chưa đạt"
    assert last_ok is not None, f"k={k}: không có mức minsup nào chạy được trọn 5 lớp"
    w = min((r for r in rows if r["minsup_pct"] == last_ok), key=lambda r: r["n_len2"])
    return rows, {"k": k, "minsup_pct": last_ok, "met": False, "weakest_class": w["class"],
                  "weakest_n_len2": w["n_len2"], "note": note}


def verify(k, m):
    """Đếm lại support (mọi tập) và kiểm tra tính đóng (mẫu tối đa CLOSED_CHECK_SAMPLE tập) cho mỗi lớp."""
    rows, table = [], []
    rng = random.Random(SEED)
    for c in CLASSES:
        tx = read_transactions(DATA_TX / f"k{k}_{VARIANT}" / f"class_{c}.txt")
        bits = {}                                           # item -> bitmask các giao dịch chứa item
        for t_i, t in enumerate(tx):
            for it in t:
                bits[it] = bits.get(it, 0) | (1 << t_i)
        full = (1 << len(tx)) - 1

        def tidset(items):
            b = full
            for it in items:
                b &= bits.get(it, 0)
            return b

        def is_closed(p, s):
            """Đóng <=> thêm bất kỳ item nào (ngoài p) cũng làm support giảm. Đủ để xét mở rộng 1 item: nếu một
            tập cha có cùng support thì mọi tập cha 1 item nằm giữa cũng có cùng support."""
            tb, inside = tidset(p), set(p)
            return all((tb & b).bit_count() < s for it, b in bits.items() if it not in inside)

        out_path = DATA_PATTERNS / f"k{k}_{VARIANT}" / f"ms{m:02d}" / f"class_{c}.txt"
        pats = read_patterns(out_path)
        min_count = -(-m * len(tx) // 100)                  # ceil(m% * n) bằng số nguyên, như SPMF
        fp_count = int(dict(KV.findall(out_path.with_suffix(".err").read_text(encoding="utf-8")))["minsup_count"])
        sup_ok = all(tidset(p).bit_count() == s and s >= min_count for p, s in pats)
        sample = pats if len(pats) <= CLOSED_CHECK_SAMPLE else rng.sample(pats, CLOSED_CHECK_SAMPLE)
        closed_ok = all(is_closed(p, s) for p, s in sample)
        rows.append({"k": k, "class": c, "minsup_pct": m, "minsup_count_python": min_count,
                     "minsup_count_fpclose": fp_count, "n_closed": len(pats), "support_all_ok": sup_ok,
                     "closed_checked": len(sample), "closed_ok": closed_ok})
        print(rows[-1], flush=True)
        n = len(tx)
        table += [{"class": c, "minsup_pct": m, "items": " ".join(map(str, p)), "length": len(p), "sup": s,
                   "sup_rel": round(s / n, 4)} for p, s in pats]
    return rows, pd.DataFrame(table)


def main(force: bool = False):
    jv = subprocess.run([JULIA, "--version"], capture_output=True, text=True).stdout.strip()
    outs, ins, params = spec(jv)
    if not force and step_done("s06", outs, ins, params):
        return
    clear_step("s06")                   # chạy lại: bỏ dấu hoàn tất cũ ngay từ đầu
    code_sig = code_signature(jv)
    print(f"FPClose của nhóm: {FPCLOSE_DEMO} | {jv} | {N_JOBS} lần gọi song song", flush=True)
    OUT.mkdir(exist_ok=True)
    rows, choices, checks, tables = [], [], [], {}
    for k in K_LIST:
        r, ch = sweep(k, force, code_sig)
        rows += r
        choices.append(ch)
        print(ch, flush=True)
        chk, tables[k] = verify(k, ch["minsup_pct"])
        checks += chk
    sweep_df, chk = pd.DataFrame(rows), pd.DataFrame(checks)
    sweep_df.to_csv(OUT / "mining_sweep.csv", index=False)       # bảng chẩn đoán: ghi cả khi kiểm tra thất bại
    chk.to_csv(OUT / "fpclose_check.csv", index=False)
    for k in K_LIST:
        print(f"\nk={k}: số tập đóng dài >= {MIN_PATTERN_LEN} (hàng: minsup %, cột: lớp)")
        print(sweep_df[sweep_df.k == k].pivot(index="minsup_pct", columns="class", values="n_len2")
              .sort_index(ascending=False)[CLASSES].to_string())
    print(pd.DataFrame(choices).to_string(index=False))
    # Kiểm tra TRƯỚC khi ghi kết quả mà bước sau dùng (minsup_choice, bảng mẫu) và trước khi đánh dấu hoàn tất
    assert chk.support_all_ok.all() and chk.closed_ok.all(), "kiểm tra độc lập thất bại, xem out/fpclose_check.csv"
    print("Kiểm tra độc lập: support và tính đóng đều đúng")
    diff = chk[chk.minsup_count_python != chk.minsup_count_fpclose]
    if len(diff):                                           # chỉ báo, không dừng: khác cách làm tròn ngưỡng
        print("LƯU Ý: ngưỡng support của FPClose khác ceil(minsup * n) tính bằng số nguyên:\n", diff.to_string())
    pd.DataFrame(choices).to_csv(OUT / "minsup_choice.csv", index=False)
    for k, table in tables.items():
        table.to_csv(DATA_PATTERNS / f"k{k}_{VARIANT}_closed.csv", index=False)
    mark_step_done("s06", ins, params)


if __name__ == "__main__":
    main("--force" in sys.argv)
