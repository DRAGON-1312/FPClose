# FP-array: bảng đếm số lần xuất hiện chung của từng cặp item trong một FP-tree, giúp bỏ bớt
# một lần duyệt cây khi dựng cây điều kiện.
#   tri_index         : vị trí của ô (r, c) trong mảng tam giác xếp phẳng
#   new_fparray       : cấp phát mảng đếm cho m item
#   accumulate_pairs! : cộng count vào mọi cặp item của một đường chèn vào cây
#   has_row           : cây có hàng FP-array của một item hay không
#   tail_counts       : đọc count các item trong pattern base của một item từ FP-array
#   is_dense          : đoán cây dày hay thưa
# Chỉ lưu nửa tam giác dưới theo hạng trong header: ô (r, c) với r > c là count của cặp item
# hạng r và item hạng c. Hàng r gồm đúng các item xếp trước item hạng r, cũng là các item có thể
# nằm trong pattern base của nó, nên đọc hàng r là đủ, không cần duyệt cây.

"""
    tri_index(r, c) -> Int

Vị trí của ô (r, c), với r > c ≥ 1, trong mảng tam giác dưới xếp phẳng theo từng hàng.

- `r` : hạng của item ở hàng (lớn hơn `c`)
- `c` : hạng của item ở cột
"""
@inline tri_index(r::Int, c::Int) = ((r - 1) * (r - 2)) >> 1 + c

"""
    new_fparray(m) -> Vector{Int32}

Mảng đếm cho cây có `m` item, gồm m(m-1)/2 ô, ban đầu đều bằng 0.
"""
new_fparray(m::Int) = zeros(Int32, (m * (m - 1)) >> 1)

"""
    accumulate_pairs!(A, ranks, count, skip) -> A

Cộng `count` vào ô của mọi cặp item trong một đường vừa chèn vào cây. Phải cộng theo `count`
của đường chứ không cộng 1, vì một dòng pattern base đại diện cho nhiều giao dịch.

- `A`     : FP-array
- `ranks` : hạng (tăng dần) của các item trong đường
- `count` : trọng số của đường
- `skip`  : bỏ qua hàng của các item có hạng ≤ `skip`
"""
function accumulate_pairs!(A::Vector{Int32}, ranks::Vector{Int}, count::Int, skip::Int)
    c32 = Int32(count)
    @inbounds for b in 2:length(ranks)
        rb = ranks[b]
        rb > skip || continue
        off = ((rb - 1) * (rb - 2)) >> 1
        for a in 1:(b - 1)
            A[off + ranks[a]] += c32
        end
    end
    return A
end

"""
    has_row(t, item) -> Bool

`true` nếu `t` có FP-array và hàng của `item` đã được tính (hạng của `item` lớn hơn `t.fparray_skip`).
"""
has_row(t::FPTree, item::Int) = t.fparray !== nothing && t.rank[item] > t.fparray_skip

"""
    tail_counts(t, item, minsup) -> Dict{Int,Int}

Các item phổ biến trong pattern base của `item` cùng count của chúng, đọc từ hàng của `item`
trong FP-array. Chỉ gọi khi `has_row(t, item)`.

- `t`      : FP-tree có FP-array
- `item`   : item cần lấy
- `minsup` : chỉ giữ item có count ≥ `minsup`
"""
function tail_counts(t::FPTree, item::Int, minsup::Int)
    A = t.fparray::Vector{Int32}
    r = t.rank[item]
    off = ((r - 1) * (r - 2)) >> 1
    counts = Dict{Int,Int}()
    @inbounds for c in 1:(r - 1)
        v = Int(A[off + c])
        v >= minsup && (counts[t.items[c]] = v)
    end
    return counts
end

"""
    is_dense(levels, ratio) -> Bool

Đoán cây dày: một phần tư trên của cây (cld(D, 4) mức đầu, D là số mức) chứa ít hơn `ratio`
tổng số nút. Cây rỗng coi là không dày.

- `levels` : `levels[d]` là số nút ở mức d (mức 1 = con của gốc)
- `ratio`  : ngưỡng tỉ lệ
"""
function is_dense(levels::Vector{Int}, ratio::Float64)
    depth = something(findlast(>(0), levels), 0)
    depth == 0 && return false
    total = sum(levels)
    upper = sum(@view levels[1:cld(depth, 4)])
    return upper < ratio * total
end
