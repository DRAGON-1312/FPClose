# Vẽ bảng và biểu đồ Chương 2 từ các CSV kết quả trong results/ (không chạy lại thực nghiệm).
#
#   julia --project=scripts/plots scripts/make_figures.jl
#
# Hoặc mở notebooks/chapter2_results.ipynb: notebook `include` file này rồi gọi từng hàm, kèm mô tả và nhận xét.
#
# Môi trường vẽ riêng (scripts/plots/Project.toml, chỉ có Plots.jl) để Project.toml chính của thuật toán
# không phải cài thư viện vẽ. Lần đầu: julia --project=scripts/plots -e "using Pkg; Pkg.instantiate()"
#
# Kết quả:
#   - hình: results/figures/<tên>.pdf (chèn vào LaTeX) và .png (xem trên GitHub, Colab)
#   - bảng: docs/IEEE-conference-template-062824/tables/<tên>.tex (chỉ phần tabular, báo cáo \input vào);
#     notebook hiển thị cùng bảng đó dưới dạng Markdown
#
#   1. Correctness        : correctness_table
#   2. Thời gian / minsup  : runtime_vs_minsup, runtime_ratio_table
#   3. Số itemset / minsup : itemsets_vs_minsup
#   4. Bộ nhớ              : memory_basic_vs_optimized, memory_table, ablation_table
#   5. Scalability         : scalability, scalability_table
#   6. Độ dài giao dịch    : txlen, txlen_table
#
# Thời gian là TRUNG VỊ của các lần đo (tính từ CSV từng lần đo, giống scripts/plot_results.jl), GỒM đọc và ghi file ở cả
# hai phía (SPMF: "Total time" tự in) để so công bằng. Bộ nhớ chỉ so các biến thể của nhóm với nhau: RSS của
# Julia và heap JVM của SPMF đo hai thứ khác nhau.

using Plots, Printf, Statistics

const ROOT = normpath(joinpath(@__DIR__, ".."))
const RESULTS = joinpath(ROOT, "results")
const FIGURES = mkpath(joinpath(RESULTS, "figures"))
# Bảng LaTeX ghi thẳng vào thư mục báo cáo (mẫu IEEE) để \input{tables/<tên>} trong file .tex
const REPORT_DIR = joinpath(ROOT, "docs", "IEEE-conference-template-062824")
const TABLES = mkpath(joinpath(REPORT_DIR, "tables"))

const DATASETS = ["chess", "mushrooms", "connect", "pumsb_star", "accidents",
                  "retail", "T10I4D100K", "T40I10D100K", "kosarak"]
const DENSE = ["chess", "mushrooms", "connect", "pumsb_star", "accidents"]
const SPARSE = ["retail", "T10I4D100K", "T40I10D100K", "kosarak"]

# Màu cố định (bảng màu đã kiểm tra cho người mù màu). Nhóm luôn xanh dương, SPMF luôn cam; mỗi đường có
# thêm kiểu điểm riêng để không chỉ dựa vào màu.
const TOOL = Dict(
    "ours_opt" => (label = "Nhóm (Julia)", color = "#2a78d6", marker = :circle),
    "spmf"     => (label = "SPMF (Java)",  color = "#eb6834", marker = :rect))
const DATASET_STYLE = Dict(
    "chess" => ("#1baf7a", :circle), "mushrooms" => ("#eda100", :rect), "connect" => ("#e87ba4", :diamond),
    "pumsb_star" => ("#008300", :utriangle), "accidents" => ("#6250d6", :dtriangle),
    "retail" => ("#1baf7a", :circle), "T10I4D100K" => ("#eda100", :rect), "T40I10D100K" => ("#e87ba4", :diamond),
    "kosarak" => ("#008300", :utriangle))
# Tên biến thể hiển thị: basic, pruning-only (khóa "paper" trong CSV), optimized
const VARIANT_SHORT = Dict("basic" => "basic", "paper" => "pruning-only", "optimized" => "optimized")
const VARIANT = [("basic", "Cơ bản (tắt hết tối ưu)", "#1baf7a"),
                 ("paper", "Chỉ cắt nhánh (dòng 8)", "#eda100"),
                 ("optimized", "Tối ưu (bật hết)", "#2a78d6")]
const INK = "#444444"

"""
Font chữ trong hình: Times New Roman, giống phần chữ của báo cáo. Font "times" dựng sẵn của GR là Type 1 không có dấu
tiếng Việt (PDF hiện "th?i gian"), nên nạp thẳng file .ttf và đăng ký với Plots; GR vẽ chữ thành nét nên PDF hiện đúng
dấu mà không phải nhúng font. Máy không có Times New Roman (vd. Colab trên Linux) thì dùng Liberation Serif (cùng kích
thước chữ với Times), không có nữa thì DejaVu Sans của GR.
"""
function figure_font()
    gr()
    candidates = [raw"C:\Windows\Fonts\times.ttf",
                  "/usr/share/fonts/truetype/msttcorefonts/Times_New_Roman.ttf",
                  "/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf",
                  "/usr/share/fonts/liberation/LiberationSerif-Regular.ttf"]
    for path in candidates
        isfile(path) || continue
        id = Plots.GR.loadfont(path)
        id > 0 || continue
        Plots.gr_font_family["times new roman"] = id
        return "Times New Roman"
    end
    @warn "Không tìm thấy Times New Roman hoặc Liberation Serif, chữ trong hình dùng DejaVu Sans"
    return "sans-serif"
end

# Kiểu hình theo bài báo gốc (Grahne & Zhu, TKDE 2005): mỗi hình là một biểu đồ nhỏ vừa một cột, khung trục đủ bốn
# cạnh, chú thích có viền. Kích thước tính theo điểm ảnh ở 100 dpi, tức 1 px = 1/100 inch trong PDF: COL vừa một cột
# IEEE (3,5 inch), WIDE vừa cả trang (7,16 inch), nên khi chèn vào LaTeX gần như không phải co giãn và cỡ chữ trong
# hình khớp với chữ chú thích.
const COL = (350, 240)
const WIDE = (716, 250)
default(fontfamily = figure_font(), titlefontsize = 9, guidefontsize = 8, tickfontsize = 7,
        legendfontsize = 7, linewidth = 1.4, markersize = 3.5, markerstrokewidth = 0,
        framestyle = :box, grid = true, gridalpha = 0.15, dpi = 300,
        foreground_color_legend = :black, background_color_legend = :white)

# ---------------------------------------------------------------------------
# Hàm dùng chung
# ---------------------------------------------------------------------------

"Đọc CSV đơn giản (không có dấu phẩy trong ô) thành danh sách Dict cột => giá trị (chuỗi)."
function read_csv_rows(path)
    lines = filter(!isempty, strip.(readlines(path)))
    header = split(lines[1], ',')
    return [Dict(String(h) => String(v) for (h, v) in zip(header, split(l, ','; keepempty = true)))
            for l in lines[2:end]]
end

"Đổi ô CSV sang số; ô trống thành `missing`."
num(x) = isempty(x) ? missing : parse(Float64, x)
int(x) = parse(Int, x)

"""
Dấu thập phân kiểu Việt Nam, giống phần văn bản của báo cáo: "0.05" -> "0,05". Chỉ đổi dấu chấm nằm giữa hai
chữ số, nên tên như T10I4D100K hay đường dẫn file không bị ảnh hưởng.
"""
vn(s::AbstractString) = replace(s, r"(?<=\d)\.(?=\d)" => ",")

"Chuỗi minsup gọn: 90.0 -> \"90%\", 0.05 -> \"0,05%\"."
pct(x::AbstractString) = pct(parse(Float64, x))
pct(x::Real) = (s = string(x); vn(endswith(s, ".0") ? s[1:end-2] : s) * "%")

"Số có khoảng trắng phân cách hàng nghìn: 190309 -> \"190 309\" (dấu phẩy để dành cho phần thập phân)."
thousands(n::Integer) = replace(string(n), r"(?<=\d)(?=(\d{3})+$)" => " ")

"Số trên trục: 0,02, 0,5, 3, 1 000, 100 000 (không dùng dạng 10^x)."
tick_label(v) = v >= 1000 ? thousands(round(Int, v)) : vn(@sprintf("%g", v))

"Mốc trục log dạng 1-2-3-5 × 10^k nằm trong [lo, hi], kèm nhãn số thường."
function log_ticks(lo, hi)
    pick(ms) = filter(v -> lo / 1.08 <= v <= hi * 1.08, [m * 10.0^k for k in -4:6 for m in ms])
    t = pick((1, 2, 3, 5))
    length(t) < 3 && (t = pick((1, 1.5, 2, 3, 5, 7)))
    return (t, tick_label.(t))
end
log_ticks(values) = log_ticks(extrema(skipmissing(values))...)

# Trục tuyến tính (không đặt mốc bằng log_ticks) cũng hiện số kiểu Việt Nam: 0,25 và 2 000
default(formatter = tick_label)

"""
Hình của báo cáo nay do scripts/plot_results.jl (nhánh main) sinh vào results/figures/, cùng tên với một số hình ở đây.
Để không ghi đè, script này mặc định KHÔNG lưu hình (chỉ trả về `p` để notebook hiển thị) và chỉ sinh bảng LaTeX.
Đặt biến môi trường FPCLOSE_SAVE_FIGURES=1 nếu thật sự muốn lưu hình kiểu cũ.
"""
const WRITE_FIGURES = get(ENV, "FPCLOSE_SAVE_FIGURES", "0") == "1"

"Lưu hình `p` thành results/figures/<name>.pdf và .png nếu WRITE_FIGURES; luôn trả về `p` để notebook hiển thị."
function save_figure(p, name)
    WRITE_FIGURES || return p
    for ext in ("pdf", "png")
        savefig(p, joinpath(FIGURES, "$name.$ext"))
    end
    println("Đã lưu results/figures/$name.{pdf,png}")
    return p
end

"""
    median_summary(path, keys) -> Vector{Dict}

Tổng hợp file CSV từng lần đo (status OK) thành một dòng cho mỗi (keys..., tool): `time_s` là TRUNG VỊ của
`time_with_write_s`, cùng quy ước với scripts/plot_results.jl của main. Các cột khác (n_itemsets, n_transactions, ...)
lấy từ lần đo đầu tiên vì không đổi giữa các lần.
"""
function median_summary(path, keys)
    rows = [r for r in read_csv_rows(path) if r["status"] == "OK"]
    groups = Dict{Vector{String},Vector{Dict{String,String}}}()
    order = Vector{Vector{String}}()
    for r in rows
        k = [[r[c] for c in keys]; r["tool"]]
        haskey(groups, k) || push!(order, k)
        push!(get!(groups, k, Dict{String,String}[]), r)
    end
    out = Dict{String,String}[]
    for k in order
        g = groups[k]
        d = copy(g[1])
        d["time_s"] = string(median(num(r["time_with_write_s"]) for r in g))
        push!(out, d)
    end
    return out
end

"""
    save_table(name, header, rows; align) -> String

Ghi bảng LaTeX (chỉ phần tabular) vào docs/IEEE-conference-template-062824/tables/<name>.tex để báo cáo
`\\input{tables/<name>}`, và trả về bảng dạng Markdown để notebook hiển thị (display("text/markdown", ...)).
`rows` là các vector chuỗi; `align` là chuỗi căn lề LaTeX, ví dụ "lrrr".
Tiêu đề cột có thể chứa "\\n" để xuống dòng (LaTeX: \\shortstack), giúp bảng hẹp lại mà không phải thu nhỏ chữ.
Mọi số thập phân dùng dấu phẩy (`vn`).
"""
function save_table(name, header, rows; align = "l" * "r"^(length(header) - 1))
    rows = [vn.(r) for r in rows]
    header = vn.(header)
    markdown = sprint() do io
        println(io, "| ", join(replace.(header, "\n" => " "), " | "), " |")
        println(io, "|", join((a == 'l' ? "---" : "---:" for a in align), "|"), "|")
        for r in rows
            println(io, "| ", join(r, " | "), " |")
        end
    end
    tex(s) = replace(s, "%" => "\\%", "_" => "\\_", "≥" => "\$\\geq\$", "×" => "\$\\times\$")
    # tiêu đề nhiều dòng: tabular lồng căn theo dòng cuối, để mọi ô tiêu đề cùng một đường chân chữ
    head(s) = occursin('\n', s) ? "\\begin{tabular}[b]{@{}c@{}}" * join(tex.(split(s, '\n')), "\\\\") * "\\end{tabular}" :
                                  tex(s)
    open(joinpath(TABLES, "$name.tex"), "w") do io
        println(io, "\\begin{tabular}{", align, "}")
        println(io, "\\hline")
        println(io, join(head.(header), " & "), " \\\\")
        println(io, "\\hline")
        for r in rows
            startswith(r[1], "Tổng") && println(io, "\\hline")
            println(io, join(tex.(r), " & "), " \\\\")
        end
        println(io, "\\hline")
        println(io, "\\end{tabular}")
    end
    println("Đã lưu docs/IEEE-conference-template-062824/tables/$name.tex")
    return markdown
end

# Bảng tổng hợp thời gian (nhóm và SPMF) dùng chung cho mục 2 và 3
const RUNTIME = median_summary(joinpath(RESULTS, "runtime", "grid_runtime.csv"), ["dataset", "minsup_pct"])

"Các mức minsup của một dataset, theo thứ tự trong CSV (từ cao xuống thấp)."
minsups(rows, d) = unique(r["minsup_pct"] for r in rows if r["dataset"] == d)

"Giá trị cột `col` của (dataset, minsup, tool) trong một bảng tổng hợp."
value(rows, d, m, tool, col) =
    num(only(r for r in rows if r["dataset"] == d && r["minsup_pct"] == m && r["tool"] == tool)[col])

# ---------------------------------------------------------------------------
# 1. Correctness
# ---------------------------------------------------------------------------
# Tỉ lệ khớp = itemset khớp (cùng itemset, cùng support) / itemset khác nhau của cả hai phía
#            = n_match / (n_match + only_ours + only_spmf + n_diff_support), cộng dồn mọi cấu hình.

"""
Bảng correctness từ lần so mọi mức minsup (`run_benchmark_grid.jl --only correctness --fi-all-levels`): closed ở mọi
cấu hình, mọi frequent itemset (FI) ở mọi mức có số FI không vượt `--fi-limit` (2 triệu). Mức bị bỏ qua (SKIPPED) đếm
riêng, không tính vào tỉ lệ.
"""
const CORRECTNESS_CSV = joinpath(RESULTS, "correctness", "grid_correctness_fi_all_levels.csv")

function correctness_table()
    corr = read_csv_rows(CORRECTNESS_CSV)
    union_size(r) = int(r["n_match"]) + int(r["only_ours"]) + int(r["only_spmf"]) + int(r["n_diff_support"])
    rows = Vector{String}[]
    tot = Dict(:cfg => 0, :m => 0, :u => 0, :fcfg => 0, :fm => 0, :fu => 0)
    for d in DATASETS
        closed = filter(r -> r["dataset"] == d && r["mode"] == "closed" && r["status"] == "OK", corr)
        fi_all = filter(r -> r["dataset"] == d && r["mode"] == "all_fi", corr)
        fi = filter(r -> r["status"] == "OK", fi_all)
        m, u = sum(int(r["n_match"]) for r in closed), sum(union_size(r) for r in closed)
        fm, fu = sum(int(r["n_match"]) for r in fi; init = 0), sum(union_size(r) for r in fi; init = 0)
        tot[:cfg] += length(closed); tot[:m] += m; tot[:u] += u
        tot[:fcfg] += length(fi); tot[:fm] += fm; tot[:fu] += fu
        push!(rows, [d, string(length(closed)), "$(thousands(m))/$(thousands(u))", @sprintf("%.2f%%", 100 * m / u),
                     "$(length(fi))/$(length(fi_all))", "$(thousands(fm))/$(thousands(fu))",
                     @sprintf("%.2f%%", 100 * fm / fu)])
    end
    push!(rows, ["Tổng", string(tot[:cfg]), "$(thousands(tot[:m]))/$(thousands(tot[:u]))",
                 @sprintf("%.2f%%", 100 * tot[:m] / tot[:u]), "$(tot[:fcfg])/$(tot[:cfg])",
                 "$(thousands(tot[:fm]))/$(thousands(tot[:fu]))", @sprintf("%.2f%%", 100 * tot[:fm] / tot[:fu])])
    save_table("correctness_table",
               ["Dataset", "Số mức
minsup", "Closed
khớp/tổng", "Tỉ lệ
closed", "Mức so
mọi FI", "Mọi FI
khớp/tổng", "Tỉ lệ
mọi FI"],
               rows; align = "lrrrrrr")
end

# ---------------------------------------------------------------------------
# 2. Thời gian chạy theo minsup
# ---------------------------------------------------------------------------
# Lưới 3×3, mỗi ô một dataset; trục x là các mức minsup đã chọn, giảm dần từ trái sang phải (cách đều);
# trục y log. Kèm bảng tỉ lệ thời gian nhóm/SPMF.

"Một ô thời gian theo minsup cho dataset `d` (nhóm và SPMF)."
function runtime_panel(d; legend = :topleft, xlabel = "minsup (giảm dần)", ylabel = "thời gian (s, thang log)")
    ms = minsups(RUNTIME, d)
    x = 1:length(ms)
    times = Dict(tool => [value(RUNTIME, d, m, tool, "time_s") for m in ms] for tool in ("ours_opt", "spmf"))
    p = plot(title = d, xticks = (x, pct.(ms)), yscale = :log10, xlims = (0.6, length(ms) + 0.4),
             yticks = log_ticks(vcat(values(times)...)), legend = legend, xlabel = xlabel, ylabel = ylabel)
    for tool in ("ours_opt", "spmf")
        st = TOOL[tool]
        plot!(p, x, times[tool]; label = st.label, color = st.color, marker = st.marker)
    end
    return p
end

"""
Hình riêng cho một dataset, vừa một cột (kiểu bài báo gốc: mỗi hình một CSDL). Lưu results/figures/runtime_<d>.{pdf,png}
để báo cáo chèn; notebook hiển thị trực tiếp.
"""
runtime_figure(d::AbstractString) = save_figure(plot(runtime_panel(d); size = COL, left_margin = 1Plots.mm),
                                                "runtime_$d")

"""
Vẽ 9 hình riêng (dùng trong báo cáo) và một lưới 3×3 tổng hợp runtime_vs_minsup (để xem nhanh trong notebook,
README); trả về lưới.
"""
function runtime_figure()
    foreach(runtime_figure, DATASETS)
    panels = [runtime_panel(d; legend = i == 1 ? :topleft : false, xlabel = i > 6 ? "minsup (giảm dần)" : "",
                            ylabel = i % 3 == 1 ? "thời gian (s, thang log)" : "")
              for (i, d) in enumerate(DATASETS)]
    save_figure(plot(panels...; layout = (3, 3), size = (WIDE[1], 600)), "runtime_vs_minsup")
end

"""
Tỉ lệ thời gian nhóm / SPMF (< 1: nhóm nhanh hơn). Cột M1..M7 là các mức minsup của từng dataset từ cao xuống thấp,
đúng thứ tự trên trục x của hình thời gian (mức cụ thể khác nhau giữa các dataset, xem data/meta/benchmark_config.csv).
"""
function runtime_ratio_table()
    rows = Vector{String}[]
    nmax = maximum(length(minsups(RUNTIME, d)) for d in DATASETS)
    for d in DATASETS
        ms = minsups(RUNTIME, d)
        ratios = [value(RUNTIME, d, m, "ours_opt", "time_s") / value(RUNTIME, d, m, "spmf", "time_s") for m in ms]
        cells = [k <= length(ratios) ? @sprintf("%.2f", ratios[k]) : "" for k in 1:nmax]
        push!(rows, [d, "$(pct(ms[1]))–$(pct(ms[end]))", cells...])
    end
    save_table("runtime_ratio_table", ["Dataset", "minsup", ("M$k" for k in 1:nmax)...], rows;
               align = "ll" * "r"^nmax)
end

"""
Phân rã thời gian của nhóm ở mức minsup thấp nhất của mỗi dataset: đọc file (`read_spmf`), khai thác (`fpclose`,
gồm dựng FP-tree), ghi file (`write_spmf`), so với "Total time" của SPMF. Ba thành phần lấy từ CÙNG lần đo có tổng
thời gian là trung vị (với 3 lần đo: lần ở giữa), nên cộng lại đúng bằng tổng.
"""
function runtime_breakdown_table()
    raw = [r for r in read_csv_rows(joinpath(RESULTS, "runtime", "grid_runtime.csv")) if r["status"] == "OK"]
    rows = Vector{String}[]
    for d in DATASETS
        m = minsups(RUNTIME, d)[end]
        function mid(tool)
            runs = sort([r for r in raw if r["dataset"] == d && r["minsup_pct"] == m && r["tool"] == tool];
                        by = r -> num(r["time_with_write_s"]))
            return runs[(length(runs) + 1) ÷ 2]
        end
        o, s = mid("ours_opt"), mid("spmf")
        t, rd, mi, wr, sp = num(o["time_with_write_s"]), num(o["read_s"]), num(o["mine_s"]), num(o["write_s"]),
                            num(s["time_with_write_s"])
        push!(rows, [d, pct(m), @sprintf("%.3f", rd), @sprintf("%.3f", mi), @sprintf("%.3f", wr), @sprintf("%.3f", t),
                     @sprintf("%.3f", sp), @sprintf("%.2f", t / sp), @sprintf("%.2f", mi / sp)])
    end
    save_table("runtime_breakdown_table", ["Dataset", "minsup", "Đọc", "Khai thác", "Ghi", "Tổng
nhóm", "SPMF",
                                           "Tổng /
SPMF", "Khai thác /
tổng SPMF"], rows; align = "llrrrrrrr")
end

"Thống kê 9 dataset benchmark (data/meta/dataset_statistics.csv)."
function datasets_table()
    st = read_csv_rows(joinpath(ROOT, "data", "meta", "dataset_statistics.csv"))
    rows = Vector{String}[]
    for d in DATASETS
        r = only(x for x in st if x["dataset"] == d)
        src = occursin("fimi", lowercase(r["source_url"])) ? "FIMI" : "SPMF"
        push!(rows, [d, d in DENSE ? "dày" : "thưa", thousands(int(r["n_transactions"])), thousands(int(r["n_unique_items"])),
                     @sprintf("%.1f", num(r["avg_transaction_length"])), r["max_transaction_length"],
                     @sprintf("%.3f", num(r["density_pct"])), src])
    end
    save_table("datasets_table", ["Dataset", "Loại", "Giao
dịch", "Item", "Độ dài
TB", "Độ dài
max", "Mật độ
(%)", "Nguồn"],
               rows; align = "llrrrrrl")
end

# ---------------------------------------------------------------------------
# 3. Số itemset theo minsup
# ---------------------------------------------------------------------------
# Hai ô: dữ liệu dày và thưa. Trục x là minsup (%) thang log, giảm dần từ trái sang phải; trục y log.
# Số itemset lấy từ phía nhóm (đã khớp SPMF 100% ở mục 1).

"""
Hai hình vừa một cột: itemsets_dense và itemsets_sparse (báo cáo), cùng một hình ghép hai ô itemsets_vs_minsup
(notebook); trả về hình ghép.
"""
function itemsets_figure()
    panels = Plots.Plot[]
    for (name, title, group) in (("dense", "Dữ liệu dày", DENSE), ("sparse", "Dữ liệu thưa", SPARSE))
        xs = [parse.(Float64, minsups(RUNTIME, d)) for d in group]
        ys = [[value(RUNTIME, d, m, "ours_opt", "n_itemsets") for m in minsups(RUNTIME, d)] for d in group]
        p = plot(title = title, xscale = :log10, yscale = :log10, xflip = true, legend = :bottomright,
                 xticks = log_ticks(vcat(xs...)), yticks = log_ticks(vcat(ys...)),
                 xlabel = "minsup (%, thang log), giảm dần", ylabel = "số closed itemsets")
        for (d, x, y) in zip(group, xs, ys)
            color, marker = DATASET_STYLE[d]
            plot!(p, x, y; label = d, color = color, marker = marker)
        end
        save_figure(plot(p; size = COL, left_margin = 1Plots.mm), "itemsets_$name")
        push!(panels, p)
    end
    save_figure(plot(panels...; layout = (1, 2), size = WIDE), "itemsets_vs_minsup")
end

# ---------------------------------------------------------------------------
# 4. Bộ nhớ: bản cơ bản và bản tối ưu
# ---------------------------------------------------------------------------
# Một mức minsup ở giữa danh sách của mỗi dataset. Mỗi biến thể chạy 3 lần trong tiến trình riêng; lấy trung vị.
#   peak_mem_mb  : RSS đỉnh của tiến trình (gồm khoảng 285 MB nền của Julia và mã đã biên dịch)
#   mem_delta_mb : peak - baseline, phần tăng thêm do dữ liệu và khai thác
#   alloc_mb     : tổng bộ nhớ cấp phát trong bước đọc file và khai thác (Base.gc_bytes)

const MEMORY = read_csv_rows(joinpath(RESULTS, "memory", "basic_vs_optimized.csv"))
mem_median(d, v, col) = median(num(r[col]) for r in MEMORY if r["dataset"] == d && r["variant"] == v)
mem_minsup(d) = first(r["minsup_pct"] for r in MEMORY if r["dataset"] == d)

function memory_figure()
    x = 1:length(DATASETS)
    w = 0.26
    labels = ["$d\n$(pct(mem_minsup(d)))" for d in DATASETS]
    pa = plot(title = "(a) RAM tối đa của tiến trình", ylabel = "MB", xticks = (x, labels), xtickfontsize = 6,
              legend = :topleft, xrotation = 0)
    deltas = [mem_median(d, v, "mem_delta_mb") for d in DATASETS for (v, _, _) in VARIANT]
    pb = plot(title = "(b) Phần tăng thêm do đọc dữ liệu và khai thác", ylabel = "MB (thang log)", xticks = (x, labels), xtickfontsize = 6,
              yscale = :log10, yticks = log_ticks(5, maximum(deltas)), ylims = (5, 1.15 * maximum(deltas)), legend = false)
    for (k, (v, label, color)) in enumerate(VARIANT)
        off = (k - 2) * w
        bar!(pa, x .+ off, [mem_median(d, v, "peak_mem_mb") for d in DATASETS];
             bar_width = w * 0.9, color = color, linewidth = 0, label = label)
        bar!(pb, x .+ off, [mem_median(d, v, "mem_delta_mb") for d in DATASETS];
             bar_width = w * 0.9, color = color, linewidth = 0, label = label, fillrange = 5)
    end
    base = median(num(r["baseline_mem_mb"]) for r in MEMORY)
    hline!(pa, [base]; color = INK, linestyle = :dash, linewidth = 1, label = @sprintf("nền Julia ≈ %.0f MB", base))
    save_figure(plot(pa, pb; layout = (2, 1), size = (WIDE[1], 440), left_margin = 2Plots.mm),
                "memory_basic_vs_optimized")
end

"""
Hình chính của Mục 2.5: RAM tối đa của cả tiến trình (peak RSS) của bản basic và optimized tại minsup giữa lưới, trung
vị 3 lần đo. Hình này không có trong scripts/plot_results.jl nên luôn được lưu (tên riêng, không trùng hình của main),
dùng font DejaVu Sans và màu giống các hình của main. Trục tung bắt đầu từ 0, không cắt trục để phóng đại chênh lệch.
"""
function peak_rss_figure()
    x = 1:length(DATASETS)
    w = 0.38
    labels = ["$d ($(pct(mem_minsup(d))))" for d in DATASETS]
    p = plot(; fontfamily = "DejaVu Sans", titlefontsize = 8, guidefontsize = 7, tickfontsize = 6, legendfontsize = 6,
             ylabel = "RAM tối đa của tiến trình (MB)", xticks = (x, labels), xrotation = 45, legend = :topleft,
             ylims = (0, 2200), size = (350, 260), left_margin = 2Plots.mm, bottom_margin = 2Plots.mm,
             gridalpha = 0.25, grid = :y)
    for (k, (v, label, color)) in enumerate((("basic", "basic", "#b0b0b0"), ("optimized", "optimized", "#4169e1")))
        bar!(p, x .+ (k - 1.5) * w, [mem_median(d, v, "peak_mem_mb") for d in DATASETS];
             bar_width = w * 0.95, color = color, linewidth = 0, label = label)
    end
    base = median(num(r["baseline_mem_mb"]) for r in MEMORY)
    hline!(p, [base]; color = INK, linestyle = :dash, linewidth = 1, label = @sprintf("mốc sau warm-up ≈ %.0f MB", base))
    for ext in ("pdf", "png")
        savefig(p, joinpath(FIGURES, "peak_rss_basic_optimized.$ext"))
    end
    println("Đã lưu results/figures/peak_rss_basic_optimized.{pdf,png}")
    return p
end

function memory_tables()
    rows = Vector{String}[]
    for d in DATASETS, (v, label, _) in VARIANT
        push!(rows, [v == "basic" ? d : "", v == "basic" ? pct(mem_minsup(d)) : "", VARIANT_SHORT[v],
                     @sprintf("%.0f", mem_median(d, v, "peak_mem_mb")), @sprintf("%.1f", mem_median(d, v, "mem_delta_mb")),
                     @sprintf("%.0f", mem_median(d, v, "alloc_mb")), @sprintf("%.3f", mem_median(d, v, "mine_s"))])
    end
    memory_md = save_table("memory_table", ["Dataset", "minsup", "Biến thể", "RAM tối đa
(MB)", "Tăng thêm
(MB)",
                                            "Cấp phát
(MB)", "Khai thác
(s)"], rows; align = "lllrrrr")

    # Ablation: thời gian khai thác của từng biến thể chia cho bản tối ưu (>1: chậm hơn bản tối ưu)
    variants = ["basic", "paper", "opt_no_prune_line8", "opt_no_fparray", "opt_no_early_termination",
                "opt_no_exact_count", "opt_no_reduced_cfitree"]
    rows = Vector{String}[]
    for d in DATASETS
        t_opt = mem_median(d, "optimized", "mine_s")
        push!(rows, [d, @sprintf("%.3f", t_opt), (@sprintf("%.2f", mem_median(d, v, "mine_s") / t_opt) for v in variants)...])
    end
    ablation_md = save_table("ablation_table", ["Dataset", "optimized
(s)", "basic", "pruning-
only", "Không
cắt nhánh",
                                                "Không
FP-array", "Không
kết thúc sớm", "Không
exact count",
                                                "Không CFI-tree
rút gọn"], rows; align = "lrrrrrrrr")
    return (memory = memory_md, ablation = ablation_md)
end

# ---------------------------------------------------------------------------
# 5. Scalability
# ---------------------------------------------------------------------------
# Retail 10%..100% giao dịch, hai mức minsup (nét liền và nét đứt). (a) thời gian tuyệt đối; (b) thời gian
# chia cho thời gian ở 100%, so với đường chéo y = x (tăng tuyến tính theo số giao dịch).

const MINSUP_LINE = Dict("0.1" => :solid, "0.05" => :dash, "0.5" => :solid, "0.2" => :dash)

function scalability_figure_and_table()
    sc = median_summary(joinpath(RESULTS, "scalability", "scalability.csv"), ["fraction_pct", "minsup_pct"])
    fracs = sort(unique(parse(Int, r["fraction_pct"]) for r in sc))
    t(f, m, tool) = num(only(r for r in sc if parse(Int, r["fraction_pct"]) == f && r["minsup_pct"] == m &&
                                              r["tool"] == tool)["time_s"])
    ms = sort(unique(r["minsup_pct"] for r in sc); by = x -> -parse(Float64, x))
    tmax = maximum(t(f, m, tool) for f in fracs, m in ms, tool in ("ours_opt", "spmf"))
    pa = plot(title = "Retail", xlabel = "% giao dịch của Retail", ylabel = "thời gian (s)",
              xticks = fracs, ylims = (0, 1.08 * tmax), legend = :topleft)
    pb = plot(title = "Retail", xlabel = "% giao dịch của Retail", ylabel = "thời gian / thời gian ở 100%",
              xticks = fracs, legend = :topleft, ylims = (0, 1.62), yticks = 0:0.25:1)
    plot!(pb, [0, 100], [0, 1]; color = INK, linestyle = :dot, linewidth = 1, label = "tuyến tính (y = x)")
    for tool in ("ours_opt", "spmf"), m in ms
        st = TOOL[tool]
        y = [t(f, m, tool) for f in fracs]
        lab = "$(first(split(st.label))), minsup $(pct(m))"
        plot!(pa, fracs, y; label = lab, color = st.color, marker = st.marker, linestyle = MINSUP_LINE[m])
        plot!(pb, fracs, y ./ y[end]; label = lab, color = st.color, marker = st.marker, linestyle = MINSUP_LINE[m])
    end
    # báo cáo: hai hình vừa một cột; notebook: hình ghép hai ô
    save_figure(plot(pa; size = COL, left_margin = 1Plots.mm), "scalability_time")
    save_figure(plot(pb; size = COL, left_margin = 1Plots.mm), "scalability_ratio")
    fig = save_figure(plot(pa, pb; layout = (1, 2), size = WIDE), "scalability")

    rows = Vector{String}[]
    for f in fracs
        r = first(x for x in sc if parse(Int, x["fraction_pct"]) == f)
        push!(rows, ["$f%", thousands(int(r["n_transactions"])),
                     (@sprintf("%.3f", t(f, m, tool)) for m in ms for tool in ("ours_opt", "spmf"))...])
    end
    short = Dict("ours_opt" => "Nhóm", "spmf" => "SPMF")
    table = save_table("scalability_table", ["Kích
thước", "Giao
dịch",
                       ("$(short[tool])
$(pct(m))" for m in ms for tool in ("ours_opt", "spmf"))...],
                       rows; align = "lr" * "r"^(2 * length(ms)))
    return (figure = fig, table = table)
end

# ---------------------------------------------------------------------------
# 6. Độ dài giao dịch
# ---------------------------------------------------------------------------
# Synthetic len05..len30 (10.000 giao dịch, 500 item), hai mức minsup. (a) thời gian; (b) số closed itemsets.

function txlen_figure_and_table()
    tx = median_summary(joinpath(RESULTS, "txlen", "txlen.csv"), ["avg_length", "minsup_pct"])
    lens = sort(unique(parse(Float64, r["avg_length"]) for r in tx))
    get(l, m, tool, col) = num(only(r for r in tx if parse(Float64, r["avg_length"]) == l && r["minsup_pct"] == m &&
                                                     r["tool"] == tool)[col])
    ms = sort(unique(r["minsup_pct"] for r in tx); by = x -> -parse(Float64, x))
    pa = plot(title = "CSDL tổng hợp", xlabel = "độ dài giao dịch trung bình",
              ylabel = "thời gian (s, thang log)", yscale = :log10, xticks = lens, legend = :topleft,
              yticks = log_ticks([get(l, m, tool, "time_s") for l in lens, m in ms, tool in ("ours_opt", "spmf")]))
    pb = plot(title = "CSDL tổng hợp", xlabel = "độ dài giao dịch trung bình",
              ylabel = "số closed itemsets (thang log)", yscale = :log10, xticks = lens, legend = :topleft,
              yticks = log_ticks([get(l, m, "ours_opt", "n_itemsets") for l in lens, m in ms]))
    for tool in ("ours_opt", "spmf"), m in ms
        st = TOOL[tool]
        plot!(pa, lens, [get(l, m, tool, "time_s") for l in lens]; label = "$(first(split(st.label))), minsup $(pct(m))",
              color = st.color, marker = st.marker, linestyle = MINSUP_LINE[m])
    end
    for m in ms
        plot!(pb, lens, [get(l, m, "ours_opt", "n_itemsets") for l in lens]; label = "minsup $(pct(m))",
              color = INK, marker = :circle, linestyle = MINSUP_LINE[m])
    end
    save_figure(plot(pa; size = COL, left_margin = 1Plots.mm), "txlen_time")
    save_figure(plot(pb; size = COL, left_margin = 1Plots.mm), "txlen_itemsets")
    fig = save_figure(plot(pa, pb; layout = (1, 2), size = WIDE), "txlen")

    rows = Vector{String}[]
    for l in lens, m in ms
        push!(rows, [@sprintf("%.0f", l), pct(m), thousands(Int(get(l, m, "ours_opt", "n_itemsets"))),
                     @sprintf("%.3f", get(l, m, "ours_opt", "time_s")), @sprintf("%.3f", get(l, m, "spmf", "time_s")),
                     @sprintf("%.2f", get(l, m, "ours_opt", "time_s") / get(l, m, "spmf", "time_s"))])
    end
    table = save_table("txlen_table", ["Độ dài
TB", "minsup", "Closed
itemsets", "Nhóm
(s)", "SPMF
(s)", "Nhóm /
SPMF"],
                       rows; align = "rrrrrr")
    return (figure = fig, table = table)
end

# ---------------------------------------------------------------------------
# Chạy bằng dòng lệnh: sinh mọi hình và bảng. Khi `include` từ notebooks/chapter2_results.ipynb thì chỉ nạp các
# hàm, notebook tự gọi từng hàm.

function main()
    datasets_table()
    correctness_table()
    runtime_figure()
    runtime_ratio_table()
    runtime_breakdown_table()
    itemsets_figure()
    memory_figure()
    peak_rss_figure()
    memory_tables()
    scalability_figure_and_table()
    txlen_figure_and_table()
    println("Xong. Bảng nằm trong ", TABLES)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
