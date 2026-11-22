# utils.jl
# Đọc/ghi định dạng SPMF, đổi minsup, đọc tham số dòng lệnh.

"""
    read_spmf(path) -> Vector{Vector{Int}}

Đọc CSDL định dạng SPMF: mỗi dòng một giao dịch, item là số nguyên dương
cách nhau dấu cách. Bỏ dòng trống và dòng metadata của SPMF (bắt đầu bằng
`#`, `%` hoặc `@`). Mỗi giao dịch được bỏ item trùng và sắp tăng dần.
"""
function read_spmf(path::AbstractString)
    db = Vector{Int}[]
    for line in eachline(path)
        s = strip(line)
        (isempty(s) || s[1] in ('#', '%', '@')) && continue
        push!(db, sort!(unique!(parse.(Int, split(s)))))
    end
    return db
end

"""
Cách làm tròn ngưỡng tương đối thành số giao dịch. Đặt ở MỘT chỗ duy nhất: nếu đối chiếu
SPMF cho thấy SPMF làm tròn khác (ví dụ `round`), chỉ cần đổi hằng này.
Hiện dùng `ceil`: một itemset phổ biến khi support ≥ minsup × n, nên số giao dịch tối
thiểu là ceil(minsup × n) (Sec 1 tr. 1347: "support is greater than or equal to some
given percentage s"). Không cộng/trừ dung sai: 0.07 × 100 = 7.000000000000001 → 8.
"""
const MINSUP_ROUNDING = ceil

"""
    minsup_count(minsup, n; rounding = MINSUP_ROUNDING) -> Int

Đổi ngưỡng tương đối `minsup` (0 < minsup ≤ 1) sang số giao dịch tối thiểu
trên CSDL `n` giao dịch: `rounding(Int, minsup × n)`, tối thiểu là 1.
Ví dụ: 0.2 × 7 = 1.4 → 2; 0.4 × 5 = 2.0 → 2.
"""
function minsup_count(minsup::Real, n::Int; rounding = MINSUP_ROUNDING)
    0 < minsup <= 1 || throw(ArgumentError("minsup phải nằm trong (0, 1], nhận $minsup"))
    return max(1, rounding(Int, minsup * n))
end

"""
    sort_results!(results)

Sắp kết quả theo độ dài itemset rồi theo thứ tự từ điển, để output ổn định.
"""
sort_results!(results) = sort!(results; by = p -> (length(p.first), p.first))

"""
    write_spmf(io, results)
    write_spmf(path, results)

Ghi kết quả theo định dạng output của SPMF, mỗi dòng: `1 2 6 #SUP: 2`.
"""
function write_spmf(io::IO, results)
    for (items, sup) in results
        println(io, join(items, ' '), " #SUP: ", sup)
    end
end

write_spmf(path::AbstractString, results) = open(io -> write_spmf(io, results), path, "w")

"""
    parse_minsup_ratio(s) -> Float64

Đọc ngưỡng tương đối: "0.4" (tỉ lệ trong (0, 1]) hoặc "40%" (phần trăm trong (0, 100]),
giống cách SPMF nhận minsup. Số > 1 không có dấu % bị từ chối (tránh nhầm "2" là 2 giao dịch
hay 200%); "1" nghĩa là 100%. Muốn số giao dịch tuyệt đối thì dùng `--minsup-count`.
"""
function parse_minsup_ratio(s::AbstractString)
    pct = endswith(s, "%")
    v = tryparse(Float64, pct ? s[1:end-1] : s)
    v === nothing && throw(ArgumentError("--minsup không đọc được: \"$s\" (ví dụ 0.4 hoặc 40%)"))
    r = pct ? v / 100 : v
    (isfinite(r) && 0 < r <= 1) ||
        throw(ArgumentError("--minsup phải là tỉ lệ trong (0, 1] hoặc phần trăm trong (0, 100]%, nhận \"$s\"; " *
                            "dùng --minsup-count cho số giao dịch tuyệt đối"))
    return r
end

"""
    parse_minconf(s) -> Float64

Đọc ngưỡng confidence "0.6" hoặc "60%", trong [0, 1].
"""
function parse_minconf(s::AbstractString)
    pct = endswith(s, "%")
    v = tryparse(Float64, pct ? s[1:end-1] : s)
    v === nothing && throw(ArgumentError("--minconf không đọc được: \"$s\" (ví dụ 0.6 hoặc 60%)"))
    r = pct ? v / 100 : v
    (isfinite(r) && 0 <= r <= 1) ||
        throw(ArgumentError("--minconf phải nằm trong [0, 1] (hoặc [0, 100]%), nhận \"$s\""))
    return r
end

const CLI_USAGE = "cách dùng: demo.jl (--minsup <tỉ lệ> | --minsup-count <số giao dịch>) " *
    "[--output-closed <file>] [--output-all <file>] [--rules <file> --minconf <0..1> [--top <k>]] <input.txt>"

# Bộ phân tích chung cho `parse_cli_args` (extended = false: chỉ 4 tham số gốc) và
# `parse_cli_options` (extended = true: thêm các tham số của recovery và luật kết hợp).
function parse_cli_impl(args::Vector{String}, extended::Bool)
    usage = extended ? CLI_USAGE :
        "cách dùng: demo.jl (--minsup <tỉ lệ> | --minsup-count <số giao dịch>) [--output <file>] <input.txt>"
    valued = extended ?
        ("--minsup", "--minsup-count", "--output", "--output-closed", "--output-all", "--rules", "--minconf", "--top") :
        ("--minsup", "--minsup-count", "--output")
    got = Dict{String,String}()
    input = nothing
    i = 1
    while i <= length(args)
        a = args[i]
        if a in valued
            i < length(args) || throw(ArgumentError("thiếu giá trị sau $a
$usage"))
            haskey(got, a) && throw(ArgumentError("$a bị lặp"))
            got[a] = args[i+1]
            i += 2
        elseif startswith(a, "--")
            throw(ArgumentError("tham số không hợp lệ: $a
$usage"))
        else
            input === nothing || throw(ArgumentError("chỉ nhận một file input, nhận thêm: $a"))
            input = a
            i += 1
        end
    end
    input === nothing && throw(ArgumentError("thiếu file input
$usage"))

    minsup = haskey(got, "--minsup") ? parse_minsup_ratio(got["--minsup"]) : nothing
    count = nothing
    if haskey(got, "--minsup-count")
        v = got["--minsup-count"]
        count = tryparse(Int, v)
        (count !== nothing && count >= 1) ||
            throw(ArgumentError("--minsup-count phải là số nguyên ≥ 1, nhận \"$v\""))
    end
    (minsup === nothing && count === nothing) &&
        throw(ArgumentError("cần --minsup hoặc --minsup-count
$usage"))
    (minsup !== nothing && count !== nothing) &&
        throw(ArgumentError("chỉ được dùng MỘT trong --minsup và --minsup-count"))

    extended || return (minsup = minsup, minsup_count = count, input = input,
                        output = get(got, "--output", nothing))

    # --output là tên cũ của --output-closed; dùng cả hai thì báo lỗi vì không rõ chọn cái nào.
    (haskey(got, "--output") && haskey(got, "--output-closed")) &&
        throw(ArgumentError("--output là tên cũ của --output-closed, chỉ dùng một trong hai"))
    output_closed = get(got, "--output-closed", get(got, "--output", nothing))

    rules = get(got, "--rules", nothing)
    minconf = haskey(got, "--minconf") ? parse_minconf(got["--minconf"]) : nothing
    top = nothing
    if haskey(got, "--top")
        v = got["--top"]
        top = tryparse(Int, v)
        (top !== nothing && top >= 1) ||
            throw(ArgumentError("--top phải là số nguyên dương, nhận \"$v\""))
    end
    rules === nothing && minconf !== nothing &&
        throw(ArgumentError("--minconf chỉ có nghĩa khi có --rules <file>"))
    rules === nothing && top !== nothing &&
        throw(ArgumentError("--top chỉ có nghĩa khi có --rules <file>"))
    rules !== nothing && minconf === nothing &&
        throw(ArgumentError("--rules cần --minconf (ví dụ --minconf 0.6)
$usage"))

    return (minsup = minsup, minsup_count = count, input = input,
            output_closed = output_closed, output_all = get(got, "--output-all", nothing),
            rules = rules, minconf = minconf, top = top)
end

"""
    parse_cli_args(args) -> NamedTuple

Đọc tham số dòng lệnh dạng:
    demo.jl (--minsup <tỉ lệ> | --minsup-count <số giao dịch>) [--output out.txt] input.txt
- `--minsup 0.4` hoặc `--minsup 40%`: tỉ lệ (như SPMF).
- `--minsup-count 2`: số giao dịch tuyệt đối (số nguyên ≥ 1).
Báo `ArgumentError` nếu thiếu cả hai, có cả hai, giá trị ngoài miền, lặp tham số,
thiếu giá trị, tham số lạ, hoặc không có đúng một file input.
Trả về `(minsup, minsup_count, input, output)`; tham số không dùng là `nothing`.
Bản đầy đủ có recovery và luật kết hợp là `parse_cli_options`.
"""
parse_cli_args(args::Vector{String}) = parse_cli_impl(args, false)

"""
    parse_cli_options(args) -> NamedTuple

Như `parse_cli_args` nhưng nhận thêm:
- `--output-closed <file>` (và `--output` như tên cũ): ghi closed frequent itemset;
- `--output-all <file>`: ghi MỌI frequent itemset (chạy recovery);
- `--rules <file> --minconf <0..1> [--top <k>]`: ghi luật kết hợp (cũng chạy recovery),
  lọc theo confidence ≥ minconf, giữ k luật lift cao nhất nếu có `--top`.
Trả về `(minsup, minsup_count, input, output_closed, output_all, rules, minconf, top)`.
Lỗi giá trị ném `ArgumentError` với thông báo nói rõ tham số nào sai.
"""
parse_cli_options(args::Vector{String}) = parse_cli_impl(args, true)

"""
    resolve_minsup(opts, n) -> Int

Ngưỡng tuyệt đối (số giao dịch) từ kết quả `parse_cli_args` và số giao dịch `n` của CSDL.
"""
resolve_minsup(opts, n::Int) =
    opts.minsup_count !== nothing ? opts.minsup_count : minsup_count(opts.minsup, n)
