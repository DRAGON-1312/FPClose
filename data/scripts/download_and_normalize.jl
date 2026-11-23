# Tải 9 dataset gốc từ SPMF/FIMI rồi chuẩn hóa, so với hồ sơ đã lưu.
#
#   julia data/scripts/download_and_normalize.jl
#   julia data/scripts/download_and_normalize.jl --only retail,kosarak
#
# Đọc URL, tên file raw, SHA-256 raw/clean và số giao dịch từ
# data/results/dataset_statistics.csv. Với mỗi dataset:
#   1. tải raw vào --rawdir (bỏ qua nếu đã có và đúng hash), so SHA-256 raw;
#   2. chuẩn hóa bằng normalize.jl với offset trong DATASET_OFFSETS;
#   3. so số giao dịch và SHA-256 bản chuẩn hóa với hồ sơ.
# Raw khác hash (nguồn đã đổi) vẫn được chuẩn hóa nhưng báo rõ để biết nguyên nhân.

isdefined(@__MODULE__, :sha256_file) || include(joinpath(@__DIR__, "common.jl"))
isdefined(@__MODULE__, :normalize_transactions) || include(joinpath(@__DIR__, "normalize.jl"))
using Downloads

"Item-ID offset đã dùng cho từng dataset (xem MANIFEST.md)."
const DATASET_OFFSETS = Dict(
    "chess" => 0, "mushrooms" => 0, "retail" => 0, "T10I4D100K" => 0, "accidents" => 0,
    "connect" => 0, "kosarak" => 0, "pumsb_star" => 1, "T40I10D100K" => 1)

"""
    download_and_normalize(statistics, rawdir, outdir; only = nothing) -> Vector{NamedTuple}

Trả về một dòng kết quả cho mỗi dataset: raw_ok, clean_ok, số giao dịch, số dòng đã khử item trùng.
"""
function download_and_normalize(statistics::AbstractString, rawdir::AbstractString,
        outdir::AbstractString; only = nothing)
    mkpath(rawdir)
    mkpath(outdir)
    results = NamedTuple[]
    for row in read_csv_rows(statistics)
        name = row["dataset"]
        only === nothing || name in only || continue
        raw = joinpath(rawdir, row["raw_filename"])
        raw_expected = lowercase(row["raw_sha256"])
        if !(isfile(raw) && sha256_file(raw) == raw_expected)
            println("Tải ", row["source_url"])
            Downloads.download(row["source_url"], raw)
        end
        raw_ok = sha256_file(raw) == raw_expected

        dst = joinpath(outdir, "$name.txt")
        r = normalize_transactions(raw, dst; offset = DATASET_OFFSETS[name])
        clean = sha256_file(dst)
        clean_ok = clean == lowercase(row["clean_sha256"]) &&
                   r.n_transactions == parse(Int, row["n_transactions"])
        push!(results, (dataset = name, raw_ok = raw_ok, gzip = is_gzip(raw),
            offset = DATASET_OFFSETS[name], n_transactions = r.n_transactions,
            dedup_rows = r.n_dedup_rows, metadata_removed = r.n_metadata,
            clean_ok = clean_ok, clean_sha256 = clean))
        println(clean_ok ? "[PASS] " : "[FAIL] ", rpad(name, 12),
            "raw=", raw_ok ? "khớp" : "KHÁC", "  gzip=", is_gzip(raw),
            "  offset=", DATASET_OFFSETS[name], "  n=", r.n_transactions,
            "  dedup_rows=", r.n_dedup_rows)
    end
    return results
end

function main(args)
    opts = parse_options(args, Dict(
        "statistics" => joinpath(repo_root(), "data", "results", "dataset_statistics.csv"),
        "rawdir" => joinpath(repo_root(), "data", "raw"),
        "outdir" => joinpath(repo_root(), "data", "benchmark"),
        "only" => ""))
    only = isempty(opts["only"]) ? nothing : split(opts["only"], ',')
    results = download_and_normalize(opts["statistics"], opts["rawdir"], opts["outdir"]; only = only)
    all(r -> r.clean_ok, results) || (println("Có dataset không khớp hồ sơ."); exit(1))
    println("Tất cả dataset khớp SHA-256 và số giao dịch đã ghi.")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
