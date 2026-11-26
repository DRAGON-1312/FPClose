# Kiểm tra dữ liệu benchmark đã chuẩn hóa: số giao dịch, số giao dịch phân biệt về nội dung, số lượt lặp, miền mã
# item, offset đã dùng khi chuẩn hóa và SHA-256 của file. Thêm một dòng cho bản mushrooms của SPMF (file thô) để
# làm căn cứ cho số liệu "8 416 giao dịch, 8 124 phân biệt, 292 lượt lặp" ở Mục 2.1 của báo cáo.
#
# duplicate_occurrences = transaction_count - unique_transactions: một giao dịch xuất hiện k lần đóng góp k - 1
# lượt lặp. Giao dịch được so theo tập item (đã sắp, bỏ item trùng trong dòng).
#
#   julia --project=. scripts/verify_datasets.jl [--out results/dataset_validation.csv]
using SHA
using Printf

const ROOT = normpath(joinpath(@__DIR__, ".."))
const ORDER = ["chess", "mushrooms", "connect", "pumsb_star", "accidents",
               "retail", "T10I4D100K", "T40I10D100K", "kosarak"]

"Đọc dataset_statistics.csv: dataset => (source_url, id_offset)."
function meta()
    lines = readlines(joinpath(ROOT, "data", "meta", "dataset_statistics.csv"))
    hdr = split(lines[1], ',')
    col(name) = findfirst(==(name), hdr)
    iu, io = col("source_url"), col("id_offset")
    d = Dict{String,Tuple{String,Int}}()
    for l in lines[2:end]
        f = split(l, ',')
        d[String(f[1])] = (String(f[iu]), parse(Int, f[io]))
    end
    return d
end

"Thống kê một file giao dịch; bỏ dòng trống và dòng metadata (#, @, %) như data_setup.jl."
function scan(path::AbstractString)
    n = 0
    seen = Set{Vector{Int}}()
    items = Set{Int}()
    for line in eachline(path)
        s = strip(lstrip(line, '﻿'))
        (isempty(s) || s[1] in ('#', '@', '%')) && continue
        t = sort!(unique!(parse.(Int, split(s))))
        n += 1
        push!(seen, t)
        union!(items, t)
    end
    return n, length(seen), length(items), minimum(items), maximum(items)
end

sha_hex(path) = open(io -> bytes2hex(sha256(io)), path)

function main(args)
    out = joinpath(ROOT, "results", "dataset_validation.csv")
    i = findfirst(==("--out"), args)
    i === nothing || (out = args[i+1])
    m = meta()
    rows = Tuple{String,String,String}[]
    for ds in ORDER
        push!(rows, (ds, m[ds][1], joinpath(ROOT, "data", "benchmark", ds * ".txt")))
    end
    push!(rows, ("mushrooms_spmf_raw", "SPMF (không dùng trong thực nghiệm)",
                 joinpath(ROOT, "data", "raw", "mushrooms.txt")))
    mkpath(dirname(out))
    open(out, "w") do io
        println(io, "dataset,source,transaction_count,unique_transactions,duplicate_occurrences,distinct_items,",
                "min_item_id,max_item_id,id_offset,sha256")
        for (ds, src, path) in rows
            n, u, k, lo, hi = scan(path)
            off = haskey(m, ds) ? string(m[ds][2]) : ""
            h = sha_hex(path)
            println(io, join((ds, src, n, u, n - u, k, lo, hi, off, h), ','))
            @printf("%-20s tx %8d  unique %8d  dup %7d  items %6d  id %d..%d  offset %s\n",
                    ds, n, u, n - u, k, lo, hi, off)
        end
    end
    println("Đã ghi ", out)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
