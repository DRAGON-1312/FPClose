# Tải 9 dataset công khai từ Hugging Face và so SHA-256, số giao dịch với
# data/results/benchmark_inventory.csv. Không cần token (repo public).
#
#   julia data/scripts/verify_hf.jl --outdir data/benchmark
#
# File đã có trong --outdir và đúng hash thì không tải lại.

isdefined(@__MODULE__, :sha256_file) || include(joinpath(@__DIR__, "common.jl"))
using Downloads

const HF_REPO = "hytrang/fpclose-fim-benchmarks"
hf_url(name) = "https://huggingface.co/datasets/$HF_REPO/resolve/main/$name"

"""
    verify_hf(inventory, outdir; names = nothing) -> Bool

Trả về `true` nếu mọi file khớp hash và số giao dịch. `names` giới hạn danh sách dataset.
"""
function verify_hf(inventory::AbstractString, outdir::AbstractString; names = nothing)
    mkpath(outdir)
    ok = true
    for row in read_csv_rows(inventory)
        name = row["dataset"]
        names === nothing || name in names || continue
        file = joinpath(outdir, "$name.txt")
        expected = lowercase(row["sha256"])
        if !(isfile(file) && sha256_file(file) == expected)
            Downloads.download(hf_url("$name.txt"), file)
        end
        actual = sha256_file(file)
        lines = countlines(file)
        good = actual == expected && lines == parse(Int, row["transactions"])
        ok &= good
        println(good ? "[PASS] " : "[FAIL] ", rpad(name, 12), lines, " giao dịch  ", actual)
    end
    return ok
end

function main(args)
    opts = parse_options(args, Dict(
        "inventory" => joinpath(repo_root(), "data", "results", "benchmark_inventory.csv"),
        "outdir" => joinpath(repo_root(), "data", "benchmark")))
    verify_hf(opts["inventory"], opts["outdir"]) || (println("Có file không khớp."); exit(1))
    println("Tất cả file khớp SHA-256 và số giao dịch.")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
