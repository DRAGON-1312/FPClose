# Kiểm tra trên CSDL lớn hơn, nơi vét cạn không chạy nổi:
# mọi kết quả phải có support đúng và đóng, không có itemset trùng.
# Nếu data/benchmark/ có file .txt thì chạy thử thêm ở minsup cao (chỉ kiểm tra chạy được).

@testset "CSDL tổng hợp vừa (kiểm tra tính chất)" begin
    rng = MersenneTwister(42)
    n_items = 40
    db = [sort!(unique!(rand(rng, 1:n_items, rand(rng, 3:12)))) for _ in 1:400]
    minsup = 20
    res = fpclose(db, minsup)
    @test !isempty(res)
    @test length(unique(first.(res))) == length(res)
    @test all(p -> is_closed_frequent(db, p.first, p.second, minsup), res)
end

@testset "data/benchmark (nếu có)" begin
    dir = joinpath(@__DIR__, "..", "data", "benchmark")
    files = isdir(dir) ? filter(f -> endswith(f, ".txt"), readdir(dir; join = true)) : String[]
    if isempty(files)
        @test_skip "chưa có file benchmark"
    end
    for f in files
        db = read_spmf(f)
        @test fpclose(db, 0.9) isa Vector
    end
end
