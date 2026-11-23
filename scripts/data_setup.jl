# Chuẩn bị toàn bộ dữ liệu benchmark của FPClose (Julia, chỉ dùng thư viện chuẩn).
#
#   1. Lấy 9 dataset benchmark, chuẩn hóa sang định dạng SPMF vào data/benchmark/
#   2. Thống kê từng dataset và đối chiếu với data/meta/dataset_statistics.csv
#   3. Sinh 5 Retail subsets (data/scalability/) cho thí nghiệm scalability
#   4. Sinh 6 synthetic datasets (data/synthetic/) cho thí nghiệm độ dài giao dịch
#
# Mọi cấu hình (nguồn tải, URL dự phòng, SHA-256, số giao dịch, offset item, hash của file dẫn xuất)
# được ĐỌC từ data/meta/*.csv, không chép cứng trong code. Mỗi file sinh ra được kiểm SHA-256.
#
# Cách dùng (từ thư mục gốc repo):
#   julia --project=. scripts/data_setup.jl                    # --from-hf (mặc định)
#   julia --project=. scripts/data_setup.jl --from-source      # tải từ SPMF/FIMI rồi chuẩn hóa
#   julia --project=. scripts/data_setup.jl --only mushrooms,chess
#
#   --from-hf       tải 9 dataset đã chuẩn hóa từ Hugging Face (hytrang/fpclose-fim-benchmarks)
#                   và kiểm SHA-256 (mặc định)
#   --from-source   tải file gốc từ SPMF/FIMI (thử URL chính, lỗi thì thử fallback_url) rồi chuẩn hóa
#   --only a,b      chỉ xử lý các dataset này (bước Retail subsets và synthetic vẫn chạy nếu đủ điều kiện)
#
# Mã thoát: 0 nếu mọi bước khớp hash, 1 nếu có bước lệch hoặc lỗi, 2 nếu sai tham số.

using SHA
using Downloads
using Zlib_jll: libz

# Gốc repo suy ra từ vị trí script (scripts/ nằm ngay dưới gốc)
const ROOT = normpath(joinpath(@__DIR__, ".."))
const DATA = joinpath(ROOT, "data")
const META_DIR = joinpath(DATA, "meta")
const RAW_DIR = joinpath(DATA, "raw")
const BENCHMARK_DIR = joinpath(DATA, "benchmark")
const SCALABILITY_DIR = joinpath(DATA, "scalability")
const SYNTHETIC_DIR = joinpath(DATA, "synthetic")

const HF_REPO = "hytrang/fpclose-fim-benchmarks"
hf_url(name) = "https://huggingface.co/datasets/$HF_REPO/resolve/main/$name"

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

"File có phải gzip không (2 byte đầu là 1f 8b)."
is_gzip(path::AbstractString) = open(io -> read(io, 2) == UInt8[0x1f, 0x8b], path)

"""
    gunzip(path) -> IOBuffer

Giải nén file gzip bằng zlib đi kèm Julia (`Zlib_jll`), không cần lệnh `gzip` của hệ điều hành
(Windows thường không có).
"""
function gunzip(path::AbstractString)
    gz = ccall((:gzopen, libz), Ptr{Cvoid}, (Cstring, Cstring), path, "rb")
    gz == C_NULL && error("Không mở được file gzip: $path")
    out = IOBuffer()
    buf = Vector{UInt8}(undef, 1 << 20)
    try
        while true
            n = ccall((:gzread, libz), Cint, (Ptr{Cvoid}, Ptr{UInt8}, Cuint), gz, buf, length(buf))
            n < 0 && error("Lỗi giải nén gzip: $path")
            n == 0 && break
            write(out, view(buf, 1:n))
        end
    finally
        ccall((:gzclose, libz), Cint, (Ptr{Cvoid},), gz)
    end
    return seekstart(out)
end

"Mở file thô để đọc text; file gzip (nhận theo magic bytes) được giải nén trước."
open_raw(path::AbstractString) = is_gzip(path) ? gunzip(path) : open(path)

"""
    normalize_transactions(src, dst; offset = 0) -> (n_transactions, n_dedup_rows, n_metadata)

Chuẩn hóa `src` vào `dst`. Trả về số giao dịch ghi ra, số dòng có item trùng đã khử, số dòng metadata đã bỏ.
"""
function normalize_transactions(src::AbstractString, dst::AbstractString; offset::Integer = 0)
    mkpath(dirname(abspath(dst)))
    count = 0
    dedup_rows = 0
    metadata = 0
    input = open_raw(src)
    try
        open(dst, "w") do out
            for (line_number, raw) in enumerate(eachline(input))
                line = line_number == 1 ? lstrip(raw, '﻿') : raw
                line = strip(line)
                if startswith(line, '#') || startswith(line, '@') || startswith(line, '%')
                    metadata += 1
                    continue
                end
                isempty(line) && error("Giao dịch trống tại $src:$line_number")
                values = parse.(Int, split(line))
                minimum(values) + offset > 0 || error("Item ID không hợp lệ tại $src:$line_number")
                items = sort!(unique!(values .+ offset))
                length(items) < length(values) && (dedup_rows += 1)
                println(out, join(items, ' '))
                count += 1
            end
        end
    finally
        close(input)
    end
    return (n_transactions = count, n_dedup_rows = dedup_rows, n_metadata = metadata)
end

const STATS_HEADER = ["dataset", "n_transactions", "n_unique_items", "avg_transaction_length",
    "max_transaction_length", "density_pct", "sha256"]

"Thống kê một file; đọc từng dòng nên dùng được cả với kosarak (~1 triệu giao dịch)."
function dataset_stats(path::AbstractString)
    n = 0
    total = 0
    maxlen = 0
    items = Set{Int}()
    for line in eachline(path)
        s = strip(line)
        isempty(s) && error("Dòng trống trong $path")
        k = 0
        for tok in eachsplit(s)
            push!(items, parse(Int, tok))
            k += 1
        end
        n += 1
        total += k
        maxlen = max(maxlen, k)
    end
    avg = total / n
    return (dataset = splitext(basename(path))[1], n_transactions = n,
        n_unique_items = length(items), avg_transaction_length = round(avg; digits = 4),
        max_transaction_length = maxlen,
        density_pct = round(avg / length(items) * 100; digits = 6), sha256 = sha256_file(path))
end

stats_row(s) = [getfield(s, Symbol(h)) for h in STATS_HEADER]

const _MT_N = 624
const _MT_M = 397
const _MATRIX_A = 0x9908b0df
const _UPPER_MASK = 0x80000000
const _LOWER_MASK = 0x7fffffff

"""
    PyRandom(seed)

Tương đương `random.Random(seed)` của Python với `seed` là số nguyên.
"""
mutable struct PyRandom
    mt::Vector{UInt32}
    mti::Int
end

function PyRandom(seed::Integer)
    # CPython: seed nguyên -> abs(seed) -> mảng các từ 32 bit, little-endian.
    s = abs(BigInt(seed))
    key = UInt32[]
    if s == 0
        push!(key, UInt32(0))
    else
        while s > 0
            push!(key, UInt32(s & 0xffffffff))
            s >>= 32
        end
    end

    # init_genrand(19650218)
    mt = zeros(UInt32, _MT_N)
    mt[1] = UInt32(19650218)
    for i in 1:_MT_N-1
        prev = mt[i]
        mt[i+1] = UInt32(1812433253) * (prev ⊻ (prev >> 30)) + UInt32(i)
    end

    # init_by_array(key). i, j là chỉ số 0-based như mã C; mt[i+1] là mt[i] của C.
    i, j = 1, 0
    klen = length(key)
    for _ in 1:max(_MT_N, klen)
        prev = mt[i]
        mt[i+1] = (mt[i+1] ⊻ ((prev ⊻ (prev >> 30)) * UInt32(1664525))) + key[j+1] + UInt32(j)
        i += 1
        j += 1
        if i >= _MT_N
            mt[1] = mt[_MT_N]
            i = 1
        end
        j >= klen && (j = 0)
    end
    for _ in 1:_MT_N-1
        prev = mt[i]
        mt[i+1] = (mt[i+1] ⊻ ((prev ⊻ (prev >> 30)) * UInt32(1566083941))) - UInt32(i)
        i += 1
        if i >= _MT_N
            mt[1] = mt[_MT_N]
            i = 1
        end
    end
    mt[1] = 0x80000000
    return PyRandom(mt, _MT_N)
end

@inline _mag01(y::UInt32) = (y & 0x00000001) == 0 ? UInt32(0) : _MATRIX_A

"genrand_uint32 của CPython: một số nguyên 32 bit."
function genrand_uint32!(r::PyRandom)
    mt = r.mt
    if r.mti >= _MT_N
        for kk in 0:_MT_N-_MT_M-1
            y = (mt[kk+1] & _UPPER_MASK) | (mt[kk+2] & _LOWER_MASK)
            mt[kk+1] = mt[kk+_MT_M+1] ⊻ (y >> 1) ⊻ _mag01(y)
        end
        for kk in _MT_N-_MT_M:_MT_N-2
            y = (mt[kk+1] & _UPPER_MASK) | (mt[kk+2] & _LOWER_MASK)
            mt[kk+1] = mt[kk+(_MT_M-_MT_N)+1] ⊻ (y >> 1) ⊻ _mag01(y)
        end
        y = (mt[_MT_N] & _UPPER_MASK) | (mt[1] & _LOWER_MASK)
        mt[_MT_N] = mt[_MT_M] ⊻ (y >> 1) ⊻ _mag01(y)
        r.mti = 0
    end
    y = mt[r.mti+1]
    r.mti += 1
    y ⊻= y >> 11
    y ⊻= (y << 7) & 0x9d2c5680
    y ⊻= (y << 15) & 0xefc60000
    y ⊻= y >> 18
    return y
end

"`random.random()`: số thực trong [0, 1) với 53 bit ngẫu nhiên."
function pyrandom!(r::PyRandom)
    a = genrand_uint32!(r) >> 5
    b = genrand_uint32!(r) >> 6
    return (Float64(a) * 67108864.0 + Float64(b)) * (1.0 / 9007199254740992.0)
end

"`getrandbits(k)` với 1 ≤ k ≤ 32 (đủ cho mọi n dùng ở đây)."
function getrandbits!(r::PyRandom, k::Integer)
    1 <= k <= 32 || throw(ArgumentError("getrandbits chỉ hỗ trợ 1 ≤ k ≤ 32, nhận $k"))
    return Int(genrand_uint32!(r) >> (32 - k))
end

"`_randbelow(n)`: số nguyên đều trong [0, n), phương pháp loại bỏ như CPython."
function randbelow!(r::PyRandom, n::Integer)
    n > 0 || throw(ArgumentError("n phải dương"))
    k = ndigits(n; base = 2)          # n.bit_length()
    x = getrandbits!(r, k)
    while x >= n
        x = getrandbits!(r, k)
    end
    return x
end

"`random.shuffle(x)` (tại chỗ), cùng thứ tự gọi số ngẫu nhiên như Python."
function pyshuffle!(r::PyRandom, x::AbstractVector)
    for i in length(x)-1:-1:1         # i là chỉ số 0-based
        j = randbelow!(r, i + 1)
        x[i+1], x[j+1] = x[j+1], x[i+1]
    end
    return x
end

"`random.randint(a, b)`: số nguyên trong [a, b]."
pyrandint!(r::PyRandom, a::Integer, b::Integer) = a + randbelow!(r, b - a + 1)

"""
    pysample_range!(r, start, stop, k)

`random.sample(range(start, stop), k)`.
"""
function pysample_range!(r::PyRandom, start::Integer, stop::Integer, k::Integer)
    n = stop - start
    0 <= k <= n || throw(ArgumentError("k nằm ngoài [0, n]"))
    setsize = 21
    if k > 5
        setsize += 4^ceil(Int, log(3k) / log(4))
    end
    result = Vector{Int}(undef, k)
    if n <= setsize
        pool = collect(start:stop-1)
        for i in 0:k-1
            j = randbelow!(r, n - i)
            result[i+1] = pool[j+1]
            pool[j+1] = pool[n-i]
        end
    else
        selected = Set{Int}()
        for i in 0:k-1
            j = randbelow!(r, n)
            while j in selected
                j = randbelow!(r, n)
            end
            push!(selected, j)
            result[i+1] = start + j
        end
    end
    return result
end

"Cộng dồn trái sang phải như `itertools.accumulate`."
function cumulative(weights)
    cum = Vector{Float64}(undef, length(weights))
    acc = 0.0
    for (i, w) in enumerate(weights)
        acc += Float64(w)
        cum[i] = acc
    end
    return cum
end

"""
    pychoice_index!(r, cum_weights) -> Int

Một lần chọn của `random.choices(population, weights=..., k=1)`; trả về chỉ số 0-based
trong population. `cum_weights` lấy từ `cumulative(weights)`.
"""
function pychoice_index!(r::PyRandom, cum_weights::Vector{Float64})
    total = cum_weights[end] + 0.0
    x = pyrandom!(r) * total
    lo, hi = 0, length(cum_weights) - 1   # bisect_right(cum, x, 0, n-1)
    while lo < hi
        mid = (lo + hi) ÷ 2
        if x < cum_weights[mid+1]
            hi = mid
        else
            lo = mid + 1
        end
    end
    return lo
end

"""
    cpow(x, y)

`x ** y` của Python gọi hàm `pow` của thư viện C. Dùng cùng hàm đó (nếu gọi được) để
trọng số khớp từng bit với dữ liệu sinh trên Colab; nếu không thì dùng `^` của Julia.
"""
const cpow = try
    ccall(:pow, Float64, (Float64, Float64), 2.0, 0.5)
    (x::Float64, y::Float64) -> ccall(:pow, Float64, (Float64, Float64), x, y)
catch
    (x::Float64, y::Float64) -> x^y
end

const RETAIL_PERCENTAGES = (10, 25, 50, 75, 100)

"""
    make_retail_subsets(src, outdir; n_expected, seed = 2026) -> Vector{NamedTuple}

Ghi `retail_p010.txt` … `retail_p100.txt` vào `outdir`, trả về tên file, số giao dịch, SHA-256.
"""
function make_retail_subsets(src::AbstractString, outdir::AbstractString; n_expected::Integer,
        seed::Integer = 2026)
    transactions = String[]
    for line in eachline(src)
        s = strip(line)
        isempty(s) || push!(transactions, String(s))
    end
    length(transactions) == n_expected ||
        error("retail.txt có $(length(transactions)) giao dịch, mong đợi $n_expected")

    order = collect(0:length(transactions)-1)
    pyshuffle!(PyRandom(seed), order)

    mkpath(outdir)
    reports = NamedTuple[]
    previous = Set{Int}()
    for p in RETAIL_PERCENTAGES
        n = length(transactions) * p ÷ 100
        chosen = @view order[1:n]
        current = Set(chosen)
        issubset(previous, current) || error("Subset $p% không chứa subset trước")
        previous = current
        file = joinpath(outdir, "retail_p$(lpad(p, 3, '0')).txt")
        open(file, "w") do io
            for idx in chosen
                write(io, transactions[idx+1], '\n')
            end
        end
        push!(reports, (dataset = basename(file), n_transactions = n, sha256 = sha256_file(file)))
    end
    return reports
end

const SYN_N_TRANSACTIONS = 10_000
const SYN_N_ITEMS = 500
const SYN_MAX_LENGTH = 32
const SYN_TARGETS = (5, 10, 15, 20, 25, 30)

"Sinh 10.000 giao dịch nền (mỗi giao dịch 32 item, giữ thứ tự sinh)."
function synthetic_master(seed::Integer)
    pool_rng = PyRandom(seed)
    item_ids = collect(1:SYN_N_ITEMS)
    pyshuffle!(pool_rng, item_ids)
    patterns = [item_ids[i:i+3] for i in 1:4:SYN_N_ITEMS]
    for _ in 1:75
        push!(patterns, pysample_range!(pool_rng, 1, SYN_N_ITEMS + 1, 4))
    end
    length(patterns) == 200 || error("Số pattern phải là 200")

    weights = [1.0 / cpow(Float64(i + 1), 0.8) for i in 0:length(patterns)-1]
    cum_patterns = cumulative(weights)
    cum_npatterns = cumulative([25, 50, 25])   # cho n_patterns ∈ (1, 2, 3)

    rng = PyRandom(seed + 1)
    master = Vector{Vector{Int}}(undef, SYN_N_TRANSACTIONS)
    for t in 0:SYN_N_TRANSACTIONS-1
        transaction = Int[]
        seen = Set{Int}()
        n_patterns = (1, 2, 3)[pychoice_index!(rng, cum_npatterns)+1]
        first_pattern = t < 125 ? t : pychoice_index!(rng, cum_patterns)
        selected = [first_pattern]
        for _ in 1:n_patterns-1
            push!(selected, pychoice_index!(rng, cum_patterns))
        end
        for pid in selected, item in patterns[pid+1]
            if !(item in seen)
                push!(seen, item)
                push!(transaction, item)
            end
        end
        while length(transaction) < SYN_MAX_LENGTH
            item = pyrandint!(rng, 1, SYN_N_ITEMS)
            if !(item in seen)
                push!(seen, item)
                push!(transaction, item)
            end
        end
        master[t+1] = transaction
    end
    return master
end

"""
    gen_synthetic(outdir; seed = 2026) -> Vector{NamedTuple}

Ghi `len05.txt` … `len30.txt` vào `outdir` và trả về thống kê của từng file
(không ghi `data/meta/synthetic_statistics.csv`: đó là cấu hình để đối chiếu, không phải đầu ra).
"""
function gen_synthetic(outdir::AbstractString; seed::Integer = 2026)
    mkpath(outdir)
    master = synthetic_master(seed)
    stats = NamedTuple[]
    previous = nothing
    for target in SYN_TARGETS
        offsets = target == 5 ? (-1, -1, 0, 1, 1) : (-2, -1, 0, 1, 2)
        per = SYN_N_TRANSACTIONS ÷ length(offsets)
        lengths = [target + o for o in offsets for _ in 1:per]
        pyshuffle!(PyRandom(seed + target), lengths)

        file = joinpath(outdir, "len$(lpad(target, 2, '0')).txt")
        current = Vector{Set{Int}}(undef, SYN_N_TRANSACTIONS)
        unique_items = Set{Int}()
        open(file, "w") do io
            for (i, len) in enumerate(lengths)
                items = sort(master[i][1:len])
                current[i] = Set(items)
                union!(unique_items, items)
                println(io, join(items, ' '))
            end
        end
        if previous !== nothing
            all(issubset(a, b) for (a, b) in zip(previous, current)) ||
                error("len$target không chứa mức trước (không lồng nhau)")
        end
        previous = current
        avg = sum(lengths) / SYN_N_TRANSACTIONS
        avg == target || error("Độ dài trung bình $avg ≠ $target")
        length(unique_items) == SYN_N_ITEMS || error("Không phủ đủ $SYN_N_ITEMS item")
        push!(stats, (dataset = basename(file), n_transactions = SYN_N_TRANSACTIONS,
            n_items = length(unique_items), avg_length = avg,
            min_length = minimum(lengths), max_length = maximum(lengths),
            density = avg / SYN_N_ITEMS, seed = seed, sha256 = sha256_file(file)))
    end
    return stats
end

# ---------------------------------------------------------------------------
# Cấu hình đọc từ data/meta/*.csv
# ---------------------------------------------------------------------------

"Đọc ba bảng cấu hình trong data/meta/: 9 dataset, hash file dẫn xuất, thống kê synthetic."
function load_meta()
    table(name) = read_csv_rows(joinpath(META_DIR, name))
    return (datasets = table("dataset_statistics.csv"),
        derived = Dict(r["dataset"] => r for r in table("derived_hashes.csv")),
        synthetic = Dict(r["dataset"] => r for r in table("synthetic_statistics.csv")))
end

"Item-ID offset của một dataset, đọc từ cột `id_offset` của dataset_statistics.csv."
function id_offset(row)
    v = tryparse(Int, row["id_offset"])
    v === nothing && error("id_offset của $(row["dataset"]) không phải số nguyên: \"$(row["id_offset"])\" " *
                           "(sửa data/meta/dataset_statistics.csv)")
    return v
end

# ---------------------------------------------------------------------------
# Bước 1: lấy dataset
# ---------------------------------------------------------------------------

"""
    fetch_from_hf(row) -> Bool

Tải `<dataset>.txt` đã chuẩn hóa từ Hugging Face vào data/benchmark/ (tải vào file `.part` rồi mới
đổi tên nếu SHA-256 và số giao dịch khớp, nên file đúng đang có không bị ghi đè bằng bản sai).
"""
function fetch_from_hf(row)
    name = row["dataset"]
    dst = joinpath(BENCHMARK_DIR, "$name.txt")
    expected = lowercase(row["clean_sha256"])
    n_expected = parse(Int, row["n_transactions"])
    mkpath(BENCHMARK_DIR)
    if isfile(dst) && sha256_file(dst) == expected
        println("[PASS] ", rpad(name, 12), "đã có file đúng SHA-256, không tải lại")
        return true
    end
    part = dst * ".part"
    url = hf_url("$name.txt")
    println("Tải ", url)
    try
        Downloads.download(url, part)
    catch err
        rm(part; force = true)
        println("[FAIL] ", rpad(name, 12), "không tải được: ", first(sprint(showerror, err), 200))
        return false
    end
    got = sha256_file(part)
    n = countlines(part)
    if got == expected && n == n_expected
        mv(part, dst; force = true)
        println("[PASS] ", rpad(name, 12), n, " giao dịch, SHA-256 khớp")
        return true
    end
    rm(part; force = true)
    println("[FAIL] ", rpad(name, 12), "bản trên Hugging Face không khớp: ", n, " giao dịch, SHA-256 ",
            got[1:8], "… (cần ", n_expected, " giao dịch, ", expected[1:8], "…). ",
            "Upload lại bản đúng lên Hugging Face hoặc chạy với --from-source.")
    return false
end

"""
    download_raw(row) -> Union{Nothing,NamedTuple}

Lấy file gốc vào data/raw/: dùng file đã có nếu đúng `raw_sha256`, nếu không thì tải từ `source_url`,
lỗi thì thử `fallback_url` (nếu có). Trả về `(path, source, raw_ok)` hoặc `nothing` nếu mọi nguồn đều lỗi.
`raw_ok` là so SHA-256 của file gốc; file tải từ URL dự phòng có thể khác định dạng (không nén) nên
`raw_ok = false` là bình thường, hash của bản chuẩn hóa mới là chuẩn.
"""
function download_raw(row)
    raw = joinpath(RAW_DIR, row["raw_filename"])
    raw_expected = lowercase(row["raw_sha256"])
    mkpath(RAW_DIR)
    if isfile(raw) && sha256_file(raw) == raw_expected
        return (path = raw, source = "file raw đã có", raw_ok = true)
    end
    println("Tải ", row["source_url"])
    try
        Downloads.download(row["source_url"], raw)
        return (path = raw, source = "URL chính", raw_ok = sha256_file(raw) == raw_expected)
    catch err
        rm(raw; force = true)
        println("  URL chính lỗi: ", first(sprint(showerror, err), 160))
    end
    fallback = row["fallback_url"]
    isempty(fallback) && return nothing
    fallback_raw = joinpath(RAW_DIR, "fimi_" * basename(fallback))
    println("Thử URL dự phòng ", fallback)
    try
        Downloads.download(fallback, fallback_raw)
        return (path = fallback_raw, source = "URL dự phòng", raw_ok = sha256_file(fallback_raw) == raw_expected)
    catch err
        rm(fallback_raw; force = true)
        println("  URL dự phòng lỗi: ", first(sprint(showerror, err), 160))
    end
    return nothing
end

"""
    fetch_from_source(row) -> Bool

Tải file gốc (`download_raw`), chuẩn hóa vào data/benchmark/ với offset trong `id_offset`, rồi so
SHA-256 và số giao dịch của bản chuẩn hóa với `clean_sha256` và `n_transactions`.
"""
function fetch_from_source(row)
    name = row["dataset"]
    got = download_raw(row)
    if got === nothing
        println("[FAIL] ", rpad(name, 12), "không tải được từ URL chính lẫn URL dự phòng")
        return false
    end
    dst = joinpath(BENCHMARK_DIR, "$name.txt")
    offset = id_offset(row)
    r = normalize_transactions(got.path, dst; offset = offset)
    clean = sha256_file(dst)
    ok = clean == lowercase(row["clean_sha256"]) && r.n_transactions == parse(Int, row["n_transactions"])
    raw_note = got.raw_ok ? "khớp" : (got.source == "URL dự phòng" ? "khác (bình thường với URL dự phòng)" : "KHÁC")
    println(ok ? "[PASS] " : "[FAIL] ", rpad(name, 12), "nguồn=", got.source, "  raw=", raw_note,
            "  gzip=", is_gzip(got.path), "  offset=", offset, "  n=", r.n_transactions,
            "  dedup_rows=", r.n_dedup_rows)
    ok || println("       SHA-256 bản chuẩn hóa ", clean, " (cần ", row["clean_sha256"], ")")
    return ok
end

# ---------------------------------------------------------------------------
# Bước 2: thống kê
# ---------------------------------------------------------------------------

"So thống kê của file trong data/benchmark/ với các cột trong dataset_statistics.csv."
function check_stats(row)
    s = dataset_stats(joinpath(BENCHMARK_DIR, row["dataset"] * ".txt"))
    ok = s.n_transactions == parse(Int, row["n_transactions"]) &&
         s.n_unique_items == parse(Int, row["n_unique_items"]) &&
         isapprox(s.avg_transaction_length, parse(Float64, row["avg_transaction_length"]); atol = 1e-6) &&
         s.max_transaction_length == parse(Int, row["max_transaction_length"]) &&
         isapprox(s.density_pct, parse(Float64, row["density_pct"]); atol = 1e-5) &&
         s.sha256 == lowercase(row["clean_sha256"])
    println(ok ? "[OK]   " : "[SAI]  ", "thống kê ", rpad(s.dataset, 12), "n=", s.n_transactions,
            "  items=", s.n_unique_items, "  avg=", s.avg_transaction_length, "  max=", s.max_transaction_length)
    return ok
end

# ---------------------------------------------------------------------------
# Bước 3 và 4: file dẫn xuất
# ---------------------------------------------------------------------------

"Retail subsets: sinh từ data/benchmark/retail.txt và so hash với derived_hashes.csv."
function derived_retail(meta)
    retail = joinpath(BENCHMARK_DIR, "retail.txt")
    if !isfile(retail)
        println("[BỎ QUA] Retail subsets: chưa có data/benchmark/retail.txt (chạy lại với retail trong --only)")
        return true
    end
    row = only(r for r in meta.datasets if r["dataset"] == "retail")
    subsets = try
        make_retail_subsets(retail, SCALABILITY_DIR; n_expected = parse(Int, row["n_transactions"]))
    catch err
        println("[FAIL] Retail subsets: ", first(sprint(showerror, err), 200))
        return false
    end
    ok = true
    for r in subsets
        exp = meta.derived[r.dataset]
        good = r.sha256 == lowercase(exp["sha256"]) && r.n_transactions == parse(Int, exp["n_transactions"])
        ok &= good
        println(good ? "[OK]   " : "[SAI]  ", rpad(r.dataset, 18), r.n_transactions)
    end
    return ok
end

"Synthetic datasets: sinh len05..len30 và so với derived_hashes.csv và synthetic_statistics.csv."
function derived_synthetic(meta)
    ok = true
    for s in gen_synthetic(SYNTHETIC_DIR)
        exp = meta.derived[s.dataset]
        st = meta.synthetic[s.dataset]
        good = s.sha256 == lowercase(exp["sha256"]) && s.n_transactions == parse(Int, exp["n_transactions"]) &&
               s.sha256 == lowercase(st["sha256"]) && s.n_items == parse(Int, st["n_items"]) &&
               s.min_length == parse(Int, st["min_length"]) && s.max_length == parse(Int, st["max_length"]) &&
               isapprox(s.avg_length, parse(Float64, st["avg_length"]))
        ok &= good
        println(good ? "[OK]   " : "[SAI]  ", rpad(s.dataset, 12), "avg=", s.avg_length,
                "  min=", s.min_length, "  max=", s.max_length)
    end
    return ok
end

# ---------------------------------------------------------------------------
# Dòng lệnh
# ---------------------------------------------------------------------------

const USAGE = "cách dùng: julia --project=. scripts/data_setup.jl [--from-hf | --from-source] [--only ds1,ds2]"

"Đọc tham số dòng lệnh; trả về `(source, only)` với `source` là `:hf` hoặc `:source`."
function parse_args(args)
    source = nothing
    only = nothing
    i = 1
    while i <= length(args)
        a = args[i]
        if a in ("--from-hf", "--from-source")
            new = a == "--from-hf" ? :hf : :source
            (source === nothing || source == new) || error("chỉ dùng một trong --from-hf và --from-source")
            source = new
        elseif a == "--only"
            i < length(args) || error("thiếu giá trị sau --only")
            only = String.(strip.(split(args[i+1], ',')))
            i += 1
        else
            error("tham số không hợp lệ: $a")
        end
        i += 1
    end
    return (source = something(source, :hf), only = only)
end

function main(args)
    opts = try
        parse_args(args)
    catch err
        println(stderr, "Lỗi: ", sprint(showerror, err), "\n", USAGE)
        return 2
    end
    meta = load_meta()
    names = [r["dataset"] for r in meta.datasets]
    if opts.only !== nothing
        unknown = setdiff(opts.only, names)
        if !isempty(unknown)
            println(stderr, "Lỗi: dataset không có trong data/meta/dataset_statistics.csv: ", join(unknown, ", "),
                    "\nCác dataset hợp lệ: ", join(names, ", "))
            return 2
        end
    end
    println("Julia ", VERSION, "  |  dữ liệu ghi vào ", DATA, "  |  nguồn: ",
            opts.source == :hf ? "Hugging Face (--from-hf)" : "SPMF/FIMI (--from-source)")

    ok = true
    selected = [r for r in meta.datasets if opts.only === nothing || r["dataset"] in opts.only]
    println("\n== Bước 1: lấy ", length(selected), " dataset")
    fetched = String[]
    for row in selected
        good = opts.source == :hf ? fetch_from_hf(row) : fetch_from_source(row)
        ok &= good
        good && push!(fetched, row["dataset"])
    end

    println("\n== Bước 2: thống kê")
    for row in selected
        row["dataset"] in fetched && (ok &= check_stats(row))
    end

    println("\n== Bước 3: Retail subsets (scalability)")
    ok &= derived_retail(meta)

    println("\n== Bước 4: synthetic datasets (độ dài giao dịch)")
    ok &= derived_synthetic(meta)

    println()
    println(ok ? "Hoàn tất: mọi bước khớp hash. Dữ liệu nằm trong " * DATA :
                 "CÓ BƯỚC KHÔNG KHỚP, xem các dòng [FAIL]/[SAI] ở trên.")
    return ok ? 0 : 1
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end
