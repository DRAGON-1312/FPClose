# Sinh 6 synthetic datasets cho thí nghiệm ảnh hưởng của độ dài giao dịch.
#
#   julia data/scripts/gen_synthetic.jl --outdir data/synthetic
#
# Cơ chế (giống bản đã công bố, seed 2026):
#   - 500 item; 200 pattern 4 item: 125 pattern đầu chia đều toàn bộ 500 item
#     (sau một lần xáo trộn), 75 pattern sau lấy ngẫu nhiên.
#   - Pattern được chọn theo trọng số 1/(i+1)^0.8 (vài pattern rất phổ biến).
#   - 10.000 giao dịch "nền" dài 32 item: 1–3 pattern + item ngẫu nhiên cho đủ 32.
#   - len05..len30: giao dịch thứ i lấy PREFIX của giao dịch nền thứ i, độ dài
#     dao động quanh mức đích (±1 với len05, ±2 với các mức khác), trung bình đúng
#     bằng mức đích. Vì là prefix của cùng giao dịch nền nên các mức lồng nhau.
# Đây là dữ liệu có tương quan (correlated), không phải ngẫu nhiên độc lập.

isdefined(@__MODULE__, :sha256_file) || include(joinpath(@__DIR__, "common.jl"))
isdefined(@__MODULE__, :PyRandom) || include(joinpath(@__DIR__, "pyrandom.jl"))

const SYN_N_TRANSACTIONS = 10_000
const SYN_N_ITEMS = 500
const SYN_MAX_LENGTH = 32
const SYN_TARGETS = (5, 10, 15, 20, 25, 30)

"Sinh 10.000 giao dịch nền (mỗi giao dịch 32 item, giữ thứ tự sinh)."
function synthetic_master(seed::Integer)
    pool_rng = PyRandom(seed)
    item_ids = collect(1:SYN_N_ITEMS)
    pyshuffle!(pool_rng, item_ids)
    patterns = [item_ids[i:i+3] for i in 1:4:SYN_N_ITEMS]
    for _ in 1:75
        push!(patterns, pysample_range!(pool_rng, 1, SYN_N_ITEMS + 1, 4))
    end
    length(patterns) == 200 || error("Số pattern phải là 200")

    weights = [1.0 / cpow(Float64(i + 1), 0.8) for i in 0:length(patterns)-1]
    cum_patterns = cumulative(weights)
    cum_npatterns = cumulative([25, 50, 25])   # cho n_patterns ∈ (1, 2, 3)

    rng = PyRandom(seed + 1)
    master = Vector{Vector{Int}}(undef, SYN_N_TRANSACTIONS)
    for t in 0:SYN_N_TRANSACTIONS-1
        transaction = Int[]
        seen = Set{Int}()
        n_patterns = (1, 2, 3)[pychoice_index!(rng, cum_npatterns)+1]
        first_pattern = t < 125 ? t : pychoice_index!(rng, cum_patterns)
        selected = [first_pattern]
        for _ in 1:n_patterns-1
            push!(selected, pychoice_index!(rng, cum_patterns))
        end
        for pid in selected, item in patterns[pid+1]
            if !(item in seen)
                push!(seen, item)
                push!(transaction, item)
            end
        end
        while length(transaction) < SYN_MAX_LENGTH
            item = pyrandint!(rng, 1, SYN_N_ITEMS)
            if !(item in seen)
                push!(seen, item)
                push!(transaction, item)
            end
        end
        master[t+1] = transaction
    end
    return master
end

"""
    gen_synthetic(outdir; seed = 2026) -> Vector{NamedTuple}

Ghi `len05.txt` … `len30.txt` và `synthetic_statistics.csv` vào `outdir`.
"""
function gen_synthetic(outdir::AbstractString; seed::Integer = 2026)
    mkpath(outdir)
    master = synthetic_master(seed)
    stats = NamedTuple[]
    previous = nothing
    for target in SYN_TARGETS
        offsets = target == 5 ? (-1, -1, 0, 1, 1) : (-2, -1, 0, 1, 2)
        per = SYN_N_TRANSACTIONS ÷ length(offsets)
        lengths = [target + o for o in offsets for _ in 1:per]
        pyshuffle!(PyRandom(seed + target), lengths)

        file = joinpath(outdir, "len$(lpad(target, 2, '0')).txt")
        current = Vector{Set{Int}}(undef, SYN_N_TRANSACTIONS)
        unique_items = Set{Int}()
        open(file, "w") do io
            for (i, len) in enumerate(lengths)
                items = sort(master[i][1:len])
                current[i] = Set(items)
                union!(unique_items, items)
                println(io, join(items, ' '))
            end
        end
        if previous !== nothing
            all(issubset(a, b) for (a, b) in zip(previous, current)) ||
                error("len$target không chứa mức trước (không lồng nhau)")
        end
        previous = current
        avg = sum(lengths) / SYN_N_TRANSACTIONS
        avg == target || error("Độ dài trung bình $avg ≠ $target")
        length(unique_items) == SYN_N_ITEMS || error("Không phủ đủ $SYN_N_ITEMS item")
        push!(stats, (dataset = basename(file), n_transactions = SYN_N_TRANSACTIONS,
            n_items = length(unique_items), avg_length = avg,
            min_length = minimum(lengths), max_length = maximum(lengths),
            density = avg / SYN_N_ITEMS, seed = seed, sha256 = sha256_file(file)))
    end
    header = ["dataset", "n_transactions", "n_items", "avg_length", "min_length",
        "max_length", "density", "seed", "sha256"]
    write_csv(joinpath(outdir, "synthetic_statistics.csv"), header,
        [[getfield(s, Symbol(h)) for h in header] for s in stats])
    return stats
end

function main(args)
    opts = parse_options(args, Dict(
        "outdir" => joinpath(repo_root(), "data", "synthetic"),
        "seed" => "2026"))
    for s in gen_synthetic(opts["outdir"]; seed = parse(Int, opts["seed"]))
        println(s.dataset, "  avg=", s.avg_length, "  ", s.sha256)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
