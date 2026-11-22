# Kiểm tra tính đúng của FPClose trên các ví dụ biết trước đáp án
# và trên CSDL ngẫu nhiên so với bộ vét cạn.

mine(db, minsup) = sort_results!(fpclose(db, minsup))

@testset "Bài tập 5 giao dịch (a=1, b=2, c=3, d=4, e=5)" begin
    # abce, ade, ad, acd, bce; minsup 2 → 7 tập đóng. Test này chỉ so KẾT QUẢ;
    # việc dòng 8 thực sự cắt nhánh được kiểm ở testset "Bộ đếm FPCloseStats" bên dưới.
    db = [[1, 2, 3, 5], [1, 4, 5], [1, 4], [1, 3, 4], [2, 3, 5]]
    expected = sort_results!([
        [1] => 4, [3] => 3, [5] => 3, [1, 4] => 3,
        [1, 3] => 2, [1, 5] => 2, [2, 3, 5] => 2,
    ])
    @test mine(db, 2) == expected
end

@testset "Fig. 1 của bài báo (minsup 20%)" begin
    # a=1, b=2, c=3, d=4, e=5, f=6, g=7, h=8, i=9, j=10, k=11
    fig1 = [[1, 4, 5], [1, 2, 6, 7, 8], [1, 2, 4, 6], [1, 2, 3],
            [1, 4, 7, 11], [2, 3, 4, 7, 9], [2, 4, 5, 7, 10]]
    expected = sort_results!([
        [1] => 5, [2] => 5, [4] => 5, [7] => 4,
        [1, 2] => 3, [1, 4] => 3, [2, 4] => 3, [2, 7] => 3, [4, 7] => 3,
        [1, 7] => 2, [2, 3] => 2, [4, 5] => 2, [1, 2, 6] => 2, [2, 4, 7] => 2,
    ])
    @test minsup_count(0.2, 7) == 2
    @test mine(fig1, 0.2) == expected
    @test length(expected) == 14
end

@testset "Trường hợp biên" begin
    @test isempty(fpclose(Vector{Int}[], 1))
    @test isempty(fpclose([[1, 2], [3]], 2))                 # không item nào phổ biến
    @test mine([[1, 2], [1, 2], [1, 2]], 1) == [[1, 2] => 3] # {1}, {2} không đóng
    @test mine([[1], [1, 2]], 1) == [[1] => 2, [1, 2] => 1]
end

@testset "CSDL ngẫu nhiên so với vét cạn (seed cố định)" begin
    rng = MersenneTwister(2026)
    for trial in 1:300
        n_items = rand(rng, 3:9)
        n_tx = rand(rng, 1:25)
        db = [sort!(unique!(rand(rng, 1:n_items, rand(rng, 1:n_items)))) for _ in 1:n_tx]
        minsup = rand(rng, 1:max(1, n_tx ÷ 2))
        @test mine(db, minsup) == brute_force_closed(db, minsup)
    end
end

@testset "Đọc/ghi định dạng SPMF" begin
    path, io = mktemp()
    write(io, "# metadata của SPMF\n1 4 5\n\n2 1 2 6\n@CONVERTED_FROM_TEXT\n")
    close(io)
    @test read_spmf(path) == [[1, 4, 5], [1, 2, 6]]

    buf = IOBuffer()
    write_spmf(buf, [[1, 2, 6] => 2, [4] => 5])
    @test String(take!(buf)) == "1 2 6 #SUP: 2\n4 #SUP: 5\n"

    args = parse_cli_args(["--minsup", "0.2", "--output", "out.txt", "in.txt"])
    @test args == (minsup = 0.2, minsup_count = nothing, input = "in.txt", output = "out.txt")
    @test minsup_count(0.2, 10) == 2
    @test minsup_count(0.01, 10) == 1
end

@testset "minsup_count làm tròn bằng ceil, không dung sai" begin
    @test minsup_count(0.07, 100) == 8      # 0.07 * 100 = 7.000000000000001
    @test minsup_count(0.4, 5) == 2
    @test minsup_count(0.2, 7) == 2
    @test minsup_count(1.0, 7) == 7
    @test minsup_count(1e-9, 7) == 1        # tối thiểu là 1
    @test minsup_count(0.4, 5; rounding = floor) == 2   # đổi cách làm tròn ở một chỗ
    @test minsup_count(0.07, 100; rounding = floor) == 7
    @test_throws ArgumentError minsup_count(0.0, 5)
    @test_throws ArgumentError minsup_count(1.5, 5)
end

@testset "CLI: --minsup (tỉ lệ hoặc %) và --minsup-count" begin
    @test parse_cli_args(["--minsup", "0.4", "in.txt"]).minsup == 0.4
    @test parse_cli_args(["--minsup", "40%", "in.txt"]).minsup == 0.4
    @test parse_cli_args(["--minsup", "7%", "in.txt"]).minsup == 0.07
    @test parse_cli_args(["--minsup", "1", "in.txt"]).minsup == 1.0     # 100%
    o = parse_cli_args(["in.txt", "--minsup-count", "3"])
    @test o.minsup === nothing && o.minsup_count == 3 && o.input == "in.txt"
    @test resolve_minsup(o, 100) == 3
    @test resolve_minsup(parse_cli_args(["--minsup", "40%", "in.txt"]), 5) == 2

    @test_throws ArgumentError parse_cli_args(["in.txt"])                                    # thiếu cả hai
    @test_throws ArgumentError parse_cli_args(["--minsup", "0.4", "--minsup-count", "2", "in.txt"])  # có cả hai
    @test_throws ArgumentError parse_cli_args(["--minsup", "0", "in.txt"])                   # ngoài miền
    @test_throws ArgumentError parse_cli_args(["--minsup", "2", "in.txt"])                   # > 1, không phải %
    @test_throws ArgumentError parse_cli_args(["--minsup", "150%", "in.txt"])
    @test_throws ArgumentError parse_cli_args(["--minsup", "-0.1", "in.txt"])
    @test_throws ArgumentError parse_cli_args(["--minsup", "abc", "in.txt"])
    @test_throws ArgumentError parse_cli_args(["--minsup", "NaN", "in.txt"])
    @test_throws ArgumentError parse_cli_args(["--minsup-count", "0", "in.txt"])
    @test_throws ArgumentError parse_cli_args(["--minsup-count", "2.5", "in.txt"])
    @test_throws ArgumentError parse_cli_args(["--minsup"])                                  # thiếu giá trị
    @test_throws ArgumentError parse_cli_args(["--minsup", "0.4"])                           # thiếu input
    @test_throws ArgumentError parse_cli_args(["--minsup", "0.4", "a.txt", "b.txt"])         # hai input
    @test_throws ArgumentError parse_cli_args(["--minsup", "0.4", "--foo", "in.txt"])
end

@testset "build_fptree bỏ item trùng trong giao dịch" begin
    @test mine([[1, 1, 2], [1, 2, 2], [2, 1, 1]], 1) == [[1, 2] => 3]
    @test mine([[1, 1, 2, 2], [1, 2]], 2) == mine([[1, 2], [1, 2]], 2)
    t = FPClose.build_fptree([[1, 1, 2], [1, 2, 2]], 1)
    @test t.item_count == Dict(1 => 2, 2 => 2)
    @test t.base_count == 2
end

@testset "Ví dụ chính thức của SPMF (contextPasquier99), minsup 40%" begin
    db = [[1, 3, 4], [2, 3, 5], [1, 2, 3, 5], [2, 5], [1, 2, 3, 5]]
    res = mine(db, 0.4)
    buf = IOBuffer()
    write_spmf(buf, res)
    @test String(take!(buf)) == "3 #SUP: 4
1 3 #SUP: 3
2 5 #SUP: 4
2 3 5 #SUP: 3
1 2 3 5 #SUP: 2
"
    @test res == brute_force_closed(db, minsup_count(0.4, 5))
end

@testset "Bộ đếm FPCloseStats: dòng 8 thực sự cắt nhánh" begin
    # Bài tập 5 giao dịch, minsup 2: sau khi xử lý item 2 đã có CFI {2,3,5} (count 2);
    # khi tới Y = {3,5} (count 2) thì dòng 8 phải cắt vì {2,3,5} ⊇ {3,5} cùng count.
    db = [[1, 2, 3, 5], [1, 4, 5], [1, 4], [1, 3, 4], [2, 3, 5]]
    st = FPCloseStats(keep_pruned = true)
    res = fpclose(db, 2; stats = st)
    @test length(res) == 7 == st.cfis
    @test st.pruned_line8 > 0
    @test [3, 5] in st.pruned_sets
    @test st.calls >= 1 && st.closed_checks > 0

    # Tắt cắt nhánh: kết quả y hệt, không còn lần cắt nào, và phải gọi đệ quy nhiều hơn.
    st2 = FPCloseStats()
    res2 = fpclose(db, 2; stats = st2, prune_line8 = false)
    @test sort_results!(copy(res)) == sort_results!(copy(res2))
    @test st2.pruned_line8 == 0
    @test st2.calls > st.calls
    @test st2.cfis == st.cfis

    # Không truyền stats thì vẫn chạy và ra cùng kết quả.
    @test sort_results!(fpclose(db, 2)) == sort_results!(copy(res))
end

@testset "Tắt cắt nhánh dòng 8 không đổi kết quả (CSDL ngẫu nhiên)" begin
    rng = MersenneTwister(7)
    for trial in 1:200
        n_items = rand(rng, 3:9)
        db = [sort!(unique!(rand(rng, 1:n_items, rand(rng, 1:n_items)))) for _ in 1:rand(rng, 1:25)]
        minsup = rand(rng, 1:max(1, length(db) ÷ 2))
        @test mine(db, minsup) == sort_results!(fpclose(db, minsup; prune_line8 = false))
    end
end

@testset "Fig. 1: C_∅ chứa đúng 14 CFI (Fig. 7b)" begin
    fig1 = [[1, 4, 5], [1, 2, 6, 7, 8], [1, 2, 4, 6], [1, 2, 3],
            [1, 4, 7, 11], [2, 3, 4, 7, 9], [2, 4, 5, 7, 10]]
    results, croot = FPClose.run_fpclose(fig1, 2, nothing, true)
    stored = FPClose.cfi_list(croot)
    @test length(stored) == 14
    @test sort_results!([sort(p.first) => p.second for p in stored]) == sort_results!(copy(results))
    @test croot.root.count == 5          # count lớn nhất = support của {a}, {b}, {d}
    @test all(p -> p.second >= 2, stored)
end

@testset "Fig. 1: nhãn item:level:count của C_∅ khớp Fig. 7b" begin
    # Đánh số lại item để tie-break (item nhỏ trước) cho ra đúng thứ tự header của bài báo
    # b a d g f e c (Fig. 1b). Nhãn nút của Fig. 7b đọc từ bài báo (tr. 1354).
    names = Dict('b' => 1, 'a' => 2, 'd' => 3, 'g' => 4, 'f' => 5, 'e' => 6, 'c' => 7,
                 'h' => 8, 'i' => 9, 'j' => 10, 'k' => 11)
    inv = Dict(v => k for (k, v) in names)
    db = [sort([names[ch] for ch in t]) for t in ["ade", "bafgh", "badf", "bac", "adgk", "bdgci", "bdgej"]]
    _, croot = FPClose.run_fpclose(db, 2, nothing, true)
    labels = sort!(["$(inv[n.item]):$(n.level):$(n.count)"
                    for i in keys(croot.head) for n in FPClose.nodelink(croot, i)])
    fig7b = sort!(["d:1:5", "g:1:4", "a:1:5", "b:1:5",
                   "e:2:2", "g:2:3", "d:2:3", "g:2:2", "c:2:2", "a:2:3", "d:2:3", "g:2:3",
                   "f:3:2", "g:3:2"])
    @test labels == fig7b
end
