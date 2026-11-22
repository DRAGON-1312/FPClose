# fparray.jl
# Kỹ thuật FP-array (Grahne & Zhu 2005, Section 2.2–2.3 tr. 1350–1351, Fig. 2).
#
#   tri_index          : vị trí của ô (r, c) trong mảng tam giác xếp phẳng
#   new_fparray        : cấp phát mảng đếm cặp cho m item
#   accumulate_pairs!  : cộng count của mọi cặp item trong một đường chèn vào cây
#   has_row            : cây có sẵn hàng FP-array của item này không?
#   tail_counts        : count các item trong pattern base của một item, đọc từ FP-array
#   is_dense           : heuristic dày/thưa của Sec 2.3 tr. 1351
#
# FP-array A_X là ma trận đếm cặp item của T_X. Bài báo (tr. 1350): "there is no need to set
# a counter for both item pairs (ij, ik) and (ik, ij). Therefore, we only store the
# counters for all pairs (ik, ij) such that k < j." Ta chỉ lưu nửa tam giác dưới theo hạng
# trong header (hạng 1 = phổ biến nhất): ô (r, c) với r > c chứa count của cặp {item hạng r,
# item hạng c}. Hàng r gồm đúng các item xếp TRƯỚC item hạng r, cũng là các item có thể
# nằm trong pattern base của nó (một nhánh luôn đi theo hạng tăng dần), nên hàng r thay
# thế hoàn toàn lần duyệt đầu tiên của T_X dọc node-link của item đó (Sec 2.2 tr. 1350:
# "A_∅ gives all frequent items for i").

"""
    tri_index(r, c) -> Int

Vị trí của ô (r, c), r > c ≥ 1, trong mảng tam giác dưới xếp phẳng theo hàng:
hàng r bắt đầu sau (r-1)(r-2)/2 ô trước đó. Mảng cho m item dài m(m-1)/2.
"""
@inline tri_index(r::Int, c::Int) = ((r - 1) * (r - 2)) >> 1 + c

"""
    new_fparray(m) -> Vector{Int32}

FP-array cho cây có `m` item, mọi ô bằng 0. Sec 2.3 tr. 1349: kích thước tỉ lệ với
m(m-1)/2, bằng số ứng viên 2-itemset của Apriori.
"""
new_fparray(m::Int) = zeros(Int32, (m * (m - 1)) >> 1)

"""
    accumulate_pairs!(A, ranks, count, skip)

Sec 2.2 tr. 1350: khi chèn tập J vào cây "at the same time A[i, j] is incremented by 1
if {i, j} is contained in J". Ở đây `ranks` là hạng (tăng dần) của các item của một đường
chèn vào cây, `count` là trọng số của đường đó (1 với giao dịch, count của nút với một
dòng pattern base). Cộng `count` vào mọi cặp trong đường.

Hàng của `skip` item đầu header không được tính (Sec 2.3 tr. 1351: "the cells for the first
several (we use 15 based on our experience) items in its header table are not calculated").
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

`true` nếu `t` có FP-array và hàng của `item` đã được tính (hạng của `item` vượt `skip`).
"""
has_row(t::FPTree, item::Int) = t.fparray !== nothing && t.rank[item] > t.fparray_skip

"""
    tail_counts(t, item, minsup) -> Dict{Int,Int}

Fig. 8 dòng 9–10 (và Fig. 3 dòng 6–7): "if T.FP-array is defined, let tail be the set of
frequent items for i in T.FP-array". Trả các item phổ biến (count ≥ `minsup`) trong
conditional pattern base của `item` cùng count của chúng, đọc từ hàng của `item` trong
FP-array, không duyệt cây. Chỉ gọi khi `has_row(t, item)`.
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

Sec 2.3 tr. 1351: "during the construction of each FP-tree, we count the number of nodes
in each level of the tree. Based on experiments, we found that if the upper quarter of the
tree contains less than 15 percent of the total number of nodes, we are most likely dealing
with a dense data set."

`levels[d]` là số nút ở mức d (mức 1 = con của gốc). "Upper quarter" là `cld(D, 4)` mức
đầu, D là số mức của cây. Cây rỗng coi là không dày.
"""
function is_dense(levels::Vector{Int}, ratio::Float64)
    depth = something(findlast(>(0), levels), 0)
    depth == 0 && return false
    total = sum(levels)
    upper = sum(@view levels[1:cld(depth, 4)])
    return upper < ratio * total
end
