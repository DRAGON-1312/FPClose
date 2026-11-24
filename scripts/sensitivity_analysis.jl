# Phân tích độ nhạy theo cách tổng hợp 3 lần đo: tính tỉ lệ thời gian nhóm/SPMF bằng giá trị nhỏ nhất (cách dùng
# trong báo cáo) và bằng trung vị, trên mọi cấu hình so sánh với SPMF (grid minsup, scalability, độ dài giao dịch).
# Thời gian là cột time_with_write_s (gồm đọc và ghi file), chỉ lấy các lần đo có status OK.
#
#   r = T_nhóm / T_SPMF, phân nhóm: r < 0,90 nhanh hơn | 0,90 <= r <= 1,10 gần tương đương | r > 1,10 chậm hơn
#   ratio_change_pct     = |r_median - r_min| / r_min × 100
#   *_relative_range_pct = (T_max - T_min) / T_min × 100 (khoảng biến thiên tương đối của 3 lần đo)
#
#   julia --project=. scripts/sensitivity_analysis.jl [--out results/runtime/runtime_sensitivity.csv]
using Printf

const ROOT = normpath(joinpath(@__DIR__, ".."))
const OURS = "ours_opt"
const SOURCES = [("grid", joinpath("results", "runtime", "grid_runtime.csv")),
                 ("scalability", joinpath("results", "scalability", "scalability.csv")),
                 ("txlen", joinpath("results", "txlen", "txlen.csv"))]

function median_of(x::Vector{Float64})
    s = sort(x)
    n = length(s)
    return isodd(n) ? s[(n+1)÷2] : (s[n÷2] + s[n÷2+1]) / 2
end

category(r) = r < 0.90 ? "faster" : (r > 1.10 ? "slower" : "similar")
rel_range(x) = 100 * (maximum(x) - minimum(x)) / minimum(x)

function read_rows(path)
    lines = readlines(path)
    hdr = String.(split(lines[1], ','))
    return [Dict(zip(hdr, String.(split(l, ',')))) for l in lines[2:end] if !isempty(strip(l))]
end

function main(args)
    out = joinpath(ROOT, "results", "runtime", "runtime_sensitivity.csv")
    i = findfirst(==("--out"), args)
    i === nothing || (out = args[i+1])
    mkpath(dirname(out))
    rows = String[]
    stats = Dict{String,Vector{Float64}}("ours" => Float64[], "spmf" => Float64[])
    grid_ranges = Dict{String,Vector{Float64}}("ours" => Float64[], "spmf" => Float64[])
    n = flips = changed = 0
    worst = (0.0, "")
    for (exp, rel) in SOURCES
        raw = read_rows(joinpath(ROOT, rel))
        keys = unique((r["dataset"], r["minsup_pct"]) for r in raw)
        for (ds, ms) in keys
            t(tool) = [parse(Float64, r["time_with_write_s"]) for r in raw
                       if r["dataset"] == ds && r["minsup_pct"] == ms && r["tool"] == tool && r["status"] == "OK"]
            a, b = t(OURS), t("spmf")
            (isempty(a) || isempty(b)) && continue
            r0 = first(r for r in raw if r["dataset"] == ds && r["minsup_pct"] == ms)
            size = get(r0, "n_transactions", "")
            avglen = get(r0, "avg_length", "")
            rmin = minimum(a) / minimum(b)
            rmed = median_of(a) / median_of(b)
            chg = 100 * abs(rmed - rmin) / rmin
            dir = (rmin < 1) != (rmed < 1)
            cat = category(rmin) != category(rmed)
            n += 1
            flips += dir
            changed += cat
            chg > worst[1] && (worst = (chg, "$exp $ds $ms"))
            for (k, x) in (("ours", a), ("spmf", b))
                push!(stats[k], rel_range(x))
                exp == "grid" && push!(grid_ranges[k], rel_range(x))
            end
            push!(rows, join((exp, ds, ms, size, avglen,
                              @sprintf("%.5f", minimum(a)), @sprintf("%.5f", median_of(a)),
                              @sprintf("%.5f", minimum(b)), @sprintf("%.5f", median_of(b)),
                              @sprintf("%.4f", rmin), @sprintf("%.4f", rmed), @sprintf("%.2f", chg),
                              @sprintf("%.2f", rel_range(a)), @sprintf("%.2f", rel_range(b)),
                              category(rmin), category(rmed), dir, cat), ','))
        end
    end
    open(out, "w") do io
        println(io, "experiment,dataset,minsup_pct,dataset_size,avg_tx_length,ours_min_s,ours_median_s,spmf_min_s,",
                "spmf_median_s,ratio_min,ratio_median,ratio_change_pct,ours_relative_range_pct,",
                "spmf_relative_range_pct,category_min,category_median,direction_changed,category_changed")
        foreach(r -> println(io, r), rows)
    end
    pct_le(x, v) = 100 * count(<=(v), x) / length(x)
    @printf("Cấu hình: %d | đảo chiều quanh 1,0: %d | đổi nhóm ±10%%: %d | giữ nhóm: %d/%d\n",
            n, flips, changed, n - changed, n)
    @printf("Thay đổi tỉ lệ lớn nhất: %.2f%% (%s)\n", worst...)
    for (lbl, s) in (("grid (56)", grid_ranges), ("cả 78", stats))
        @printf("Khoảng biến thiên %s: trung vị nhóm %.1f%%, SPMF %.1f%% | <= 20%%: nhóm %.0f%%, SPMF %.0f%%, chung %.0f%%\n",
                lbl, median_of(s["ours"]), median_of(s["spmf"]), pct_le(s["ours"], 20), pct_le(s["spmf"], 20),
                pct_le(vcat(s["ours"], s["spmf"]), 20))
    end
    println("Đã ghi ", out)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
