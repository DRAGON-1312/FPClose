# Kiểm tra các tối ưu (prune_line8, fparray, early_termination): mọi tổ hợp bật/tắt phải
# cho kết quả giống hệt bản cơ bản và giống bộ vét cạn. Kèm kiểm tra riêng cho FP-array
# và kết thúc sớm, và đối chiếu SPMF trên data/toy.
#
# Mặc định skip_items = 15 nên CSDL nhỏ không bao giờ dùng đến FP-array; các test dưới đây
# ép skip_items = 0 và dense_ratio = 0.0 (không bao giờ coi là dày) để FP-array luôn chạy.

const TOY_DIR = joinpath(@__DIR__, "..", "data", "toy")

# Mọi tổ hợp công tắc; `fparray` có hai cấu hình: bình thường và ép chạy.
const OPT_COMBOS = [
    (; prune_line8 = p, fparray = f, early_termination = e, skip_items = s, dense_ratio = d)
    for p in (true, false), f in (false, true), e in (false, true),
        (s, d) in ((0, 0.0), (15, 0.15))
    if f || (s, d) == (0, 0.0)          # khi tắt fparray thì s, d vô nghĩa: chỉ giữ một bản
]

const BASELINE = (; prune_line8 = true, fparray = false, early_termination = false)

@testset "Số tổ hợp công tắc" begin
    @test length(OPT_COMBOS) == 2 * (1 + 2) * 2     # prune × (fparray tắt + 2 cấu hình bật) × early
    @test count(o -> o.fparray, OPT_COMBOS) == 8
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
