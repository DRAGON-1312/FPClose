# Chạy lưới thực nghiệm Chương 2: correctness, runtime, memory, scalability, txlen.
#
# So cài đặt của nhóm (`fpclose`) với SPMF FPClose trên 9 dataset benchmark (lưới minsup trong
# data/meta/benchmark_config.csv), Retail subsets (scalability) và synthetic theo độ dài giao dịch (txlen).
# CHƯA vẽ biểu đồ: script chỉ ghi CSV vào results/ để script vẽ đọc.
#
# Cách dùng (từ thư mục gốc repo):
#   julia --project=. scripts/run_benchmark_grid.jl                          # cả 5 phần, 3 lần mỗi cấu hình
#   julia --project=. scripts/run_benchmark_grid.jl --only runtime,memory --datasets chess,mushrooms
#   julia --project=. scripts/run_benchmark_grid.jl --quick                  # chess + mushrooms, 1 lần, hậu tố _quick
#
#   --only a,b       chọn phần: correctness, runtime, memory, scalability, txlen, txlen_pilot (mặc định: 5 phần đầu)
#   --datasets a,b   giới hạn dataset của correctness, runtime, memory (scalability dùng retail_p*, txlen dùng len*)
#   --runs N         số lần đo mỗi cấu hình (mặc định 3, lấy nhỏ nhất khi tổng hợp)
#   --timeout S      giới hạn S giây cho MỖI lần chạy (mặc định 600); quá thì ghi TIMEOUT và chạy tiếp
#   --quick          chess + mushrooms, 2-3 mức minsup, 1 lần, file kết quả có hậu tố _quick (vài phút)
#   --suffix S       hậu tố tên file kết quả (--quick ngầm đặt _quick)
#   --machine NAME   nhãn máy ghi vào cột machine (mặc định: tên máy; hoặc biến môi trường FPCLOSE_MACHINE)
#   --fi-limit N     giới hạn số frequent itemset khi so mọi FI (mặc định 2000000)
#   --fi-all-levels  so mọi FI ở mọi mức minsup của lưới (mặc định chỉ mức cao nhất); dừng ở mức đầu tiên vượt --fi-limit
#   --txlen-minsups  các mức minsup (%) cho txlen, ví dụ 2,1; --scal-minsups cho scalability (mặc định 0.1,0.05)
#   --no-skip-after-timeout   chạy cả các minsup thấp hơn sau khi một công cụ đã TIMEOUT
#   --jar PATH, --java-heap 4g   spmf.jar và heap của JVM (-Xmx, mặc định 4g như lần chạy thử lưới)
#
# Chạy tiếp được: kết quả ghi từng dòng; chạy lại đúng lệnh cũ thì bỏ qua các dòng đã có (OK, TIMEOUT, SKIPPED;
# dòng FAILED được chạy lại). Log: out/grid.log. Cấu hình máy: results/ENVIRONMENT.md.
#
# Cách đo:
#   - Mỗi lần đo của nhóm chạy trong MỘT TIẾN TRÌNH JULIA RIÊNG, warm-up trên CSDL toy rồi mới đo. Bộ nhớ là
#     Sys.maxrss() (RSS đỉnh của tiến trình) cuối lần đo; số đo nền (baseline_mem_mb) là maxrss ngay sau warm-up,
#     lúc chưa đọc dữ liệu.
#   - Thời gian của nhóm tách: read_s (read_spmf), mine_s (fpclose), recover_s (chỉ khi so mọi FI), write_s (write_spmf).
#     `time_with_write_s` = read + mine + recover + write (cột CÓ ghi file, để so với SPMF vì "Total time" của SPMF đã
#     gồm ghi output); `time_no_write_s` = read + mine + recover (KHÔNG ghi file; SPMF không tách được nên để trống).
#     Không sắp xếp kết quả trước khi ghi. Việc đọc lại output và so từng itemset làm SAU khi dừng đồng hồ.
#   - SPMF: time_with_write_s lấy từ "Total time" do SPMF tự in, peak_mem_mb từ "Max memory usage" của SPMF
#     (bộ nhớ heap JVM do MemoryLogger đo, KHÔNG phải RSS nên không so trực tiếp với số của nhóm);
#     process_wall_s là thời gian cả tiến trình java (gồm khởi động JVM).
#
# Mã thoát: 0 nếu không có lỗi, 1 nếu có mục lệch (itemset khác, kết quả các variant khác nhau) hoặc FAILED, 2 nếu sai tham số.

using FPClose
using Dates
using SHA
using Printf

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DATA = joinpath(ROOT, "data")
const META_DIR = joinpath(DATA, "meta")
const BENCHMARK_DIR = joinpath(DATA, "benchmark")
const SCALABILITY_DIR = joinpath(DATA, "scalability")
const SYNTHETIC_DIR = joinpath(DATA, "synthetic")
const TOOLS_DIR = joinpath(ROOT, "tools")
const OUT_DIR = joinpath(ROOT, "out")
const GRID_OUT_DIR = joinpath(OUT_DIR, "grid")
const RESULTS_DIR = joinpath(ROOT, "results")
const LOGFILE = joinpath(OUT_DIR, "grid.log")

const ALL_PARTS = ["correctness", "runtime", "memory", "scalability", "txlen"]
const OPTION_NAMES = (:prune_line8, :fparray, :early_termination, :exact_count, :reduced_cfitree)

# Các variant của phần memory: tên => (prune_line8, fparray, early_termination, exact_count, reduced_cfitree)
const VARIANTS = [
    "optimized" => (true, true, true, true, true),                 # mặc định của fpclose
    "basic" => (false, false, false, false, false),                # tắt hết
    "paper" => (true, false, false, false, false),                 # chỉ cắt nhánh dòng 8 như bài báo
    "opt_no_prune_line8" => (false, true, true, true, true),       # ablation: tắt từng tối ưu
    "opt_no_fparray" => (true, false, true, true, true),
    "opt_no_early_termination" => (true, true, false, true, true),
    "opt_no_exact_count" => (true, true, true, false, true),
    "opt_no_reduced_cfitree" => (true, true, true, true, false),
]
const STAT_FIELDS = (:calls, :pruned_line8, :closed_checks, :cfis, :fparray_hits, :early_stops,
                     :tree_traversals, :subset_tests, :cfi_nodes, :root_cfi_nodes)

# ---------------------------------------------------------------------------
# Tiện ích chung: log, CSV, cấu hình
# ---------------------------------------------------------------------------

"Mô tả ngắn một lần đo OK để ghi log (an toàn khi thiếu số đo)."
function summary_of(m)
    (m.status == "OK" && !ismissing(m.time_with_write_s)) || return m.status == "OK" ? "OK" : m.note
    peak = ismissing(m.peak_mem_mb) ? "?" : @sprintf("%.1f", m.peak_mem_mb)
    return @sprintf("%.3f s (có ghi file)  %d itemset  peak %s MB", m.time_with_write_s, m.n, peak)
end

"Ghi một dòng ra màn hình và vào out/grid.log (kèm giờ)."
function logmsg(msg...)
    line = string(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"), "  ", msg...)
    println(line)
    flush(stdout)
    mkpath(OUT_DIR)
    open(io -> println(io, line), LOGFILE, "a")
end

sha256_file(path) = open(io -> bytes2hex(sha256(io)), path)

"Giá trị CSV: `nothing`/`missing` thành rỗng, bỏ dấu phẩy và xuống dòng."
csv_value(v) = (v === nothing || v === missing) ? "" : replace(string(v), ',' => ';', '\n' => ' ', '\r' => ' ')

"Đọc CSV đơn giản (không có dấu phẩy trong ô) thành danh sách Dict; trả `[]` nếu chưa có file."
function csv_load(path)
    isfile(path) || return Dict{String,String}[]
    lines = filter(!isempty, strip.(readlines(path)))
    isempty(lines) && return Dict{String,String}[]
    header = split(lines[1], ',')
    return [Dict(String(h) => String(v) for (h, v) in zip(header, split(l, ','))) for l in lines[2:end]]
end

"Ghi thêm một dòng vào CSV; tạo file kèm header nếu chưa có, báo lỗi nếu header cũ khác header hiện tại."
function csv_append(path, header, values)
    mkpath(dirname(path))
    if isfile(path) && filesize(path) > 0
        old = split(strip(readline(path)), ',')       # readline đóng file ngay (first(eachline) để file mở, Windows không xóa được)
        old == header || error("Header của $path khác với phiên bản script hiện tại: xóa file hoặc dùng --suffix khác")
    end
    fresh = !isfile(path) || filesize(path) == 0
    open(path, "a") do io
        fresh && println(io, join(header, ','))
        println(io, join(csv_value.(values), ','))
    end
end

rnd(x; digits = 4) = x isa Real ? round(x; digits = digits) : x

"Một cấu hình đo: tên dataset, file, số giao dịch, minsup (%) và ngưỡng tuyệt đối."
struct Cfg
    dataset::String
    path::String
    n::Int
    pct::Float64
    count::Int
end

format_pct(pct) = (s = string(pct); endswith(s, ".0") ? s[1:end-2] : s)
tag_of(c::Cfg) = string(c.dataset, "_", replace(format_pct(c.pct), "." => "p"))

"Lưới 56 cấu hình từ data/meta/benchmark_config.csv (theo thứ tự trong file: mỗi dataset từ minsup cao xuống thấp)."
function load_grid()
    return [Cfg(r["dataset"], joinpath(BENCHMARK_DIR, r["dataset"] * ".txt"), parse(Int, r["n_transactions"]),
                parse(Float64, r["minsup_pct"]), parse(Int, r["minsup_count"]))
            for r in csv_load(joinpath(META_DIR, "benchmark_config.csv"))]
end

"Retail subsets: mỗi mức p và mỗi minsup tương đối; ngưỡng tuyệt đối tăng theo số giao dịch."
function scalability_cfgs(minsups; quick = false)
    rows = [r for r in csv_load(joinpath(META_DIR, "derived_hashes.csv")) if r["group"] == "scalability"]
    quick && (rows = [r for r in rows if r["dataset"] in ("retail_p010.txt", "retail_p050.txt", "retail_p100.txt")])
    cfgs = Cfg[]
    for pct in minsups, r in rows
        name = splitext(r["dataset"])[1]
        n = parse(Int, r["n_transactions"])
        push!(cfgs, Cfg(name, joinpath(SCALABILITY_DIR, r["dataset"]), n, pct, minsup_count(pct / 100, n)))
    end
    return cfgs
end

"Synthetic len05..len30 ở các minsup tương đối cho trước."
function txlen_cfgs(minsups; quick = false)
    rows = [r for r in csv_load(joinpath(META_DIR, "derived_hashes.csv")) if r["group"] == "synthetic"]
    quick && (rows = [r for r in rows if r["dataset"] in ("len05.txt", "len15.txt", "len30.txt")])
    cfgs = Cfg[]
    for pct in minsups, r in rows
        n = parse(Int, r["n_transactions"])
        push!(cfgs, Cfg(splitext(r["dataset"])[1], joinpath(SYNTHETIC_DIR, r["dataset"]), n, pct, minsup_count(pct / 100, n)))
    end
    return cfgs
end

# ---------------------------------------------------------------------------
# Ngữ cảnh chạy
# ---------------------------------------------------------------------------

struct Ctx
    parts::Vector{String}
    datasets::Union{Nothing,Vector{String}}
    runs::Int
    timeout::Int
    quick::Bool
    suffix::String
    machine::String
    fi_limit::Int
    fi_all_levels::Bool
    txlen_minsups::Vector{Float64}
    scal_minsups::Vector{Float64}
    skip_after_timeout::Bool
    jar::String
    java::String
    heap::String
end

results_path(ctx, dir, name) = joinpath(RESULTS_DIR, dir, name * ctx.suffix * ".csv")

# ---------------------------------------------------------------------------
# Tiến trình con có giới hạn thời gian
# ---------------------------------------------------------------------------

"""
    run_with_timeout(cmd, logpath; timeout_s) -> (status, wall_s)

Chạy `cmd` (stdout và stderr vào `logpath`); status là `:ok`, `:failed` hoặc `:timeout` (khi đó tiến trình bị kill).
"""
function run_with_timeout(cmd::Cmd, logpath::AbstractString; timeout_s)
    t0 = time()
    proc = open(logpath, "w") do io
        run(pipeline(cmd; stdout = io, stderr = io); wait = false)
    end
    while process_running(proc)
        if time() - t0 > timeout_s
            kill(proc)
            wait(proc)
            return (:timeout, time() - t0)
        end
        sleep(0.02)
    end
    return (success(proc) ? :ok : :failed, time() - t0)
end

"Tìm java của JDK 25 (SPMF mới build cho Java 25); không thấy thì dùng `java` trên PATH."
function find_java()
    for root in ("C:\\Program Files\\Eclipse Adoptium", "/usr/lib/jvm")
        isdir(root) || continue
        for d in sort(readdir(root); rev = true)
            (startswith(d, "jdk-25") || startswith(d, "temurin-25")) || continue
            for exe in ("java.exe", "java")
                p = joinpath(root, d, "bin", exe)
                isfile(p) && return p
            end
        end
    end
    return "java"
end

function java_version(java)
    buf = IOBuffer()
    try
        run(pipeline(ignorestatus(`$java -version`); stdout = buf, stderr = buf))
    catch
        return "không chạy được"
    end
    return strip(first(split(String(take!(buf)), '\n')))
end

# ---------------------------------------------------------------------------
# Tiến trình con đo của nhóm (--worker)
# ---------------------------------------------------------------------------

"Chuỗi tùy chọn `prune_line8=1,fparray=0,...` thành NamedTuple Bool."
function parse_opts(s::AbstractString)
    kv = Dict(Symbol(k) => v == "1" for (k, v) in (split(p, '=') for p in split(s, ',')))
    return NamedTuple{OPTION_NAMES}(Tuple(kv[k] for k in OPTION_NAMES))
end

opts_string(t::NTuple{5,Bool}) = join(("$(k)=$(v ? 1 : 0)" for (k, v) in zip(OPTION_NAMES, t)), ',')

"""
Warm-up cho tiến trình đo: chạy đúng các tùy chọn sẽ đo (và nhánh FP-array, ghi file, recovery) trên CSDL toy
để loại thời gian biên dịch JIT khỏi lần đo thật.
"""
function warm_up(opts, mode::AbstractString)
    for f in ("pasquier99.txt", joinpath("extra", "random200.txt"))
        db = read_spmf(joinpath(DATA, "toy", f))
        for ms in (2, 6)
            res = fpclose(db, ms; opts...)
            fpclose(db, ms; opts..., skip_items = 0, dense_ratio = 0.0)      # ép chạy qua nhánh FP-array
            mode == "all" && recover_all_frequent(res)
            tmp = tempname()
            write_spmf(tmp, res)
            rm(tmp; force = true)
        end
    end
    return nothing
end

"""
    worker(args)

Một lần đo của nhóm, chạy trong tiến trình riêng:
`--worker <file> <minsup_count> <output|-> <tùy chọn> <stats 0/1> <mode closed|all> <hash 0/1> <fi_limit>`.
In đúng một dòng `RESULT key=value ...` cho tiến trình cha đọc.
"""
function worker(args)
    path, count, outpath, optstr, with_stats, mode, with_hash, limit =
        args[1], parse(Int, args[2]), args[3], args[4], args[5] == "1", args[6], args[7] == "1", parse(Int, args[8])
    opts = parse_opts(optstr)
    warm_up(opts, mode)       # không warm-up bộ đếm: lần chạy bộ đếm nằm SAU lúc ghi peak
    GC.gc()
    baseline = Sys.maxrss()                                    # số đo nền: sau warm-up, trước khi đọc dữ liệu
    t0 = time_ns()
    alloc0 = Base.gc_bytes()                                   # tổng byte cấp phát (xác định, phân biệt được các variant)
    local db, closed, res
    try
        db = read_spmf(path)
        t1 = time_ns()
        closed = fpclose(db, count; opts...)
        t2 = time_ns()
        alloc_mine = Base.gc_bytes() - alloc0                   # cấp phát của đọc + khai thác
        res = closed
        if mode == "all"
            res = recover_all_frequent(closed; limit = limit)
        end
        t3 = time_ns()
        outpath == "-" || write_spmf(outpath, res)
        t4 = time_ns()
        peak = Sys.maxrss()                                    # RSS đỉnh, đọc ngay sau bước cuối của lần đo
        fields = Pair{String,Any}["status" => "OK", "n" => length(res),
            "read_s" => (t1 - t0) / 1e9, "mine_s" => (t2 - t1) / 1e9, "recover_s" => (t3 - t2) / 1e9,
            "write_s" => (t4 - t3) / 1e9, "peak_mb" => peak / 2^20, "base_mb" => baseline / 2^20,
            "alloc_mb" => alloc_mine / 2^20]
        if with_hash                                           # băm không phụ thuộc thứ tự để so các variant
            h = reduce(xor, (hash((p.first, p.second)) for p in res); init = UInt64(0))
            push!(fields, "hash" => string(h; base = 16))
        end
        if with_stats                                          # lần chạy thứ hai chỉ để lấy bộ đếm (không tính thời gian)
            st = FPCloseStats()
            fpclose(db, count; stats = st, opts...)
            for f in STAT_FIELDS
                push!(fields, string(f) => getfield(st, f))
            end
        end
        println("RESULT ", join(("$k=$v" for (k, v) in fields), ' '))
    catch err
        if err isa RecoveryLimitExceeded
            println("RESULT status=SKIPPED reason=so_FI_vuot_gioi_han_", limit)
        else
            println("RESULT status=FAILED reason=", replace(first(sprint(showerror, err), 160), r"\s+" => "_"))
        end
    end
end

# ---------------------------------------------------------------------------
# Một lần đo của mỗi công cụ (tiến trình cha)
# ---------------------------------------------------------------------------

"Kết quả một lần đo (cột không áp dụng để `missing`)."
function blank(status; note = "")
    return (status = status, n = missing, read_s = missing, mine_s = missing, recover_s = missing, write_s = missing,
            time_with_write_s = missing, time_no_write_s = missing, process_wall_s = missing, peak_mem_mb = missing,
            baseline_mem_mb = missing, mem_delta_mb = missing, alloc_mb = missing, mem_source = missing, hash = missing,
            stats = Dict{String,String}(), note = note)
end

"Đọc dòng `RESULT k=v ...` trong log của tiến trình con; `nothing` nếu không có."
function parse_result(log)
    for line in split(read(log, String), '
')                 # đọc cả file (không để eachline giữ file mở: Windows không xóa được)
        startswith(line, "RESULT ") || continue
        return Dict(String(k) => String(v) for (k, v) in (split(tok, '='; limit = 2) for tok in split(strip(line))[2:end]))
    end
    return nothing
end

"""
    run_ours(ctx, cfg; out, opts, stats, hash, mode) -> NamedTuple

Một lần đo của nhóm trong tiến trình Julia riêng (xem phần đầu file). `out = "-"` thì không ghi file (phần memory).
"""
function run_ours(ctx::Ctx, cfg::Cfg; out::AbstractString, opts = (true, true, true, true, true),
                  stats::Bool = false, hash::Bool = false, mode::AbstractString = "closed")
    log = tempname() * "_ours.log"
    cmd = `$(Base.julia_cmd()) --project=$ROOT $(@__FILE__) --worker $(cfg.path) $(cfg.count) $out $(opts_string(opts)) $(stats ? 1 : 0) $mode $(hash ? 1 : 0) $(ctx.fi_limit)`
    status, wall = run_with_timeout(cmd, log; timeout_s = ctx.timeout)
    try
        status == :timeout && return blank("TIMEOUT"; note = "quá $(ctx.timeout) s")
        r = parse_result(log)
        if r === nothing
            msg = first(replace(strip(read(log, String)), r"\s+" => " "), 160)
            return blank("FAILED"; note = status == :failed ? msg : "không có RESULT: $msg")
        end
        r["status"] == "OK" || return blank(r["status"]; note = get(r, "reason", ""))
        f(k) = parse(Float64, r[k])
        read_s, mine_s, recover_s, write_s = f("read_s"), f("mine_s"), f("recover_s"), f("write_s")
        peak, base = f("peak_mb"), f("base_mb")
        no_write = read_s + mine_s + recover_s
        return (status = "OK", n = parse(Int, r["n"]), read_s = read_s, mine_s = mine_s, recover_s = recover_s,
                write_s = write_s, time_with_write_s = no_write + write_s, time_no_write_s = no_write,
                process_wall_s = wall, peak_mem_mb = peak, baseline_mem_mb = base, mem_delta_mb = max(peak - base, 0.0),
                alloc_mb = parse(Float64, r["alloc_mb"]), mem_source = "rss_maxrss", hash = get(r, "hash", missing),
                stats = Dict(k => v for (k, v) in r if k in string.(STAT_FIELDS)), note = "")
    finally
        rm(log; force = true)
    end
end

"""
    run_spmf(ctx, cfg; out, mode) -> NamedTuple

Một lần chạy SPMF (`FPClose` hoặc `FPGrowth_itemsets`). Thời gian và bộ nhớ lấy từ chính SPMF: `Total time` (đã gồm
đọc và ghi output) và `Max memory usage` (heap JVM).
"""
function run_spmf(ctx::Ctx, cfg::Cfg; out::AbstractString, mode::AbstractString = "closed")
    algorithm = mode == "closed" ? "FPClose" : "FPGrowth_itemsets"
    log = tempname() * "_spmf.log"
    cmd = `$(ctx.java) -Xmx$(ctx.heap) -jar $(ctx.jar) run $algorithm $(cfg.path) $out $(format_pct(cfg.pct))%`
    status, wall = run_with_timeout(cmd, log; timeout_s = ctx.timeout)
    try
        if status == :timeout
            rm(out; force = true)
            return blank("TIMEOUT"; note = "quá $(ctx.timeout) s")
        end
        text = read(log, String)
        if status != :ok || !isfile(out)
            return blank("FAILED"; note = first(replace(strip(text), r"\s+" => " "), 160))
        end
        tm = match(r"Total time ~\s*(\d+)\s*ms", text)
        mm = match(r"Max memory usage:\s*([\d.]+)", text)
        nm = match(r"itemsets? count\s*:\s*(\d+)"i, text)
        n = nm === nothing ? count(l -> !isempty(l) && !startswith(l, '@'), eachline(out)) : parse(Int, nm[1])
        total = tm === nothing ? missing : parse(Int, tm[1]) / 1000
        return (status = "OK", n = n, read_s = missing, mine_s = missing, recover_s = missing, write_s = missing,
                time_with_write_s = total, time_no_write_s = missing, process_wall_s = wall,
                peak_mem_mb = mm === nothing ? missing : parse(Float64, mm[1]), baseline_mem_mb = missing,
                mem_delta_mb = missing, alloc_mb = missing, mem_source = "spmf_memorylogger", hash = missing,
                stats = Dict{String,String}(), note = tm === nothing || mm === nothing ? "không đọc được thời gian/bộ nhớ" : "")
    finally
        rm(log; force = true)
    end
end

# ---------------------------------------------------------------------------
# So từng itemset (sau khi đã dừng đồng hồ)
# ---------------------------------------------------------------------------

"Đọc file output dạng `1 2 #SUP: 3` thành `itemset đã sắp => support`; trả `(dict, số dòng lặp)`."
function read_output(path)
    d = Dict{Vector{Int},Int}()
    dup = 0
    for line in eachline(path)
        s = strip(line)
        (isempty(s) || startswith(s, '@')) && continue
        parts = split(s, "#SUP:")
        items = sort!(parse.(Int, split(parts[1])))
        haskey(d, items) && (dup += 1)
        d[items] = parse(Int, strip(parts[2]))
    end
    return d, dup
end

"So hai file output: số itemset khớp hoàn toàn, chỉ có ở một phía, cùng itemset khác support."
function compare_outputs(ours_path, spmf_path)
    a, dup_a = read_output(ours_path)
    b, dup_b = read_output(spmf_path)
    n_match = count(k -> get(b, k, -1) == a[k], keys(a))
    only_ours = count(k -> !haskey(b, k), keys(a))
    only_spmf = count(k -> !haskey(a, k), keys(b))
    diff_sup = count(k -> haskey(b, k) && b[k] != a[k], keys(a))
    union_size = length(a) + only_spmf
    perfect = only_ours == 0 && only_spmf == 0 && diff_sup == 0 && dup_a == 0 && dup_b == 0
    return (n_ours = length(a), n_spmf = length(b), n_match = n_match, only_ours = only_ours, only_spmf = only_spmf,
            diff_sup = diff_sup, match_rate = union_size == 0 ? 1.0 : n_match / union_size,
            status = perfect ? "OK" : "MISMATCH", note = dup_a + dup_b == 0 ? "" : "itemset lặp trong output")
end

const CORR_HEADER = ["dataset", "n_transactions", "minsup_pct", "minsup_count", "mode", "n_ours", "n_spmf", "n_match",
                     "only_ours", "only_spmf", "n_diff_support", "match_rate", "status", "note", "machine"]

corr_key(cfg::Cfg, mode) = (cfg.dataset, format_pct(cfg.pct), mode)

"Các khóa (dataset, minsup, mode) đã có dòng trong CSV correctness."
function corr_done_keys(ctx)
    return Set((r["dataset"], format_pct(parse(Float64, r["minsup_pct"])), r["mode"])
               for r in csv_load(results_path(ctx, "correctness", "grid_correctness")))
end

"Ghi một dòng correctness và trả `true` nếu khớp hoàn toàn (hoặc không so được vì lý do không phải lệch)."
function record_correctness(ctx, cfg::Cfg, mode, ours, spmf, ours_out, spmf_out)
    row = if ours.status != "OK" || spmf.status != "OK"
        # SKIPPED chỉ dành cho so mọi FI không khả thi (vượt giới hạn số FI); các trường hợp khác là NOT_COMPARED
        status = ours.status == "SKIPPED" ? "SKIPPED" : "NOT_COMPARED"
        reason = ours.status != "OK" ? "nhóm: $(ours.status) $(ours.note)" : "SPMF: $(spmf.status) $(spmf.note)"
        (n_ours = ours.n, n_spmf = spmf.n, n_match = missing, only_ours = missing, only_spmf = missing,
         diff_sup = missing, match_rate = missing, status = status, note = reason)
    else
        compare_outputs(ours_out, spmf_out)
    end
    csv_append(results_path(ctx, "correctness", "grid_correctness"), CORR_HEADER,
        [cfg.dataset, cfg.n, format_pct(cfg.pct), cfg.count, mode, row.n_ours, row.n_spmf, row.n_match, row.only_ours,
         row.only_spmf, row.diff_sup, rnd(row.match_rate; digits = 6), row.status, row.note, ctx.machine])
    logmsg("  correctness ", cfg.dataset, " ", format_pct(cfg.pct), "% ", mode, ": ", row.status,
           row.status == "OK" ? "  ($(row.n_match) itemset khớp)" : "  $(row.note)")
    return row.status in ("OK", "SKIPPED", "NOT_COMPARED")
end

# ---------------------------------------------------------------------------
# Vòng đo dùng chung cho runtime, scalability, txlen
# ---------------------------------------------------------------------------

"Header chung của các CSV đo thời gian; `extra` là cột thông số riêng (fraction_pct, avg_length) hoặc rỗng."
function run_header(extra::AbstractString)
    cols = ["dataset"]
    isempty(extra) || push!(cols, extra)
    append!(cols, ["n_transactions", "minsup_pct", "minsup_count", "tool", "run", "status", "n_itemsets",
                   "time_with_write_s", "time_no_write_s", "read_s", "mine_s", "write_s", "process_wall_s", "peak_mem_mb",
                   "baseline_mem_mb", "mem_delta_mb", "mem_source", "machine", "note"])
    return cols
end

function run_row(ctx, cfg::Cfg, extra_value, tool, run, m)
    vals = Any[cfg.dataset]
    extra_value === nothing || push!(vals, extra_value)
    append!(vals, [cfg.n, format_pct(cfg.pct), cfg.count, tool, run, m.status, m.n, rnd(m.time_with_write_s; digits = 5),
                   rnd(m.time_no_write_s; digits = 5), rnd(m.read_s; digits = 5), rnd(m.mine_s; digits = 5),
                   rnd(m.write_s; digits = 5), rnd(m.process_wall_s; digits = 3), rnd(m.peak_mem_mb; digits = 2),
                   rnd(m.baseline_mem_mb; digits = 2), rnd(m.mem_delta_mb; digits = 2), m.mem_source, ctx.machine, m.note])
    return vals
end

"""
    measure_part!(ctx, cfgs; csv, extra_name, extra_of, share_correctness) -> Bool

Đo nhóm (`ours_opt`, tùy chọn mặc định) và SPMF xen kẽ: với mỗi cấu hình và mỗi lần đo, nhóm rồi SPMF. Ghi từng dòng vào
`csv`, bỏ qua dòng đã có (chạy tiếp). Lần đo đầu của mỗi cấu hình giữ output của hai bên để so từng itemset nếu
`share_correctness` (dùng chung lần chạy cho correctness; đọc và so làm sau khi đã dừng đồng hồ).
"""
function measure_part!(ctx::Ctx, cfgs::Vector{Cfg}; csv::AbstractString, extra_name::AbstractString = "",
                       extra_of = c -> nothing, share_correctness::Bool = false)
    header = run_header(extra_name)
    existing = csv_load(csv)
    done = Set((r["dataset"], format_pct(parse(Float64, r["minsup_pct"])), r["tool"], parse(Int, r["run"])) for r in existing)
    timed_out = Dict{Tuple{String,String},Float64}()           # (dataset, tool) => minsup (%) cao nhất đã TIMEOUT
    for r in existing
        r["status"] == "TIMEOUT" || continue
        k = (r["dataset"], r["tool"])
        timed_out[k] = max(get(timed_out, k, 0.0), parse(Float64, r["minsup_pct"]))
    end
    corr_done = share_correctness ? corr_done_keys(ctx) : Set{Tuple{String,String,String}}()
    ok = true
    mkpath(GRID_OUT_DIR)
    for cfg in cfgs
        want_corr = share_correctness && !(corr_key(cfg, "closed") in corr_done)
        logmsg(cfg.dataset, " minsup ", format_pct(cfg.pct), "% (", cfg.count, " giao dịch)")
        shared = Dict{String,Any}()
        for run in 1:ctx.runs, tool in ("ours_opt", "spmf")
            key = (cfg.dataset, format_pct(cfg.pct), tool, run)
            key in done && continue
            keep = run == 1 && want_corr
            out = joinpath(GRID_OUT_DIR, string(tag_of(cfg), "__", tool, keep ? "" : "_tmp", ".txt"))
            to = get(timed_out, (cfg.dataset, tool), nothing)
            m = if ctx.skip_after_timeout && to !== nothing && to >= cfg.pct
                blank("SKIPPED"; note = "bỏ qua: $tool đã TIMEOUT ở minsup $(format_pct(to))% (cao hơn hoặc bằng)")
            elseif tool == "ours_opt"
                run_ours(ctx, cfg; out = out)
            else
                run_spmf(ctx, cfg; out = out)
            end
            m.status == "FAILED" && (ok = false)
            csv_append(csv, header, run_row(ctx, cfg, extra_of(cfg), tool, run, m))
            logmsg("  ", rpad(tool, 9), "run ", run, ": ", m.status, "  ", summary_of(m))
            if m.status == "TIMEOUT"
                timed_out[(cfg.dataset, tool)] = max(get(timed_out, (cfg.dataset, tool), 0.0), cfg.pct)
            end
            keep && (shared[tool] = (m, out))
            keep || rm(out; force = true)
        end
        if haskey(shared, "ours_opt") && haskey(shared, "spmf")      # đồng hồ đã dừng: giờ mới đọc lại và so
            (mo, oo), (ms, so) = shared["ours_opt"], shared["spmf"]
            ok &= record_correctness(ctx, cfg, "closed", mo, ms, oo, so)
            push!(corr_done, corr_key(cfg, "closed"))
        end
        for (_, (_, p)) in shared
            rm(p; force = true)
        end
    end
    return ok
end

"Tổng hợp CSV theo từng (cấu hình, công cụ): thời gian nhỏ nhất của các lần OK, bộ nhớ của lần nhanh nhất, match_rate."
function write_summary(ctx::Ctx, csv_in, csv_out; extra_name = "")
    rows = csv_load(csv_in)
    isempty(rows) && return nothing
    match = Dict{Tuple{String,String},String}()
    for r in csv_load(results_path(ctx, "correctness", "grid_correctness"))
        r["mode"] == "closed" && (match[(r["dataset"], format_pct(parse(Float64, r["minsup_pct"])))] = r["match_rate"])
    end
    groups = Dict{Tuple,Vector{Dict{String,String}}}()
    order = Tuple[]
    for r in rows
        k = (r["dataset"], r["minsup_pct"], r["tool"])
        haskey(groups, k) || (groups[k] = []; push!(order, k))
        push!(groups[k], r)
    end
    header = ["dataset"]
    isempty(extra_name) || push!(header, extra_name)
    append!(header, ["n_transactions", "minsup_pct", "minsup_count", "tool", "mode", "n_itemsets", "time_s", "time_no_write_s",
                     "peak_mem_mb", "match_rate", "n_runs_ok", "status", "machine"])
    rm(csv_out; force = true)
    for k in order
        g = groups[k]
        good = [r for r in g if r["status"] == "OK" && !isempty(r["time_with_write_s"])]
        best = isempty(good) ? g[1] : good[argmin([parse(Float64, r["time_with_write_s"]) for r in good])]
        vals = Any[best["dataset"]]
        isempty(extra_name) || push!(vals, best[extra_name])
        append!(vals, [best["n_transactions"], best["minsup_pct"], best["minsup_count"], best["tool"], "closed", best["n_itemsets"],
                       best["time_with_write_s"], best["time_no_write_s"], best["peak_mem_mb"],
                       get(match, (best["dataset"], format_pct(parse(Float64, best["minsup_pct"]))), ""),
                       length(good), isempty(good) ? g[1]["status"] : "OK", best["machine"]])
        csv_append(csv_out, header, vals)
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Các phần
# ---------------------------------------------------------------------------

"Chọn cấu hình của lưới theo --datasets và --quick (chess, mushrooms; mức cao nhất, giữa và gần cuối)."
function select_grid(ctx::Ctx, grid::Vector{Cfg})
    names = ctx.datasets === nothing ? (ctx.quick ? ["chess", "mushrooms"] : unique(c.dataset for c in grid)) : ctx.datasets
    cfgs = Cfg[]
    for d in names
        levels = [c for c in grid if c.dataset == d]
        isempty(levels) && error("dataset không có trong data/meta/benchmark_config.csv: $d")
        if ctx.quick
            idx = sort(unique([1, cld(length(levels), 2), max(1, length(levels) - 1)]))
            levels = levels[idx]
        end
        append!(cfgs, levels)
    end
    return cfgs
end

"Phần correctness (dùng riêng): các cấu hình chưa có dòng correctness, mỗi cấu hình một lần đo của mỗi công cụ."
function part_correctness!(ctx::Ctx, cfgs::Vector{Cfg})
    done = corr_done_keys(ctx)
    ok = true
    mkpath(GRID_OUT_DIR)
    timed_out = Dict{String,Float64}()
    for cfg in cfgs
        corr_key(cfg, "closed") in done && continue
        logmsg("correctness ", cfg.dataset, " ", format_pct(cfg.pct), "%")
        if ctx.skip_after_timeout && get(timed_out, cfg.dataset, 0.0) >= cfg.pct
            ok &= record_correctness(ctx, cfg, "closed", blank("SKIPPED"; note = "đã TIMEOUT ở minsup cao hơn"), blank("SKIPPED"), "", "")
            continue
        end
        oo = joinpath(GRID_OUT_DIR, tag_of(cfg) * "__ours.txt")
        so = joinpath(GRID_OUT_DIR, tag_of(cfg) * "__spmf.txt")
        mo = run_ours(ctx, cfg; out = oo)
        ms = run_spmf(ctx, cfg; out = so)
        (mo.status == "TIMEOUT" || ms.status == "TIMEOUT") && (timed_out[cfg.dataset] = max(get(timed_out, cfg.dataset, 0.0), cfg.pct))
        ok &= record_correctness(ctx, cfg, "closed", mo, ms, oo, so)
        rm(oo; force = true)
        rm(so; force = true)
    end
    # So mọi frequent itemset (khôi phục từ tập đóng, so với FPGrowth_itemsets của SPMF). Mặc định chỉ ở minsup cao
    # nhất của mỗi dataset; với --fi-all-levels thì ở mọi mức minsup của lưới, đi từ cao xuống thấp. Số FI chỉ tăng khi
    # minsup giảm, nên khi một mức vượt --fi-limit (SKIPPED) thì các mức thấp hơn của dataset đó cũng ghi SKIPPED mà
    # không chạy. SPMF chỉ chạy khi phía nhóm OK (tránh để SPMF ghi file khổng lồ).
    for d in unique(c.dataset for c in cfgs)
        levels = [c for c in cfgs if c.dataset == d]           # lưới sắp từ minsup cao xuống thấp
        ctx.fi_all_levels || (levels = levels[1:1])
        over_limit = false
        for cfg in levels
            corr_key(cfg, "all_fi") in done && continue
            if over_limit
                ok &= record_correctness(ctx, cfg, "all_fi",
                                         blank("SKIPPED"; note = "số FI vượt giới hạn $(ctx.fi_limit) ở minsup cao hơn"),
                                         blank("SKIPPED"), "", "")
                continue
            end
            logmsg("correctness (mọi FI) ", cfg.dataset, " ", format_pct(cfg.pct), "%")
            oo = joinpath(GRID_OUT_DIR, tag_of(cfg) * "__ours_all.txt")
            so = joinpath(GRID_OUT_DIR, tag_of(cfg) * "__spmf_all.txt")
            mo = run_ours(ctx, cfg; out = oo, mode = "all")
            ms = mo.status == "OK" ? run_spmf(ctx, cfg; out = so, mode = "all") : blank("SKIPPED")
            ok &= record_correctness(ctx, cfg, "all_fi", mo, ms, oo, so)
            mo.status == "SKIPPED" && (over_limit = true)
            rm(oo; force = true)
            rm(so; force = true)
        end
    end
    return ok
end

"Phần runtime: lưới (đã chọn), nhóm (mặc định) và SPMF xen kẽ, dùng chung lần đo đầu cho correctness nếu được chọn."
function part_runtime!(ctx::Ctx, cfgs::Vector{Cfg})
    csv = results_path(ctx, "runtime", "grid_runtime")
    ok = measure_part!(ctx, cfgs; csv = csv, share_correctness = "correctness" in ctx.parts)
    write_summary(ctx, csv, results_path(ctx, "runtime", "grid_runtime_summary"))
    return ok
end

const MEMORY_HEADER = ["dataset", "n_transactions", "minsup_pct", "minsup_count", "variant", "run", "status", "n_closed",
                       "result_hash", "same_as_optimized", "read_s", "mine_s", "peak_mem_mb", "baseline_mem_mb", "mem_delta_mb", "alloc_mb",
                       string.(STAT_FIELDS)..., "machine", "note"]

"Phần memory: minsup ở giữa lưới của mỗi dataset; mỗi variant chạy trong tiến trình riêng; kiểm mọi variant cùng tập đóng."
function part_memory!(ctx::Ctx, cfgs::Vector{Cfg})
    csv = results_path(ctx, "memory", "basic_vs_optimized")
    existing = csv_load(csv)
    done = Set((r["dataset"], r["variant"], parse(Int, r["run"])) for r in existing)
    reference = Dict{String,Tuple{String,String}}()           # dataset => (n_closed, hash) của variant optimized
    for r in existing
        r["variant"] == "optimized" && r["status"] == "OK" && (reference[r["dataset"]] = (r["n_closed"], r["result_hash"]))
    end
    ok = true
    mkpath(GRID_OUT_DIR)
    for d in unique(c.dataset for c in cfgs)
        levels = [c for c in cfgs if c.dataset == d]
        cfg = levels[cld(length(levels), 2)]                   # minsup ở giữa lưới
        logmsg("memory ", d, " minsup ", format_pct(cfg.pct), "% (", cfg.count, " giao dịch)")
        for (name, opts) in VARIANTS
            for run in 1:ctx.runs
                (d, name, run) in done && continue
                m = run_ours(ctx, cfg; out = "-", opts = opts, stats = true, hash = true)
                same = m.status != "OK" ? missing :
                       (haskey(reference, d) ? (string(m.n), m.hash) == reference[d] : name == "optimized" ? true : missing)
                if name == "optimized" && m.status == "OK" && !haskey(reference, d)
                    reference[d] = (string(m.n), m.hash)
                end
                same === false && (ok = false)
                m.status == "FAILED" && (ok = false)
                csv_append(csv, MEMORY_HEADER,
                    [d, cfg.n, format_pct(cfg.pct), cfg.count, name, run, m.status, m.n, m.hash, same, rnd(m.read_s; digits = 5),
                     rnd(m.mine_s; digits = 5), rnd(m.peak_mem_mb; digits = 2), rnd(m.baseline_mem_mb; digits = 2),
                     rnd(m.mem_delta_mb; digits = 2), rnd(m.alloc_mb; digits = 2), (get(m.stats, string(f), missing) for f in STAT_FIELDS)..., ctx.machine, m.note])
                logmsg("  ", rpad(name, 26), "run ", run, ": ", m.status,
                       m.status == "OK" ? @sprintf("  mine %.3f s  peak %.1f MB (+%.1f)  %d tập đóng  cùng optimized: %s",
                                                   m.mine_s, m.peak_mem_mb, m.mem_delta_mb, m.n, same) : "  " * m.note)
                m.status == "TIMEOUT" && break                 # variant này quá chậm: bỏ các lần còn lại
            end
        end
    end
    return ok
end

function part_scalability!(ctx::Ctx)
    cfgs = scalability_cfgs(ctx.scal_minsups; quick = ctx.quick)
    csv = results_path(ctx, "scalability", "scalability")
    frac = Dict(c.dataset => parse(Int, last(c.dataset, 3)) for c in cfgs)
    ok = measure_part!(ctx, cfgs; csv = csv, extra_name = "fraction_pct", extra_of = c -> frac[c.dataset])
    write_summary(ctx, csv, results_path(ctx, "scalability", "scalability_summary"); extra_name = "fraction_pct")
    return ok
end

function part_txlen!(ctx::Ctx)
    cfgs = txlen_cfgs(ctx.txlen_minsups; quick = ctx.quick)
    csv = results_path(ctx, "txlen", "txlen")
    avg = Dict(c.dataset => parse(Int, last(c.dataset, 2)) for c in cfgs)
    ok = measure_part!(ctx, cfgs; csv = csv, extra_name = "avg_length", extra_of = c -> avg[c.dataset])
    write_summary(ctx, csv, results_path(ctx, "txlen", "txlen_summary"); extra_name = "avg_length")
    return ok
end

"""
Chạy thử để chọn minsup cho txlen: mỗi độ dài và mỗi mức minsup ứng viên chạy MỘT lần với cả hai công cụ, ghi
results/txlen/pilot.csv để chọn mức chạy được với mọi độ dài.
"""
function part_txlen_pilot!(ctx::Ctx)
    cands = ctx.txlen_minsups
    cfgs = txlen_cfgs(cands; quick = ctx.quick)
    csv = results_path(ctx, "txlen", "pilot")
    header = ["dataset", "avg_length", "minsup_pct", "minsup_count", "tool", "status", "n_itemsets", "time_with_write_s", "note"]
    done = Set((r["dataset"], format_pct(parse(Float64, r["minsup_pct"])), r["tool"]) for r in csv_load(csv))
    mkpath(GRID_OUT_DIR)
    for cfg in cfgs, tool in ("ours_opt", "spmf")
        (cfg.dataset, format_pct(cfg.pct), tool) in done && continue
        out = joinpath(GRID_OUT_DIR, tag_of(cfg) * "__pilot.txt")
        m = tool == "ours_opt" ? run_ours(ctx, cfg; out = out) : run_spmf(ctx, cfg; out = out)
        rm(out; force = true)
        csv_append(csv, header, [cfg.dataset, parse(Int, last(cfg.dataset, 2)), format_pct(cfg.pct), cfg.count, tool, m.status,
                                 m.n, rnd(m.time_with_write_s; digits = 4), m.note])
        logmsg("txlen pilot ", cfg.dataset, " ", format_pct(cfg.pct), "% ", tool, ": ", m.status, "  ", summary_of(m))
    end
    return true
end

# ---------------------------------------------------------------------------
# Môi trường, dòng lệnh, main
# ---------------------------------------------------------------------------

"Ghi cấu hình máy và tham số chạy vào results/ENVIRONMENT.md (hoặc ENVIRONMENT_quick.md khi --quick)."
function write_environment(ctx::Ctx)
    git(args...) = try strip(read(Cmd(`git $args`; dir = ROOT), String)) catch; "không rõ" end
    cpu = Sys.cpu_info()[1].model
    path = joinpath(RESULTS_DIR, "ENVIRONMENT" * (ctx.quick ? "_quick" : "") * ".md")
    mkpath(RESULTS_DIR)
    write(path, """
        # Môi trường chạy thực nghiệm

        Ghi tự động bởi `scripts/run_benchmark_grid.jl` ở lần chạy gần nhất (mỗi dòng của các CSV có cột `machine`).

        | Mục | Giá trị |
        |---|---|
        | Cập nhật lúc (UTC) | $(Dates.format(now(UTC), "yyyy-mm-dd HH:MM:SS")) |
        | Nhãn máy | $(ctx.machine) |
        | Hệ điều hành | $(Sys.KERNEL) ($(Sys.MACHINE)) |
        | CPU | $cpu |
        | Số luồng logic | $(Sys.CPU_THREADS) |
        | RAM | $(round(Sys.total_memory() / 2^30; digits = 1)) GiB |
        | Julia | $VERSION |
        | Java | $(java_version(ctx.java)) |
        | spmf.jar SHA-256 | `$(isfile(ctx.jar) ? sha256_file(ctx.jar) : "không thấy")` |
        | JVM heap (-Xmx) | $(ctx.heap) |
        | Commit | $(git("rev-parse", "--short", "HEAD")) ($(isempty(git("status", "--porcelain")) ? "sạch" : "có thay đổi chưa commit")) |
        | Số lần đo mỗi cấu hình | $(ctx.runs) (tổng hợp lấy nhỏ nhất) |
        | Timeout mỗi lần chạy | $(ctx.timeout) s |
        | Chế độ | $(ctx.quick ? "--quick" : "đầy đủ") |

        Chưa ghi tự động (cần ghi tay trước khi chạy chính thức): chế độ nguồn/hiệu năng của máy, ứng dụng nền đang mở,
        nhiệt độ. Mọi số liệu trên cùng một biểu đồ phải đo trên cùng máy.
        """)
    return path
end

const USAGE = "cách dùng: julia --project=. scripts/run_benchmark_grid.jl [--only a,b] [--datasets a,b] [--runs N] [--timeout S] [--quick] [--suffix S] [--machine NAME] [--fi-limit N] [--fi-all-levels]"

function parse_args(args)
    o = Dict{String,Any}("only" => nothing, "datasets" => nothing, "runs" => nothing, "timeout" => 600, "quick" => false,
                         "suffix" => nothing, "machine" => get(ENV, "FPCLOSE_MACHINE", gethostname()), "fi-limit" => 2_000_000,
                         "txlen-minsups" => nothing, "scal-minsups" => "0.1,0.05", "skip" => true,
                         "jar" => joinpath(TOOLS_DIR, "spmf.jar"), "java-heap" => "4g", "fi-all-levels" => false)
    flags = ("--quick", "--no-skip-after-timeout", "--fi-all-levels")
    valued = ("--only", "--datasets", "--runs", "--timeout", "--suffix", "--machine", "--fi-limit", "--txlen-minsups",
              "--scal-minsups", "--jar", "--java-heap")
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--quick"
            o["quick"] = true
        elseif a == "--no-skip-after-timeout"
            o["skip"] = false
        elseif a == "--fi-all-levels"
            o["fi-all-levels"] = true
        elseif a in valued
            i < length(args) || error("thiếu giá trị sau $a")
            o[a[3:end]] = args[i+1]
            i += 1
        else
            error("tham số không hợp lệ: $a")
        end
        i += 1
    end
    csvlist(s) = String.(strip.(split(s, ',')))
    posint(name, v) = (x = tryparse(Int, string(v)); (x !== nothing && x > 0) || error("--$name phải là số nguyên dương, nhận \"$v\""); x)
    parts = o["only"] === nothing ? copy(ALL_PARTS) : csvlist(o["only"])
    bad = setdiff(parts, [ALL_PARTS; "txlen_pilot"])
    isempty(bad) || error("--only không hợp lệ: $(join(bad, ", ")) (hợp lệ: $(join(ALL_PARTS, ", ")), txlen_pilot)")
    quick = o["quick"]
    runs = o["runs"] === nothing ? (quick ? 1 : 3) : posint("runs", o["runs"])
    floats(s) = parse.(Float64, csvlist(s))
    # mức minsup (%) của txlen: giá trị mặc định chọn từ lần chạy thử, ghi lý do ở results/txlen/README.md
    tl = o["txlen-minsups"] === nothing ? (quick ? [0.5] : DEFAULT_TXLEN_MINSUPS) : floats(o["txlen-minsups"])
    sc = floats(o["scal-minsups"])
    quick && o["scal-minsups"] == "0.1,0.05" && (sc = [0.1])
    return Ctx(parts, o["datasets"] === nothing ? nothing : csvlist(o["datasets"]), runs, posint("timeout", o["timeout"]),
               quick, o["suffix"] === nothing ? (quick ? "_quick" : "") : o["suffix"], o["machine"], posint("fi-limit", o["fi-limit"]),
               o["fi-all-levels"], tl, sc, o["skip"], o["jar"], find_java(), o["java-heap"])
end

# Mức minsup (%) mặc định cho txlen (chọn bằng `--only txlen_pilot`, lý do ở results/txlen/README.md)
const DEFAULT_TXLEN_MINSUPS = [0.5, 0.2]

function main(args)
    ctx = try
        parse_args(args)
    catch err
        println(stderr, "Lỗi: ", sprint(showerror, err), "\n", USAGE)
        return 2
    end
    isfile(ctx.jar) || (println(stderr, "Không thấy ", ctx.jar, " (tải theo README)"); return 2)
    env = write_environment(ctx)
    t0 = time()
    logmsg("=== run_benchmark_grid: phần ", join(ctx.parts, ","), " | runs=", ctx.runs, " timeout=", ctx.timeout, "s",
           ctx.quick ? " | --quick" : "", " | máy ", ctx.machine)
    logmsg("môi trường: ", env)
    ok = true
    try
        grid = load_grid()
        cfgs = any(p in ctx.parts for p in ("correctness", "runtime", "memory")) ? select_grid(ctx, grid) : Cfg[]
        # runtime chạy trước để correctness dùng chung lần đo đầu; correctness riêng chỉ lo các cấu hình còn thiếu
        "runtime" in ctx.parts && (ok &= part_runtime!(ctx, cfgs))
        "correctness" in ctx.parts && (ok &= part_correctness!(ctx, cfgs))
        "memory" in ctx.parts && (ok &= part_memory!(ctx, cfgs))
        "scalability" in ctx.parts && (ok &= part_scalability!(ctx))
        "txlen" in ctx.parts && (ok &= part_txlen!(ctx))
        "txlen_pilot" in ctx.parts && (ok &= part_txlen_pilot!(ctx))
    catch err
        logmsg("LỖI: ", sprint(showerror, err))
        println(stderr, sprint(showerror, err, catch_backtrace()))
        return 2
    end
    logmsg("=== xong sau ", round((time() - t0) / 60; digits = 1), " phút", ok ? "" : " | CÓ MỤC LỆCH HOẶC FAILED, xem log")
    return ok ? 0 : 1
end

if abspath(PROGRAM_FILE) == @__FILE__
    # Tiến trình đo của nhóm gọi thẳng `worker`, KHÔNG qua `main`: gọi `main` làm Julia suy luận kiểu cho cả script
    # trước khi worker chạy và đẩy đỉnh RSS nền lên ~470 MB (lớn hơn bộ nhớ của thuật toán trên CSDL nhỏ, làm số đo
    # `peak - baseline` luôn bằng 0). Gọi thẳng cho nền ~290 MB.
    if !isempty(ARGS) && ARGS[1] == "--worker"
        worker(ARGS[2:end])
        exit(0)
    end
    exit(main(ARGS))
end
