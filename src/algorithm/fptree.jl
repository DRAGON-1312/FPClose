# fptree.jl
# Dựng FP-tree và conditional FP-tree (Grahne & Zhu 2005, Section 2.1 tr. 1348–1350, Fig. 1).
#
#   build_fptree       : dựng T_∅ từ CSDL bằng 2 lần quét
#   insert_path!       : chèn một giao dịch (hoặc một dòng pattern base) vào cây
#   pattern_base       : conditional pattern base của một item
#   conditional_tree   : dựng T_Y với Y = T.base ∪ {item}

"""
    insert_path!(t, items, count)

Sec 2.1 tr. 1348: "If an itemset shares a prefix with an itemset already in the tree,
this part of the branch will be shared. In addition, a counter is associated with each
node in the tree." (Fig. 1b).

Chèn `items` vào FP-tree `t` với trọng số `count`.
`items` PHẢI đã lọc (chỉ item có trong header) và sắp theo `t.rank` tăng dần.
Đi từ gốc xuống: có sẵn con mang item thì cộng count, chưa có thì tạo nút mới.

`levels` (tùy chọn): nếu có thì `levels[d] += 1` mỗi khi tạo nút mới ở mức d, để đếm số
nút theo mức cho heuristic dày/thưa của FP-array (Sec 2.3 tr. 1351, `is_dense`).
"""
function insert_path!(t::FPTree, items::Vector{Int}, count::Int,
                      levels::Union{Vector{Int},Nothing} = nothing)
    node = t.root
    for (d, item) in enumerate(items)
        child = get(node.children, item, nothing)
        if child === nothing
            child = add_child!(t, node, item, count)
            levels === nothing || (levels[d] += 1)
        else
            child.count += count
        end
        node = child
    end
    return t
end

"""
    sort_by_rank(t, items)

Giữ lại các item có trong header của `t` và sắp theo thứ tự header.
Sec 2.1 tr. 1348: "the set of frequent items in it is inserted into the FP-tree"
(item không phổ biến bị bỏ, phần còn lại theo thứ tự header giảm dần theo count).
"""
sort_by_rank(t::FPTree, items) =
    sort!([i for i in items if haskey(t.rank, i)]; by = i -> t.rank[i])

"""
    build_fptree(db, minsup)

Dựng FP-tree T_∅ cho CSDL `db` (mỗi giao dịch là một `Vector{Int}`),
`minsup` là ngưỡng support tuyệt đối (số giao dịch). Sec 2.1 tr. 1348:
"The first scan is to find all frequent items. These items are inserted into the header
table in decreasing order of their count. In the second scan, as each transaction is
scanned, the set of frequent items in it is inserted into the FP-tree as a branch."

- Lần quét 1: đếm support từng item, giữ item có count ≥ minsup.
- Lần quét 2: lọc và sắp từng giao dịch theo header rồi chèn vào cây.

Item trùng trong một giao dịch bị bỏ (giao dịch là một tập, Sec 1 tr. 1347), kẻo đếm
hai lần và chèn một item hai lần trên cùng đường đi. `read_spmf` đã làm việc này,
nhưng ở đây làm lại để `fpclose` an toàn với `db` tạo bằng tay.
"""
function build_fptree(db::Vector{Vector{Int}}, minsup::Int,
                      cfg::Union{FPArrayConfig,Nothing} = nothing)
    counts = Dict{Int,Int}()
    for t in db, item in unique(t)               # lần quét 1
        counts[item] = get(counts, item, 0) + 1
    end
    filter!(p -> p.second >= minsup, counts)
    tree = FPTree(Int[], length(db), counts)
    m = length(tree.items)
    levels = cfg === nothing ? nothing : zeros(Int, m)
    for t in db                                  # lần quét 2
        items = sort_by_rank(tree, unique(t))
        isempty(items) || insert_path!(tree, items, 1, levels)
    end
    if cfg !== nothing
        tree.dense = is_dense(levels, cfg.dense_ratio)
        # A_∅: bài báo dựng song song với T_∅ ở lần quét 2 (Sec 2.2 tr. 1350). T_∅ không có
        # cây cha để suy ra dày/thưa, nên ta dùng chính độ dày của T_∅ rồi mới đếm cặp
        # bằng một lần quét giao dịch nữa, và chỉ khi dữ liệu thưa (docs/DEVIATIONS.md mục 10).
        if !tree.dense && cfg.skip_items < m <= cfg.max_items
            A = new_fparray(m)
            ranks = Int[]
            for t in db
                items = sort_by_rank(tree, unique(t))
                resize!(ranks, length(items))
                for (k, x) in enumerate(items)
                    ranks[k] = tree.rank[x]
                end
                accumulate_pairs!(A, ranks, 1, cfg.skip_items)
            end
            tree.fparray = A
            tree.fparray_skip = cfg.skip_items
        end
    end
    return tree
end

"""
    pattern_base(t, item)

Conditional pattern base của `item` trong `t` (Sec 2.1 tr. 1349: "by following the linked
list starting at i … all branches that contain item i are visited. The portion of these
branches from i to the root forms the conditional pattern base"): đi theo node-link của
`item`, với mỗi nút lấy đường đi từ gốc tới cha của nó, kèm count của nút.
Ví dụ Fig. 1c: pattern base của f là [(b,a,g):1, (b,a,d):1].
"""
pattern_base(t::FPTree, item::Int) =
    [(prefix_path(n), n.count) for n in nodelink(t, item)]

"""
    conditional_tree(t, item, minsup, cfg = nothing)

Dựng T_Y với Y = t.base ∪ {item} (Fig. 8 dòng 9–14; Sec 2.1 tr. 1349: "The FP-growth
method then constructs the conditional FP-tree T_{X∪{i}} by first initializing its header
table based on the frequent items found, then revisiting the branches of T_X along the
linked list of i and inserting the corresponding itemsets in T_{X∪{i}}").

1. Lấy pattern base của `item` trong `t`.
2. Tìm item phổ biến trong pattern base (dòng 9–12 Fig. 8): nếu `t` có hàng FP-array của
   `item` thì đọc từ đó (`tail_counts`, dòng 9–10, không duyệt cây); không thì đếm bằng
   cách duyệt pattern base (dòng 11–12).
3. Tạo cây rỗng với header mới (thứ tự item có thể khác `t`: "the order of items can be
   different in T_X and T_{X∪{i}}", tr. 1349), rồi chèn từng dòng của pattern base
   đã lọc và sắp lại (lần duyệt thứ hai).

Với `cfg` khác `nothing`, trong lúc chèn còn đếm số nút theo mức để tính `ty.dense`, và,
nếu `t` không dày (Sec 2.3 tr. 1351: "If the data set appears to be dense, we do not
calculate the FP-array for the next level of the FP-tree"), điền luôn FP-array A_Y cho
`ty` (Fig. 3 dòng 9: "construct Y's conditional FP-tree T_Y and possibly its FP-array A_Y").
Không cấp phát FP-array khi `ty` có ≤ `skip_items` item (mọi hàng đều bị bỏ) hoặc > `max_items`.

Count của Y là `t.item_count[item]`.
"""
function conditional_tree(t::FPTree, item::Int, minsup::Int,
                          cfg::Union{FPArrayConfig,Nothing} = nothing)
    base = sort!(vcat(t.base, item))
    base_count = t.item_count[item]
    pb = pattern_base(t, item)

    if has_row(t, item)
        counts = tail_counts(t, item, minsup)
    else
        counts = Dict{Int,Int}()
        for (path, c) in pb, i in path
            counts[i] = get(counts, i, 0) + c
        end
        filter!(p -> p.second >= minsup, counts)
    end

    ty = FPTree(base, base_count, counts)
    m = length(ty.items)
    levels = cfg === nothing ? nothing : zeros(Int, m)
    fill = cfg !== nothing && !t.dense && cfg.skip_items < m <= cfg.max_items
    A = fill ? new_fparray(m) : nothing
    ranks = Int[]
    for (path, c) in pb
        items = sort_by_rank(ty, path)
        isempty(items) && continue
        insert_path!(ty, items, c, levels)
        if fill
            resize!(ranks, length(items))
            for (k, x) in enumerate(items)
                ranks[k] = ty.rank[x]
            end
            accumulate_pairs!(A, ranks, c, cfg.skip_items)
        end
    end
    if cfg !== nothing
        ty.dense = is_dense(levels, cfg.dense_ratio)
        if fill
            ty.fparray = A
            ty.fparray_skip = cfg.skip_items
        end
    end
    return ty
end
