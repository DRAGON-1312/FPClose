# Đo thời gian và bộ nhớ đỉnh của FPClose khi bật/tắt từng tối ưu.
#
#   julia --project scripts/benchmark.jl [--minsups 0.05,0.03,0.02] [--reps 3] [--csv out/x.csv]
#                                        [--combos all|ablation] [--recovery] [--max-fi N] <input.txt>
#   julia --project scripts/benchmark.jl --synthetic [...]     # CSDL tổng hợp, seed cố định
#
# - Mỗi (minsup, tổ hợp) chạy trong MỘT TIẾN TRÌNH JULIA RIÊNG: bộ nhớ đỉnh lấy từ
#   Sys.maxrss() (RSS đỉnh của tiến trình) nên không lẫn giữa các lần chạy.
# - Warm-up: trước khi đo, tiến trình con chạy cùng tổ hợp trên một CSDL nhỏ cố định để
#   biên dịch JIT xong; sau đó GC.gc() rồi mới đo. Thời gian = nhỏ nhất của `--reps` lần chạy.
# - `peak_rss_mb` là RSS đỉnh cả tiến trình (gồm Julia runtime và CSDL đã nạp);
#   `delta_rss_mb` = đỉnh sau khi đo trừ đỉnh trước khi đo (phần tăng thêm do khai thác;
#   bằng 0 nếu khai thác không vượt mức đỉnh đã có). `alloc_mb` = tổng byte cấp phát của một
#   lần chạy (@timed), ổn định giữa các lần và không phụ thuộc cách hệ điều hành báo RSS.
# - CSDL tổng hợp (--synthetic): MersenneTwister(2026), 20000 giao dịch, 200 item, 40 pattern cài sẵn
#   kiểu IBM Quest (xem `synthetic_db`); cố định nên mọi lần chạy cùng một CSDL.
# - Tổ hợp (prune_line8, fparray, early_termination): `all` = 8 tổ hợp; `ablation` = bản cơ bản
#   (chỉ dòng 8 của Fig. 8), +fparray, +early_termination, +cả hai.
# - `--recovery`: đo THÊM bước recovery (src/recovery.jl, khôi phục mọi frequent itemset từ tập đóng),
#   tách khỏi mining: với mỗi minsup, tập đóng được ghi ra out/.closed_*.txt rồi một tiến trình riêng
#   đọc file đó, warm-up, GC, và đo recover_all_frequent (nhỏ nhất của --reps lần) cùng RSS đỉnh.
#   Vì tiến trình recovery không chạy mining nên RSS đỉnh của nó không lẫn với mining.
#   Kết quả ở CSV thứ hai out/benchmark_<tên>_recovery.csv, kèm cột mining_time_s (tổ hợp bật hết
#   tối ưu) để so. Recovery nổ theo cấp số mũ trên dữ liệu dày: số FI vượt `--max-fi` (mặc định
#   5.000.000) thì dừng và ghi status = LIMIT thay vì hết bộ nhớ.
# - Kết quả: CSV ở out/ (thư mục tự tạo). Số itemset tìm được của mọi tổ hợp cùng minsup phải
#   bằng nhau; script báo lỗi nếu không.

using Random
using Printf
using FPClose

const ROOT = normpath(joinpath(@__DIR__, ".."))
const SEED = 2026

function synthetic_db(; n_tx = 20_000, n_items = 200, n_patterns = 40, seed = SEED)
    rng = MersenneTwister(seed)
    skewed() = clamp(ceil(Int, n_items * rand(rng)^2), 1, n_items)   # item phổ biến không đều
    # Kiểu IBM Quest: cài sẵn các pattern (độ dài 4..10); mỗi giao dịch gồm 1..3 pattern
    # bị làm hỏng (mỗi item rơi với xác suất 0.03) cộng vài item nhiễu. Nhờ vậy có nhiều tập
    # không đóng (support của tập con bằng support của tập cha), khác CSDL độc lập.
    patterns = [unique!([skewed() for _ in 1:rand(rng, 4:10)]) for _ in 1:n_patterns]
    weights = cumsum(rand(rng, n_patterns) .^ 2)
    pick() = patterns[min(n_patterns, searchsortedfirst(weights, rand(rng) * weights[end]))]
    db = Vector{Int}[]
    for _ in 1:n_tx
        t = Int[]
        for _ in 1:rand(rng, 1:3), x in pick()
            rand(rng) < 0.03 || push!(t, x)
        end
        for _ in 1:rand(rng, 0:4)
            push!(t, skewed())
        end
        push!(db, sort!(unique!(t)))
    end
    return db
end

warmup_db() = synthetic_db(n_tx = 400, n_items = 60, n_patterns = 10, seed = 1)

const ALL_COMBOS = [(p, f, e) for p in (true, false), f in (false, true), e in (false, true)] |> vec
const ABLATION_COMBOS = [(true, false, false), (true, true, false), (true, false, true), (true, true, true)]

# ---------------------------------------------------------------------------
# Tiến trình con: đo một cấu hình rồi in một dòng "RESULT ...".
# ---------------------------------------------------------------------------
function worker(args)
    input, minsup, p, f, e, reps = args[1], parse(Int, args[2]), parse(Bool, args[3]),
                                   parse(Bool, args[4]), parse(Bool, args[5]), parse(Int, args[6])
    opts = (prune_line8 = p, fparray = f, early_termination = e)
    wdb = warmup_db()
    fpclose(wdb, 3; opts...); fpclose(wdb, 5; opts...)        # biên dịch JIT
    db = input == "--synthetic" ? synthetic_db() : read_spmf(input)
    GC.gc()
    rss_before = Sys.maxrss()
    best = Inf
    n = 0
    alloc = 0
    for r in 1:reps
        GC.gc()
        t = @timed fpclose(db, minsup; opts...)
        best = min(best, t.time)
        n = length(t.value)
        alloc = t.bytes
    end
    rss_after = Sys.maxrss()
    @printf("RESULT %d %.6f %.3f %.3f %.3f\n", n, best, alloc / 2^20, rss_after / 2^20,
            (rss_after - rss_before) / 2^20)
end

# Đọc file tập đóng dạng SPMF "1 2 #SUP: 3" (do tiến trình cha ghi) thành `itemset => support`.
function read_closed(path)
    out = Pair{Vector{Int},Int}[]
    for line in eachline(path)
        isempty(strip(line)) && continue
        a, b = split(line, "#SUP:")
        push!(out, parse.(Int, split(a)) => parse(Int, strip(b)))
    end
    return out
end

# Tiến trình con đo recovery: `--worker-recovery <closed.txt> <reps> <max_fi>`.
function worker_recovery(args)
    path, reps, limit = args[1], parse(Int, args[2]), parse(Int, args[3])
    warm = [[1, 2, 3, 4, 5, 6] => 5, [1, 2, 3, 7, 8] => 6, [4, 5, 9] => 7]
    recover_all_frequent(warm); recover_all_frequent(warm; limit = 1_000_000)   # biên dịch JIT
    try recover_all_frequent(warm; limit = 3) catch e; e isa RecoveryLimitExceeded || rethrow() end
    closed = read_closed(path)
    GC.gc()
    rss_before = Sys.maxrss()
    best, n, alloc = Inf, 0, 0
    for r in 1:reps
        GC.gc()
        t = try
            @timed recover_all_frequent(closed; limit = limit)
        catch e
            e isa RecoveryLimitExceeded || rethrow()
            println("RESULT_RECOVERY LIMIT 0 0 0 0 0")
            return
        end
        best = min(best, t.time)
        n = length(t.value)
        alloc = t.bytes
    end
    rss_after = Sys.maxrss()
    @printf("RESULT_RECOVERY OK %d %.6f %.3f %.3f %.3f\n", n, best, alloc / 2^20, rss_after / 2^20,
            (rss_after - rss_before) / 2^20)
end

# ---------------------------------------------------------------------------
# Tiến trình cha
# ---------------------------------------------------------------------------
function parse_args(args)
    o = Dict{String,Any}("minsups" => "0.05,0.03,0.02,0.01", "reps" => 3, "combos" => "all",
                         "csv" => nothing, "input" => nothing, "recovery" => false, "max-fi" => 5_000_000)
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--synthetic"
            o["input"] = "--synthetic"
        elseif a == "--recovery"
            o["recovery"] = true
        elseif a in ("--minsups", "--reps", "--csv", "--combos", "--max-fi")
            i < length(args) || error("thiếu giá trị sau $a")
            o[a[3:end]] = a in ("--reps", "--max-fi") ? parse(Int, args[i+1]) : args[i+1]
            i += 1
        elseif startswith(a, "--")
            error("tham số không hợp lệ: $a")
        else
            o["input"] === nothing || error("chỉ nhận một file input")
            o["input"] = a
        end
        i += 1
    end
    o["input"] === nothing && error("thiếu file input (hoặc dùng --synthetic)")
    o["combos"] in ("all", "ablation") || error("--combos phải là all hoặc ablation")
    return o
end

function main(args)
    if !isempty(args) && args[1] == "--worker"
        worker(args[2:end]); return 0
    elseif !isempty(args) && args[1] == "--worker-recovery"
        worker_recovery(args[2:end]); return 0
    end
    o = parse_args(args)
    input = o["input"]
    db = input == "--synthetic" ? synthetic_db() : read_spmf(input)
    name = input == "--synthetic" ? "synthetic" : splitext(basename(input))[1]
    outdir = joinpath(ROOT, "out"); mkpath(outdir)
    csv = something(o["csv"], joinpath(outdir, "benchmark_$name.csv"))
    combos = o["combos"] == "all" ? ALL_COMBOS : ABLATION_COMBOS
    ratios = [FPClose.parse_minsup_ratio(strip(s)) for s in split(o["minsups"], ',')]
    n_tx = length(db)
    julia = Base.julia_cmd()
    project = dirname(Base.active_project())
    println("input: $name ($n_tx giao dịch), seed $SEED, reps $(o["reps"]), CSV: $csv")
    rcsv = replace(csv, r"\.csv$" => "") * "_recovery.csv"
    rio = o["recovery"] ? open(rcsv, "w") : nothing
    rio === nothing || println(rio, "input,n_tx,minsup_ratio,minsup_count,n_cfis,n_fis,status,mining_time_s,",
                               "recovery_time_s,recovery_alloc_mb,recovery_peak_rss_mb,recovery_delta_rss_mb")
    open(csv, "w") do io
        println(io, "input,n_tx,minsup_ratio,minsup_count,prune_line8,fparray,early_termination,",
                    "n_cfis,time_s,alloc_mb,peak_rss_mb,delta_rss_mb")
        for r in ratios
            ms = minsup_count(r, n_tx)
            counts = Int[]
            mining_time = NaN                      # thời gian mining của tổ hợp bật hết tối ưu
            for (p, f, e) in combos
                cmd = `$julia --project=$project $(@__FILE__) --worker $input $ms $p $f $e $(o["reps"])`
                out = read(cmd, String)
                line = last(filter(l -> startswith(l, "RESULT "), split(out, '\n')))
                n, t, alloc, peak, delta = (parse(Int, split(line)[2]), parse.(Float64, split(line)[3:end])...)
                push!(counts, n)
                (p && f && e) && (mining_time = t)
                println(io, join((name, n_tx, r, ms, p, f, e, n, t, alloc, peak, delta), ','))
                flush(io)
                @printf("minsup %.4g (%d) | line8=%-5s fparray=%-5s early=%-5s | %7d CFI | %8.3f s | alloc %9.1f MB | peak RSS %7.1f MB (+%.1f)\n",
                        r, ms, p, f, e, n, t, alloc, peak, delta)
            end
            length(unique(counts)) == 1 ||
                (println(stderr, "LỖI: số itemset khác nhau giữa các tổ hợp ở minsup $r: $counts"); return 1)

            if rio !== nothing
                # Ghi tập đóng ra file rồi đo recovery trong tiến trình riêng.
                cpath = joinpath(outdir, ".closed_$(name)_$(ms).txt")
                write_spmf(cpath, fpclose(db, ms))
                out = read(`$julia --project=$project $(@__FILE__) --worker-recovery $cpath $(o["reps"]) $(o["max-fi"])`, String)
                line = last(filter(l -> startswith(l, "RESULT_RECOVERY "), split(out, '\n')))
                f = split(line)
                status = f[2]
                nfi = parse(Int, f[3])
                rt, ralloc, rpeak, rdelta = parse.(Float64, f[4:7])
                println(rio, join((name, n_tx, r, ms, counts[1], nfi, status, mining_time, rt, ralloc, rpeak, rdelta), ','))
                flush(rio)
                if status == "OK"
                    @printf("minsup %.4g (%d) | RECOVERY %8d FI | mining %.3f s | recovery %8.3f s | alloc %9.1f MB | peak RSS %7.1f MB (+%.1f)\n",
                            r, ms, nfi, mining_time, rt, ralloc, rpeak, rdelta)
                else
                    @printf("minsup %.4g (%d) | RECOVERY vượt giới hạn %d FI (status LIMIT)\n", r, ms, o["max-fi"])
                end
                rm(cpath; force = true)
            end
        end
    end
    rio === nothing || (close(rio); println("Đã ghi $rcsv"))
    println("Đã ghi $csv")
    return 0
end

exit(main(ARGS))
