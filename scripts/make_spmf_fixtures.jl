# Sinh fixture từ SPMF cho test của Chương 1 và lập bảng so sánh cài đặt của nhóm với SPMF.
#
# Chạy SPMF FPClose (tập đóng) và FPGrowth_itemsets (mọi tập phổ biến) trên các CSDL nhỏ trong
# data/toy/ và data/toy/extra/, mỗi CSDL ở 2 đến 4 mức minsup (có các mức làm tròn kiểu 7%), rồi lưu
# NGUYÊN output của SPMF vào test/fixtures/spmf/. Test (test/test_spmf_fixtures.jl) chỉ đọc các file đã
# lưu nên KHÔNG cần Java. SPMF chỉ dùng để tạo dữ liệu đối chiếu, mã của nhóm không tham khảo nó.
#
# Cách dùng (từ thư mục gốc repo):
#   julia --project=. scripts/make_spmf_fixtures.jl                 # sinh lại fixture bằng SPMF rồi lập bảng
#   julia --project=. scripts/make_spmf_fixtures.jl --report-only   # chỉ lập bảng từ fixture đã lưu (không cần Java)
#   julia --project=. scripts/make_spmf_fixtures.jl --jar tools/spmf.jar
#
# Sinh ra:
#   test/fixtures/spmf/<csdl>__<closed|all>__<minsup>.txt   output thô của SPMF
#   test/fixtures/spmf/manifest.csv                         danh sách fixture, hash đầu vào, số itemset
#   test/fixtures/spmf/README.md                            cách tạo (ngày, Java, hash spmf.jar)
#   results/correctness/toy_vs_spmf.csv và .md              bảng so từng itemset và support
#
# Mã thoát: 0 nếu mọi fixture khớp hoàn toàn với cài đặt của nhóm, 1 nếu có lệch, 2 nếu sai tham số hoặc
# SPMF lỗi.

using SHA
using Dates
using FPClose

const ROOT = normpath(joinpath(@__DIR__, ".."))
const FIXTURE_DIR = joinpath(ROOT, "test", "fixtures", "spmf")
const RESULTS_DIR = joinpath(ROOT, "results", "correctness")

# (tên CSDL, file đầu vào, các mức minsup). Mức 7% làm tròn lên nhờ sai số số thực: 0,07 × 100 =
# 7,000000000000001 (rounding_test, ngưỡng 8 chứ không phải 7) và 0,07 × 200 = 14,000000000000002 (random200,
# ngưỡng 15 chứ không phải 14). item0 có item 0.
const CASES = [
    ("pasquier99", "data/toy/pasquier99.txt", ["60%", "40%", "20%", "7%"]),
    ("rounding_test", "data/toy/rounding_test.txt", ["40%", "20%", "7%"]),
    ("ex5", "data/toy/extra/ex5.txt", ["60%", "40%", "20%"]),
    ("fig1", "data/toy/extra/fig1.txt", ["40%", "20%", "10%"]),
    ("random200", "data/toy/extra/random200.txt", ["20%", "7%", "2%"]),
    ("item0", "data/toy/extra/item0.txt", ["60%", "30%"]),
]

# chế độ => thuật toán của SPMF
const MODES = ["closed" => "FPClose", "all" => "FPGrowth_itemsets"]

# Các tùy chọn tắt mọi tối ưu của fpclose (để so với bản mặc định)
const ALL_OFF = (prune_line8 = false, fparray = false, early_termination = false,
                 exact_count = false, reduced_cfitree = false)

sha256_file(path) = open(io -> bytes2hex(sha256(io)), path)
fixture_name(csdl, mode, minsup) = string(csdl, "__", mode, "__", replace(minsup, "%" => "pct"), ".txt")

"""
    read_itemsets(path) -> Dict{Vector{Int},Int}

Đọc output của SPMF (dòng `1 2 #SUP: 3`) thành `itemset đã sắp => support`, bỏ dòng metadata `@...`.
Báo lỗi nếu dòng sai định dạng hoặc itemset lặp.
"""
function read_itemsets(path::AbstractString)
    out = Dict{Vector{Int},Int}()
    for (ln, line) in enumerate(eachline(path))
        s = strip(line)
        (isempty(s) || startswith(s, "@")) && continue
        parts = split(s, "#SUP:")
        length(parts) == 2 || error("$path:$ln: dòng không đúng định dạng: $s")
        items = sort!(parse.(Int, split(parts[1])))
        haskey(out, items) && error("$path:$ln: itemset lặp: $s")
        out[items] = parse(Int, strip(parts[2]))
    end
    return out
end

"Tìm java của JDK 25 (SPMF mới build cho Java 25); không thấy thì dùng `java` trên PATH."
function find_java()
    for root in ("C:\\Program Files\\Eclipse Adoptium", "/usr/lib/jvm")
        isdir(root) || continue
        for d in sort(readdir(root); rev = true)
            (startswith(d, "jdk-25") || startswith(d, "temurin-25")) || continue
            for exe in ("java.exe", "java")
                p = joinpath(root, d, "bin", exe)
                isfile(p) && return p
            end
        end
    end
    return "java"
end

function java_version(java)
    buf = IOBuffer()
    try
        run(pipeline(ignorestatus(`$java -version`); stdout = buf, stderr = buf))
    catch
        return "không chạy được"
    end
    return strip(first(split(String(take!(buf)), '\n')))
end

"""
    ours(db, minsup, mode; options...) -> Dict{Vector{Int},Int}

Kết quả của cài đặt nhóm: tập đóng (`closed`) hoặc mọi tập phổ biến khôi phục từ tập đóng (`all`).
"""
function ours(db, minsup::Int, mode::AbstractString; options...)
    closed = fpclose(db, minsup; options...)
    res = mode == "closed" ? closed : recover_all_frequent(closed)
    return Dict{Vector{Int},Int}(sort(collect(p.first)) => p.second for p in res)
end

"Đếm số itemset khớp hoàn toàn (cùng itemset, cùng support) giữa hai kết quả."
n_match(a::Dict, b::Dict) = count(k -> haskey(b, k) && b[k] == a[k], keys(a))

# ---------------------------------------------------------------------------
# Sinh fixture bằng SPMF
# ---------------------------------------------------------------------------

function generate(jar::AbstractString)
    isfile(jar) || (println(stderr, "Không thấy ", jar, " (tải theo README)"); return false)
    java = find_java()
    mkpath(FIXTURE_DIR)
    for f in readdir(FIXTURE_DIR; join = true)       # bỏ fixture cũ để không sót file không còn trong CASES
        endswith(f, ".txt") && rm(f)
    end
    rows = Vector{Vector{String}}()
    for (csdl, input, minsups) in CASES, minsup in minsups, (mode, algorithm) in MODES
        src = joinpath(ROOT, input)
        isfile(src) || (println(stderr, "Không thấy ", src); return false)
        dst = joinpath(FIXTURE_DIR, fixture_name(csdl, mode, minsup))
        try
            run(pipeline(`$java -jar $jar run $algorithm $src $dst $minsup`; stdout = devnull))
        catch err
            println(stderr, "SPMF ", algorithm, " lỗi trên ", input, " ", minsup, ": ", sprint(showerror, err))
            return false
        end
        isfile(dst) || (println(stderr, "SPMF không tạo ", dst); return false)
        n = length(read_itemsets(dst))
        push!(rows, [csdl, input, sha256_file(src), minsup, mode, algorithm, basename(dst), string(n)])
        println(rpad(csdl, 14), rpad(minsup, 5), rpad(mode, 7), lpad(n, 6), " itemset  ", basename(dst))
    end
    open(joinpath(FIXTURE_DIR, "manifest.csv"), "w") do io
        println(io, "csdl,input,input_sha256,minsup,mode,algorithm,file,n_itemsets")
        foreach(r -> println(io, join(r, ',')), rows)
    end
    write(joinpath(FIXTURE_DIR, "README.md"), """
        # Fixture SPMF

        Output NGUYÊN VĂN của SPMF trên các CSDL nhỏ của repo, dùng cho `test/test_spmf_fixtures.jl` (test không cần Java).
        Sinh bằng `julia --project=. scripts/make_spmf_fixtures.jl`.

        - Ngày sinh: $(Dates.format(now(UTC), "yyyy-mm-dd")) (UTC)
        - Java: $(java_version(java))
        - `spmf.jar` SHA-256: `$(sha256_file(jar))`
        - Thuật toán: `FPClose` (chế độ `closed`) và `FPGrowth_itemsets` (chế độ `all`)
        - Tên file: `<csdl>__<closed|all>__<minsup>.txt` (`7pct` là minsup `7%`)
        - `manifest.csv`: CSDL, file đầu vào, SHA-256 của đầu vào, minsup, chế độ, file fixture, số itemset

        Mỗi file có hai dòng metadata `@...` ở đầu, các dòng còn lại dạng `1 2 #SUP: 3`; item trong một itemset
        không được SPMF sắp thứ tự. Nếu sửa file trong `data/toy/` thì phải sinh lại fixture (test kiểm SHA-256 đầu vào).
        """)
    println("\nĐã ghi ", length(rows), " fixture vào ", FIXTURE_DIR)
    return true
end

# ---------------------------------------------------------------------------
# Bảng so sánh từng itemset
# ---------------------------------------------------------------------------

"Một dòng manifest thành NamedTuple (tên cột => giá trị chuỗi)."
function read_manifest()
    path = joinpath(FIXTURE_DIR, "manifest.csv")
    isfile(path) || error("Không thấy $path: chạy scripts/make_spmf_fixtures.jl (cần Java) trước")
    lines = filter(!isempty, strip.(readlines(path)))
    header = split(lines[1], ',')
    return [Dict(String(h) => String(v) for (h, v) in zip(header, split(l, ','))) for l in lines[2:end]]
end

function report()
    rows = read_manifest()
    mkpath(RESULTS_DIR)
    table = NamedTuple[]
    off_ok = 0
    for r in rows
        input = joinpath(ROOT, r["input"])
        sha256_file(input) == r["input_sha256"] ||
            error("Đầu vào $(r["input"]) đã đổi so với lúc sinh fixture: sinh lại bằng scripts/make_spmf_fixtures.jl")
        db = read_spmf(input)
        minsup = minsup_count(FPClose.parse_minsup_ratio(r["minsup"]), length(db))
        spmf = read_itemsets(joinpath(FIXTURE_DIR, r["file"]))
        mine = ours(db, minsup, r["mode"])
        nm = n_match(mine, spmf)
        union_size = length(union(keys(mine), keys(spmf)))
        push!(table, (csdl = r["csdl"], minsup = r["minsup"], minsup_count = minsup, mode = r["mode"],
                      n_ours = length(mine), n_spmf = length(spmf), n_match = nm,
                      match_rate = union_size == 0 ? 1.0 : round(nm / union_size; digits = 6)))
        off_ok += ours(db, minsup, r["mode"]; ALL_OFF...) == spmf
    end
    header = ["csdl", "minsup", "minsup_count", "mode", "n_ours", "n_spmf", "n_match", "match_rate"]
    open(joinpath(RESULTS_DIR, "toy_vs_spmf.csv"), "w") do io
        println(io, join(header, ','))
        for t in table
            println(io, join((getfield(t, Symbol(h)) for h in header), ','))
        end
    end
    pct(x) = string(round(100 * x; digits = 2), "%")
    perfect = count(t -> t.n_ours == t.n_spmf == t.n_match, table)
    open(joinpath(RESULTS_DIR, "toy_vs_spmf.md"), "w") do io
        println(io, "# Cài đặt của nhóm so với SPMF trên CSDL nhỏ\n")
        println(io, "So từng itemset và support (bản mặc định của `fpclose`; `all` = `recover_all_frequent` so với SPMF ",
                "`FPGrowth_itemsets`, `closed` so với SPMF `FPClose`). `match_rate` = số dòng khớp hoàn toàn / số dòng của ",
                "hợp hai bên. Fixture: `test/fixtures/spmf/`, sinh bằng `scripts/make_spmf_fixtures.jl`.\n")
        println(io, "| CSDL | minsup | ngưỡng (giao dịch) | chế độ | n_ours | n_spmf | n_match | match_rate |")
        println(io, "|---|---|---:|---|---:|---:|---:|---:|")
        for t in table
            println(io, "| $(t.csdl) | $(t.minsup) | $(t.minsup_count) | $(t.mode) | $(t.n_ours) | $(t.n_spmf) | ",
                    "$(t.n_match) | $(pct(t.match_rate)) |")
        end
        println(io, "\nTổng: $(perfect)/$(length(table)) fixture khớp hoàn toàn ",
                "(trên $(length(unique(t.csdl for t in table))) CSDL, $(length(table)) cặp CSDL × minsup × chế độ). ",
                "Bản tắt mọi tối ưu (`prune_line8`, `fparray`, `early_termination`, `exact_count`, `reduced_cfitree` đều tắt): ",
                "$(off_ok)/$(length(table)) fixture khớp hoàn toàn.")
    end
    println("Bảng so với SPMF: ", perfect, "/", length(table), " fixture khớp hoàn toàn (bản mặc định); ",
            off_ok, "/", length(table), " (tắt mọi tối ưu)")
    println("Đã ghi ", joinpath(RESULTS_DIR, "toy_vs_spmf.csv"), " và toy_vs_spmf.md")
    return perfect == length(table) && off_ok == length(table)
end

# ---------------------------------------------------------------------------
# Dòng lệnh
# ---------------------------------------------------------------------------

const USAGE = "cách dùng: julia --project=. scripts/make_spmf_fixtures.jl [--report-only] [--jar tools/spmf.jar]"

function main(args)
    report_only = false
    jar = joinpath(ROOT, "tools", "spmf.jar")
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--report-only"
            report_only = true
        elseif a == "--jar"
            i < length(args) || (println(stderr, "Lỗi: thiếu giá trị sau --jar\n", USAGE); return 2)
            jar = args[i+1]
            i += 1
        else
            println(stderr, "Lỗi: tham số không hợp lệ: ", a, "\n", USAGE)
            return 2
        end
        i += 1
    end
    if !report_only
        println("Julia ", VERSION, "  |  gốc repo ", ROOT, "\n")
        generate(jar) || return 2
        println()
    end
    return report() ? 0 : 1
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end
