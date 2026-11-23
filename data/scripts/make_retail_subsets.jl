# Sinh 5 Retail subsets lồng nhau cho thí nghiệm scalability.
#
#   julia data/scripts/make_retail_subsets.jl --src data/benchmark/retail.txt --outdir data/scalability
#
# Cách làm (giống bản đã công bố): xáo trộn CHỈ SỐ giao dịch một lần bằng
# `random.Random(seed).shuffle` (bản port trong pyrandom.jl), rồi lấy prefix
# n*p÷100 phần tử cho p = 10, 25, 50, 75, 100. Vì cùng một hoán vị nên tập nhỏ
# luôn nằm trong tập lớn (lồng nhau). Thứ tự dòng trong file theo thứ tự hoán vị.

isdefined(@__MODULE__, :sha256_file) || include(joinpath(@__DIR__, "common.jl"))
isdefined(@__MODULE__, :PyRandom) || include(joinpath(@__DIR__, "pyrandom.jl"))

const RETAIL_PERCENTAGES = (10, 25, 50, 75, 100)
const RETAIL_N = 88162

"""
    make_retail_subsets(src, outdir; seed = 2026) -> Vector{NamedTuple}

Ghi `retail_p010.txt` … `retail_p100.txt` vào `outdir`, trả về tên file, số giao dịch, SHA-256.
"""
function make_retail_subsets(src::AbstractString, outdir::AbstractString; seed::Integer = 2026)
    transactions = String[]
    for line in eachline(src)
        s = strip(line)
        isempty(s) || push!(transactions, String(s))
    end
    length(transactions) == RETAIL_N ||
        error("retail.txt có $(length(transactions)) giao dịch, mong đợi $RETAIL_N")

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

function main(args)
    opts = parse_options(args, Dict(
        "src" => joinpath(repo_root(), "data", "benchmark", "retail.txt"),
        "outdir" => joinpath(repo_root(), "data", "scalability"),
        "seed" => "2026"))
    for r in make_retail_subsets(opts["src"], opts["outdir"]; seed = parse(Int, opts["seed"]))
        println(r.dataset, "  ", r.n_transactions, "  ", r.sha256)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
