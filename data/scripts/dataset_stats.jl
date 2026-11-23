# Thống kê cho các file giao dịch đã chuẩn hóa.
#
#   julia data/scripts/dataset_stats.jl --dir data/benchmark --out out/dataset_stats.csv
#   julia data/scripts/dataset_stats.jl --dir data/scalability --out data/results/derived_hashes.csv
#
# Cột: dataset, n_transactions, n_unique_items, avg_transaction_length,
#      max_transaction_length, density_pct, sha256.
# density_pct = avg_transaction_length / n_unique_items × 100 (đơn vị %, khác cột
# `density` dạng tỉ lệ trong synthetic_statistics.csv).

isdefined(@__MODULE__, :sha256_file) || include(joinpath(@__DIR__, "common.jl"))

const STATS_HEADER = ["dataset", "n_transactions", "n_unique_items", "avg_transaction_length",
    "max_transaction_length", "density_pct", "sha256"]

"Thống kê một file; đọc từng dòng nên dùng được cả với kosarak (~1 triệu giao dịch)."
function dataset_stats(path::AbstractString)
    n = 0
    total = 0
    maxlen = 0
    items = Set{Int}()
    for line in eachline(path)
        s = strip(line)
        isempty(s) && error("Dòng trống trong $path")
        k = 0
        for tok in eachsplit(s)
            push!(items, parse(Int, tok))
            k += 1
        end
        n += 1
        total += k
        maxlen = max(maxlen, k)
    end
    avg = total / n
    return (dataset = splitext(basename(path))[1], n_transactions = n,
        n_unique_items = length(items), avg_transaction_length = round(avg; digits = 4),
        max_transaction_length = maxlen,
        density_pct = round(avg / length(items) * 100; digits = 6), sha256 = sha256_file(path))
end

stats_row(s) = [getfield(s, Symbol(h)) for h in STATS_HEADER]

function main(args)
    opts = parse_options(args, Dict("dir" => joinpath(repo_root(), "data", "benchmark"), "out" => ""))
    files = sort(filter(f -> endswith(f, ".txt"), readdir(opts["dir"]; join = true)))
    isempty(files) && error("Không có file .txt trong $(opts["dir"])")
    rows = [stats_row(dataset_stats(f)) for f in files]
    if isempty(opts["out"])
        println(join(STATS_HEADER, ','))
        foreach(r -> println(join(string.(r), ',')), rows)
    else
        write_csv(opts["out"], STATS_HEADER, rows)
        println("Đã ghi ", length(rows), " dòng vào ", opts["out"])
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
