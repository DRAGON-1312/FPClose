# =============================================================================
# scripts/summarize_results.jl — tổng hợp bảng Markdown + CSV cho báo cáo từ results/*.csv (KHÔNG đo lại).
#
# Chạy (từ bất kỳ thư mục nào):
#   julia --project=scripts/plot scripts/summarize_results.jl [--results DIR] [--outdir DIR]
#
# Ghi vào <results>/summary/: correctness_summary, speedup, ablation, scalability, txlen, time_breakdown (.csv + .md).
# Thời gian = TRUNG VỊ các lần OK (khác *_summary.csv của run_benchmark_grid.jl, vốn lấy nhỏ nhất).
# =============================================================================

include(joinpath(@__DIR__, "plot", "results_common.jl"))

const USAGE = """
Cách dùng: julia --project=scripts/plot scripts/summarize_results.jl [tùy chọn]
  --results <thư mục> thư mục kết quả (mặc định: <repo>/results)
  --outdir <thư mục>  nơi ghi bảng (mặc định: <results>/summary)"""

const MODE_LABEL = Dict("closed" => "tập đóng", "all_fi" => "mọi tập phổ biến", "all" => "mọi tập phổ biến")
mode_label(m) = m === missing ? "—" : get(MODE_LABEL, String(m), String(m))

const TIME_NOTE = "Thời gian: trung vị các lần chạy OK (thường 3 lần), cột `time_with_write_s` = đọc + khai thác + GHI file output " *
                  "cho cả hai công cụ (SPMF luôn ghi file). `t_ours_nowrite` = nhóm không tính ghi file (SPMF không tách được). " *
                  "Tỷ số = SPMF / ours (> 1 nghĩa là ours nhanh hơn)."

"Ghi bảng ra <outdir>/<name>.csv (nếu có df) và <name>.md."

"""
Tên biến thể hiển thị trong bảng Markdown: khóa `paper` trong CSV hiện là `pruning-only` (chỉ bật cắt nhánh dòng 8),
khớp nhãn trong hình (plot_results.jl) và báo cáo. CSV đầu ra vẫn giữ khóa gốc.
"""
variant_display(v) = v == "paper" ? "pruning-only" : v
display_variants(t) = (s = copy(t); s.variant = variant_display.(s.variant); s)

function write_outputs(outdir, name, df, md::AbstractString)
    df === nothing || CSV.write(joinpath(outdir, "$name.csv"), df)
    write(joinpath(outdir, "$name.md"), md)
    println("  → $name", df === nothing ? ".md" : ".csv / .md")
end

"Lấy giá trị cột `c` ở dòng đầu của `d` (rỗng hoặc không có cột ⇒ missing)."
cell(d, c) = (nrow(d) == 0 || !hasproperty(d, c)) ? missing : d[1, c]

"Hàm khóa sắp xếp: giữ thứ tự xuất hiện đầu tiên của các giá trị trong `v` (vd dataset theo thứ tự CSV)."
function order_index(v)
    d = Dict(x => i for (i, x) in enumerate(unique(v)))
    return x -> d[x]
end

"\"giá trị (+x%)\" cho bảng Markdown của ablation."
with_pct(v, p) = v === missing ? "—" : p === missing ? fmt_cell(v) : "$(fmt_cell(v)) ($(p >= 0 ? "+" : "")$(fmt_dec(p; sig = 3))%)"

"Chênh lệch % so với tham chiếu: (x / ref − 1)·100; ref ≤ 0 hoặc thiếu ⇒ missing."
rel_pct(x, ref) = (x === missing || ref === missing || ref <= 0) ? missing : round((x / ref - 1) * 100; digits = 1)

"""
Ghép dòng ours và SPMF cùng cấu hình (cùng giá trị `keys`) thành một dòng: n_itemsets, thời gian hai bên, tỷ số SPMF/ours.
Cảnh báo khi một phía thiếu (TIMEOUT/không có) hoặc số itemset hai bên khác nhau.
"""
function pair_tools(agg::DataFrame, keys::Vector{Symbol}; what = "")
    out = DataFrame()
    for g in groupby(agg, keys; sort = false)
        kv = NamedTuple{Tuple(keys)}(Tuple(g[1, k] for k in keys))
        o = g[g.tool .== OURS, :]
        s = g[g.tool .== SPMF, :]
        to, tn, ts = cell(o, :time_with_write_s), cell(o, :time_no_write_s), cell(s, :time_with_write_s)
        no, ns = cell(o, :n_itemsets), cell(s, :n_itemsets)
        (no !== missing && ns !== missing && no != ns) &&
            @warn "$what: [$(key_str(kv))] số itemset khác nhau: ours $(to_int(no)) vs SPMF $(to_int(ns))"
        (to === missing || ts === missing) && @warn "$what: [$(key_str(kv))] thiếu thời gian của một công cụ, tỷ số để trống"
        ratio = (to === missing || ts === missing || to <= 0) ? missing : round(ts / to; digits = 2)
        push!(out, (; kv..., n_transactions = to_int(tofloat(cell(g, :n_transactions))),
                    n_itemsets = to_int(no === missing ? ns : no), t_ours_s = rsig(to), t_ours_nowrite_s = rsig(tn),
                    t_spmf_s = rsig(ts), speedup_spmf_over_ours = ratio); promote = true)
    end
    return out
end

# =============================================================================
# correctness_summary
# =============================================================================

"""
Bảng đúng đắn theo dataset: số cấu hình, tổng số itemset (của nhóm), số cấu hình khớp SPMF TỪNG itemset
(only_ours = only_spmf = n_diff_support = 0 và status OK), tỷ lệ khớp. Thêm bộ toy và reference/spmf_check (nếu có),
và một dòng TỔNG cho mỗi (nguồn, chế độ).
"""
function summarize_correctness(resdir, outdir)
    rows = DataFrame()
    addrow!(src, ds, mode, n, nit, nmatch, note) =
        push!(rows, (source = src, dataset = String(ds), mode = mode, n_configs = n, n_itemsets_total = nit,
                     n_configs_match = nmatch, match_pct = n == 0 ? missing : round(100 * nmatch / n; digits = 2),
                     note = note); promote = true)

    grid = load_results_csv(joinpath(resdir, "correctness", "grid_correctness.csv"))
    if grid !== nothing
        src = "nhóm vs SPMF (từng itemset)"
        for g in groupby(grid, [:dataset, :mode]; sort = false)
            m = [r.status == "OK" && is_zero(r.only_ours) && is_zero(r.only_spmf) && is_zero(r.n_diff_support)
                 for r in eachrow(g)]
            nbad = count(!=("OK"), g.status)
            nbad > 0 && @warn "correctness: $(g[1, :dataset])/$(g[1, :mode]) có $nbad cấu hình không OK"
            addrow!(src, g[1, :dataset], g[1, :mode], nrow(g), to_int(sumskip(g.n_ours)), count(m),
                    nbad > 0 ? "$nbad cấu hình không OK" : "")
        end
    end

    toy = load_results_csv(joinpath(resdir, "correctness", "toy_vs_spmf.csv"))
    if toy !== nothing && all(c -> hasproperty(toy, c), (:n_ours, :n_spmf, :n_match))
        ndb = hasproperty(toy, :csdl) ? length(unique(toy.csdl)) : missing
        groups = hasproperty(toy, :mode) ? collect(groupby(toy, :mode; sort = false)) : [toy]
        for g in groups
            m = [let a = tofloat(r.n_ours), b = tofloat(r.n_spmf), c = tofloat(r.n_match)
                     a !== missing && isequal(a, b) && isequal(b, c)
                 end for r in eachrow(g)]
            addrow!("toy: nhóm vs SPMF (từng itemset)", "toy ($ndb CSDL)",
                    hasproperty(g, :mode) ? g[1, :mode] : missing, nrow(g), to_int(sumskip(g.n_ours)), count(m), "")
        end
    elseif toy !== nothing
        @warn "correctness: toy_vs_spmf.csv thiếu cột n_ours/n_spmf/n_match, bỏ qua"
    end

    ref = load_results_csv(joinpath(resdir, "reference", "spmf_check.csv"))
    if ref !== nothing && hasproperty(ref, :match) && hasproperty(ref, :dataset)
        for g in groupby(ref, :dataset; sort = false)
            m = [(!hasproperty(g, :status) || r.status == "OK") && lowercase(string(r.match)) == "true" for r in eachrow(g)]
            nit = hasproperty(g, :n_closed_itemsets) ? to_int(sumskip(g.n_closed_itemsets)) : missing
            addrow!("SPMF vs số tham chiếu (chỉ số lượng)", g[1, :dataset], "closed", nrow(g), nit, count(m),
                    "so số lượng tập đóng của SPMF với số tham chiếu, không so từng itemset")
        end
    end

    nrow(rows) == 0 && (@warn "correctness: không có dữ liệu"; return)
    # dòng TỔNG cho mỗi (nguồn, chế độ) có ≥ 2 dataset
    for g in collect(groupby(copy(rows), [:source, :mode]; sort = false))
        nrow(g) < 2 && continue
        n, k = sum(g.n_configs), sum(g.n_configs_match)
        nit = any(ismissing, g.n_itemsets_total) ? missing : sum(g.n_itemsets_total)
        addrow!(g[1, :source], "TỔNG", g[1, :mode], n, nit, k, "")
    end
    sort!(rows, [order(:source, by = order_index(rows.source)), order(:mode, by = order_index(rows.mode)),
                 order(:dataset, by = d -> d == "TỔNG")]; alg = MergeSort)

    md = "# Tổng hợp tính đúng đắn\n\n" *
         "Nguồn: `results/correctness/grid_correctness.csv`, `results/correctness/toy_vs_spmf.csv`, " *
         "`results/reference/spmf_check.csv`. Một cấu hình **khớp** khi status = OK và không có itemset chỉ một bên có " *
         "(`only_ours = only_spmf = 0`) và không có itemset lệch support (`n_diff_support = 0`). " *
         "Với toy: `n_ours = n_spmf = n_match`. Với spmf_check: cột `match` (chỉ so số lượng). " *
         "Tổng số itemset = tổng `n_ours` (hoặc `n_closed_itemsets`) trên các cấu hình.\n\n" *
         md_table(rows, [:source => "Nguồn so sánh", :dataset => "Dataset", :mode => "Chế độ", :n_configs => "Số cấu hình",
                         :n_itemsets_total => "Tổng số itemset", :n_configs_match => "Số cấu hình khớp",
                         :match_pct => "Tỷ lệ khớp (%)", :note => "Ghi chú"];
                  fmt = Dict{Symbol,Function}(:mode => mode_label, :note => x -> coalesce(x, "")))
    write_outputs(outdir, "correctness_summary", rows, md)
    for r in eachrow(rows[rows.dataset .== "TỔNG", :])
        println("    $(r.source), $(mode_label(r.mode)): $(r.n_configs_match)/$(r.n_configs) cấu hình khớp ($(fmt_dec(r.match_pct))%)")
    end
end

# =============================================================================
# speedup
# =============================================================================

"Ngưỡng phân loại theo r = t_ours / t_spmf (quy ước của Chương 2): r < 0,90 nhanh hơn, 0,90 ≤ r ≤ 1,10 gần tương đương, r > 1,10 chậm hơn."
const SPEED_FASTER_BELOW = 0.90
const SPEED_SLOWER_ABOVE = 1.10

"Phân loại một cấu hình theo r = t_ours / t_spmf: :faster, :similar hoặc :slower (missing nếu thiếu thời gian)."
speed_class(t_ours, t_spmf) =
    (t_ours === missing || t_spmf === missing || t_spmf <= 0) ? missing :
    (r = t_ours / t_spmf; r < SPEED_FASTER_BELOW ? :faster : r <= SPEED_SLOWER_ABOVE ? :similar : :slower)

"Bảng thời gian ours/SPMF và tỷ số theo dataset × minsup (results/runtime/grid_runtime.csv), kèm thống kê theo dataset."
function summarize_speedup(resdir, outdir)
    agg = load_tool_runs(joinpath(resdir, "runtime", "grid_runtime.csv"), [:dataset, :minsup_pct, :tool]; what = "runtime")
    agg === nothing && return
    sp = pair_tools(agg, [:dataset, :minsup_pct]; what = "speedup")
    sort!(sp, [order(:dataset, by = order_index(sp.dataset)), order(:minsup_pct, rev = true)])

    st = DataFrame()
    for g in groupby(sp, :dataset; sort = false)
        r = collect(skipmissing(g.speedup_spmf_over_ours))
        cls = collect(skipmissing(speed_class.(g.t_ours_s, g.t_spmf_s)))
        push!(st, (dataset = g[1, :dataset], n_minsup = length(r),
                   speedup_geomean = isempty(r) ? missing : round(geomean(r); digits = 2),
                   speedup_min = isempty(r) ? missing : minimum(r), speedup_max = isempty(r) ? missing : maximum(r),
                   n_faster = count(==(:faster), cls), n_similar = count(==(:similar), cls),
                   n_slower = count(==(:slower), cls)); promote = true)
    end
    allr = collect(skipmissing(sp.speedup_spmf_over_ours))
    allcls = collect(skipmissing(speed_class.(sp.t_ours_s, sp.t_spmf_s)))
    nf, nsim, nsl = count(==(:faster), allcls), count(==(:similar), allcls), count(==(:slower), allcls)

    md = "# So sánh thời gian chạy: FPClose (ours) vs SPMF\n\nNguồn: `results/runtime/grid_runtime.csv`. $TIME_NOTE\n\n" *
         "Phân loại từng cấu hình theo r = ours / SPMF (`t_ours_s / t_spmf_s`): r < 0,90 là **nhanh hơn**, " *
         "0,90 ≤ r ≤ 1,10 là **gần tương đương**, r > 1,10 là **chậm hơn**. Cột \"Tỷ số TB nhân\" là trung bình nhân " *
         "của tỷ số SPMF / ours trên các mức minsup của từng dataset.\n\n" *
         "## Theo dataset\n\n" *
         md_table(st, [:dataset => "Dataset", :n_minsup => "Số mức minsup", :speedup_geomean => "Tỷ số TB nhân",
                       :speedup_min => "Nhỏ nhất", :speedup_max => "Lớn nhất", :n_faster => "Nhanh hơn",
                       :n_similar => "Gần tương đương", :n_slower => "Chậm hơn"]) *
         "\nToàn bộ $(length(allr)) cấu hình: tỷ số SPMF / ours trung bình nhân = $(fmt_dec(geomean(allr))); " *
         "nhanh hơn $nf, gần tương đương $nsim, chậm hơn $nsl.\n\n" *
         "## Chi tiết dataset × minsup\n\n" *
         md_table(sp, [:dataset => "Dataset", :minsup_pct => "minsup (%)", :n_itemsets => "Số closed itemset",
                       :t_ours_s => "Ours (s)", :t_ours_nowrite_s => "Ours không ghi file (s)", :t_spmf_s => "SPMF (s)",
                       :speedup_spmf_over_ours => "SPMF / ours"])
    write_outputs(outdir, "speedup", sp, md)
    println("    $(length(allr)) cấu hình, tỷ số SPMF/ours TB nhân = $(fmt_dec(geomean(allr))), ",
            "nhanh hơn/gần tương đương/chậm hơn (r = ours/SPMF; < 0,90 / 0,90–1,10 / > 1,10) = ",
            "$nf/$nsim/$nsl trên $(length(allcls))")
    for r in eachrow(st)
        println("    $(rpad(r.dataset, 12)) TB nhân $(fmt_dec(r.speedup_geomean))  [$(fmt_dec(r.speedup_min)) – $(fmt_dec(r.speedup_max))]",
                "  nhanh/gần/chậm $(r.n_faster)/$(r.n_similar)/$(r.n_slower)")
    end
end

# =============================================================================
# ablation
# =============================================================================

"""
Bảng ablation theo dataset × biến thể (results/memory/basic_vs_optimized.csv, trung vị): thời gian khai thác (mine_s),
bộ nhớ thực dùng (mem_delta_mb = peak − baseline), alloc_mb, các bộ đếm; mỗi đại lượng kèm % chênh so với optimized.
Thêm bảng tổng theo biến thể (trung bình nhân tỷ số trên các dataset).
"""
function summarize_ablation(resdir, outdir)
    mem = load_memory_agg(resdir)
    mem === nothing && (@warn "ablation: không có dữ liệu"; return)
    counters = filter(c -> hasproperty(mem, c), COUNTER_COLS)
    metrics = [m for m in [:mine_s, :mem_delta_mb, :alloc_mb] if hasproperty(mem, m)]
    look = Dict((r.dataset, r.variant) => r for r in eachrow(mem))
    variants = unique(mem.variant)
    dsets = unique(mem.dataset)
    for ds in dsets
        haskey(look, (ds, REF_VARIANT)) || @warn "ablation: $ds không có biến thể $REF_VARIANT, cột % để trống"
    end

    out = DataFrame()
    for r in eachrow(mem)
        ref = get(look, (r.dataset, REF_VARIANT), nothing)
        refv(c) = ref === nothing ? missing : ref[c]
        row = (; dataset = r.dataset, minsup_pct = cell_or(r, :minsup_pct), variant = r.variant, n_ok = r.n_ok,
               n_closed = to_int(cell_or(r, :n_closed)), read_s = rsig(cell_or(r, :read_s)))
        for m in metrics
            row = merge(row, NamedTuple{(m, Symbol(m, :_vs_opt_pct))}((rsig(r[m]), rel_pct(r[m], refv(m)))))
        end
        for c in counters
            row = merge(row, NamedTuple{(c, Symbol(c, :_vs_opt_pct))}((to_int(r[c]), rel_pct(r[c], refv(c)))))
        end
        push!(out, row; promote = true)
    end

    ov = DataFrame()
    for v in variants
        tr, ar = Float64[], Float64[]
        for ds in dsets
            a, b = get(look, (ds, v), nothing), get(look, (ds, REF_VARIANT), nothing)
            (a === nothing || b === nothing) && continue
            for (m, acc) in ((:mine_s, tr), (:alloc_mb, ar))
                hasproperty(mem, m) || continue
                (a[m] !== missing && b[m] !== missing && a[m] > 0 && b[m] > 0) && push!(acc, a[m] / b[m])
            end
        end
        push!(ov, (variant = v, n_datasets = length(tr),
                   time_ratio_geomean = isempty(tr) ? missing : round(geomean(tr); digits = 3),
                   time_ratio_min = isempty(tr) ? missing : round(minimum(tr); digits = 3),
                   time_ratio_max = isempty(tr) ? missing : round(maximum(tr); digits = 3),
                   alloc_ratio_geomean = isempty(ar) ? missing : round(geomean(ar); digits = 3)); promote = true)
    end

    show_counters = [c for c in [:closed_checks, :subset_tests, :tree_traversals, :fparray_hits, :early_stops, :pruned_line8]
                     if c in counters]
    io = IOBuffer()
    print(io, "# Ablation: các biến thể của FPClose (ours)\n\n",
          "Nguồn: `results/memory/basic_vs_optimized.csv` (mỗi dataset đo tại minsup giữa lưới). Giá trị = trung vị các lần OK. ",
          "`mine_s` = chỉ khai thác (không gồm đọc/ghi). Bộ nhớ thực dùng = `mem_delta_mb` = max(peak RSS − baseline RSS, 0); ",
          "0 nghĩa là mức tăng nhỏ hơn nền Julia (~285 MB), không phân biệt được. `alloc_mb` = tổng cấp phát do Julia đếm. ",
          "Trong ngoặc: chênh lệch so với `$REF_VARIANT` (dương = lớn hơn/chậm hơn).\n\n",
          "## Tổng theo biến thể (tỷ số so với $REF_VARIANT, trung bình nhân trên các dataset)\n\n",
          md_table(display_variants(ov), [:variant => "Biến thể", :n_datasets => "Số dataset", :time_ratio_geomean => "Thời gian / opt (TB nhân)",
                        :time_ratio_min => "Nhỏ nhất", :time_ratio_max => "Lớn nhất", :alloc_ratio_geomean => "Alloc / opt (TB nhân)"]))
    for ds in dsets
        d = out[out.dataset .== ds, :]
        tbl = DataFrame(variant = variant_display.(d.variant), n_closed = d.n_closed)
        cols = Pair{Symbol,String}[:variant => "Biến thể", :n_closed => "Số tập đóng"]
        for (m, h) in ((:mine_s, "Khai thác (s)"), (:mem_delta_mb, "Bộ nhớ thực dùng (MB)"), (:alloc_mb, "Alloc (MB)"), [(c, String(c)) for c in show_counters]...)
            hasproperty(d, m) || continue
            tbl[!, m] = with_pct.(d[!, m], d[!, Symbol(m, :_vs_opt_pct)])
            push!(cols, m => h)
        end
        print(io, "\n## $ds (minsup $(fmt_dec(d[1, :minsup_pct]))%)\n\n", md_table(tbl, cols))
    end
    write_outputs(outdir, "ablation", out, String(take!(io)))
    for r in eachrow(ov)
        println("    $(rpad(r.variant, 26)) thời gian/opt TB nhân = $(fmt_dec(r.time_ratio_geomean)) trên $(r.n_datasets) dataset")
    end
end

"Lấy r[c] nếu dòng có cột c, ngược lại missing."
cell_or(r, c) = hasproperty(r, c) ? r[c] : missing

# =============================================================================
# scalability, txlen
# =============================================================================

"""
Bảng gọn ours vs SPMF theo một trục x (`xcol`) và minsup, từ CSV từng lần đo `path`. Ghi <name>.csv và <name>.md.
"""
function summarize_pairs(path, outdir; name, xcol::Symbol, xhead, title, what)
    agg = load_tool_runs(path, [:dataset, xcol, :minsup_pct, :tool]; what)
    agg === nothing && return
    t = pair_tools(agg, [:dataset, xcol, :minsup_pct]; what)
    sort!(t, [order(:minsup_pct, rev = true), xcol])
    md = "# $title\n\nNguồn: `$(replace(relpath(path, REPO_ROOT), '\\' => '/'))`. $TIME_NOTE\n\n" *
         md_table(t, [:minsup_pct => "minsup (%)", xcol => xhead, :dataset => "Dataset", :n_transactions => "Số giao dịch",
                      :n_itemsets => "Số closed itemset", :t_ours_s => "Ours (s)", :t_ours_nowrite_s => "Ours không ghi file (s)",
                      :t_spmf_s => "SPMF (s)", :speedup_spmf_over_ours => "SPMF / ours"])
    write_outputs(outdir, name, t, md)
    for g in groupby(t, :minsup_pct; sort = false)
        r = collect(skipmissing(g.speedup_spmf_over_ours))
        println("    minsup $(fmt_dec(g[1, :minsup_pct]))%: $(nrow(g)) điểm, ours $(fmt_dec(first(g.t_ours_s)))→$(fmt_dec(last(g.t_ours_s))) s, ",
                "SPMF $(fmt_dec(first(g.t_spmf_s)))→$(fmt_dec(last(g.t_spmf_s))) s, tỷ số TB nhân $(fmt_dec(geomean(r)))")
    end
end

# =============================================================================
# time_breakdown
# =============================================================================

"""
Bảng phân rã thời gian của FPClose (ours, optimized) tại minsup của memory CSV: đọc file (+ khôi phục nếu có),
dựng FP-tree + khai thác, ghi file (giây và %), kèm tổng có ghi file của ours và SPMF. Cách tính: load_time_breakdown (results_common.jl).
"""
function summarize_time_breakdown(resdir, outdir)
    bd = load_time_breakdown(resdir)
    bd === nothing && return
    srcs = unique(bd.source)
    merged = any(startswith("ghép"), srcs)
    note = merged ?
        "**Lưu ý: đây là ước lượng ghép từ hai lần đo riêng**: `mine_s` lấy từ `results/memory/basic_vs_optimized.csv` " *
        "(biến thể optimized), còn `time_no_write_s` và `time_with_write_s` lấy từ `results/runtime/grid_runtime.csv` " *
        "(cùng dataset và minsup). `mine_s` là toàn bộ lời gọi `fpclose`, gồm cả dựng FP-tree (`build_fptree`). " *
        "Dựng FP-tree + khai thác = mine_s; đọc file (+ khôi phục nếu có) = max(time_no_write_s − mine_s, 0); " *
        "ghi file = time_with_write_s − time_no_write_s." :
        "Cả ba phần lấy từ cùng một lần đo trong `results/runtime/grid_runtime.csv`, vì file này đã có cột tách riêng " *
        "`read_s`, `mine_s` và `write_s` (xem `scripts/run_benchmark_grid.jl`). Trong đó `read_s` chỉ là `read_spmf` " *
        "(đọc file); `mine_s` là toàn bộ lời gọi `fpclose`, gồm cả dựng FP-tree (`build_fptree`); " *
        "`recover_s` (khôi phục mọi tập phổ biến, chỉ có ở chế độ all) không có cột riêng trong CSV. " *
        "Đọc file (+ khôi phục nếu có) = read_s + max(time_no_write_s − read_s − mine_s, 0), trong đó phần dư là khôi phục, " *
        "≈ 0 ở chế độ closed. Dựng FP-tree + khai thác = mine_s. Ghi file = write_s. " *
        "Mức minsup lấy theo `results/memory/basic_vs_optimized.csv`. " *
        "Cột \"mine_s (memory)\" là `mine_s` đo riêng trong phần memory, để đối chiếu; " *
        "nếu hai cột mine_s chênh nhau nhiều thì kết quả đo không ổn định."
    md = "# Phân rã thời gian của FPClose (ours)\n\n$note\n\n" *
         "Mỗi phần là trung vị riêng của các lần chạy OK, nên tổng ba phần có thể lệch nhẹ so với trung vị của " *
         "`time_with_write_s`. Phần trăm được tính trên tổng ba phần. SPMF = `time_with_write_s` của SPMF (trung vị). " *
         "Phương pháp: $(join(srcs, "; ")).\n\n" *
         md_table(bd, [:dataset => "Dataset", :minsup_pct => "minsup (%)", :read_build_other_s => "Đọc file (+ khôi phục nếu có) (s)",
                       :mine_s => "Dựng FP-tree + khai thác (s)", :write_s => "Ghi file (s)", :parts_sum_s => "Tổng 3 phần (s)",
                       :ours_time_with_write_s => "Ours có ghi file (s)", :spmf_time_with_write_s => "SPMF (s)",
                       :pct_read_build_other => "% đọc file (+ khôi phục nếu có)",
                       :pct_mine => "% dựng FP-tree + khai thác", :pct_write => "% ghi file",
                       :mine_s_memory_csv => "mine_s (memory)"])
    write_outputs(outdir, "time_breakdown", bd, md)
    for r in eachrow(bd)
        println("    $(rpad(r.dataset, 12)) dựng FP-tree + khai thác $(fmt_dec(r.pct_mine))%, đọc file $(fmt_dec(r.pct_read_build_other))%, ",
                "ghi $(fmt_dec(r.pct_write))%  (ours $(fmt_dec(r.ours_time_with_write_s)) s, SPMF $(fmt_dec(r.spmf_time_with_write_s)) s)")
    end
end

# =============================================================================
# main
# =============================================================================

"Đọc tham số, sinh từng bảng; lỗi ở một bảng được in đầy đủ và không chặn các bảng khác (exit 1 ở cuối)."
function main(args)
    o = cli_options(args, ["--results", "--outdir"], USAGE)
    resdir = abspath(get(o, "--results", DEFAULT_RESULTS))
    outdir = abspath(get(o, "--outdir", joinpath(resdir, "summary")))
    mkpath(outdir)
    println("Đọc kết quả: $resdir\nGhi bảng:    $outdir")
    jobs = [
        "correctness" => () -> summarize_correctness(resdir, outdir),
        "speedup" => () -> summarize_speedup(resdir, outdir),
        "ablation" => () -> summarize_ablation(resdir, outdir),
        "scalability" => () -> summarize_pairs(joinpath(resdir, "scalability", "scalability.csv"), outdir;
                                               name = "scalability", xcol = :fraction_pct, xhead = "% giao dịch",
                                               title = "Khả năng mở rộng theo kích thước dữ liệu", what = "scalability"),
        "txlen" => () -> summarize_pairs(joinpath(resdir, "txlen", "txlen.csv"), outdir;
                                         name = "txlen", xcol = :avg_length, xhead = "Độ dài TB",
                                         title = "Ảnh hưởng của độ dài giao dịch", what = "txlen"),
        "time_breakdown" => () -> summarize_time_breakdown(resdir, outdir),
    ]
    failed = String[]
    for (name, f) in jobs
        println("== $name")
        try
            f()
        catch e
            push!(failed, name)
            @error "Bảng $name lỗi" exception = (e, catch_backtrace())
        end
    end
    isempty(failed) ? println("Xong.") : (println("Các bảng lỗi: ", join(failed, ", ")); exit(1))
end

abspath(PROGRAM_FILE) == @__FILE__() && main(ARGS)
