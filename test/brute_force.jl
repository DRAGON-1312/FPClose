# Bộ "đáp án" vét cạn: liệt kê mọi itemset, giữ tập phổ biến rồi lọc tập đóng.
# Chỉ dùng cho CSDL nhỏ (≤ khoảng 12 item), vì số itemset là 2^(số item).

support(db, X) = count(t -> issubset(X, t), db)

"""
    brute_force_closed(db, minsup) -> Vector{Pair{Vector{Int},Int}}

X đóng khi không có item nào thêm vào X mà giữ nguyên support
(tương đương định nghĩa: không có tập cha nào cùng support).
"""
function brute_force_closed(db::Vector{Vector{Int}}, minsup::Int)
    items = sort!(unique!(reduce(vcat, db; init = Int[])))
    result = Pair{Vector{Int},Int}[]
    for mask in 1:(2^length(items) - 1)
        X = [items[b] for b in eachindex(items) if (mask >> (b - 1)) & 1 == 1]
        s = support(db, X)
        s >= minsup || continue
        closed = all(j -> j in X || support(db, vcat(X, j)) < s, items)
        closed && push!(result, X => s)
    end
    return sort_results!(result)
end

"""
    is_closed_frequent(db, X, s, minsup) -> Bool

Kiểm tra một kết quả mà không cần vét cạn: support đúng, đạt minsup,
và không item nào thêm vào giữ nguyên support.
"""
function is_closed_frequent(db, X, s, minsup)
    support(db, X) == s || return false
    s >= minsup || return false
    items = unique!(reduce(vcat, db; init = Int[]))
    return all(j -> j in X || support(db, vcat(X, j)) < s, items)
end

"""
    brute_force_frequent(db, minsup) -> Vector{Pair{Vector{Int},Int}}

MỌI frequent itemset khác rỗng kèm support, bằng cách liệt kê toàn bộ 2^(số item) tập con
(cho CSDL nhỏ). Dùng làm đáp án độc lập cho `recover_all_frequent`.
"""
function brute_force_frequent(db::Vector{Vector{Int}}, minsup::Int)
    items = sort!(unique!(reduce(vcat, db; init = Int[])))
    result = Pair{Vector{Int},Int}[]
    for mask in 1:(2^length(items) - 1)
        X = [items[b] for b in eachindex(items) if (mask >> (b - 1)) & 1 == 1]
        s = support(db, X)
        s >= minsup && push!(result, X => s)
    end
    return sort_results!(result)
end
