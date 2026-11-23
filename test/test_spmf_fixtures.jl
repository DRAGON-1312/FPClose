# So TỪNG itemset và support của cài đặt nhóm với output SPMF đã lưu trong test/fixtures/spmf/.
# Test chỉ đọc file đã lưu nên KHÔNG cần Java; fixture được sinh bằng scripts/make_spmf_fixtures.jl.
# Mỗi dòng của manifest.csv là một cặp (CSDL, minsup, chế độ): `closed` so fpclose với SPMF FPClose,
# `all` so recover_all_frequent với SPMF FPGrowth_itemsets. Mỗi cặp chạy với bản mặc định và bản tắt mọi tối ưu.

using SHA   # thư viện chuẩn, dùng kiểm SHA-256 của file đầu vào

const SPMF_FIXTURE_DIR = joinpath(@__DIR__, "fixtures", "spmf")
const SPMF_REPO_ROOT = normpath(joinpath(@__DIR__, ".."))

# Tắt mọi tối ưu của fpclose
const SPMF_ALL_OFF = (prune_line8 = false, fparray = false, early_termination = false,
                      exact_count = false, reduced_cfitree = false)
const SPMF_VARIANTS = (("mặc định", (;)), ("tắt mọi tối ưu", SPMF_ALL_OFF))

"Đọc output SPMF thành `itemset đã sắp => support`, bỏ dòng `@...`; báo lỗi nếu sai định dạng hoặc itemset lặp."
function spmf_fixture_itemsets(path)
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

function spmf_manifest()
    lines = filter(!isempty, strip.(readlines(joinpath(SPMF_FIXTURE_DIR, "manifest.csv"))))
    header = split(lines[1], ',')
    return [Dict(String(h) => String(v) for (h, v) in zip(header, split(l, ','))) for l in lines[2:end]]
end

"Kết quả của cài đặt nhóm ở dạng `itemset đã sắp => support`."
function spmf_ours(db, minsup, mode; options...)
    closed = fpclose(db, minsup; options...)
    res = mode == "closed" ? closed : recover_all_frequent(closed)
    return Dict{Vector{Int},Int}(sort(collect(p.first)) => p.second for p in res)
end

@testset "Fixture SPMF: manifest đủ ≥ 5 CSDL, 2–4 mức minsup, cả hai chế độ" begin
    rows = spmf_manifest()
    csdls = unique(r["csdl"] for r in rows)
    @test length(csdls) >= 5
    for c in csdls
        minsups = unique(r["minsup"] for r in rows if r["csdl"] == c)
        @test 2 <= length(minsups) <= 4
        for m in minsups, mode in ("closed", "all")
            @test count(r -> r["csdl"] == c && r["minsup"] == m && r["mode"] == mode, rows) == 1
        end
    end
    # Có mức làm tròn kiểu 7%: ngưỡng ceil khác với làm tròn thường
    @test any(r -> r["minsup"] == "7%" && r["csdl"] == "rounding_test", rows)
    @test any(r -> r["minsup"] == "7%" && r["csdl"] == "random200", rows)
    for r in rows
        path = joinpath(SPMF_FIXTURE_DIR, r["file"])
        @test isfile(path)
        @test r["algorithm"] == (r["mode"] == "closed" ? "FPClose" : "FPGrowth_itemsets")
        # Đầu vào chưa bị sửa so với lúc sinh fixture (nếu đổi file toy thì phải sinh lại fixture)
        @test bytes2hex(open(sha256, joinpath(SPMF_REPO_ROOT, r["input"]))) == r["input_sha256"]
        @test length(spmf_fixture_itemsets(path)) == parse(Int, r["n_itemsets"])
    end
end

@testset "Fixture SPMF: so từng itemset và support ($name)" for (name, options) in SPMF_VARIANTS
    for r in spmf_manifest()
        db = read_spmf(joinpath(SPMF_REPO_ROOT, r["input"]))
        minsup = minsup_count(FPClose.parse_minsup_ratio(r["minsup"]), length(db))
        spmf = spmf_fixture_itemsets(joinpath(SPMF_FIXTURE_DIR, r["file"]))
        mine = spmf_ours(db, minsup, r["mode"]; options...)
        label = "$(r["csdl"]) $(r["minsup"]) $(r["mode"])"
        @test (label, length(mine)) == (label, length(spmf))                       # cùng số itemset
        @test (label, mine) == (label, spmf)                                       # cùng từng itemset và support
    end
end

@testset "Fixture SPMF: ngưỡng làm tròn 7% khớp SPMF" begin
    # rounding_test 7%: 0,07 × 100 = 7,000000000000001 → ngưỡng 8 (SPMF cũng vậy): {1,2}:7 không có trong kết quả.
    db = read_spmf(joinpath(SPMF_REPO_ROOT, "data", "toy", "rounding_test.txt"))
    @test minsup_count(0.07, length(db)) == 8
    spmf = spmf_fixture_itemsets(joinpath(SPMF_FIXTURE_DIR, "rounding_test__closed__7pct.txt"))
    @test spmf == Dict([2] => 100, [2, 3] => 8) && !haskey(spmf, [1, 2])
    # random200 7%: 0,07 × 200 = 14,000000000000002 → ngưỡng 15 chứ không phải 14
    db200 = read_spmf(joinpath(SPMF_REPO_ROOT, "data", "toy", "extra", "random200.txt"))
    @test minsup_count(0.07, length(db200)) == 15
    @test all(>=(15), values(spmf_fixture_itemsets(joinpath(SPMF_FIXTURE_DIR, "random200__closed__7pct.txt"))))
end
