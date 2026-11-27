# =============================================================================
# scripts/plot_results.jl — vẽ biểu đồ Chương 2 từ results/*.csv (KHÔNG đo lại).
#
# Chạy (từ bất kỳ thư mục nào):
#   julia --project=scripts/plot scripts/plot_results.jl
#   julia --project=scripts/plot scripts/plot_results.jl --only runtime,memory --outdir results/figures
#
# Mỗi hình được lưu cả PNG (300 dpi) và PDF. Chi tiết từng hình: results/figures/README.md.
# =============================================================================

ENV["GKSwstype"] = get(ENV, "GKSwstype", "100")   # GR vẽ không mở cửa sổ
include(joinpath(@__DIR__, "plot", "results_common.jl"))
using Plots
gr()

const USAGE = """
Cách dùng: julia --project=scripts/plot scripts/plot_results.jl [tùy chọn]
  --only <nhóm,...>   chỉ vẽ các nhóm: runtime,itemsets,memory,scalability,txlen,breakdown (mặc định: tất cả)
  --results <thư mục> thư mục kết quả (mặc định: <repo>/results)
  --outdir <thư mục>  nơi ghi hình (mặc định: <results>/figures)"""

const ALL_GROUPS = ["runtime", "itemsets", "memory", "scalability", "txlen", "breakdown"]

# --- Kích thước: Plots tính size theo px với 100 px = 1 inch; PNG xuất với dpi 300 ---
inch(x) = round(Int, 100x)
const W_SINGLE = inch(3.5)   # khổ một cột IEEE
const W_DOUBLE = inch(7.0)   # khổ hai cột IEEE (hình lưới)
const NCOL = 3               # số cột của hình lưới

# --- Kiểu cố định cho hai công cụ, dùng ở MỌI hình (màu + hình marker để không phụ thuộc màu) ---
const STYLE = Dict(OURS => (label = "FPClose (nhóm)", color = :royalblue, marker = :circle),
                   SPMF => (label = "SPMF", color = :darkorange, marker = :utriangle))
const MINSUP_LINESTYLES = [:solid, :dash, :dot, :dashdot]
const DATASET_MARKERS = [:circle, :rect, :utriangle, :diamond, :dtriangle, :pentagon, :hexagon, :star5, :xcross, :cross]

# --- Nhãn ngắn cho biến thể ablation (tên biến thể lấy từ CSV; tên lạ thì giữ nguyên) ---
const VARIANT_SHORT = Dict("prune_line8" => "cắt nhánh", "fparray" => "FP-array", "early_termination" => "kết thúc sớm",
                           "exact_count" => "so count chính xác", "reduced_cfitree" => "CFI-tree rút gọn")

"""
Nhãn trục cho biến thể: opt_no_X → "Không X" (tắt tối ưu X, ví dụ "Không cắt nhánh"); biến thể `paper` (tên trong CSV)
hiện là "pruning-only" vì nó chỉ bật cắt nhánh dòng 8, không phải toàn bộ bài báo gốc; còn lại giữ tên.
"""
variant_label(v::AbstractString) = startswith(v, "opt_no_") ? "Không " * get(VARIANT_SHORT, v[8:end], v[8:end]) :
                                   v == "paper" ? "pruning-only" : String(v)

"Màu cột của biến thể: optimized = màu của nhóm, ablation (opt_no_*) = xanh nhạt, basic/pruning-only (paper) = xám."
variant_color(v::AbstractString) = v == REF_VARIANT ? STYLE[OURS].color :
                                   startswith(v, "opt_no_") ? :lightskyblue : :gray70

"Nhãn mốc trục mặc định: số thập phân thường với dấu phẩy (0,8; 12,5), không dùng dạng 10^x."
fmt_tick(v) = fmt_dec(v; sig = 6)

"""
Cấu hình mặc định cho mọi hình: font Unicode (tiếng Việt có dấu), cỡ chữ hợp khổ IEEE, dpi 300,
nhãn mốc trục x/y dùng dấu phẩy thập phân (áp cho cả trục tuyến tính khi mốc tự sinh).
"""
function setup_theme()
    default(; fontfamily = "DejaVu Sans", titlefontsize = 8, guidefontsize = 7, tickfontsize = 6,
            legendfontsize = 6, dpi = 300, framestyle = :box, grid = true, gridalpha = 0.25,
            linewidth = 1.2, markersize = 3, markerstrokewidth = 0.6, foreground_color_legend = :gray80,
            xformatter = fmt_tick, yformatter = fmt_tick)
end

"Tên file an toàn từ tên dataset."
safe_name(s) = replace(String(s), r"[^A-Za-z0-9_.-]" => "_")

"Lưu hình ra <outdir>/<name>.png và .pdf."
function save_figure(p, outdir, name)
    for ext in ("png", "pdf")
        savefig(p, joinpath(outdir, "$name.$ext"))
    end
    println("  đã lưu $name.png / $name.pdf")
end

"Ẩn các ô thừa của hình lưới (khi số dataset không chia hết cho NCOL)."
function blank_unused!(p, n_used, n_total)
    for i in (n_used + 1):n_total
        plot!(p; subplot = i, framestyle = :none, grid = false, ticks = nothing, legend = false)
    end
end

"Giới hạn trục tuyến tính có lề 6%."
pad_lims(lo, hi) = lo == hi ? (lo - 1, hi + 1) : (lo - 0.06 * (hi - lo), hi + 0.06 * (hi - lo))

"Các mốc 1-2-5 (hoặc chỉ các `mantissas` cho trước) trong [lo, hi] cho trục log."
function nice_log_ticks(lo, hi; mantissas = (1, 2, 5))
    t = Float64[]
    for e in floor(Int, log10(lo)):ceil(Int, log10(hi)), m in mantissas
        v = m * 10.0^e
        lo / 1.0001 <= v <= hi * 1.0001 && push!(t, v)
    end
    return t
end

"""
Đặt trục y thang log cho `subplot` theo dữ liệu `ys`: lề ×1,25 hai đầu, mốc dãy 1–2–5 trong khoảng đó
(quá 8 mốc thì chỉ giữ 1, 10, 100…), nhãn số thập phân thường có dấu phẩy, không dùng dạng 10^x.
Dải quá hẹp (dưới 2 mốc) thì dùng hai mốc là giá trị nhỏ nhất và lớn nhất làm tròn 2 chữ số.
"""
function log_axis_y!(p, ys; subplot = 1)
    isempty(ys) && return p
    lo, hi = extrema(ys)
    lims = (lo / 1.25, hi * 1.25)
    t = nice_log_ticks(lims...)
    length(t) > 8 && (t = nice_log_ticks(lims...; mantissas = (1,)))
    length(t) < 2 && (t = unique(round.([lo, hi]; sigdigits = 2)))
    plot!(p; subplot, yscale = :log10, ylims = lims, yticks = (t, fmt_dec.(t)))
end

"""
Lọc cặp (x, y) để vẽ: bỏ điểm thiếu (và y ≤ 0 khi trục log), in cảnh báo cho từng điểm bị bỏ.
"""
function clean_xy(x, y; logy::Bool, ctx::AbstractString)
    xs, ys = Float64[], Float64[]
    for (a, b) in zip(x, y)
        if a === missing || b === missing || (logy && b <= 0)
            @warn "$ctx: bỏ điểm x=$(fmt_dec(a)) (giá trị thiếu$(logy ? " hoặc ≤ 0 trên thang log" : ""))"
            continue
        end
        push!(xs, a)
        push!(ys, b)
    end
    return xs, ys
end

"""
Vẽ một đường của công cụ `tool` (màu/marker cố định theo STYLE) lên `subplot`.
Trả về các giá trị y đã vẽ (rỗng nếu không có điểm nào) để đặt mốc trục log.
`hollow` = marker rỗng; `scatter_only` = chỉ marker, không nối đường.
"""
function tool_line!(p, x, y, tool; subplot = 1, label = STYLE[tool].label, linestyle = :solid, hollow = false,
                    logy = true, scatter_only = false, ctx = "")
    xs, ys = clean_xy(x, y; logy, ctx)
    if isempty(xs)
        @warn "$ctx: không có điểm hợp lệ, bỏ đường \"$label\""
        return Float64[]
    end
    st = STYLE[tool]
    plot!(p, xs, ys; subplot, label, seriestype = scatter_only ? :scatter : :path, color = st.color, linestyle,
          markershape = st.marker, markercolor = hollow ? :white : st.color, markerstrokecolor = st.color)
    return ys
end

"""
Trục minsup của hình runtime: vị trí CÁCH ĐỀU 1..k (tránh đè chữ khi các mức sát nhau như 0,3/0,25/0,2),
nhãn là các mức minsup `levels` theo thứ tự giảm dần từ trái sang phải.
"""
function minsup_index_axis!(p, levels; subplot = 1)
    k = length(levels)
    k == 0 && return p
    plot!(p; subplot, xticks = (1:k, fmt_dec.(levels)), xlims = (0.5, k + 0.5), xlabel = "minsup (%)")
end

# =============================================================================
# a) runtime
# =============================================================================

"""
Vẽ một panel runtime của dataset `ds`: FPClose (nhóm) và SPMF, cả hai đều dùng thời gian CÓ ghi file
(time_with_write_s, trung vị). Trục y log (mốc 1–2–5), trục x cách đều theo chỉ số các mức minsup giảm dần.
"""
function runtime_panel!(p, rt, ds; subplot = 1, legend = :topleft)
    d = rt[rt.dataset .== ds, :]
    levels = sort(unique(d.minsup_pct); rev = true)              # minsup giảm dần → vị trí 1..k
    pos = Dict(m => i for (i, m) in enumerate(levels))
    xpos(t) = [pos[m] for m in t.minsup_pct]
    ours = sort(d[d.tool .== OURS, :], :minsup_pct; rev = true)
    spmf = sort(d[d.tool .== SPMF, :], :minsup_pct; rev = true)
    ys = Float64[]
    append!(ys, tool_line!(p, xpos(ours), ours.time_with_write_s, OURS; subplot, ctx = "runtime/$ds/nhóm"))
    append!(ys, tool_line!(p, xpos(spmf), spmf.time_with_write_s, SPMF; subplot, ctx = "runtime/$ds/spmf"))
    plot!(p; subplot, title = String(ds), legend)
    log_axis_y!(p, ys; subplot)
    minsup_index_axis!(p, levels; subplot)
    return !isempty(ys)
end

"Nhóm runtime: một hình 3.5in cho mỗi dataset + một hình lưới 7in gồm mọi dataset."
function fig_runtime(rt, outdir)
    dsets = unique(rt.dataset)
    for ds in dsets
        p = plot(; size = (W_SINGLE, inch(2.6)), ylabel = "Thời gian (s, thang log)")
        runtime_panel!(p, rt, ds)
        save_figure(p, outdir, "runtime_" * safe_name(ds))
    end
    n = length(dsets)
    nr = cld(n, NCOL)
    p = plot(; layout = (nr, NCOL), size = (W_DOUBLE, inch(1.9) * nr), left_margin = 1Plots.mm)
    for (i, ds) in enumerate(dsets)
        runtime_panel!(p, rt, ds; subplot = i, legend = i == 1 ? :topleft : false)
        plot!(p; subplot = i, ylabel = (i - 1) % NCOL == 0 ? "Thời gian (s)" : "",
              xlabel = i > n - NCOL ? "minsup (%)" : "")
    end
    blank_unused!(p, n, nr * NCOL)
    save_figure(p, outdir, "runtime_grid")
end

# =============================================================================
# b) itemsets
# =============================================================================

"""
Đọc số frequent itemset (FI) từ results/correctness/grid_correctness_fi_all_levels.csv: các dòng mode = all_fi và
status = OK, giá trị là n_ours (FI do nhóm khôi phục từ tập đóng). Kiểm tra n_ours == n_spmf ở từng dòng (@warn nếu
khác). Trả `nothing` nếu thiếu file; ngược lại (counts = dataset => (xs, ys), n_ok, n_skipped, n_mismatch, limit).
"""
function load_fi_counts(resdir)
    path = joinpath(resdir, "correctness", "grid_correctness_fi_all_levels.csv")
    if !isfile(path)
        @warn "itemsets: không có $path, chỉ vẽ số tập phổ biến đóng"
        return nothing
    end
    df = load_results_csv(path)
    all_fi = df[df.mode .== "all_fi", :]
    ok = all_fi[all_fi.status .== "OK", :]
    n_mismatch = 0
    for r in eachrow(ok)
        if tofloat(r.n_ours) != tofloat(r.n_spmf)
            n_mismatch += 1
            @warn "itemsets: $(r.dataset) minsup $(fmt_dec(r.minsup_pct))%: n_ours = $(r.n_ours) khác n_spmf = $(r.n_spmf)"
        end
    end
    # giới hạn số FI (--fi-limit) đọc từ ghi chú của dòng SKIPPED, ví dụ "so_FI_vuot_gioi_han_2000000"
    notes = [string(coalesce(n, "")) for n in all_fi[all_fi.status .!= "OK", :note]]
    ms = filter(!isnothing, [match(r"(\d{4,})", n) for n in notes])
    limit = isempty(ms) ? missing : parse(Int, first(ms)[1])
    counts = Dict{String,Tuple{Vector{Float64},Vector{Float64}}}()
    for g in groupby(ok, :dataset; sort = false)
        g = sort(g, :minsup_pct)
        xs, ys = clean_xy(g.minsup_pct, tofloat.(g.n_ours); logy = true, ctx = "itemsets FI/$(g[1, :dataset])")
        isempty(xs) || (counts[String(g[1, :dataset])] = (xs, ys))
    end
    return (counts = counts, n_ok = nrow(ok), n_skipped = nrow(all_fi) - nrow(ok), n_mismatch = n_mismatch,
            limit = limit)
end

"Giới hạn số FI dạng chữ: 2000000 → \"2 triệu\"; không rõ thì \"giới hạn\"."
fi_limit_text(limit) = limit === missing ? "giới hạn" :
                       (limit % 1_000_000 == 0 ? "$(limit ÷ 1_000_000) triệu" : fmt_dec(limit))

"""
Số itemset theo minsup, khổ 7in, hai ô cạnh nhau với cùng màu và marker cho mỗi CSDL, chú giải chung bên phải ô (b):
(a) số frequent itemset (FI) do nhóm khôi phục từ tập đóng (n_ours của grid_correctness_fi_all_levels.csv, dòng
mode = all_fi và status = OK; cấu hình SKIPPED vì vượt giới hạn số FI không vẽ, có ghi chú trong tiêu đề ô);
(b) số closed itemset (n_itemsets của ours trong grid_runtime, thiếu thì lấy của SPMF). Trục x là minsup thật (thang
log, giảm dần); trục y thang log, hai ô dùng chung giới hạn để so độ lớn. Thiếu CSV FI thì chỉ vẽ ô (b) như cũ.
"""
function fig_itemsets(rt, outdir; resdir = DEFAULT_RESULTS)
    dsets = unique(rt.dataset)
    style(i) = (c = palette(:tab10)[mod1(i, 10)];
                (color = c, markercolor = c, markerstrokecolor = c,
                 markershape = DATASET_MARKERS[mod1(i, length(DATASET_MARKERS))]))
    closed = Dict{String,Tuple{Vector{Float64},Vector{Float64}}}()
    for ds in dsets
        d = rt[rt.dataset .== ds, :]
        cnt = Dict{Float64,Float64}()
        for tool in (SPMF, OURS), r in eachrow(d[d.tool .== tool, :])   # ours ghi đè SPMF
            r.n_itemsets === missing || (cnt[r.minsup_pct] = r.n_itemsets)
        end
        xs0 = sort!(collect(keys(cnt)))
        xs, ys = clean_xy(xs0, [cnt[x] for x in xs0]; logy = true, ctx = "itemsets/$ds")
        isempty(xs) ? (@warn "itemsets/$ds: không có điểm nào") : (closed[String(ds)] = (xs, ys))
    end
    isempty(closed) && (@warn "itemsets: không có dữ liệu để vẽ"; return)
    fi = load_fi_counts(resdir)
    xlab = "minsup (%, thang log)"

    if fi === nothing          # chỉ ô (b), như bản cũ
        p = plot(; size = (W_DOUBLE, inch(2.8)), legend = :outerright, xflip = true, xscale = :log10, yscale = :log10,
                 xlabel = xlab, ylabel = "Số tập phổ biến đóng (thang log)",
                 title = "Số tập phổ biến đóng theo minsup", left_margin = 2Plots.mm, bottom_margin = 2Plots.mm)
        for (i, ds) in enumerate(dsets)
            haskey(closed, String(ds)) && plot!(p, closed[String(ds)]...; label = String(ds), style(i)...)
        end
        panels = (1,)
    else
        println("  itemsets: ô (a) vẽ $(fi.n_ok) cấu hình FI, bỏ $(fi.n_skipped) cấu hình SKIPPED; ",
                "số dòng n_ours ≠ n_spmf: $(fi.n_mismatch)")
        p = plot(; layout = grid(1, 2; widths = [0.43, 0.57]), size = (W_DOUBLE, inch(3.1)), xflip = true,
                 xscale = :log10, yscale = :log10, xlabel = xlab, left_margin = 2Plots.mm, bottom_margin = 3Plots.mm,
                 top_margin = 1Plots.mm)
        for (i, ds) in enumerate(dsets)
            haskey(fi.counts, String(ds)) && plot!(p, fi.counts[String(ds)]...; subplot = 1, label = "", style(i)...)
            haskey(closed, String(ds)) && plot!(p, closed[String(ds)]...; subplot = 2, label = String(ds), style(i)...)
        end
        note = fi.n_skipped > 0 ? "\n($(fi.n_skipped) cấu hình > $(fi_limit_text(fi.limit)) FI không vẽ)" : ""
        plot!(p; subplot = 1, title = "(a) Số frequent itemset theo minsup" * note, legend = false,
              ylabel = "Số itemset (thang log)")
        plot!(p; subplot = 2, title = "(b) Số tập phổ biến đóng theo minsup", legend = :outerright)
        panels = (1, 2)
    end
    # trục x chung (minsup thật) và trục y chung cho mọi ô
    allx = vcat([v[1] for v in values(closed)]..., (fi === nothing ? Float64[] : [v[1] for v in values(fi.counts)])...)
    ally = vcat([v[2] for v in values(closed)]..., (fi === nothing ? Float64[] : [v[2] for v in values(fi.counts)])...)
    xl = (minimum(allx) / 1.3, maximum(allx) * 1.3)
    t = nice_log_ticks(xl...; mantissas = (1,))     # chỉ mốc 10^k: ô hẹp, dãy 1–2–5 hay 1–5 làm nhãn dính nhau
    for sp in panels
        plot!(p; subplot = sp, xticks = (t, fmt_dec.(t)), xlims = xl)
        log_axis_y!(p, ally; subplot = sp)
    end
    save_figure(p, outdir, "itemsets_vs_minsup")
end

# =============================================================================
# c) memory / ablation
# =============================================================================

"""
Hình lưới cột: mỗi dataset một ô (tại minsup giữa lưới đã chọn trong CSV memory), mỗi cột một biến thể
(thứ tự như trong CSV). `col` là cột đã gộp trung vị (vd :mem_delta_mb, :mine_s).
"""
function fig_variant_bars(mem, outdir; col::Symbol, ylabel, title, name)
    hasproperty(mem, col) || (@warn "$name: CSV memory không có cột $col, bỏ hình"; return)
    variants = unique(mem.variant)
    k = length(variants)
    dsets = unique(mem.dataset)
    n = length(dsets)
    nr = cld(n, NCOL)
    p = plot(; layout = (nr, NCOL), size = (W_DOUBLE, inch(2.1) * nr), legend = false, plot_title = title,
             plot_titlefontsize = 9, bottom_margin = 3Plots.mm, left_margin = 1Plots.mm)
    for (i, ds) in enumerate(dsets)
        d = mem[mem.dataset .== ds, :]
        xs, ys, cs = Int[], Float64[], Symbol[]
        for (j, v) in enumerate(variants)
            r = d[d.variant .== v, :]
            val = nrow(r) == 0 ? missing : r[1, col]
            if val === missing
                @warn "$name/$ds: thiếu $col của biến thể $v, bỏ cột này"
                continue
            end
            push!(xs, j); push!(ys, val); push!(cs, variant_color(v))
        end
        if !isempty(xs)
            ymax = maximum(ys)
            bar!(p, xs, ys; subplot = i, fillcolor = cs, linecolor = :black, linewidth = 0.3, bar_width = 0.7,
                 label = "", ylims = (0, ymax > 0 ? 1.15ymax : 1.0))
        end
        msup = hasproperty(d, :minsup_pct) && nrow(d) > 0 ? " (minsup $(fmt_dec(d[1, :minsup_pct]))%)" : ""
        plot!(p; subplot = i, title = String(ds) * msup, xticks = (1:k, variant_label.(variants)), xrotation = 45,
              xlims = (0.3, k + 0.7), ylabel = (i - 1) % NCOL == 0 ? ylabel : "", grid = :y)
    end
    blank_unused!(p, n, nr * NCOL)
    save_figure(p, outdir, name)
end

"""
Một hình 3.5in: thời gian khai thác của từng biến thể chia cho optimized, lấy trung bình nhân trên mọi dataset
(1 = bằng optimized, > 1 = chậm hơn). Đường nét đứt tại 1.
"""
function fig_ablation_relative(mem, outdir)
    variants = unique(mem.variant)
    look = Dict((r.dataset, r.variant) => r for r in eachrow(mem))
    xs, ys, cs, ns = Int[], Float64[], Symbol[], Int[]
    for (j, v) in enumerate(variants)
        ratios = Float64[]
        for ds in unique(mem.dataset)
            a = get(look, (ds, v), nothing)
            b = get(look, (ds, REF_VARIANT), nothing)
            (a === nothing || b === nothing || a.mine_s === missing || b.mine_s === missing || b.mine_s <= 0) && continue
            push!(ratios, a.mine_s / b.mine_s)
        end
        isempty(ratios) && (@warn "ablation_relative: biến thể $v không có tỷ số nào"; continue)
        push!(xs, j); push!(ys, geomean(ratios)); push!(cs, variant_color(v)); push!(ns, length(ratios))
    end
    isempty(xs) && (@warn "ablation_relative: không có dữ liệu (thiếu biến thể $REF_VARIANT?)"; return)
    p = bar(xs, ys; fillcolor = cs, linecolor = :black, linewidth = 0.3, bar_width = 0.7, legend = false,
            size = (W_SINGLE, inch(2.6)), xticks = (1:length(variants), variant_label.(variants)), xrotation = 45,
            xlims = (0.3, length(variants) + 0.7), ylims = (0, 1.15 * maximum(ys)), grid = :y,
            ylabel = "Thời gian / optimized", bottom_margin = 3Plots.mm,
            title = "Thời gian khai thác / optimized ($(maximum(ns)) CSDL)")
    hline!(p, [1.0]; color = :black, linestyle = :dash, linewidth = 0.8, label = "")
    save_figure(p, outdir, "ablation_time_relative")
end

# =============================================================================
# d) scalability, e) txlen
# =============================================================================

"""
Hình các cặp đường ours/SPMF theo `xcol`: mỗi mức minsup một kiểu nét (và marker đặc/rỗng xen kẽ),
màu/marker theo công cụ. `spmf_scatter = true`: SPMF chỉ vẽ marker rỗng (dùng khi hai bên trùng nhau, vd số itemset).
"""
function fig_pairs_by_minsup(agg, xcol::Symbol, ycol::Symbol; xlabel, ylabel, title, logy::Bool, name, outdir,
                             spmf_scatter = false)
    p = plot(; size = (W_SINGLE, inch(2.6)), xlabel, ylabel, title, legend = :topleft)
    msups = sort(unique(agg.minsup_pct); rev = true)
    ally = Float64[]
    for (i, m) in enumerate(msups), tool in (OURS, SPMF)
        d = sort(agg[(agg.minsup_pct .== m) .& (agg.tool .== tool), :], xcol)
        nrow(d) == 0 && (@warn "$name: không có dữ liệu $tool ở minsup $(fmt_dec(m))%"; continue)
        sc = spmf_scatter && tool == SPMF
        append!(ally, tool_line!(p, d[!, xcol], d[!, ycol], tool; label = "$(STYLE[tool].label), minsup $(fmt_dec(m))%",
                                 linestyle = MINSUP_LINESTYLES[mod1(i, length(MINSUP_LINESTYLES))],
                                 hollow = iseven(i) || sc, logy, scatter_only = sc,
                                 ctx = "$name/$tool/minsup $(fmt_dec(m))%"))
    end
    isempty(ally) && (@warn "$name: không có đường nào, bỏ hình"; return)
    xs = sort(unique(skipmissing(agg[!, xcol])))
    plot!(p; xticks = (xs, fmt_dec.(xs)), xlims = pad_lims(xs[1], xs[end]))
    logy ? log_axis_y!(p, ally) : plot!(p; ylims = (0, 1.08 * maximum(ally)))
    save_figure(p, outdir, name)
end

"Nhóm scalability: thời gian (có ghi file, trung vị) theo % giao dịch của dataset gốc; ours vs SPMF, mỗi minsup một cặp."
function fig_scalability(resdir, outdir)
    agg = load_tool_runs(joinpath(resdir, "scalability", "scalability.csv"),
                         [:dataset, :fraction_pct, :minsup_pct, :tool]; what = "scalability")
    agg === nothing && return
    base = join(unique(replace.(String.(agg.dataset), r"_p\d+$" => "")), ", ")   # retail_p010 → retail
    fig_pairs_by_minsup(agg, :fraction_pct, :time_with_write_s; xlabel = "Phần trăm giao dịch của $base (%)",
                        ylabel = "Thời gian (s)", title = "Khả năng mở rộng theo kích thước ($base)",
                        logy = false, name = "scalability_time", outdir)
end

"Nhóm txlen: thời gian (log) và số closed itemset (log) theo độ dài giao dịch trung bình; ours vs SPMF, mỗi minsup một cặp."
function fig_txlen(resdir, outdir)
    agg = load_tool_runs(joinpath(resdir, "txlen", "txlen.csv"), [:dataset, :avg_length, :minsup_pct, :tool];
                         what = "txlen")
    agg === nothing && return
    fig_pairs_by_minsup(agg, :avg_length, :time_with_write_s; xlabel = "Độ dài giao dịch trung bình",
                        ylabel = "Thời gian (s, thang log)", title = "Ảnh hưởng của độ dài giao dịch",
                        logy = true, name = "txlen_time", outdir)
    fig_pairs_by_minsup(agg, :avg_length, :n_itemsets; xlabel = "Độ dài giao dịch trung bình",
                        ylabel = "Số tập phổ biến đóng (thang log)", title = "Số closed itemset theo độ dài giao dịch",
                        logy = true, name = "txlen_itemsets", outdir, spmf_scatter = true)
end

# =============================================================================
# f) breakdown
# =============================================================================

"""
Cột chồng 100%: phân rã thời gian của FPClose (nhóm, optimized) cho mỗi dataset tại minsup của memory CSV
thành đọc file (+ khôi phục nếu có) / dựng FP-tree + khai thác / ghi file (xem load_time_breakdown). Dùng tỷ lệ % vì thời gian tuyệt đối
giữa các dataset chênh nhau nhiều bậc; số tuyệt đối nằm trong results/summary/time_breakdown.md.
"""
function fig_time_breakdown(resdir, outdir)
    bd = load_time_breakdown(resdir)
    bd === nothing && return
    k = nrow(bd)
    x = 1:k
    a, b = bd.pct_read_build_other, bd.pct_mine
    c = bd.pct_write
    if any(ismissing, a) || any(ismissing, b) || any(ismissing, c)
        @warn "breakdown: có phần trăm thiếu, coi là 0"
        a, b, c = coalesce.(a, 0.0), coalesce.(b, 0.0), coalesce.(c, 0.0)
    end
    labels = ["$(r.dataset) ($(fmt_dec(r.minsup_pct))%)" for r in eachrow(bd)]
    # vẽ chồng bằng cách phủ: tổng (ghi file) → đọc + mine (dựng FP-tree + khai thác) → đọc (đọc file)
    p = bar(x, a .+ b .+ c; label = "ghi file", fillcolor = :gray70, linecolor = :black, linewidth = 0.3,
            bar_width = 0.7, size = (W_SINGLE, inch(2.9)), legend = :outertop, ylims = (0, 100),
            yticks = 0:20:100, ylabel = "Tỷ lệ thời gian (%)", xticks = (x, labels), xrotation = 45,
            xlims = (0.3, k + 0.7), grid = :y, bottom_margin = 3Plots.mm,
            title = "Phân rã thời gian của FPClose (nhóm)")
    bar!(p, x, a .+ b; label = "dựng FP-tree + khai thác", fillcolor = STYLE[OURS].color, linecolor = :black, linewidth = 0.3,
         bar_width = 0.7)
    bar!(p, x, a; label = "đọc file (+ khôi phục nếu có)", fillcolor = :lightskyblue, linecolor = :black, linewidth = 0.3,
         bar_width = 0.7)
    save_figure(p, outdir, "time_breakdown")
end

# =============================================================================
# main
# =============================================================================

"Đọc tham số, vẽ từng nhóm; lỗi ở một nhóm được in đầy đủ và không chặn các nhóm khác (exit 1 ở cuối)."
function main(args)
    o = cli_options(args, ["--only", "--results", "--outdir"], USAGE)
    groups = haskey(o, "--only") ? filter!(!isempty, String.(strip.(split(o["--only"], ',')))) : copy(ALL_GROUPS)
    bad = setdiff(groups, ALL_GROUPS)
    isempty(bad) || error("Nhóm không hợp lệ: $(join(bad, ", ")). Chọn trong: $(join(ALL_GROUPS, ","))")
    resdir = abspath(get(o, "--results", DEFAULT_RESULTS))
    outdir = abspath(get(o, "--outdir", joinpath(resdir, "figures")))
    mkpath(outdir)
    setup_theme()
    println("Đọc kết quả: $resdir\nGhi hình:    $outdir")
    rt = nothing
    failed = String[]
    for g in groups
        println("== $g")
        try
            if g in ("runtime", "itemsets")
                rt === nothing && (rt = load_tool_runs(joinpath(resdir, "runtime", "grid_runtime.csv"),
                                                       [:dataset, :minsup_pct, :tool]; what = "runtime"))
                rt === nothing && (@warn "$g: không có dữ liệu runtime, bỏ qua"; continue)
                g == "runtime" ? fig_runtime(rt, outdir) : fig_itemsets(rt, outdir; resdir)
            elseif g == "memory"
                mem = load_memory_agg(resdir)
                mem === nothing && (@warn "memory: không có dữ liệu, bỏ qua"; continue)
                fig_variant_bars(mem, outdir; col = :mem_delta_mb, ylabel = "RAM tăng thêm (MB)",
                                 title = "RAM tối đa tăng thêm so với mức sau warm-up (trung vị 3 lần đo)",
                                 name = "memory_variants_grid")
                fig_variant_bars(mem, outdir; col = :mine_s, ylabel = "Thời gian khai thác (s)",
                                 title = "Thời gian khai thác theo biến thể (trung vị 3 lần đo, không gồm đọc/ghi file)",
                                 name = "time_variants_grid")
                fig_ablation_relative(mem, outdir)
            elseif g == "scalability"
                fig_scalability(resdir, outdir)
            elseif g == "txlen"
                fig_txlen(resdir, outdir)
            elseif g == "breakdown"
                fig_time_breakdown(resdir, outdir)
            end
        catch e
            push!(failed, g)
            @error "Nhóm $g lỗi" exception = (e, catch_backtrace())
        end
    end
    if isempty(failed)
        println("Xong.")
    else
        println("Các nhóm lỗi: ", join(failed, ", "))
        exit(1)
    end
end

abspath(PROGRAM_FILE) == @__FILE__() && main(ARGS)
