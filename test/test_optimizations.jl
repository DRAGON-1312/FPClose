# Kiểm tra các tối ưu (prune_line8, fparray, early_termination, exact_count, reduced_cfitree): mọi tổ hợp bật/tắt phải
# cho kết quả giống hệt bản cơ bản và giống bộ vét cạn. Kèm kiểm tra riêng cho FP-array
# và kết thúc sớm, và đối chiếu SPMF trên data/toy.
#
# Mặc định skip_items = 15 nên CSDL nhỏ không bao giờ dùng đến FP-array; các test dưới đây
# ép skip_items = 0 và dense_ratio = 0.0 (không bao giờ coi là dày) để FP-array luôn chạy.

const TOY_DIR = joinpath(@__DIR__, "..", "data", "toy")

# Mọi tổ hợp công tắc; `fparray` có hai cấu hình: bình thường và ép chạy.
const OPT_COMBOS = [
    (; prune_line8 = p, fparray = f, early_termination = e, exact_count = x, reduced_cfitree = r,
       skip_items = s, dense_ratio = d)
    for p in (true, false), f in (false, true), e in (false, true), x in (false, true),
        r in (false, true), (s, d) in ((0, 0.0), (15, 0.15))
    if f || (s, d) == (0, 0.0)          # khi tắt fparray thì s, d vô nghĩa: chỉ giữ một bản
]

const BASELINE = (; prune_line8 = true, fparray = false, early_termination = false, exact_count = false,
                   reduced_cfitree = false)

@testset "Số tổ hợp công tắc" begin
    # prune × (fparray tắt + 2 cấu hình bật) × early × exact_count × reduced
    @test length(OPT_COMBOS) == 2 * (1 + 2) * 2 * 2 * 2
    @test count(o -> o.fparray, OPT_COMBOS) == 32
end

@testset "SPMF: làm tròn minsup (rounding_test.txt, 7%)" begin
    # Đã chạy: java -jar tools/spmf.jar run FPClose data/toy/rounding_test.txt out.txt 7%
    # SPMF xuất đúng hai dòng "2 #SUP: 100" và "2 3 #SUP: 8", không có "1 2 #SUP: 7".
    db = read_spmf(joinpath(TOY_DIR, "rounding_test.txt"))
    @test length(db) == 100
    expected = [[2] => 100, [2, 3] => 8]
    @test mine(db, 0.07) == expected
    for o in OPT_COMBOS
        @test sort_results!(fpclose(db, 0.07; o...)) == expected
    end
end

@testset "SPMF: contextPasquier99 từ file, minsup 40%" begin
    db = read_spmf(joinpath(TOY_DIR, "pasquier99.txt"))
    @test db == [[1, 3, 4], [2, 3, 5], [1, 2, 3, 5], [2, 5], [1, 2, 3, 5]]
    expected = sort_results!([[3] => 4, [1, 3] => 3, [2, 5] => 4, [2, 3, 5] => 3, [1, 2, 3, 5] => 2])
    @test mine(db, 0.4) == expected
    for o in OPT_COMBOS
        @test sort_results!(fpclose(db, 0.4; o...)) == expected
    end
end

@testset "Mọi tổ hợp bằng bản cơ bản trên mọi file data/toy" begin
    files = filter(f -> endswith(f, ".txt"), readdir(TOY_DIR; join = true))
    @test length(files) >= 2
    for f in files, ms in (0.05, 0.2, 0.4, 0.6)
        db = read_spmf(f)
        base = sort_results!(fpclose(db, ms; BASELINE...))
        for o in OPT_COMBOS
            @test sort_results!(fpclose(db, ms; o...)) == base
        end
    end
end

@testset "Mọi tổ hợp so với vét cạn (CSDL ngẫu nhiên, seed cố định)" begin
    rng = MersenneTwister(31415)
    for trial in 1:150
        n_items = rand(rng, 3:10)
        db = [sort!(unique!(rand(rng, 1:n_items, rand(rng, 1:n_items)))) for _ in 1:rand(rng, 1:30)]
        minsup = rand(rng, 1:max(1, length(db) ÷ 2))
        expected = brute_force_closed(db, minsup)
        for o in OPT_COMBOS
            @test sort_results!(fpclose(db, minsup; o...)) == expected
        end
    end
end

@testset "Mọi tổ hợp bằng bản cơ bản trên CSDL vừa (nhiều item, nhiều giao dịch)" begin
    rng = MersenneTwister(2718)
    # Thưa và có nhiều item hơn skip_items mặc định (15), để cấu hình mặc định cũng dùng FP-array.
    db = [sort!(unique!(rand(rng, 1:60, rand(rng, 3:9)))) for _ in 1:600]
    for minsup in (6, 12, 25)
        base = sort_results!(fpclose(db, minsup; BASELINE...))
        @test !isempty(base)
        for o in OPT_COMBOS
            @test sort_results!(fpclose(db, minsup; o...)) == base
        end
    end
end

@testset "FP-array: ô và hàng đúng bằng đếm từ pattern base" begin
    rng = MersenneTwister(99)
    cfg = FPClose.FPArrayConfig(dense_ratio = 0.0, skip_items = 0)
    for trial in 1:40
        n_items = rand(rng, 4:12)
        db = [sort!(unique!(rand(rng, 1:n_items, rand(rng, 1:n_items)))) for _ in 1:rand(rng, 5:40)]
        minsup = rand(rng, 1:3)
        t = FPClose.build_fptree(db, minsup, cfg)
        length(t.items) >= 2 || continue
        @test t.fparray !== nothing && length(t.fparray) == length(t.items) * (length(t.items) - 1) ÷ 2
        # Mỗi hàng bằng count đếm từ pattern base (cách duyệt cây của Fig. 8 dòng 11-12).
        for i in t.items
            @test FPClose.has_row(t, i)                        # skip_items = 0: mọi hàng đều có
            expected = Dict{Int,Int}()
            for (path, c) in FPClose.pattern_base(t, i), j in path
                expected[j] = get(expected, j, 0) + c
            end
            filter!(p -> p.second >= minsup, expected)
            @test FPClose.tail_counts(t, i, minsup) == expected
        end
        # Cây con dựng với FP-array cho kết quả y hệt dựng không FP-array, và A của nó đúng.
        for i in t.items
            ty = FPClose.conditional_tree(t, i, minsup, cfg)
            ty0 = FPClose.conditional_tree(t, i, minsup)
            @test ty.items == ty0.items && ty.item_count == ty0.item_count
            if ty.fparray !== nothing
                for j in ty.items
                    exp = Dict{Int,Int}()
                    for (path, c) in FPClose.pattern_base(ty, j), k in path
                        exp[k] = get(exp, k, 0) + c
                    end
                    filter!(p -> p.second >= minsup, exp)
                    @test FPClose.tail_counts(ty, j, minsup) == exp
                end
            end
        end
    end
end

@testset "FP-array: skip_items và tri_index" begin
    # Ví dụ Fig. 1/Fig. 2a: header b a d g f e c (đánh số b=1, a=2, d=3, g=4, f=5, e=6, c=7).
    names = Dict('b' => 1, 'a' => 2, 'd' => 3, 'g' => 4, 'f' => 5, 'e' => 6, 'c' => 7,
                 'h' => 8, 'i' => 9, 'j' => 10, 'k' => 11)
    db = [sort([names[ch] for ch in t]) for t in ["ade", "bafgh", "badf", "bac", "adgk", "bdgci", "bdgej"]]
    cfg = FPClose.FPArrayConfig(dense_ratio = 0.0, skip_items = 0)
    t = FPClose.build_fptree(db, 2, cfg)
    @test [k for k in t.items] == [1, 2, 3, 4, 5, 6, 7]                    # b a d g f e c
    A = t.fparray
    cell(x, y) = (r = max(t.rank[names[x]], t.rank[names[y]]); c = min(t.rank[names[x]], t.rank[names[y]]);
                  Int(A[FPClose.tri_index(r, c)]))
    # Số đếm tính tay từ 7 giao dịch của Fig. 1 (cùng dạng Fig. 2a, tr. 1350), hàng a: b=3; hàng d: b=3 a=3; hàng g: b=3 a=2 d=3; hàng f: 2 2 1 1;
    # hàng e: 1 1 2 1 0; hàng c: 2 1 1 1 1 0 (theo cột b a d g f e).
    @test [cell('a', 'b')] == [3]
    @test [cell('d', 'b'), cell('d', 'a')] == [3, 3]
    @test [cell('g', 'b'), cell('g', 'a'), cell('g', 'd')] == [3, 2, 3]
    @test [cell('f', 'b'), cell('f', 'a'), cell('f', 'd'), cell('f', 'g')] == [2, 2, 1, 1]
    @test [cell('e', 'b'), cell('e', 'a'), cell('e', 'd'), cell('e', 'g'), cell('e', 'f')] == [1, 1, 2, 1, 0]
    @test [cell('c', c) for c in "badgfe"] == [2, 1, 1, 1, 0, 0]
    @test FPClose.tri_index(2, 1) == 1 && FPClose.tri_index(7, 6) == 21

    # skip_items = 3: hàng của 3 item đầu (b, a, d) không được tính; has_row sai cho chúng.
    cfg3 = FPClose.FPArrayConfig(dense_ratio = 0.0, skip_items = 3)
    t3 = FPClose.build_fptree(db, 2, cfg3)
    @test [FPClose.has_row(t3, names[ch]) for ch in "badgfec"] == [false, false, false, true, true, true, true]
    @test all(iszero, t3.fparray[1:FPClose.tri_index(3, 2)])               # hàng 2 và 3 trống
    # Ít item hơn hoặc bằng skip_items thì không cấp phát FP-array.
    @test FPClose.build_fptree(db, 2, FPClose.FPArrayConfig(dense_ratio = 0.0, skip_items = 7)).fparray === nothing
    # Quá max_items thì không cấp phát.
    @test FPClose.build_fptree(db, 2, FPClose.FPArrayConfig(dense_ratio = 0.0, skip_items = 0, max_items = 6)).fparray === nothing
    # Không có cfg thì không có FP-array.
    @test FPClose.build_fptree(db, 2).fparray === nothing
end

@testset "FP-array: heuristic dày/thưa (is_dense)" begin
    @test !FPClose.is_dense(Int[], 0.15)
    @test !FPClose.is_dense([0, 0, 0], 0.15)
    # 4 mức, 1/4 trên = mức 1: 1 nút trên tổng 1+10+10+10 = 31 (3,2%) < 15% → dày.
    @test FPClose.is_dense([1, 10, 10, 10], 0.15)
    # 1 nút trên tổng 1+1+1+1 = 4 (25%) → không dày.
    @test !FPClose.is_dense([1, 1, 1, 1], 0.15)
    # 8 mức: 1/4 trên = 2 mức đầu; (2+3)/ (2+3+10*6) = 7,7% → dày; đổi ngưỡng thành 5% → không.
    @test FPClose.is_dense([2, 3, 10, 10, 10, 10, 10, 10], 0.15)
    @test !FPClose.is_dense([2, 3, 10, 10, 10, 10, 10, 10], 0.05)
    # Cây 1 mức: toàn bộ nút ở 1/4 trên → không dày.
    @test !FPClose.is_dense([5], 0.15)
    # Tắt hẳn (dense_ratio = 0.0): không bao giờ dày.
    @test !FPClose.is_dense([1, 10, 10, 10], 0.0)
end

@testset "FP-array: thật sự được dùng và dày thì không dùng" begin
    rng = MersenneTwister(5)
    db = [sort!(unique!(rand(rng, 1:60, rand(rng, 3:9)))) for _ in 1:600]
    st = FPCloseStats()
    fpclose(db, 8; stats = st, fparray = true, early_termination = false, skip_items = 0, dense_ratio = 0.0)
    @test st.fparray_hits > 0
    st_off = FPCloseStats()
    fpclose(db, 8; stats = st_off, fparray = false, early_termination = false)
    @test st_off.fparray_hits == 0
    @test st.calls == st_off.calls && st.cfis == st_off.cfis     # cùng cây đệ quy, chỉ khác cách đếm
    # dense_ratio = 1.1 → mọi cây coi là dày → không bao giờ có FP-array.
    st_dense = FPCloseStats()
    fpclose(db, 8; stats = st_dense, fparray = true, skip_items = 0, dense_ratio = 1.1)
    @test st_dense.fparray_hits == 0
end

@testset "Kết thúc sớm: có xảy ra, không đổi kết quả" begin
    # Item 1, 2 có mặt ở mọi giao dịch (count = 5 = count(∅)), nên m0 = 2. Sau khi xử lý
    # item 2 thì {1,2} (count 5) đã ghi; tới item 1 thì closed_checking([1], 5) đã true.
    db = [[1, 2, 3, 4], [1, 2, 3], [1, 2, 3], [1, 2, 5], [1, 2, 5]]
    st = FPCloseStats()
    res = fpclose(db, 2; stats = st, fparray = false, early_termination = true)
    @test st.early_stops >= 1
    @test sort_results!(copy(res)) == brute_force_closed(db, 2)
    st0 = FPCloseStats()
    res0 = fpclose(db, 2; stats = st0, fparray = false, early_termination = false)
    @test st0.early_stops == 0
    @test sort_results!(copy(res0)) == sort_results!(copy(res))
    @test st.calls <= st0.calls
end

@testset "tree_traversals: FP-array giảm đúng số lần đi node-link" begin
    # Mỗi lời gọi đệ quy (trừ lời gọi gốc) dựng đúng một cây điều kiện: 2 lần đi node-link nếu phải
    # đếm item bằng cách duyệt cây, 1 lần nếu lấy tail từ FP-array. Nên:
    #   tắt FP-array: tree_traversals == 2 * (calls - 1)
    #   bật FP-array: tree_traversals == 2 * (calls - 1) - fparray_hits
    rng = MersenneTwister(5)
    db = [sort!(unique!(rand(rng, 1:60, rand(rng, 3:9)))) for _ in 1:600]
    st_off = FPCloseStats()
    res_off = fpclose(db, 8; stats = st_off, fparray = false)
    st_on = FPCloseStats()
    res_on = fpclose(db, 8; stats = st_on, fparray = true, skip_items = 0, dense_ratio = 0.0)
    @test sort_results!(copy(res_off)) == sort_results!(copy(res_on))
    @test st_off.calls == st_on.calls && st_off.calls > 1
    @test st_off.tree_traversals == 2 * (st_off.calls - 1)
    @test st_on.tree_traversals == 2 * (st_on.calls - 1) - st_on.fparray_hits
    @test st_on.fparray_hits > 0 && st_on.tree_traversals < st_off.tree_traversals
end

@testset "exact_count: cùng kết quả, không bao giờ nhiều phép kiểm tra tập con hơn" begin
    # exact_count chỉ bỏ sớm các nút có count lớn hơn count cần kiểm tra (không thể khớp), nên
    # kết quả giống hệt `>=` và số nút phải kiểm tra tập con không bao giờ nhiều hơn. Khi chạy
    # FPClose thật, item cuối của mọi truy vấn luôn có count đúng bằng count của itemset nên không
    # có nút nào có count lớn hơn: hai chế độ cho cùng số phép kiểm tra (xem docs/DEVIATIONS.md).
    rng = MersenneTwister(1618)
    for trial in 1:60
        n_items = rand(rng, 4:12)
        db = [sort!(unique!(rand(rng, 1:n_items, rand(rng, 1:n_items)))) for _ in 1:rand(rng, 5:40)]
        minsup = rand(rng, 1:max(1, length(db) ÷ 3))
        st_exact, st_loose = FPCloseStats(), FPCloseStats()
        r_exact = fpclose(db, minsup; stats = st_exact, exact_count = true)
        r_loose = fpclose(db, minsup; stats = st_loose, exact_count = false)
        @test sort_results!(copy(r_exact)) == sort_results!(copy(r_loose)) == brute_force_closed(db, minsup)
        @test st_exact.subset_tests <= st_loose.subset_tests
        @test st_exact.closed_checks == st_loose.closed_checks     # cùng chuỗi phép kiểm tra
    end
end

@testset "exact_count: bộ lọc count trên cây dựng tay" begin
    # CFI-tree cho items 1, 2, 3 (header theo count giảm dần), chứa duy nhất {1,2,3} với count 5.
    t = FPClose.build_fptree([[1, 2, 3], [1, 2, 3]], 1)
    C = CFITree(t)
    insert_cfi!(C, [1, 2, 3], 5)
    # Hỏi {1,3} với count 3 (không xảy ra với dữ liệu thật vì tập cha không thể có count lớn hơn):
    # nút của item 3 có count 5 > 3. Cách cũ (>=) phải kiểm tra tập con rồi báo `true`; cách mới (==)
    # loại nút ngay: trả `false` và không tốn phép kiểm tra tập con nào.
    st_exact, st_loose = FPCloseStats(), FPCloseStats()
    @test closed_checking(C, [1, 3], 3; exact_count = true, stats = st_exact) == false
    @test closed_checking(C, [1, 3], 3; exact_count = false, stats = st_loose) == true
    @test st_exact.subset_tests == 0 && st_loose.subset_tests == 1
    # Cùng count thì hai chế độ giống nhau.
    @test closed_checking(C, [1, 3], 5; exact_count = true) == closed_checking(C, [1, 3], 5; exact_count = false) == true
    # Truy vấn chính base (items rỗng): count của gốc là count lớn nhất.
    @test closed_checking(C, Int[], 5; exact_count = true) && closed_checking(C, Int[], 5; exact_count = false)
    @test !closed_checking(C, Int[], 4; exact_count = true) && closed_checking(C, Int[], 4; exact_count = false)
end

@testset "CFI-tree rút gọn: cây C_∅ của Fig. 1 nhỏ lại đúng như bài báo" begin
    # Đánh số lại item để thứ tự header là b a d g f e c (như Fig. 1b).
    names = Dict('b' => 1, 'a' => 2, 'd' => 3, 'g' => 4, 'f' => 5, 'e' => 6, 'c' => 7,
                 'h' => 8, 'i' => 9, 'j' => 10, 'k' => 11)
    inv = Dict(v => k for (k, v) in names)
    db = [sort([names[ch] for ch in t]) for t in ["ade", "bafgh", "badf", "bac", "adgk", "bdgci", "bdgej"]]
    base_opts(r) = FPClose.FPCloseOptions(; fparray = false, early_termination = false, exact_count = false,
                                          reduced_cfitree = r)
    full_stats, red_stats = FPCloseStats(), FPCloseStats()
    res_full, c_full = FPClose.run_fpclose(db, 2, full_stats, base_opts(false))
    res_red, c_red = FPClose.run_fpclose(db, 2, red_stats, base_opts(true))
    @test sort_results!(copy(res_full)) == sort_results!(copy(res_red)) && length(res_red) == 14

    # Số nút: bài báo nói 6 nút thay vì 15, đếm cả nút gốc (cây đầy đủ có 14 nút + gốc).
    @test FPClose.node_count(c_full) + 1 == 15
    @test FPClose.node_count(c_red) + 1 == 6
    @test red_stats.root_cfi_nodes == 5 && full_stats.root_cfi_nodes == 14
    @test red_stats.cfi_nodes < full_stats.cfi_nodes

    # Hình dạng và nhãn item:level khớp Fig. 9: d, a, b ở mức 1; a, d ở mức 2 (dưới b).
    shape(c) = sort!(["$(inv[n.item]):$(n.level)" for i in keys(c.head) for n in FPClose.nodelink(c, i)])
    @test shape(c_red) == sort!(["d:1", "a:1", "b:1", "a:2", "d:2"])
    b = c_red.root.children[names['b']]
    @test sort([inv[k] for k in keys(b.children)]) == ['a', 'd']
    # Count của nút là count lớn nhất trong các tập đã chèn (đã bỏ item mở rộng): các CFI tách thành
    # Z = CFI bỏ item ít phổ biến nhất, ví dụ {a,b,f}:2 → {b,a}:2, {b,g}:3 → {b}:3, {a,d}:3 → {a}:3.
    # Fig. 9 vẽ count 5/3 giống Fig. 7b nên khác các count này; xem docs/DEVIATIONS.md.
    labels = sort!(["$(inv[n.item]):$(n.level):$(n.count)" for i in keys(c_red.head) for n in FPClose.nodelink(c_red, i)])
    @test labels == sort!(["d:1:3", "a:1:3", "b:1:3", "a:2:2", "d:2:2"])
    # Count của gốc vẫn là max kể cả khi phần chèn rỗng ({b}:5, {a}:5, {d}:5 chỉ cập nhật gốc).
    @test c_red.root.count == 5
end

@testset "CFI-tree rút gọn: không đổi kết quả và nhỏ hơn trên dữ liệu lớn hơn" begin
    rng = MersenneTwister(3141)
    db = [sort!(unique!(rand(rng, 1:30, rand(rng, 6:14)))) for _ in 1:300]
    for minsup in (12, 25)
        st_full, st_red = FPCloseStats(), FPCloseStats()
        r_full = fpclose(db, minsup; stats = st_full, reduced_cfitree = false)
        r_red = fpclose(db, minsup; stats = st_red, reduced_cfitree = true)
        @test !isempty(r_full)
        @test sort_results!(copy(r_full)) == sort_results!(copy(r_red))
        @test st_red.cfi_nodes <= st_full.cfi_nodes
        @test st_red.root_cfi_nodes <= st_full.root_cfi_nodes
    end
end

@testset "Item 0 hợp lệ: khớp vét cạn ở mọi tổ hợp tùy chọn" begin
    # Item 0 là item thật (SPMF cho phép), không được nhầm với nút gốc của cây.
    rng = MersenneTwister(0)
    for trial in 1:120
        n_items = rand(rng, 3:9)
        db = [sort!(unique!(rand(rng, 0:(n_items - 1), rand(rng, 1:n_items)))) for _ in 1:rand(rng, 1:30)]
        minsup = rand(rng, 1:max(1, length(db) ÷ 2))
        expected = brute_force_closed(db, minsup)
        # Dịch toàn bộ item lên 1 (không còn item 0) rồi dịch kết quả về: phải giống hệt.
        shifted = [t .+ 1 for t in db]
        expected_shifted = sort_results!([(x .- 1) => s for (x, s) in brute_force_closed(shifted, minsup)])
        @test expected == expected_shifted
        for o in OPT_COMBOS
            res = sort_results!(fpclose(db, minsup; o...))
            @test res == expected
        end
    end
    # CSDL nhỏ có sẵn đáp án: {0 1}, {0 1}, {0} → {0}:3, {0,1}:2
    @test sort_results!(fpclose([[0, 1], [0, 1], [0]], 1)) == [[0] => 3, [0, 1] => 2]
    @test sort_results!(fpclose([[0], [0], [0]], 2)) == [[0] => 3]
    # Recovery và luật cũng chạy được với item 0.
    all_fi = recover_all_frequent(fpclose([[0, 1], [0, 1], [0]], 1))
    @test all_fi == sort_results!([[0] => 3, [1] => 2, [0, 1] => 2])
    rules = generate_rules(all_fi, 3; minconf = 0.5)
    @test any(r -> r.antecedent == [0] && r.consequent == [1], rules)
end

@testset "Item âm bị từ chối" begin
    # read_spmf báo ArgumentError rõ ràng, nêu số dòng.
    path, io = mktemp()
    write(io, "1 2\n3 -4 5\n")
    close(io)
    err = try; read_spmf(path); nothing; catch e; e; end
    @test err isa ArgumentError && occursin("-4", err.msg) && occursin("2", err.msg)
    # Item 0 đọc được bình thường.
    path0, io0 = mktemp()
    write(io0, "0 1\n0 2 1\n")
    close(io0)
    @test read_spmf(path0) == [[0, 1], [0, 1, 2]]
    # Gọi thẳng fpclose với item âm cũng báo lỗi thay vì cho kết quả sai (item âm trùng nút gốc).
    @test_throws ArgumentError fpclose([[1, -1], [1, 2]], 1)
end
