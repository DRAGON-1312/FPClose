# Kiểm tra recovery (src/recovery.jl) và luật kết hợp (src/rules.jl), cùng CLI mở rộng.
# Recovery được so tuyệt đối với bộ vét cạn; luật được so với phép tính tay và với một bộ sinh
# luật độc lập (đếm support thẳng trên CSDL, không dùng recovery).

const RTOY = joinpath(@__DIR__, "..", "data", "toy")
const FIG1 = [[1, 4, 5], [1, 2, 6, 7, 8], [1, 2, 4, 6], [1, 2, 3],
              [1, 4, 7, 11], [2, 3, 4, 7, 9], [2, 4, 5, 7, 10]]
const EX5 = [[1, 2, 3, 5], [1, 4, 5], [1, 4], [1, 3, 4], [2, 3, 5]]

recover(db, minsup) = recover_all_frequent(fpclose(db, minsup))

@testset "Recovery: ví dụ cụ thể" begin
    # Fig. 1, 20%: 14 CFI nhưng 19 frequent itemset.
    @test length(fpclose(FIG1, 0.2)) == 14
    all1 = recover(FIG1, 0.2)
    @test length(all1) == 19
    @test all1 == brute_force_frequent(FIG1, 2)

    # Bài tập 5 giao dịch: 7 CFI, 12 FI. {4} (support 3) không đóng, lấy từ {1,4}.
    all5 = recover(EX5, 2)
    @test length(all5) == 12
    @test all5 == brute_force_frequent(EX5, 2)
    @test Dict(all5)[[4]] == 3 && Dict(all5)[[1]] == 4 && Dict(all5)[[2]] == 2

    # pasquier99 40% (từ file toy): 5 CFI, 15 FI.
    pdb = read_spmf(joinpath(RTOY, "pasquier99.txt"))
    @test recover(pdb, 0.4) == brute_force_frequent(pdb, 2)
    @test length(recover(pdb, 0.4)) == 15

    # rounding_test, 7% (ngưỡng 8 giao dịch): chỉ {2}:100, {3}:8, {2,3}:8.
    rdb = read_spmf(joinpath(RTOY, "rounding_test.txt"))
    @test recover(rdb, 0.07) == [[2] => 100, [3] => 8, [2, 3] => 8]
    @test recover(rdb, 0.07) == brute_force_frequent(rdb, 8)

    # Biên: không có CFI thì không có FI; itemset đưa vào chưa sắp vẫn đúng.
    @test isempty(recover_all_frequent(Pair{Vector{Int},Int}[]))
    @test recover_all_frequent([[3, 1, 2] => 4]) ==
          sort_results!([[1] => 4, [2] => 4, [3] => 4, [1, 2] => 4, [1, 3] => 4, [2, 3] => 4, [1, 2, 3] => 4])
end

@testset "Recovery: so với vét cạn trên CSDL ngẫu nhiên (seed cố định)" begin
    rng = MersenneTwister(1234)
    for trial in 1:300
        n_items = rand(rng, 3:10)
        db = [sort!(unique!(rand(rng, 1:n_items, rand(rng, 1:n_items)))) for _ in 1:rand(rng, 1:30)]
        minsup = rand(rng, 1:max(1, length(db) ÷ 2))
        @test recover(db, minsup) == brute_force_frequent(db, minsup)
    end
end

@testset "Recovery: lấy max, không ghi đè bằng support nhỏ hơn" begin
    # {2} nằm trong {1,2}:4, {2,3}:3, {1,2,3}:2 → support đúng là 4. Đưa CFI theo thứ tự
    # support TĂNG dần để thứ tự đầu vào không giúp (hàm phải tự sắp giảm dần).
    closed = [[1, 2, 3] => 2, [2, 3] => 3, [1, 2] => 4]
    res = Dict(recover_all_frequent(closed))
    @test res[[2]] == 4 && res[[1]] == 4
    @test res[[3]] == 3                 # trong {2,3}:3 và {1,2,3}:2 → 3
    @test res[[1, 2]] == 4 && res[[2, 3]] == 3 && res[[1, 3]] == 2 && res[[1, 2, 3]] == 2
    @test length(res) == 7
    # Đảo thứ tự đầu vào không đổi kết quả.
    @test recover_all_frequent(reverse(closed)) == recover_all_frequent(closed)
    # Mọi support trong kết quả bằng support thật trên CSDL, và chính là max trên các CFI chứa nó.
    rng = MersenneTwister(77)
    for trial in 1:60
        db = [sort!(unique!(rand(rng, 1:8, rand(rng, 1:8)))) for _ in 1:rand(rng, 4:25)]
        ms = rand(rng, 1:3)
        closed = fpclose(db, ms)
        for (x, s) in recover_all_frequent(closed)
            @test s == maximum(c.second for c in closed if issubset(x, c.first))
            @test s == support(db, x)
        end
    end
end

@testset "Recovery: cắt nhánh làm số lần duyệt bị chặn" begin
    # Mỗi FI được gán đúng một lần; số lần gọi duyệt ≤ tổng độ dài các FI (mỗi FI độ dài > 1
    # sinh ra |S| lần thử con) + số CFI. Không cắt nhánh thì phải thăm lại tập con nhiều lần.
    for (db, ms) in ((FIG1, 2), (EX5, 2), (read_spmf(joinpath(RTOY, "pasquier99.txt")), 1))
        closed = fpclose(db, ms)
        visits = Ref(0)
        all_fi = recover_all_frequent(closed; visits = visits)
        bound = sum(length(x) for (x, _) in all_fi if length(x) > 1; init = 0) + length(closed)
        @test visits[] <= bound
    end
    # CFI dài: 2^12 - 1 = 4095 FI, số lần duyệt bị chặn đúng như vậy.
    visits = Ref(0)
    res = recover_all_frequent([collect(1:12) => 5, collect(1:11) => 6, collect(2:12) => 6]; visits = visits)
    @test length(res) == 2^12 - 1
    @test visits[] <= sum(length(x) for (x, _) in res if length(x) > 1) + 3
    # limit chặn kích thước.
    @test_throws RecoveryLimitExceeded recover_all_frequent([collect(1:12) => 5]; limit = 100)
end

@testset "Luật kết hợp: tính tay trên bài tập 5 giao dịch" begin
    # N = 5. sup: {1}=4, {3}=3, {4}=3, {5}=3, {2}=2; {1,4}=3, {3,5}=2, {2,3,5}=2.
    all5 = recover(EX5, 2)
    rules = generate_rules(all5, 5; minconf = 0.0)
    find(x, y) = only(r for r in rules if r.antecedent == x && r.consequent == y)

    r41 = find([4], [1])                 # conf = 3/3 = 1, lift = 1 / (4/5) = 1.25
    @test r41.count == 3 && r41.support ≈ 3 / 5 && r41.confidence == 1.0 && r41.lift ≈ 1.25
    r14 = find([1], [4])                 # conf = 3/4, lift = 0.75 / (3/5) = 1.25
    @test r14.confidence ≈ 0.75 && r14.lift ≈ 1.25
    r35 = find([3], [5])                 # conf = 2/3, lift = (2/3) / (3/5) = 10/9
    @test r35.support ≈ 2 / 5 && r35.confidence ≈ 2 / 3 && r35.lift ≈ 10 / 9
    r2_35 = find([2], [3, 5])            # conf = 2/2 = 1, lift = 1 / (2/5) = 2.5
    @test r2_35.confidence == 1.0 && r2_35.lift ≈ 2.5
    r35_2 = find([3, 5], [2])            # conf = 2/2 = 1, lift = 1 / (2/5) = 2.5
    @test r35_2.confidence == 1.0 && r35_2.lift ≈ 2.5
    # Luật 2 → 3: vế phải {3} có sup 3, lấy từ recovery; conf = 2/2 = 1, lift = 1 / (3/5).
    @test find([2], [3]).lift ≈ 1.0 / (3 / 5)

    # Không có luật trùng, mọi luật hợp lệ (X, Y khác rỗng, rời nhau).
    @test length(unique((r.antecedent, r.consequent) for r in rules)) == length(rules)
    @test all(r -> !isempty(r.antecedent) && !isempty(r.consequent) &&
                   isempty(intersect(r.antecedent, r.consequent)), rules)
end

# Bộ sinh luật độc lập: đếm support thẳng trên CSDL, không dùng recovery.
function brute_force_rules(db, minsup, minconf)
    n = length(db)
    out = Tuple{Vector{Int},Vector{Int},Int,Float64,Float64}[]
    for (z, sz) in brute_force_frequent(db, minsup), mask in 1:(2^length(z) - 2)
        x = [z[b] for b in eachindex(z) if (mask >> (b - 1)) & 1 == 1]
        y = [z[b] for b in eachindex(z) if (mask >> (b - 1)) & 1 == 0]
        conf = sz / support(db, x)
        conf >= minconf && push!(out, (x, y, sz, conf, conf / (support(db, y) / n)))
    end
    return out
end

@testset "Luật kết hợp: khớp bộ sinh độc lập và đúng minconf" begin
    rng = MersenneTwister(555)
    for trial in 1:60
        n_items = rand(rng, 3:7)
        db = [sort!(unique!(rand(rng, 1:n_items, rand(rng, 1:n_items)))) for _ in 1:rand(rng, 4:20)]
        minsup = rand(rng, 1:max(1, length(db) ÷ 2))
        minconf = rand(rng, (0.0, 0.3, 0.5, 0.6, 0.8, 1.0))
        rules = generate_rules(recover(db, minsup), length(db); minconf = minconf)
        expected = brute_force_rules(db, minsup, minconf)
        @test length(rules) == length(expected)
        got = Dict((r.antecedent, r.consequent) => (r.count, r.confidence, r.lift) for r in rules)
        for (x, y, c, conf, lift) in expected
            @test haskey(got, (x, y))
            haskey(got, (x, y)) && @test got[(x, y)][1] == c && got[(x, y)][2] ≈ conf && got[(x, y)][3] ≈ lift
        end
        @test all(r -> r.confidence >= minconf, rules)       # không luật nào vi phạm minconf
        @test all(r -> r.support >= minsup / length(db) - eps(), rules)
    end
end

@testset "Luật kết hợp: xếp hạng và top-k theo lift" begin
    all5 = recover(EX5, 2)
    rules = generate_rules(all5, 5; minconf = 0.5)
    @test issorted(rules; by = r -> -r.lift)
    top = top_rules(rules, 4)
    @test length(top) == 4 && top == rules[1:4]
    @test minimum(r.lift for r in top) >= maximum(r.lift for r in rules[5:end])   # top-k đúng là k lift lớn nhất
    @test top_rules(rules, 10_000) == rules
    # Đảo thứ tự đầu vào rồi xếp lại ra đúng thứ tự cũ (xếp hạng ổn định).
    @test top_rules(reverse(rules), 5) == rules[1:5]
    @test_throws ArgumentError top_rules(rules, 0)
    # Ngưỡng đúng biên: confidence = 0.6 chính xác (3/5) phải được giữ khi minconf = 0.6.
    db = [[1, 2], [1, 2], [1, 2], [1, 3], [1, 4]]
    @test any(r -> r.antecedent == [1] && r.consequent == [2] && r.confidence == 0.6,
              generate_rules(recover(db, 2), 5; minconf = 0.6))
    @test_throws ArgumentError generate_rules(all5, 5; minconf = 1.5)
    @test_throws ArgumentError generate_rules(all5, 5; minconf = -0.1)
    # Thiếu support của vế trái/phải (truyền nhầm tập đóng) phải báo lỗi chứ không sinh sai.
    @test_throws ArgumentError generate_rules(fpclose(EX5, 2), 5; minconf = 0.0)

    buf = IOBuffer()
    write_rules(buf, top_rules(rules, 1))
    line = String(take!(buf))
    @test occursin(" ==> ", line) && occursin("#SUP: ", line) && occursin("#CONF: ", line) &&
          occursin("#LIFT: ", line)
end

@testset "CLI mở rộng: parse_cli_options" begin
    o = parse_cli_options(["--minsup", "40%", "--output-closed", "c.txt", "--output-all", "a.txt",
                           "--rules", "r.txt", "--minconf", "0.6", "--top", "10", "in.txt"])
    @test o.minsup == 0.4 && o.output_closed == "c.txt" && o.output_all == "a.txt" &&
          o.rules == "r.txt" && o.minconf == 0.6 && o.top == 10 && o.input == "in.txt"
    # --output vẫn dùng được như --output-closed.
    @test parse_cli_options(["--minsup", "0.4", "--output", "x.txt", "in.txt"]).output_closed == "x.txt"
    @test parse_cli_options(["--minsup", "0.4", "in.txt"]).output_all === nothing
    @test parse_cli_options(["--minsup", "0.4", "--rules", "r.txt", "--minconf", "60%", "in.txt"]).minconf == 0.6
    # Lỗi có thông báo rõ.
    function msg(args)
        try
            parse_cli_options(args)
            return ""
        catch e
            e isa ArgumentError || rethrow()
            return e.msg
        end
    end
    @test occursin("--top", msg(["--minsup", "0.4", "--rules", "r", "--minconf", "0.5", "--top", "0", "in"]))
    @test occursin("--top", msg(["--minsup", "0.4", "--rules", "r", "--minconf", "0.5", "--top", "abc", "in"]))
    @test occursin("--minconf", msg(["--minsup", "0.4", "--rules", "r", "--minconf", "1.5", "in"]))
    @test occursin("--minconf", msg(["--minsup", "0.4", "--rules", "r", "--minconf", "x", "in"]))
    @test occursin("--minconf", msg(["--minsup", "0.4", "--minconf", "0.5", "in"]))     # không có --rules
    @test occursin("--top", msg(["--minsup", "0.4", "--top", "3", "in"]))               # không có --rules
    @test occursin("--minconf", msg(["--minsup", "0.4", "--rules", "r", "in"]))         # thiếu --minconf
    @test occursin("--output", msg(["--minsup", "0.4", "--output", "a", "--output-closed", "b", "in"]))
    @test occursin("--minsup", msg(["--minsup", "0", "in"]))
    @test occursin("input", msg(["--minsup", "0.4"]))
    # Bản gốc vẫn từ chối tham số mới (giữ nguyên hợp đồng cũ).
    @test_throws ArgumentError parse_cli_args(["--minsup", "0.4", "--output-all", "a", "in.txt"])
end

@testset "CLI: demo.jl chạy thật (closed, all-FI, luật, lỗi)" begin
    demo = joinpath(@__DIR__, "..", "demo.jl")
    proj = joinpath(@__DIR__, "..")
    input = joinpath(RTOY, "pasquier99.txt")
    # ignorestatus bọc Cmd TRƯỚC rồi mới pipeline: Julia ≤ 1.12 không có ignorestatus(::CmdRedirect)
    julia(args...) = run(pipeline(ignorestatus(`$(Base.julia_cmd()) --project=$proj $demo $args`);
                                  stdout = devnull, stderr = devnull))
    dir = mktempdir()
    c, a, r = joinpath(dir, "sub", "closed.txt"), joinpath(dir, "all.txt"), joinpath(dir, "rules.txt")
    @test julia("--minsup", "40%", "--output-closed", c, "--output-all", a,
                "--rules", r, "--minconf", "0.6", "--top", "3", input).exitcode == 0
    @test length(readlines(c)) == 5 && length(readlines(a)) == 15
    @test length(readlines(r)) == 3 && all(l -> occursin(" ==> ", l), readlines(r))
    @test sort(readlines(c)) == sort(["3 #SUP: 4", "1 3 #SUP: 3", "2 5 #SUP: 4", "2 3 5 #SUP: 3", "1 2 3 5 #SUP: 2"])
    # --output cũ vẫn ghi file closed.
    old = joinpath(dir, "old.txt")
    @test julia("--minsup", "40%", "--output", old, input).exitcode == 0
    @test readlines(old) == readlines(c)
    # Lỗi: mã thoát 2.
    @test julia("--minsup", "40%", joinpath(dir, "khong_ton_tai.txt")).exitcode == 2
    @test julia("--minsup", "2", input).exitcode == 2
    @test julia("--minsup", "40%", "--rules", r, "--minconf", "2", input).exitcode == 2
    @test julia("--minsup", "40%", "--rules", r, "--minconf", "0.5", "--top", "-3", input).exitcode == 2
end
