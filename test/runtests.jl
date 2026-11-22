# Chạy toàn bộ test:  julia --project test/runtests.jl
using Test
using Random
using FPClose

include("brute_force.jl")

@testset "FPClose" begin
    include("test_correctness.jl")
    include("test_optimizations.jl")
    include("test_recovery.jl")
    include("test_benchmark.jl")
end
