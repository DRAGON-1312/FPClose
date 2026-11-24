# =============================================================================
# scripts/plot/results_common.jl
#
# Hàm dùng chung cho scripts/plot_results.jl và scripts/summarize_results.jl:
#   - tìm gốc repo (theo vị trí file này, không phụ thuộc thư mục hiện tại),
#   - đọc CSV kết quả thành DataFrame,
#   - lọc lần đo OK và gộp TRUNG VỊ theo cấu hình (cảnh báo khi TIMEOUT/thiếu, không crash),
#   - định dạng số kiểu Việt (dấu phẩy thập phân) cho nhãn hình và bảng Markdown.
#
# Chỉ dùng CSV.jl, DataFrames.jl và Printf (stdlib). Không đọc gì ngoài thư mục results/.
# =============================================================================

using CSV, DataFrames, Printf

"Gốc repo: file này nằm ở scripts/plot/, tức hai cấp dưới gốc."
const REPO_ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const DEFAULT_RESULTS = joinpath(REPO_ROOT, "results")

# Mã công cụ / biến thể do scripts/run_benchmark_grid.jl ghi (không phải tên dataset).
const OURS = "ours_opt"          # fpclose của nhóm, mọi tối ưu bật
const SPMF = "spmf"              # SPMF FPClose
const REF_VARIANT = "optimized"  # biến thể tham chiếu của phần memory/ablation

# Cột khóa dạng số: ép về Float64 để nhóm/sắp xếp ổn định (CSV có thể đọc thành Int ở file này, Float ở file khác).
const KEY_FLOAT_COLS = (:minsup_pct, :fraction_pct, :avg_length)
# Cột luôn đọc dạng chuỗi (tránh CSV.jl đoán kiểu sai, ví dụ hash toàn chữ số).
const STRING_COLS = (:dataset, :tool, :status, :variant, :mode, :csdl, :minsup, :result_hash, :note, :machine, :mem_source)
# Bộ đếm thuật toán trong results/memory/basic_vs_optimized.csv (STAT_FIELDS của run_benchmark_grid.jl); cột nào có thì dùng.
const COUNTER_COLS = [:calls, :pruned_line8, :closed_checks, :cfis, :fparray_hits, :early_stops,
                      :tree_traversals, :subset_tests, :cfi_nodes, :root_cfi_nodes]

# -----------------------------------------------------------------------------
# Chuyển kiểu
# -----------------------------------------------------------------------------

"Chuyển một ô bất kỳ về Float64 (chấp nhận chuỗi \"60%\", \"0,5\"); không đọc được thì trả `missing`."
tofloat(::Missing) = missing
tofloat(x::Real) = Float64(x)
function tofloat(x::AbstractString)
    v = tryparse(Float64, replace(strip(x), "%" => "", "," => "."))
    return v === nothing ? missing : v
end
tofloat(_) = missing

"Làm tròn về Int, giữ `missing`."
to_int(x) = x === missing ? missing : round(Int, x)

"Làm tròn theo số chữ số có nghĩa, giữ `missing`."
rsig(x, s::Int = 4) = x === missing ? missing : round(x; sigdigits = s)

"Tổng bỏ qua missing (0 nếu rỗng)."
sumskip(v) = sum(skipmissing(tofloat.(v)); init = 0.0)

"Trung bình nhân của các số dương; rỗng thì `missing`."
geomean(v) = isempty(v) ? missing : exp(sum(log, v) / length(v))

"Trung vị (không cần Statistics.jl); rỗng thì `missing`."
function med(v)
    x = sort!(Float64[y for y in v if y !== missing])
    isempty(x) && return missing
    n = length(x)
    h = n ÷ 2
    return isodd(n) ? x[h + 1] : (x[h] + x[h + 1]) / 2
end

"So sánh ô với 0 (missing ⇒ false)."
is_zero(x) = (v = tofloat(x); v !== missing && v == 0)

# -----------------------------------------------------------------------------
# Định dạng
# -----------------------------------------------------------------------------

"Số gọn, bỏ số 0 thừa, dấu phẩy thập phân kiểu Việt: 0.5 → \"0,5\", 90.0 → \"90\", 0.02215 → \"0,02215\"."
function fmt_dec(x; sig::Int = 4)
    x === missing && return "—"
    v = round(Float64(x); sigdigits = sig)
    isfinite(v) || return "—"
    s = (isinteger(v) && abs(v) < 1e15) ? string(Int(v)) : @sprintf("%.10f", v)
    occursin('.', s) && (s = rstrip(rstrip(s, '0'), '.'))
    return replace(s, "." => ",")
end

"Định dạng một ô cho bảng Markdown."
function fmt_cell(x)
    x === missing && return "—"
    x isa Bool && return x ? "có" : "không"
    x isa Integer && return string(x)
    x isa AbstractFloat && return fmt_dec(x)
    return string(x)
end

"Mô tả khóa cấu hình cho thông báo cảnh báo: `dataset=chess, minsup_pct=90`."
key_str(kv::NamedTuple) = join(("$(k)=$(v isa AbstractFloat ? fmt_dec(v) : v)" for (k, v) in pairs(kv)), ", ")

"""
    md_table(df, cols; fmt) -> String

Bảng Markdown từ `df`. `cols` là vector `:cột => "Tiêu đề"`; `fmt` (tùy chọn) ánh xạ cột → hàm định dạng ô.
Cột số căn phải.
"""
function md_table(df::AbstractDataFrame, cols::Vector{<:Pair}; fmt::AbstractDict = Dict{Symbol,Function}())
    io = IOBuffer()
    println(io, "| ", join(last.(cols), " | "), " |")
    aligns = map(cols) do (c, _)
        T = nonmissingtype(eltype(df[!, c]))
        (T <: Number && !(T <: Bool)) ? "---:" : "---"
    end
    println(io, "|", join(aligns, "|"), "|")
    for r in eachrow(df)
        cells = [haskey(fmt, c) ? fmt[c](r[c]) : fmt_cell(r[c]) for (c, _) in cols]
        println(io, "| ", join(cells, " | "), " |")
    end
    return String(take!(io))
end

# -----------------------------------------------------------------------------
# Đọc CSV và gộp các lần đo
# -----------------------------------------------------------------------------

"""
    load_results_csv(path) -> DataFrame | nothing

Đọc một CSV kết quả. Thiếu file thì cảnh báo và trả `nothing`. Ô rỗng ⇒ `missing`.
Cột khóa số (minsup_pct, fraction_pct, avg_length) ép về Float64; cột `status` thành chuỗi.
"""
function load_results_csv(path::AbstractString)
    if !isfile(path)
        @warn "Không tìm thấy file kết quả, bỏ qua: $path"
        return nothing
    end
    types = Dict{Symbol,Type}(c => String for c in STRING_COLS)
    df = CSV.read(path, DataFrame; types = types, validate = false, stringtype = String, pool = false,
                  missingstring = ["", "NA"])
    for c in KEY_FLOAT_COLS
        hasproperty(df, c) && (df[!, c] = tofloat.(df[!, c]))
    end
    hasproperty(df, :status) && (df[!, :status] = string.(coalesce.(df[!, :status], "")))
    return df
end

"Mặt nạ các dòng có status == OK (file không có cột status thì coi mọi dòng là OK)."
ok_mask(df) = hasproperty(df, :status) ? (df.status .== "OK") : trues(nrow(df))

"""
    median_runs(df, keys, cols; first_cols, what) -> DataFrame

Gộp các lần đo cùng cấu hình (cùng giá trị các cột `keys`): chỉ giữ lần `OK`, lấy TRUNG VỊ từng cột trong `cols`,
lấy giá trị dòng OK đầu tiên cho `first_cols` (vd n_transactions). Thêm cột `n_ok`.
Cấu hình không có lần OK nào (TIMEOUT/SKIPPED/FAILED) bị bỏ và in cảnh báo; thiếu bớt lần OK cũng cảnh báo.
Cột không tồn tại trong `df` thì bỏ qua.
"""
function median_runs(df::DataFrame, keys::Vector{Symbol}, cols::Vector{Symbol};
                     first_cols::Vector{Symbol} = Symbol[], what::AbstractString = "")
    cols = filter(c -> hasproperty(df, c), cols)
    first_cols = filter(c -> hasproperty(df, c) && !(c in keys), first_cols)
    names_ = (keys..., first_cols..., :n_ok, cols...)
    out = DataFrame()
    for g in groupby(df, keys; sort = false)
        kv = NamedTuple{Tuple(keys)}(Tuple(g[1, k] for k in keys))
        ok = g[ok_mask(g), :]
        if nrow(ok) == 0
            st = hasproperty(g, :status) ? join(unique(g.status), ",") : "?"
            @warn "$what: bỏ cấu hình [$(key_str(kv))] — không có lần chạy OK (trạng thái: $st)"
            continue
        end
        nrow(ok) < nrow(g) && @warn "$what: [$(key_str(kv))] chỉ $(nrow(ok))/$(nrow(g)) lần OK, trung vị tính trên các lần OK"
        vals = (Tuple(g[1, k] for k in keys)..., Tuple(ok[1, c] for c in first_cols)..., nrow(ok),
                Tuple(med(tofloat.(ok[!, c])) for c in cols)...)
        push!(out, NamedTuple{names_}(vals); promote = true)
    end
    return out
end

"""
    load_tool_runs(path, keys; what) -> DataFrame | nothing

Đọc CSV từng lần đo dạng runtime/scalability/txlen (cột `tool`, mỗi dòng một lần chạy) và gộp trung vị theo `keys`
cho các cột thời gian (time_with_write_s = CÓ ghi file, time_no_write_s = KHÔNG ghi file), n_itemsets, mem_delta_mb.
"""
function load_tool_runs(path::AbstractString, keys::Vector{Symbol}; what::AbstractString = "")
    df = load_results_csv(path)
    df === nothing && return nothing
    agg = median_runs(df, keys, [:time_with_write_s, :time_no_write_s, :n_itemsets, :mem_delta_mb];
                      first_cols = [:n_transactions], what = what)
    nrow(agg) == 0 && (@warn "$what: không còn cấu hình nào sau khi lọc OK"; return nothing)
    return agg
end

"""
    load_memory_agg(resdir) -> DataFrame | nothing

Đọc results/memory/basic_vs_optimized.csv và gộp trung vị theo (dataset, variant): read_s, mine_s, bộ nhớ
(peak, baseline, mem_delta_mb = phần thuật toán thực dùng), alloc_mb, n_closed và các bộ đếm có mặt.
Nếu thiếu cột mem_delta_mb thì tính max(peak − baseline, 0). Cảnh báo dòng nào có same_as_optimized = false.
"""
function load_memory_agg(resdir::AbstractString)
    df = load_results_csv(joinpath(resdir, "memory", "basic_vs_optimized.csv"))
    df === nothing && return nothing
    if !hasproperty(df, :mem_delta_mb) && hasproperty(df, :peak_mem_mb) && hasproperty(df, :baseline_mem_mb)
        @info "memory: không có cột mem_delta_mb, tính = max(peak_mem_mb − baseline_mem_mb, 0)"
        df[!, :mem_delta_mb] = [(p === missing || b === missing) ? missing : max(p - b, 0.0)
                                for (p, b) in zip(tofloat.(df.peak_mem_mb), tofloat.(df.baseline_mem_mb))]
    end
    if hasproperty(df, :same_as_optimized)
        for r in eachrow(df)
            r.status == "OK" && lowercase(string(r.same_as_optimized)) == "false" &&
                @warn "memory: $(r.dataset)/$(r.variant) lần $(r.run) cho tập đóng KHÁC optimized!"
        end
    end
    counters = filter(c -> hasproperty(df, c), COUNTER_COLS)
    agg = median_runs(df, [:dataset, :variant],
                      [:read_s, :mine_s, :peak_mem_mb, :baseline_mem_mb, :mem_delta_mb, :alloc_mb, :n_closed, counters...];
                      first_cols = [:minsup_pct, :n_transactions], what = "memory")
    nrow(agg) == 0 && return nothing
    return agg
end

"""
    load_time_breakdown(resdir) -> DataFrame | nothing

Phân rã thời gian của FPClose (nhóm) cho mỗi dataset tại minsup của results/memory/basic_vs_optimized.csv
(biến thể optimized), dùng trung vị các lần OK:

- Nếu grid_runtime.csv có cột tách `read_s`, `mine_s`, `write_s`, dùng chúng (cùng một lần đo runtime):
  dựng FP-tree + khai thác = mine_s (toàn bộ lời gọi fpclose, gồm build_fptree);
  đọc file (+ khôi phục nếu có) = read_s (chỉ read_spmf) + max(time_no_write_s − read_s − mine_s, 0); ghi file = write_s.
- Nếu không có, ghép từ hai lần đo riêng: dựng FP-tree + khai thác = mine_s (memory CSV);
  đọc file (+ khôi phục nếu có) = max(time_no_write_s − mine_s, 0); ghi file = max(time_with_write_s − time_no_write_s, 0) (runtime CSV).
Tên cột read_build_other_s / mine_s giữ nguyên để không đổi cấu trúc CSV; nhãn hiển thị dùng tên mới.

Kèm time_with_write_s của ours và SPMF, và % từng phần trên tổng ba phần. Cột `source` ghi phương pháp đã dùng.
Dataset nào có minsup không xuất hiện trong runtime CSV thì bị bỏ và in cảnh báo.
"""
function load_time_breakdown(resdir::AbstractString)
    mem = load_memory_agg(resdir)
    mem === nothing && return nothing
    raw = load_results_csv(joinpath(resdir, "runtime", "grid_runtime.csv"))
    raw === nothing && return nothing
    has_split = all(c -> hasproperty(raw, c), (:read_s, :mine_s, :write_s))
    rt = median_runs(raw, [:dataset, :minsup_pct, :tool],
                     [:time_with_write_s, :time_no_write_s, :read_s, :mine_s, :write_s]; what = "breakdown/runtime")
    nrow(rt) == 0 && return nothing
    look = Dict((r.dataset, r.minsup_pct, r.tool) => r for r in eachrow(rt))
    pct(x, tot) = (x === missing || tot <= 0) ? missing : round(100 * x / tot; digits = 1)
    out = DataFrame()
    for m in eachrow(mem[mem.variant .== REF_VARIANT, :])
        ds, ms = m.dataset, m.minsup_pct
        o = get(look, (ds, ms, OURS), nothing)
        if o === nothing
            @warn "breakdown: $ds minsup $(fmt_dec(ms))% (từ memory CSV) không có trong runtime CSV cho $OURS, bỏ dataset này"
            continue
        end
        s = get(look, (ds, ms, SPMF), nothing)
        tnw, tw = o.time_no_write_s, o.time_with_write_s
        if has_split && o.read_s !== missing && o.mine_s !== missing && o.write_s !== missing
            mine = o.mine_s
            pre = o.read_s + (tnw === missing ? 0.0 : max(tnw - o.read_s - o.mine_s, 0.0))
            write = o.write_s
            src = "runtime: read_s, mine_s, write_s"
        else
            mine = m.mine_s
            if mine === missing || tnw === missing || tw === missing
                @warn "breakdown: $ds thiếu mine_s/time_no_write_s/time_with_write_s, bỏ dataset này"
                continue
            end
            pre = max(tnw - mine, 0.0)
            write = max(tw - tnw, 0.0)
            src = "ghép: mine_s (memory) + time_no_write_s, time_with_write_s (runtime)"
        end
        tot = pre + mine + write
        push!(out, (dataset = ds, minsup_pct = ms, read_build_other_s = rsig(pre), mine_s = rsig(mine), write_s = rsig(write),
                    parts_sum_s = rsig(tot), ours_time_with_write_s = rsig(tw),
                    spmf_time_with_write_s = rsig(s === nothing ? missing : s.time_with_write_s),
                    pct_read_build_other = pct(pre, tot), pct_mine = pct(mine, tot), pct_write = pct(write, tot),
                    mine_s_memory_csv = rsig(m.mine_s), source = src); promote = true)
    end
    nrow(out) == 0 && (@warn "breakdown: không dataset nào ghép được"; return nothing)
    return out
end

"""
    cli_options(args, allowed, usage) -> Dict{String,String}

Phân tích tham số dạng `--key value` hoặc `--key=value`; chỉ nhận các khóa trong `allowed`. `-h/--help` in `usage` rồi thoát.
"""
function cli_options(args::Vector{String}, allowed::Vector{String}, usage::AbstractString)
    opts = Dict{String,String}()
    i = 1
    while i <= length(args)
        a = args[i]
        if a in ("-h", "--help")
            println(usage)
            exit(0)
        elseif startswith(a, "--") && occursin('=', a)
            k, v = split(a, '='; limit = 2)
            i += 1
        elseif a in allowed
            i < length(args) || error("Thiếu giá trị sau $a\n$usage")
            k, v = a, args[i + 1]
            i += 2
        else
            error("Tham số không hiểu: $a\n$usage")
        end
        k in allowed || error("Tham số không hiểu: $k\n$usage")
        opts[String(k)] = String(v)
    end
    return opts
end
