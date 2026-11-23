# =============================================================================
# scripts/bench_reader.jl — so sánh bộ đọc read_spmf_simple (bản gốc) với read_spmf (đọc theo byte).
#
# Chạy:  julia --project=. scripts/bench_reader.jl [--runs 3] [--machine NHÃN] [--data <thư mục>] [--out <file.csv>]
#
# Với mỗi file *.txt trong data/benchmark/: 1 lần warm-up mỗi hàm (biên dịch + nạp file vào cache hệ điều hành),
# sau đó đo xen kẽ hai hàm `runs` lần (GC.gc() trước mỗi lần), lấy TRUNG VỊ thời gian và bộ nhớ cấp phát (@timed),
# kiểm tra hai kết quả bằng nhau. Ghi results/optimization/reader_bench.csv và in bảng ngắn.
# =============================================================================

using FPClose
using Printf

const ROOT = normpath(joinpath(@__DIR__, ".."))

"Đọc tham số --key value; trả Dict."
function parse_opts(args)
    o = Dict("--runs" => "3", "--machine" => get(ENV, "FPCLOSE_MACHINE", gethostname()),
             "--data" => joinpath(ROOT, "data", "benchmark"),
             "--out" => joinpath(ROOT, "results", "optimization", "reader_bench.csv"))
    i = 1
    while i <= length(args)
        haskey(o, args[i]) && i < length(args) || error("Tham số không hiểu hoặc thiếu giá trị: $(args[i])")
        o[args[i]] = args[i + 1]
        i += 2
    end
    return o
end

"Trung vị của một vector số."
function median_of(v)
    x = sort(collect(v))
    n = length(x)
    return isodd(n) ? x[n ÷ 2 + 1] : (x[n ÷ 2] + x[n ÷ 2 + 1]) / 2
end

"Một lần đo: (giây, MB cấp phát, kết quả)."
function measure(f, path)
    GC.gc()
    st = @timed f(path)
    return st.time, st.bytes / 2^20, st.value
end

function main(args)
    o = parse_opts(args)
    runs = parse(Int, o["--runs"])
    files = sort(filter(f -> endswith(f, ".txt"), readdir(o["--data"]; join = true)))
    isempty(files) && error("Không có file .txt trong $(o["--data"])")
    rows = Vector{Vector{Any}}()
    println(@sprintf("%-12s %9s %8s %10s %10s %8s %11s %11s %6s", "dataset", "n_tx", "MB", "simple_s", "fast_s",
                     "speedup", "simple_MB", "fast_MB", "bằng"))
    for f in files
        ds = splitext(basename(f))[1]
        read_spmf_simple(f); read_spmf(f)                         # warm-up
        ts, as, tf, af = Float64[], Float64[], Float64[], Float64[]
        rs = rf = nothing
        for _ in 1:runs                                           # xen kẽ để hai hàm chịu cùng điều kiện máy
            t, a, rs = measure(read_spmf_simple, f); push!(ts, t); push!(as, a)
            t, a, rf = measure(read_spmf, f);        push!(tf, t); push!(af, a)
        end
        equal = rs == rf
        equal || @warn "$ds: read_spmf và read_spmf_simple cho kết quả KHÁC nhau!"
        mts, mtf = median_of(ts), median_of(tf)
        row = Any[ds, length(rs), round(filesize(f) / 2^20; digits = 2), round(mts; sigdigits = 4), round(mtf; sigdigits = 4),
                  round(mts / mtf; digits = 2), round(median_of(as); digits = 1), round(median_of(af); digits = 1),
                  equal, runs, o["--machine"], string(VERSION)]
        push!(rows, row)
        println(@sprintf("%-12s %9d %8.2f %10.4f %10.4f %7.2fx %11.1f %11.1f %6s", ds, row[2], row[3], mts, mtf,
                         row[6], row[7], row[8], equal ? "có" : "KHÔNG"))
    end
    mkpath(dirname(o["--out"]))
    open(o["--out"], "w") do io
        println(io, "dataset,n_transactions,file_mb,simple_s,fast_s,speedup,simple_alloc_mb,fast_alloc_mb,equal,runs,machine,julia")
        for r in rows
            println(io, join(string.(r), ","))
        end
    end
    println("Đã ghi ", o["--out"])
    all(r -> r[9], rows) || exit(1)
end

main(ARGS)
