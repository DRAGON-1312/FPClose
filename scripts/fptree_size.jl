# Tỉ lệ kích thước FP-tree gốc: R_tree = số nút (không tính gốc) / tổng lượt xuất hiện item phổ biến × 100%.
# Mẫu số là tổng, trên mọi giao dịch, số item phổ biến (support >= minsup_count) còn lại sau khi lọc; đó cũng là
# số nút tối đa nếu không giao dịch nào chia sẻ tiền tố. R_tree nhỏ = nhiều tiền tố chung = cây nén tốt.
# Đo ở minsup giữa lưới của mỗi CSDL (cùng mức với thực nghiệm bộ nhớ), minsup_count lấy từ benchmark_config.csv.
#
#   julia --project scripts/fptree_size.jl [--out results/fptree/fptree_size.csv]
using FPClose
using Printf

const ROOT = normpath(joinpath(@__DIR__, ".."))
const MID = Dict("chess" => 75.0, "mushrooms" => 7.0, "connect" => 85.0, "pumsb_star" => 50.0,
                 "accidents" => 70.0, "retail" => 0.2, "T10I4D100K" => 0.2, "T40I10D100K" => 2.0,
                 "kosarak" => 0.4)
const ORDER = ["chess", "mushrooms", "connect", "pumsb_star", "accidents",
               "retail", "T10I4D100K", "T40I10D100K", "kosarak"]

function config_counts()
    lines = readlines(joinpath(ROOT, "data", "meta", "benchmark_config.csv"))
    hdr = split(lines[1], ',')
    id, ip, ic = findfirst(==("dataset"), hdr), findfirst(==("minsup_pct"), hdr), findfirst(==("minsup_count"), hdr)
    d = Dict{Tuple{String,Float64},Int}()
    for l in lines[2:end]
        f = split(l, ',')
        d[(String(f[id]), parse(Float64, f[ip]))] = parse(Int, f[ic])
    end
    return d
end

function count_nodes(t::FPTree)
    s = 0
    for item in t.items, _ in FPClose.nodelink(t, item)
        s += 1
    end
    return s
end

function main(args)
    out = joinpath(ROOT, "results", "fptree", "fptree_size.csv")
    i = findfirst(==("--out"), args)
    i === nothing || (out = args[i+1])
    cfg = config_counts()
    mkpath(dirname(out))
    open(out, "w") do io
        println(io, "dataset,minsup_pct,minsup_count,n_transactions,frequent_items,nodes,frequent_occurrences,ratio_pct")
        for ds in ORDER
            db = read_spmf(joinpath(ROOT, "data", "benchmark", ds * ".txt"))
            pct = MID[ds]
            sigma = cfg[(ds, pct)]
            tree = build_fptree(db, sigma)
            nodes = count_nodes(tree)
            occ = sum(t -> count(x -> haskey(tree.rank, x), unique(t)), db)
            r = 100 * nodes / occ
            @printf(io, "%s,%g,%d,%d,%d,%d,%d,%.4f\n", ds, pct, sigma, length(db), length(tree.items), nodes, occ, r)
            @printf("%-12s minsup %5g%%  items %5d  nodes %10d  occ %11d  R_tree %7.3f%%\n",
                    ds, pct, length(tree.items), nodes, occ, r)
        end
    end
    println("Đã ghi ", out)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
