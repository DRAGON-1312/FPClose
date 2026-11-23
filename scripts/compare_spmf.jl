# So kết quả của nhóm với SPMF trên cùng input và minsup.
#
#   Một file, một ngưỡng:
#     julia --project scripts/compare_spmf.jl [--mode closed|all|both] [--baseline] [--jar J] <input.txt> <minsup>
#   Bảng cho nhiều file và nhiều ngưỡng (mặc định mọi data/toy/*.txt, ngưỡng 60%,40%,20%,7%):
#     julia --project scripts/compare_spmf.jl --table [--dir data/toy] [--minsups 40%,20%] [--csv out/x.csv]
#
#   <minsup>    dạng SPMF, ví dụ "40%" (hoặc tỉ lệ "0.4").
#   --mode      closed (mặc định): FPClose của nhóm so với SPMF `FPClose` (closed frequent itemsets).
#               all: recovery (src/recovery.jl) so với SPMF `FPGrowth_itemsets` (MỌI frequent itemset).
#               both: cả hai.
#   --baseline  chạy FPClose bản cơ bản (không FP-array, không kết thúc sớm) thay cho bản mặc định.
#   --jar       đường dẫn spmf.jar (mặc định tools/spmf.jar, tải theo README; cần Java 25).
#
# SPMF chỉ dùng để đối chiếu kết quả, không phải một phần của cài đặt.
# Output của SPMF có dòng metadata bắt đầu bằng "@" và item trong mỗi itemset không được sắp,
# nên cả hai phía được chuẩn hóa trước khi so: bỏ dòng "@...", sắp item trong từng itemset, so
# theo tập (itemset, support) nên thứ tự dòng không ảnh hưởng. Mã thoát: 0 nếu khớp hoàn toàn,
# 1 nếu có lệch, 2 nếu SPMF lỗi hoặc tham số sai.
# Output thô: out/spmf_<mode>_<tên>_<minsup>.txt và out/ours_<mode>_<tên>_<minsup>.txt.

using FPClose

const ROOT = normpath(joinpath(@__DIR__, ".."))
const SPMF_ALGORITHM = Dict(:closed => "FPClose", :all => "FPGrowth_itemsets")
const RECOVERY_LIMIT = 5_000_000      # chặn recovery nổ bộ nhớ trên dữ liệu dày

"""
Đọc output dạng `items #SUP: n` thành `Dict(itemset đã sắp => support)`; bỏ dòng "@..." và
dòng trống. Báo lỗi nếu có dòng không đúng định dạng hoặc itemset xuất hiện hai lần.
"""
function read_normalized(path::AbstractString)
    out = Dict{Vector{Int},Int}()
    for (ln, line) in enumerate(eachline(path))
        s = strip(line)
        (isempty(s) || startswith(s, "@")) && continue
        parts = split(s, "#SUP:")
        length(parts) == 2 || error("$path:$ln: dòng không đúng định dạng 'items #SUP: n': $s")
        items = sort!(parse.(Int, split(parts[1])))
        haskey(out, items) && error("$path:$ln: itemset $(join(items, ' ')) xuất hiện hai lần")
        out[items] = parse(Int, strip(parts[2]))
    end
    return out
end

fmt(items, sup) = string(join(items, ' '), " #SUP: ", sup)
tag(minsup_arg) = replace(minsup_arg, "%" => "pct")

"Chạy SPMF; ném `ErrorException` nếu lỗi."
function run_spmf(jar, algorithm, input, output, minsup_arg)
    try
        run(pipeline(`java -jar $jar run $algorithm $input $output $minsup_arg`; stdout = devnull))
    catch err
        error("SPMF ($algorithm) chạy lỗi: ", sprint(showerror, err))
    end
    isfile(output) || error("SPMF không tạo file output $output")
    return read_normalized(output)
end

"Kết quả so hai bảng: số khớp, số chỉ ở một phía, số khác support, và danh sách các dòng lệch."
function compare_tables(spmf::Dict, ours::Dict)
    both = intersect(keys(spmf), keys(ours))
    key_order = k -> (length(k), k)
    only_spmf = sort!(collect(setdiff(keys(spmf), keys(ours))); by = key_order)
    only_ours = sort!(collect(setdiff(keys(ours), keys(spmf))); by = key_order)
    diff_sup = sort!(filter(k -> spmf[k] != ours[k], collect(both)); by = key_order)
    same = count(k -> spmf[k] == ours[k], both)
    return (; same, total = length(union(keys(spmf), keys(ours))), only_spmf, only_ours, diff_sup,
            ok = isempty(only_spmf) && isempty(only_ours) && isempty(diff_sup))
end

"Chạy phía nhóm. Trả `(closed, all)` ở dạng Dict; `all` là `nothing` nếu không cần hoặc vượt giới hạn."
function run_ours(db, minsup, baseline::Bool, need_all::Bool)
    opts = baseline ? (fparray = false, early_termination = false) : NamedTuple()
    closed = sort_results!(fpclose(db, minsup; opts...))
    all_fi = nothing
    if need_all
        all_fi = try
            recover_all_frequent(closed; limit = RECOVERY_LIMIT)
        catch e
            e isa RecoveryLimitExceeded || rethrow()
            nothing
        end
    end
    return closed, all_fi
end

as_dict(results) = Dict{Vector{Int},Int}(sort(collect(p.first)) => p.second for p in results)

function print_comparison(label, cmp, n_spmf, n_ours)
    println("[$label] SPMF: $n_spmf itemset | nhóm: $n_ours itemset")
    println("[$label] khớp (cùng itemset, cùng support): $(cmp.same) / $(cmp.total)")
    println("[$label] chỉ có ở SPMF: $(length(cmp.only_spmf)) | chỉ có ở nhóm: $(length(cmp.only_ours)) | cùng itemset khác support: $(length(cmp.diff_sup))")
end

function compare_one(input, minsup_arg, modes, baseline, jar)
    outdir = joinpath(ROOT, "out"); mkpath(outdir)
    name = splitext(basename(input))[1]
    db = read_spmf(input)
    ratio = FPClose.parse_minsup_ratio(minsup_arg)
    minsup = minsup_count(ratio, length(db))      # cùng cách đổi minsup như demo.jl (ceil(minsup × n))
    println("input: $input ($(length(db)) giao dịch), minsup $minsup_arg → $minsup giao dịch",
            baseline ? " [FPClose bản cơ bản]" : "")
    closed, all_fi = run_ours(db, minsup, baseline, :all in modes)
    ok = true
    for mode in modes
        ours = mode == :closed ? closed : all_fi
        if ours === nothing
            println("[$mode] bỏ qua: recovery vượt giới hạn $RECOVERY_LIMIT itemset"); ok = false; continue
        end
        stem = "$(mode)_$(name)_$(tag(minsup_arg)).txt"
        write_spmf(joinpath(outdir, "ours_$stem"), ours)
        spmf = run_spmf(jar, SPMF_ALGORITHM[mode], input, joinpath(outdir, "spmf_$stem"), minsup_arg)
        o = as_dict(ours)
        cmp = compare_tables(spmf, o)
        print_comparison("$mode ($(SPMF_ALGORITHM[mode]))", cmp, length(spmf), length(o))
        for k in cmp.only_spmf; println("  chỉ SPMF  : ", fmt(k, spmf[k])); end
        for k in cmp.only_ours; println("  chỉ nhóm  : ", fmt(k, o[k])); end
        for k in cmp.diff_sup;  println("  khác sup  : ", join(k, ' '), " SPMF=", spmf[k], " nhóm=", o[k]); end
        println("[$mode] KẾT QUẢ: ", cmp.ok ? "KHỚP HOÀN TOÀN" : "CÓ LỆCH")
        ok &= cmp.ok
    end
    return ok
end

function compare_table(dir, minsups, baseline, jar, csv)
    outdir = joinpath(ROOT, "out"); mkpath(outdir)
    files = sort(filter(f -> endswith(f, ".txt"), readdir(dir; join = true)))
    isempty(files) && (println(stderr, "không có file .txt trong $dir"); return 2)
    rows = NamedTuple[]
    for f in files, ms in minsups
        db = read_spmf(f)
        minsup = minsup_count(FPClose.parse_minsup_ratio(ms), length(db))
        closed, all_fi = run_ours(db, minsup, baseline, true)
        name = splitext(basename(f))[1]
        res = Dict{Symbol,Any}()
        for mode in (:closed, :all)
            ours = mode == :closed ? closed : all_fi
            if ours === nothing
                res[mode] = (n = -1, same = 0, total = 0); continue
            end
            stem = "$(mode)_$(name)_$(tag(ms)).txt"
            write_spmf(joinpath(outdir, "ours_$stem"), ours)
            spmf = run_spmf(jar, SPMF_ALGORITHM[mode], f, joinpath(outdir, "spmf_$stem"), ms)
            cmp = compare_tables(spmf, as_dict(ours))
            res[mode] = (n = length(ours), same = cmp.same, total = cmp.total)
        end
        push!(rows, (file = basename(f), minsup = ms, n_tx = length(db), minsup_count = minsup,
                     n_closed = res[:closed].n, closed_match = res[:closed].same, closed_total = res[:closed].total,
                     n_all = res[:all].n, all_match = res[:all].same, all_total = res[:all].total))
    end
    ratio(a, b) = b == 0 ? "n/a" : string(round(100 * a / b; digits = 2), "%")
    header = "| file | minsup | số giao dịch | số closed FI | closed khớp | tỉ lệ closed | số all-FI | all-FI khớp | tỉ lệ all-FI |"
    println(header); println("|---|---|---|---|---|---|---|---|---|")
    for r in rows
        println("| $(r.file) | $(r.minsup) | $(r.n_tx) | $(r.n_closed) | $(r.closed_match)/$(r.closed_total) | ",
                ratio(r.closed_match, r.closed_total), " | $(r.n_all) | $(r.all_match)/$(r.all_total) | ",
                ratio(r.all_match, r.all_total), " |")
    end
    open(csv, "w") do io
        println(io, "file,minsup,n_tx,minsup_count,n_closed,closed_match,closed_total,n_all,all_match,all_total")
        for r in rows
            println(io, join((r.file, r.minsup, r.n_tx, r.minsup_count, r.n_closed, r.closed_match,
                              r.closed_total, r.n_all, r.all_match, r.all_total), ','))
        end
    end
    println("Đã ghi $csv")
    # Cả hai phía cùng rỗng (0/0) vẫn là khớp; n_all = -1 nghĩa là recovery vượt giới hạn, tính là chưa kiểm.
    return all(r -> r.closed_match == r.closed_total && r.all_match == r.all_total && r.n_all >= 0, rows) ? 0 : 1
end

function main(args)
    baseline = false
    table = false
    jar = joinpath(ROOT, "tools", "spmf.jar")
    mode = "closed"
    dir = joinpath(ROOT, "data", "toy")
    minsups = ["60%", "40%", "20%", "7%"]
    csv = joinpath(ROOT, "out", "compare_table.csv")
    pos = String[]
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--baseline"
            baseline = true
        elseif a == "--table"
            table = true
        elseif a in ("--jar", "--mode", "--dir", "--minsups", "--csv")
            i < length(args) || (println(stderr, "thiếu giá trị sau $a"); return 2)
            v = args[i+1]; i += 1
            a == "--jar" && (jar = v)
            a == "--mode" && (mode = v)
            a == "--dir" && (dir = v)
            a == "--minsups" && (minsups = String.(strip.(split(v, ','))))
            a == "--csv" && (csv = v)
        elseif startswith(a, "--")
            println(stderr, "tham số không hợp lệ: $a"); return 2
        else
            push!(pos, a)
        end
        i += 1
    end
    mode in ("closed", "all", "both") || (println(stderr, "--mode phải là closed, all hoặc both"); return 2)
    isfile(jar) || (println(stderr, "không thấy $jar; tải theo hướng dẫn trong README"); return 2)
    try
        if table
            isempty(pos) || (println(stderr, "--table không nhận file input"); return 2)
            isdir(dir) || (println(stderr, "không thấy thư mục $dir"); return 2)
            return compare_table(dir, minsups, baseline, jar, csv)
        end
        if length(pos) != 2
            println(stderr, "cách dùng: julia --project scripts/compare_spmf.jl [--mode closed|all|both] [--baseline] [--jar spmf.jar] <input.txt> <minsup, ví dụ 40%>")
            println(stderr, "       hoặc: julia --project scripts/compare_spmf.jl --table [--dir data/toy] [--minsups 40%,20%]")
            return 2
        end
        isfile(pos[1]) || (println(stderr, "không thấy file input: $(pos[1])"); return 2)
        modes = mode == "both" ? [:closed, :all] : [Symbol(mode)]
        return compare_one(pos[1], pos[2], modes, baseline, jar) ? 0 : 1
    catch err
        err isa ErrorException || err isa ArgumentError || rethrow()
        println(stderr, "Lỗi: ", err isa ArgumentError ? err.msg : err.msg)
        return 2
    end
end

exit(main(ARGS))
