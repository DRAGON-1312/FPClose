# Tiện ích: đọc/ghi định dạng SPMF, đổi ngưỡng minsup, đọc tham số dòng lệnh.
#   read_spmf, write_spmf            : đọc cơ sở dữ liệu, ghi kết quả theo định dạng SPMF
#   read_spmf_simple                 : bản đọc gốc (chuẩn so sánh cho read_spmf)
#   minsup_count, MINSUP_ROUNDING    : đổi ngưỡng tương đối sang số giao dịch
#   sort_results!                    : sắp kết quả cho ổn định
#   parse_minsup_ratio, parse_minconf, parse_cli_args, parse_cli_options, resolve_minsup : tham số dòng lệnh

"""
    read_spmf_simple(path) -> Vector{Vector{Int}}

Bản đọc gốc (eachline + strip + split + tryparse), giữ nguyên làm chuẩn so sánh cho [`read_spmf`](@ref).

Đọc cơ sở dữ liệu định dạng SPMF: mỗi dòng là một giao dịch gồm các số nguyên không âm cách nhau
dấu cách (item 0 hợp lệ). Bỏ dòng trống và dòng metadata (bắt đầu bằng `#`, `%` hoặc `@`). Mỗi giao dịch
được bỏ item trùng và sắp tăng dần.

- `path` : đường dẫn file input

Trả về danh sách giao dịch. Báo `ArgumentError` (kèm số dòng) nếu có item âm hoặc không phải số nguyên.
"""
function read_spmf_simple(path::AbstractString)
    db = Vector{Int}[]
    for (ln, line) in enumerate(eachline(path))
        s = strip(line)
        (isempty(s) || s[1] in ('#', '%', '@')) && continue
        items = Int[]
        for tok in split(s)
            v = tryparse(Int, tok)
            v === nothing && throw(ArgumentError("$path, dòng $ln: \"$tok\" không phải số nguyên"))
            v >= 0 || throw(ArgumentError("$path, dòng $ln: item âm ($v) không hợp lệ, item phải là số nguyên ≥ 0"))
            push!(items, v)
        end
        push!(db, sort!(unique!(items)))
    end
    return db
end

"""
    read_spmf(path) -> Vector{Vector{Int}}

Đọc cơ sở dữ liệu định dạng SPMF, cho kết quả và lỗi y hệt [`read_spmf_simple`](@ref) nhưng nhanh hơn:
đọc cả file một lần (`read(path)`), tách dòng theo byte `\\n`, tự parse số nguyên không tạo chuỗi.

Quy tắc (giống bản gốc): mỗi dòng là một giao dịch gồm các số nguyên không âm cách nhau khoảng trắng
(item 0 hợp lệ). Bỏ dòng trống và dòng metadata (ký tự khác khoảng trắng đầu tiên là `#`, `%` hoặc `@`).
Mỗi giao dịch được bỏ item trùng và sắp tăng dần. Báo `ArgumentError` (kèm tên file và số dòng) nếu có item âm
hoặc không phải số nguyên.

Cách làm: dòng nào chỉ gồm khoảng trắng ASCII và chữ số (trường hợp gần như luôn gặp) đi đường nhanh. Dòng có bất
kỳ ký tự nào khác (dấu `+`/`-`, chữ, byte không phải ASCII như khoảng trắng Unicode, số tràn Int) được xử lý lại
bằng đúng logic của bản gốc trên riêng dòng đó, nên mọi trường hợp biên và thông báo lỗi đều trùng khớp.

- `path` : đường dẫn file input
"""
function read_spmf(path::AbstractString)
    bytes = read(path)
    n = length(bytes)
    db = Vector{Int}[]
    sizehint!(db, count(==(0x0a), bytes) + 1)       # cấp phát mảng giao dịch một lần
    buf = Int[]                                      # bộ đệm item dùng lại cho mọi dòng
    i = 1
    ln = 0
    while i <= n
        nl = findnext(==(0x0a), bytes, i)            # eachline tách theo '\n'; dòng cuối có thể không có '\n'
        j = nl === nothing ? n + 1 : nl
        ln += 1
        st = _spmf_parse_line_fast!(buf, bytes, i, j - 1)
        if st == _LINE_OK
            push!(db, _spmf_transaction(buf))
        elseif st == _LINE_FALLBACK
            t = _spmf_parse_line_simple(path, ln, String(bytes[i:(j - 1)]))
            t === nothing || push!(db, t)
        end                                          # _LINE_SKIP: dòng trống hoặc metadata
        i = j + 1
    end
    return db
end

const _LINE_SKIP = 0
const _LINE_OK = 1
const _LINE_FALLBACK = 2

"Khoảng trắng ASCII theo `isspace` của Julia: ' ', '\\t', '\\n', '\\v', '\\f', '\\r'."
@inline _spmf_isspace(b::UInt8) = b == 0x20 || (0x09 <= b <= 0x0d)

"""
Parse nhanh dòng `bytes[lo:hi]` (không gồm '\\n') vào `buf`. Trả `_LINE_SKIP` (trống/metadata), `_LINE_OK`
(buf chứa các item theo thứ tự gặp), hoặc `_LINE_FALLBACK` khi gặp ký tự ngoài [0-9] và khoảng trắng ASCII hay số
tràn Int, để xử lý lại dòng bằng logic gốc.
"""
function _spmf_parse_line_fast!(buf::Vector{Int}, bytes::Vector{UInt8}, lo::Int, hi::Int)
    empty!(buf)
    k = lo
    @inbounds while k <= hi && _spmf_isspace(bytes[k])
        k += 1
    end
    k > hi && return _LINE_SKIP
    @inbounds b = bytes[k]
    (b == UInt8('#') || b == UInt8('%') || b == UInt8('@')) && return _LINE_SKIP
    @inbounds while k <= hi
        b = bytes[k]
        if _spmf_isspace(b)
            k += 1
            continue
        end
        v = 0
        while k <= hi
            b = bytes[k]
            _spmf_isspace(b) && break
            d = Int(b) - 48
            0 <= d <= 9 || return _LINE_FALLBACK             # '+', '-', chữ, byte ≥ 0x80, ...
            v > (typemax(Int) - d) ÷ 10 && return _LINE_FALLBACK   # tràn: bản gốc báo "không phải số nguyên"
            v = 10v + d
            k += 1
        end
        push!(buf, v)
    end
    return _LINE_OK
end

"Giao dịch từ bộ đệm: sao chép; nếu chưa tăng ngặt thì sắp và bỏ trùng (cùng kết quả với sort!(unique!(x)))."
function _spmf_transaction(buf::Vector{Int})
    items = copy(buf)
    m = length(items)
    @inbounds for t in 2:m
        if items[t] <= items[t - 1]
            sort!(items)
            w = 1
            for u in 2:m
                if items[u] != items[w]
                    w += 1
                    items[w] = items[u]
                end
            end
            return resize!(items, w)
        end
    end
    return items
end

"""
Logic gốc của `read_spmf_simple` cho một dòng (dùng khi đường nhanh không xử lý được): trả `nothing` nếu bỏ dòng,
ngược lại là giao dịch; lỗi ném ra giống hệt bản gốc.
"""
function _spmf_parse_line_simple(path::AbstractString, ln::Int, line::AbstractString)
    s = strip(line)
    (isempty(s) || s[1] in ('#', '%', '@')) && return nothing
    items = Int[]
    for tok in split(s)
        v = tryparse(Int, tok)
        v === nothing && throw(ArgumentError("$path, dòng $ln: \"$tok\" không phải số nguyên"))
        v >= 0 || throw(ArgumentError("$path, dòng $ln: item âm ($v) không hợp lệ, item phải là số nguyên ≥ 0"))
        push!(items, v)
    end
    return sort!(unique!(items))
end

"""
    MINSUP_ROUNDING

Cách làm tròn ngưỡng tương đối thành số giao dịch, đặt ở một chỗ duy nhất. Dùng `ceil` thuần,
không cộng trừ dung sai (ví dụ 0.07 × 100 = 7.000000000000001 nên ngưỡng là 8); cách này
khớp với SPMF.
"""
const MINSUP_ROUNDING = ceil

"""
    minsup_count(minsup, n; rounding = MINSUP_ROUNDING) -> Int

Đổi ngưỡng tương đối sang số giao dịch tối thiểu, ít nhất là 1.

- `minsup`   : ngưỡng tương đối, 0 < minsup ≤ 1
- `n`        : số giao dịch của cơ sở dữ liệu
- `rounding` : hàm làm tròn

Ví dụ: 0.2 × 7 = 1.4 → 2.
"""
function minsup_count(minsup::Real, n::Int; rounding = MINSUP_ROUNDING)
    0 < minsup <= 1 || throw(ArgumentError("minsup phải nằm trong (0, 1], nhận $minsup"))
    return max(1, rounding(Int, minsup * n))
end

"""
    sort_results!(results) -> results

Sắp kết quả theo độ dài itemset rồi theo thứ tự từ điển để output ổn định.

- `results` : danh sách `itemset => support`, bị sắp tại chỗ
"""
sort_results!(results) = sort!(results; by = p -> (length(p.first), p.first))

"""
    write_spmf(io, results)
    write_spmf(path, results)

Ghi kết quả theo định dạng output của SPMF, mỗi dòng dạng `1 2 6 #SUP: 2`.

- `io` / `path` : nơi ghi (luồng hoặc đường dẫn file)
- `results`     : danh sách `itemset => support`
"""
function write_spmf(io::IO, results)
    for (items, sup) in results
        println(io, join(items, ' '), " #SUP: ", sup)
    end
end

write_spmf(path::AbstractString, results) = open(io -> write_spmf(io, results), path, "w")

"""
    parse_minsup_ratio(s) -> Float64

Đọc ngưỡng tương đối dạng tỉ lệ "0.4" (trong (0, 1]) hoặc phần trăm "40%" (trong (0, 100]),
giống cách SPMF nhận minsup. Số lớn hơn 1 không có dấu % bị từ chối để khỏi nhầm với số giao dịch;
muốn dùng số giao dịch thì dùng `--minsup-count`.

- `s` : chuỗi người dùng nhập

Trả về tỉ lệ trong (0, 1]; báo `ArgumentError` nếu không đọc được hoặc ngoài miền.
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

Đọc ngưỡng confidence dạng "0.6" hoặc "60%".

- `s` : chuỗi người dùng nhập

Trả về giá trị trong [0, 1]; báo `ArgumentError` nếu không đọc được hoặc ngoài miền.
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

# Câu hướng dẫn cách dùng, in kèm khi báo lỗi tham số
const CLI_USAGE = "cách dùng: demo.jl (--minsup <tỉ lệ> | --minsup-count <số giao dịch>) " *
    "[--output-closed <file>] [--output-all <file>] [--rules <file> --minconf <0..1> [--top <k>]] <input.txt>"

"""
    parse_cli_impl(args, extended) -> NamedTuple

Bộ phân tích chung cho `parse_cli_args` và `parse_cli_options`.

- `args`     : danh sách tham số dòng lệnh
- `extended` : `false` chỉ nhận 4 tham số gốc, `true` nhận thêm các tham số của recovery và luật

Báo `ArgumentError` với thông báo nói rõ tham số nào sai. Kết quả: xem `parse_cli_args` và
`parse_cli_options`.
"""
function parse_cli_impl(args::Vector{String}, extended::Bool)
    usage = extended ? CLI_USAGE :
        "cách dùng: demo.jl (--minsup <tỉ lệ> | --minsup-count <số giao dịch>) [--output <file>] <input.txt>"
    valued = extended ?
        ("--minsup", "--minsup-count", "--output", "--output-closed", "--output-all", "--rules", "--minconf", "--top") :
        ("--minsup", "--minsup-count", "--output")
    got = Dict{String,String}()
    input = nothing
    # Duyệt tham số: tham số có giá trị lấy thêm phần tử kế tiếp, còn lại là file input
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

    # Phải có đúng một trong hai cách đặt ngưỡng
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

    # --output là tên cũ của --output-closed; dùng cả hai thì không rõ chọn cái nào nên báo lỗi
    (haskey(got, "--output") && haskey(got, "--output-closed")) &&
        throw(ArgumentError("--output là tên cũ của --output-closed, chỉ dùng một trong hai"))
    output_closed = get(got, "--output-closed", get(got, "--output", nothing))

    # --minconf và --top chỉ có nghĩa khi có --rules, và --rules bắt buộc có --minconf
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

Đọc tham số dòng lệnh dạng
`demo.jl (--minsup <tỉ lệ> | --minsup-count <số giao dịch>) [--output <file>] <input.txt>`.

- `args` : danh sách tham số dòng lệnh

Trả về `(minsup, minsup_count, input, output)`, tham số không dùng là `nothing`.
Báo `ArgumentError` nếu thiếu hoặc có cả hai cách đặt ngưỡng, giá trị ngoài miền, tham số bị lặp,
thiếu giá trị, tham số lạ, hoặc không có đúng một file input.
"""
parse_cli_args(args::Vector{String}) = parse_cli_impl(args, false)

"""
    parse_cli_options(args) -> NamedTuple

Như `parse_cli_args` nhưng nhận thêm các tham số cho recovery và luật kết hợp.

- `args` : danh sách tham số dòng lệnh. Ngoài các tham số gốc còn có
  `--output-closed <file>` (tên cũ `--output`), `--output-all <file>`, `--rules <file>`,
  `--minconf <0..1>` (bắt buộc khi có `--rules`) và `--top <k>`

Trả về `(minsup, minsup_count, input, output_closed, output_all, rules, minconf, top)`,
tham số không dùng là `nothing`.
"""
parse_cli_options(args::Vector{String}) = parse_cli_impl(args, true)

"""
    resolve_minsup(opts, n) -> Int

Đổi ngưỡng trong tham số dòng lệnh thành số giao dịch tuyệt đối.

- `opts` : kết quả của `parse_cli_args` hoặc `parse_cli_options`
- `n`    : số giao dịch của cơ sở dữ liệu
"""
resolve_minsup(opts, n::Int) =
    opts.minsup_count !== nothing ? opts.minsup_count : minsup_count(opts.minsup, n)
