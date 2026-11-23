# Kiểm tra dữ liệu bằng các thuật toán tham chiếu: SPMF FPClose và FPclose gốc của Grahne & Zhu (FIMI).
#
# Chạy hai cài đặt có sẵn trên các cấu hình minsup của data/meta/benchmark_config.csv:
#   - SPMF FPClose (Java, spmf.jar): số closed itemsets phải bằng `reference_closed_itemsets`; mỗi dòng
#     đúng định dạng, không có item trùng, support >= minsup_count.
#   - FIMI FPclose (C++, fimi06b.tgz): tập closed itemsets và support phải giống SPMF từng dòng.
# Phần này kiểm tra DỮ LIỆU và CÔNG CỤ THAM CHIẾU, không kiểm tra cài đặt của nhóm. Thời gian đo ở đây
# gồm cả khởi động JVM, không dùng làm số benchmark.
#
# Cấu hình (data/meta/benchmark_config.csv, benchmark_inventory.csv) được ĐỌC từ file, không chép cứng.
# Kết quả ghi vào results/reference/ (spmf_check.csv và fimi_compare.csv).
#
# Cách dùng (từ thư mục gốc repo):
#   julia --project=. scripts/reference_check.jl                     # cả 9 dataset, 56 cấu hình
#   julia --project=. scripts/reference_check.jl --datasets chess    # chạy thử nhanh
#   julia --project=. scripts/reference_check.jl --timeout 300 --skip-fimi
#
#   --datasets a,b  chỉ chạy các dataset này; file kết quả có thêm hậu tố _a+b để không ghi đè kết quả đầy đủ
#   --timeout S     giới hạn S giây cho mỗi lần chạy (mặc định 600)
#   --skip-fimi     chỉ kiểm SPMF, không tải và biên dịch FIMI (khi máy không có g++)
#
# Cần: dataset trong data/benchmark/ (chưa có thì tải từ Hugging Face và kiểm SHA-256), Java 25 (trên
# Linux/Colab tự tải Temurin 25), tools/spmf.jar (tự tải), g++ để biên dịch FIMI. Toàn bộ mất khoảng 10 phút.
#
# Mã thoát: 0 nếu mọi cấu hình khớp, 1 nếu có cấu hình lệch hoặc lỗi, 2 nếu sai tham số.

using SHA
using Downloads

# Gốc repo suy ra từ vị trí script (scripts/ nằm ngay dưới gốc)
const ROOT = normpath(joinpath(@__DIR__, ".."))
const META_DIR = joinpath(ROOT, "data", "meta")
const BENCHMARK_DIR = joinpath(ROOT, "data", "benchmark")
const TOOLS_DIR = joinpath(ROOT, "tools")
const RESULTS_DIR = joinpath(ROOT, "results", "reference")

"""
    sha256_file(path) -> String

SHA-256 (hex, chữ thường) của file, đọc theo luồng nên không tốn RAM với file lớn.
"""
sha256_file(path::AbstractString) = open(io -> bytes2hex(sha256(io)), path)

"""
    read_csv_rows(path) -> Vector{Dict{String,String}}

Đọc CSV đơn giản (không có dấu phẩy trong ô), đủ cho các file trong `data/meta/`.
"""
function read_csv_rows(path::AbstractString)
    lines = filter(!isempty, strip.(readlines(path)))
    header = split(lines[1], ',')
    return [Dict(String(h) => String(v) for (h, v) in zip(header, split(l, ','))) for l in lines[2:end]]
end

"""
    write_csv(path, header, rows)

Ghi CSV với xuống dòng LF. `rows` là danh sách vector giá trị theo đúng thứ tự `header`.
"""
function write_csv(path::AbstractString, header::Vector{String}, rows)
    mkpath(dirname(abspath(path)))
    open(path, "w") do io
        println(io, join(header, ','))
        for r in rows
            println(io, join(string.(r), ','))
        end
    end
end

const HF_REPO = "hytrang/fpclose-fim-benchmarks"
hf_url(name) = "https://huggingface.co/datasets/$HF_REPO/resolve/main/$name"

"""
    verify_hf(inventory, outdir; names = nothing) -> Bool

Trả về `true` nếu mọi file khớp hash và số giao dịch. `names` giới hạn danh sách dataset.
"""
function verify_hf(inventory::AbstractString, outdir::AbstractString; names = nothing)
    mkpath(outdir)
    ok = true
    for row in read_csv_rows(inventory)
        name = row["dataset"]
        names === nothing || name in names || continue
        file = joinpath(outdir, "$name.txt")
        expected = lowercase(row["sha256"])
        if !(isfile(file) && sha256_file(file) == expected)
            Downloads.download(hf_url("$name.txt"), file)
        end
        actual = sha256_file(file)
        lines = countlines(file)
        good = actual == expected && lines == parse(Int, row["transactions"])
        ok &= good
        println(good ? "[PASS] " : "[FAIL] ", rpad(name, 12), lines, " giao dịch  ", actual)
    end
    return ok
end

"Tìm java.exe của JDK 25 (Temurin) nếu `java` trên PATH là bản cũ."
function find_java()
    for root in ("C:\\Program Files\\Eclipse Adoptium", "/usr/lib/jvm")
        isdir(root) || continue
        for d in sort(readdir(root); rev = true)
            startswith(d, "jdk-25") || startswith(d, "temurin-25") || continue
            for exe in ("java.exe", "java")
                p = joinpath(root, d, "bin", exe)
                isfile(p) && return p
            end
        end
    end
    return "java"
end


const SPMF_JAR_URL = "https://www.philippe-fournier-viger.com/spmf/spmf.jar"
const FIMI_SRC_URL = "https://fimi.uantwerpen.be/src/fimi06b.tgz"
const TEMURIN25_LINUX_URL = "https://api.adoptium.net/v3/binary/latest/25/ga/linux/x64/jdk/hotspot/normal/eclipse"

"Phiên bản chính của `java` (vd. 25), 0 nếu không chạy được."
function java_major(java)
    buf = IOBuffer()
    try
        run(pipeline(ignorestatus(`$java -version`); stdout = buf, stderr = buf))
    catch
        return 0
    end
    m = match(r"version \"(\d+)", String(take!(buf)))
    return m === nothing ? 0 : parse(Int, m[1])
end

"Tìm hoặc tải Java ≥ 25; trả về đường dẫn tới lệnh java."
function ensure_java(toolsdir)
    candidates = [find_java()]
    if isdir(toolsdir)
        for d in readdir(toolsdir; join = true)
            startswith(basename(d), "jdk-25") && push!(candidates, joinpath(d, "bin", Sys.iswindows() ? "java.exe" : "java"))
        end
    end
    for java in candidates
        java_major(java) >= 25 && return java
    end
    Sys.islinux() || error("Cần Java 25: cài Eclipse Temurin 25 (https://adoptium.net) rồi chạy lại")
    mkpath(toolsdir)
    tarball = joinpath(toolsdir, "temurin25.tar.gz")
    println("Tải Temurin 25 (~200 MB) ...")
    Downloads.download(TEMURIN25_LINUX_URL, tarball)
    run(Cmd(`tar -xzf temurin25.tar.gz`; dir = toolsdir))
    rm(tarball)
    for d in readdir(toolsdir; join = true)
        java = joinpath(d, "bin", "java")
        startswith(basename(d), "jdk-25") && java_major(java) >= 25 && return java
    end
    error("Đã tải Temurin 25 nhưng không tìm thấy bin/java trong $toolsdir")
end

"Tải spmf.jar nếu chưa có."
function ensure_spmf(toolsdir)
    jar = joinpath(toolsdir, "spmf.jar")
    if !isfile(jar)
        mkpath(toolsdir)
        println("Tải spmf.jar ...")
        Downloads.download(SPMF_JAR_URL, jar)
    end
    return jar
end

"Tải fimi06b.tgz và biên dịch FPclose (`-DCFI`) nếu chưa có."
function ensure_fimi(toolsdir)
    fimidir = mkpath(joinpath(toolsdir, "fimi"))
    exe = joinpath(fimidir, Sys.iswindows() ? "fim_closed.exe" : "fim_closed")
    isfile(exe) && return exe
    src = mkpath(joinpath(fimidir, "src"))
    println("Tải và biên dịch FIMI FPclose ...")
    Downloads.download(FIMI_SRC_URL, joinpath(src, "fimi06b.tgz"))
    run(Cmd(`tar -xzf fimi06b.tgz`; dir = src))
    # Code năm 2003 dùng các header cũ (<iostream.h>, ...); thêm header tương thích,
    # không sửa code gốc.
    compat = mkpath(joinpath(src, "compat"))
    for (old, new) in ("iostream.h" => "iostream", "fstream.h" => "fstream",
                       "iomanip.h" => "iomanip", "strstream.h" => "sstream")
        write(joinpath(compat, old), "#pragma once\n#include <$new>\nusing namespace std;\n")
    end
    sources = ["fpmax.cpp", "data.cpp", "fp_tree.cpp", "buffer.cpp", "fsout.cpp", "fp_node.cpp"]
    run(Cmd(`g++ -O3 -w -fpermissive -I compat -DCFI $sources -o $exe`; dir = src))
    return exe
end

"""
    setup_tools(toolsdir; with_fimi = true) -> (java, jar, fimi)

Chuẩn bị Java 25, tools/spmf.jar và (nếu `with_fimi`) tools/fimi/fim_closed; `fimi = nothing` khi bỏ qua.
"""
function setup_tools(toolsdir; with_fimi::Bool = true)
    java = ensure_java(toolsdir)
    jar = ensure_spmf(toolsdir)
    fimi = with_fimi ? ensure_fimi(toolsdir) : nothing
    println("java  ", java, "  (Java ", java_major(java), ")")
    println("spmf  ", jar)
    println("fimi  ", fimi === nothing ? "(bỏ qua: --skip-fimi)" : fimi)
    return (java = java, jar = jar, fimi = fimi)
end

"""
    check_spmf_output(path, minsup_count) -> Int

Đếm closed itemsets trong output SPMF và kiểm tra định dạng, support.
"""
function check_spmf_output(path::AbstractString, minsup_count::Integer)
    count = 0
    for line in eachline(path)
        s = strip(line)
        (isempty(s) || startswith(s, '@') || startswith(s, '#')) && continue
        parts = split(s, "#SUP:")
        length(parts) == 2 || error("Dòng output lạ: $(first(s, 120))")
        items = parse.(Int, split(parts[1]))
        support = parse(Int, strip(parts[2]))
        allunique(items) || error("Itemset có item trùng: $(first(s, 120))")
        support >= minsup_count || error("Support $support < minsup_count $minsup_count")
        count += 1
    end
    return count
end

"Chạy SPMF FPClose một lần; trả về (status, wall_time_s, n_closed, output_mb)."
function run_spmf(java, jar, input, minsup_pct, minsup_count; timeout_s = 300)
    out = tempname() * "_closed.txt"
    log = tempname() * "_spmf.log"
    pct = string(minsup_pct)
    pct = endswith(pct, ".0") ? pct[1:end-2] : pct
    cmd = `$java -Xmx4g -jar $jar run FPClose $input $out $(pct)%`
    t0 = time()
    proc = open(log, "w") do io
        run(pipeline(cmd; stdout = io, stderr = io); wait = false)
    end
    while process_running(proc)
        if time() - t0 > timeout_s
            kill(proc)
            wait(proc)
            rm(out; force = true)
            return (status = "TIMEOUT", wall_time_s = round(time() - t0; digits = 3),
                n_closed = missing, output_mb = missing)
        end
        sleep(0.05)
    end
    elapsed = round(time() - t0; digits = 3)
    try
        if !success(proc) || !isfile(out)
            msg = isfile(log) ? strip(read(log, String)) : ""
            return (status = "FAILED: " * first(replace(msg, '\n' => ' '), 200),
                wall_time_s = elapsed, n_closed = missing, output_mb = missing)
        end
        n = check_spmf_output(out, minsup_count)
        return (status = "OK", wall_time_s = elapsed, n_closed = n,
            output_mb = round(filesize(out) / 2^20; digits = 3))
    finally
        rm(out; force = true)
        rm(log; force = true)
    end
end

"""
    spmf_check(config, datadir; java, jar, datasets, levels, timeout_s) -> Vector{NamedTuple}
"""
function spmf_check(config::AbstractString, datadir::AbstractString; java = find_java(),
        jar, datasets = nothing,
        levels = "all", timeout_s = 300)
    isfile(jar) || error("Không thấy $jar")
    rows = read_csv_rows(config)
    if levels == "top"
        best = Dict{String,Dict{String,String}}()
        for r in rows
            d = r["dataset"]
            if !haskey(best, d) || parse(Float64, r["minsup_pct"]) > parse(Float64, best[d]["minsup_pct"])
                best[d] = r
            end
        end
        rows = [r for r in rows if best[r["dataset"]] === r]
    end
    results = NamedTuple[]
    for r in rows
        d = r["dataset"]
        datasets === nothing || d in datasets || continue
        input = joinpath(datadir, "$d.txt")
        isfile(input) || error("Không thấy $input: chạy scripts/data_setup.jl trước")
        pct = parse(Float64, r["minsup_pct"])
        mc = parse(Int, r["minsup_count"])
        ref = parse(Int, r["reference_closed_itemsets"])
        res = run_spmf(java, jar, input, pct, mc; timeout_s = timeout_s)
        match = res.status == "OK" && res.n_closed == ref
        push!(results, (dataset = d, minsup_pct = pct, minsup_count = mc,
            reference_closed_itemsets = ref, n_closed_itemsets = res.n_closed,
            match = match, wall_time_s = res.wall_time_s, output_mb = res.output_mb,
            status = res.status))
        println(match ? "[OK]   " : "[SAI]  ", rpad(d, 12), lpad(string(pct, "%"), 7),
            "  ref=", lpad(ref, 9), "  spmf=", lpad(coalesce(res.n_closed, "-"), 9),
            "  ", res.wall_time_s, "s  ", res.status == "OK" ? "" : res.status)
    end
    return results
end

const SPMF_CHECK_HEADER = ["dataset", "minsup_pct", "minsup_count", "reference_closed_itemsets",
    "n_closed_itemsets", "match", "wall_time_s", "output_mb", "status"]

"Chạy lệnh với giới hạn thời gian; trả về (status, wall_time_s)."
function run_timed(cmd::Cmd; timeout_s = 300)
    log = tempname() * ".log"
    t0 = time()
    proc = open(log, "w") do io
        run(pipeline(cmd; stdout = io, stderr = io); wait = false)
    end
    while process_running(proc)
        if time() - t0 > timeout_s
            kill(proc)
            wait(proc)
            rm(log; force = true)
            return ("TIMEOUT", round(time() - t0; digits = 3))
        end
        sleep(0.02)
    end
    elapsed = round(time() - t0; digits = 3)
    msg = success(proc) ? "OK" : "FAILED: " * first(replace(strip(read(log, String)), '\n' => ' '), 200)
    rm(log; force = true)
    return (msg, elapsed)
end

"Đọc output thành tập `\"i1 i2 ...#sup\"` (item đã sắp tăng), bỏ tập rỗng."
function read_itemsets(path::AbstractString, format::Symbol)
    result = Set{String}()
    for line in eachline(path)
        s = strip(line)
        (isempty(s) || startswith(s, '@')) && continue
        if format == :spmf
            lhs, rhs = split(s, "#SUP:")
        else
            m = match(r"^(.*)\((\d+)\)$", s)
            m === nothing && error("Dòng FIMI lạ: $(first(s, 120))")
            lhs, rhs = m.captures
        end
        items = sort!(parse.(Int, split(lhs)))
        isempty(items) && continue
        key = join(items, ' ') * "#" * strip(rhs)
        key in result && error("Itemset bị lặp trong output $format: $key")
        push!(result, key)
    end
    return result
end

"""
    fimi_compare(config, datadir; ...) -> Vector{NamedTuple}
"""
function fimi_compare(config::AbstractString, datadir::AbstractString; java = find_java(),
        jar, fimi,
        datasets = nothing, timeout_s = 300)
    isfile(jar) || error("Không thấy $jar")
    isfile(fimi) || error("Không thấy $fimi — biên dịch FPclose của FIMI trước")
    results = NamedTuple[]
    for r in read_csv_rows(config)
        d = r["dataset"]
        datasets === nothing || d in datasets || continue
        input = joinpath(datadir, "$d.txt")
        pct = parse(Float64, r["minsup_pct"])
        mc = parse(Int, r["minsup_count"])
        ref = parse(Int, r["reference_closed_itemsets"])
        pct_s = string(pct)
        pct_s = endswith(pct_s, ".0") ? pct_s[1:end-2] : pct_s
        spmf_out = tempname() * "_spmf.txt"
        fimi_out = tempname() * "_fimi.txt"
        try
            s_status, s_time = run_timed(`$java -Xmx4g -jar $jar run FPClose $input $spmf_out $(pct_s)%`; timeout_s)
            f_status, f_time = run_timed(`$fimi $input $mc $fimi_out`; timeout_s)
            spmf = s_status == "OK" ? read_itemsets(spmf_out, :spmf) : nothing
            fim = f_status == "OK" ? read_itemsets(fimi_out, :fimi) : nothing
            same = spmf !== nothing && fim !== nothing && spmf == fim
            only_spmf = spmf !== nothing && fim !== nothing ? length(setdiff(spmf, fim)) : missing
            only_fimi = spmf !== nothing && fim !== nothing ? length(setdiff(fim, spmf)) : missing
            n_s = spmf === nothing ? missing : length(spmf)
            n_f = fim === nothing ? missing : length(fim)
            ok = same && n_s == ref
            push!(results, (dataset = d, minsup_pct = pct, minsup_count = mc,
                reference_closed_itemsets = ref, n_spmf = n_s, n_fimi = n_f,
                only_spmf = only_spmf, only_fimi = only_fimi, identical = same,
                spmf_time_s = s_time, fimi_time_s = f_time,
                status = s_status == "OK" && f_status == "OK" ? "OK" : "spmf=$s_status; fimi=$f_status"))
            println(ok ? "[OK]   " : "[SAI]  ", rpad(d, 12), lpad(string(pct, "%"), 7),
                "  ref=", lpad(ref, 8), "  spmf=", lpad(coalesce(n_s, "-"), 8),
                "  fimi=", lpad(coalesce(n_f, "-"), 8), "  giống từng dòng=", same,
                "  spmf ", s_time, "s / fimi ", f_time, "s")
        finally
            rm(spmf_out; force = true)
            rm(fimi_out; force = true)
        end
    end
    return results
end

const FIMI_COMPARE_HEADER = ["dataset", "minsup_pct", "minsup_count", "reference_closed_itemsets",
    "n_spmf", "n_fimi", "only_spmf", "only_fimi", "identical", "spmf_time_s", "fimi_time_s", "status"]

# ---------------------------------------------------------------------------
# Dòng lệnh
# ---------------------------------------------------------------------------

const USAGE = "cách dùng: julia --project=. scripts/reference_check.jl [--datasets ds1,ds2] [--timeout giây] [--skip-fimi]"

"Đọc tham số dòng lệnh; trả về `(datasets, timeout, skip_fimi)` (`datasets = nothing` nghĩa là cả 9 dataset)."
function parse_args(args)
    datasets = nothing
    timeout = 600
    skip_fimi = false
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--skip-fimi"
            skip_fimi = true
        elseif a in ("--datasets", "--timeout")
            i < length(args) || error("thiếu giá trị sau $a")
            v = args[i+1]
            if a == "--datasets"
                datasets = String.(strip.(split(v, ',')))
            else
                timeout = tryparse(Int, v)
                (timeout !== nothing && timeout > 0) || error("--timeout phải là số nguyên dương (giây), nhận \"$v\"")
            end
            i += 1
        else
            error("tham số không hợp lệ: $a")
        end
        i += 1
    end
    return (datasets = datasets, timeout = timeout, skip_fimi = skip_fimi)
end

function main(args)
    opts = try
        parse_args(args)
    catch err
        println(stderr, "Lỗi: ", sprint(showerror, err), "\n", USAGE)
        return 2
    end
    config = joinpath(META_DIR, "benchmark_config.csv")
    inventory = joinpath(META_DIR, "benchmark_inventory.csv")
    names = unique(r["dataset"] for r in read_csv_rows(config))
    if opts.datasets !== nothing
        unknown = setdiff(opts.datasets, names)
        if !isempty(unknown)
            println(stderr, "Lỗi: dataset không có trong data/meta/benchmark_config.csv: ", join(unknown, ", "),
                    "\nCác dataset hợp lệ: ", join(names, ", "))
            return 2
        end
    end
    suffix = opts.datasets === nothing ? "" : "_" * join(opts.datasets, "+")
    println("Julia ", VERSION, "  |  gốc repo ", ROOT)

    println("\n== Bước 1: dữ liệu và công cụ")
    verify_hf(inventory, BENCHMARK_DIR; names = opts.datasets) ||
        (println("Có dataset không khớp SHA-256 (chạy scripts/data_setup.jl để tạo lại)"); return 1)
    tools = setup_tools(TOOLS_DIR; with_fimi = !opts.skip_fimi)

    println("\n== Bước 2: SPMF FPClose so với số closed itemsets tham chiếu")
    spmf_results = spmf_check(config, BENCHMARK_DIR; java = tools.java, jar = tools.jar,
        datasets = opts.datasets, timeout_s = opts.timeout)
    mkpath(RESULTS_DIR)
    spmf_csv = joinpath(RESULTS_DIR, "spmf_check$suffix.csv")
    write_csv(spmf_csv, SPMF_CHECK_HEADER,
        [[coalesce(getfield(r, Symbol(h)), "") for h in SPMF_CHECK_HEADER] for r in spmf_results])
    n_spmf = count(r -> r.match, spmf_results)
    println("\n", n_spmf, "/", length(spmf_results), " cấu hình khớp số tham chiếu")
    ok = n_spmf == length(spmf_results)

    fimi_results = NamedTuple[]
    if tools.fimi !== nothing
        println("\n== Bước 3: SPMF so với FIMI FPclose, từng itemset và support")
        fimi_results = fimi_compare(config, BENCHMARK_DIR; java = tools.java, jar = tools.jar,
            fimi = tools.fimi, datasets = opts.datasets, timeout_s = opts.timeout)
        write_csv(joinpath(RESULTS_DIR, "fimi_compare$suffix.csv"), FIMI_COMPARE_HEADER,
            [[coalesce(getfield(r, Symbol(h)), "") for h in FIMI_COMPARE_HEADER] for r in fimi_results])
        n_fimi = count(r -> r.identical && r.n_spmf == r.reference_closed_itemsets, fimi_results)
        println("\n", n_fimi, "/", length(fimi_results),
                " cấu hình: SPMF = FIMI từng itemset và support, đúng số tham chiếu")
        ok &= n_fimi == length(fimi_results)

        println("\n", rpad("dataset", 13), lpad("cấu hình", 9), lpad("SPMF=tham chiếu", 17), lpad("SPMF=FIMI", 11))
        for d in unique(r.dataset for r in fimi_results)
            s = filter(r -> r.dataset == d, spmf_results)
            f = filter(r -> r.dataset == d, fimi_results)
            println(rpad(d, 13), lpad(length(f), 9),
                lpad(string(count(r -> r.match, s), "/", length(s)), 17),
                lpad(string(count(r -> r.identical, f), "/", length(f)), 11))
        end
    end
    println("\nChi tiết: ", spmf_csv, tools.fimi === nothing ? "" : " và " * joinpath(RESULTS_DIR, "fimi_compare$suffix.csv"))
    return ok ? 0 : 1
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end
