# Test đột biến (KHÔNG nằm trong runtests.jl): đo xem bỏ "bước ghi chính X = T.base ở cuối
# mỗi lời gọi" (docs/DEVIATIONS.md mục 3) thì sai bao nhiêu ca.
#
#   julia --project test/mutation_record_x.jl
#
# Cách làm: sao chép src/ ra thư mục tạm, sửa bản sao (đổi điều kiện ghi X thành `false`),
# nạp bản sao làm module FPClose rồi so với bộ vét cạn trên cùng các CSDL ngẫu nhiên
# (seed cố định). Code trong src/ không bị đụng tới.

using Random

const SRC = joinpath(@__DIR__, "..", "src")
tmp = mktempdir()
cp(SRC, joinpath(tmp, "src"))
target = joinpath(tmp, "src", "algorithm", "fpclose.jl")
code = read(target, String)
from = "if !isempty(T.base) && !check!(stats, C, Int[], T.base_count)"
occursin(from, code) || error("không tìm thấy dòng ghi X trong fpclose.jl; cập nhật script này")
write(target, replace(code, from => "if false && !check!(stats, C, Int[], T.base_count)"))

include(joinpath(tmp, "src", "FPClose.jl"))
using .FPClose
include(joinpath(@__DIR__, "brute_force.jl"))

wrong = 0
total = 0
for seed in 1:4000
    rng = MersenneTwister(seed)
    n_items = rand(rng, 2:11)
    n_tx = rand(rng, 1:40)
    dens = rand(rng)                         # từ rất thưa đến rất dày
    db = [sort!(unique!([i for i in 1:n_items if rand(rng) < dens])) for _ in 1:n_tx]
    filter!(!isempty, db)
    isempty(db) && continue
    for ms in unique([1, 2, max(1, length(db) ÷ 3), max(1, length(db) ÷ 2)])
        global total += 1
        got = sort_results!(fpclose(db, ms))
        got == brute_force_closed(db, ms) || (global wrong += 1)
    end
end
println("Bỏ bước ghi X: $wrong / $total ca sai")
