# Dựng FP-tree và conditional FP-tree.
#   insert_path!     : chèn một đường item (giao dịch hoặc dòng pattern base) vào cây
#   sort_by_rank     : lọc và sắp item theo thứ tự header của cây
#   build_fptree     : dựng cây gốc T_∅ từ cơ sở dữ liệu bằng 2 lần quét
#   pattern_base     : conditional pattern base của một item (dùng khi test, không dùng khi dựng cây)
#   prefix_items!    : lấy các item trên đường lên gốc của một nút vào bộ đệm
#   conditional_tree : dựng cây điều kiện T_Y với Y = base ∪ {item}

"""
    insert_path!(t, items, count, levels = nothing) -> t

Chèn một đường `items` vào FP-tree `t` với trọng số `count`. Đi từ gốc xuống: nút con đã có
thì cộng thêm `count`, chưa có thì tạo nút mới với count = `count`.

- `t`      : FP-tree
- `items`  : các item đã lọc (chỉ gồm item trong header) và sắp theo `t.rank` tăng dần
- `count`  : trọng số của đường (1 với giao dịch, count của nút với dòng pattern base)
- `levels` : nếu có thì `levels[d]` được cộng 1 mỗi khi tạo nút mới ở mức d (để tính độ dày của cây)
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
    sort_by_rank(t, items) -> Vector{Int}

Bỏ các item không có trong header của `t` rồi sắp phần còn lại theo thứ tự header.

- `t`     : FP-tree
- `items` : danh sách item cần lọc và sắp
"""
sort_by_rank(t::FPTree, items) =
    sort!([i for i in items if haskey(t.rank, i)]; by = i -> t.rank[i])

"""
    build_fptree(db, minsup, cfg = nothing) -> FPTree

Dựng FP-tree gốc T_∅ của cơ sở dữ liệu bằng hai lần quét: lần 1 đếm support từng item và giữ
item phổ biến, lần 2 lọc, sắp từng giao dịch theo header rồi chèn vào cây.
Item trùng trong một giao dịch bị bỏ (giao dịch là một tập hợp).

- `db`     : danh sách giao dịch, mỗi giao dịch là một `Vector{Int}` gồm các item ≥ 0 (item âm bị từ chối
             vì trùng với item giả của nút gốc)
- `minsup` : ngưỡng support tuyệt đối (số giao dịch)
- `cfg`    : cấu hình FP-array, `nothing` là không dùng FP-array

Trả về FP-tree; khi có `cfg`, cây còn được đánh dấu dày/thưa và (nếu thưa) có FP-array.
Cơ sở dữ liệu chỉ bị quét đúng 2 lần: FP-array của cây gốc được đếm ngay trong lần quét 2,
cùng lúc với việc chèn từng giao dịch vào cây.
"""
function build_fptree(db::Vector{Vector{Int}}, minsup::Int,
                      cfg::Union{FPArrayConfig,Nothing} = nothing)
    counts = Dict{Int,Int}()
    for t in db, item in unique(t)               # lần quét 1
        item >= 0 || throw(ArgumentError("item âm ($item) không hợp lệ, item phải là số nguyên ≥ 0"))
        counts[item] = get(counts, item, 0) + 1
    end
    filter!(p -> p.second >= minsup, counts)
    tree = FPTree(Int[], length(db), counts)
    m = length(tree.items)
    levels = cfg === nothing ? nothing : zeros(Int, m)
    # Cây gốc chưa biết dày hay thưa trước khi dựng xong, nên cứ cấp phát FP-array nếu kích thước hợp lệ
    # và đếm song song; nếu cuối cùng cây dày thì bỏ mảng
    fill = cfg !== nothing && cfg.skip_items < m <= cfg.max_items
    A = fill ? new_fparray(m) : nothing
    ranks = Int[]
    for t in db                                  # lần quét 2
        items = sort_by_rank(tree, unique(t))
        isempty(items) && continue
        insert_path!(tree, items, 1, levels)
        if fill
            resize!(ranks, length(items))
            for (k, x) in enumerate(items)
                ranks[k] = tree.rank[x]
            end
            accumulate_pairs!(A, ranks, 1, cfg.skip_items)
        end
    end
    if cfg !== nothing
        tree.dense = is_dense(levels, cfg.dense_ratio)
        if fill && !tree.dense
            tree.fparray = A
            tree.fparray_skip = cfg.skip_items
        end
    end
    return tree
end

"""
    pattern_base(t, item) -> Vector{Tuple{Vector{Int},Int}}

Conditional pattern base của `item` trong `t`: với mỗi nút mang `item` (đi theo node-link) lấy
đường từ gốc tới cha của nút, kèm count của nút.

- `t`    : FP-tree
- `item` : item cần lấy pattern base
"""
pattern_base(t::FPTree, item::Int) =
    [(prefix_path(n), n.count) for n in nodelink(t, item)]

"""
    prefix_items!(buf, ty, node) -> buf

Ghi vào `buf` (xóa nội dung cũ) các item nằm trên đường từ gốc tới cha của `node`, chỉ giữ item có
trong header của `ty`, rồi sắp theo thứ tự header của `ty`. Dùng lại cùng một `buf` cho nhiều nút
để không phải tạo mảng mới cho mỗi nút.

- `buf`  : mảng dùng làm bộ đệm
- `ty`   : cây đích, quyết định item nào được giữ và thứ tự của chúng
- `node` : nút của FP-tree cha, đường đi tính từ cha của nút này lên gốc
"""
function prefix_items!(buf::Vector{Int}, ty::FPTree, node::FPNode)
    empty!(buf)
    p = node.parent
    while p !== nothing && p.item != ROOT_ITEM
        haskey(ty.rank, p.item) && push!(buf, p.item)
        p = p.parent
    end
    return sort!(buf; by = i -> ty.rank[i])
end

"""
    conditional_tree(t, item, minsup, cfg = nothing; stats = nothing) -> FPTree

Dựng cây điều kiện T_Y của Y = `t.base` ∪ {`item`}. Không dựng sẵn pattern base trong bộ nhớ mà
đi theo node-link của `item` trực tiếp, hai luồng:
- Nếu `t` có hàng FP-array của `item`: đọc count các item phổ biến từ FP-array (không duyệt cây),
  tạo cây mới, rồi đi theo node-link ĐÚNG MỘT LẦN, với mỗi nút lấy các item trên đường lên gốc,
  lọc, sắp theo header cây mới và chèn ngay vào cây mới.
- Nếu không: đi theo node-link lần 1 để đếm count từng item (cộng theo count của nút), giữ item
  có count ≥ `minsup`, tạo cây mới, rồi đi theo node-link lần 2 để chèn như trên.

Header của cây mới có thể xếp khác `t`.

- `t`      : FP-tree cha
- `item`   : item mở rộng thêm vào `t.base`
- `minsup` : ngưỡng support tuyệt đối
- `cfg`    : cấu hình FP-array, `nothing` là không dùng. Có `cfg` thì trong lúc chèn còn đếm số nút
             theo mức để đánh dấu độ dày của cây mới, và nếu `t` không dày thì điền luôn FP-array
             cho cây mới (cộng theo count của nút, không cộng 1)
- `stats`  : một `FPCloseStats` hoặc `nothing`; nếu có thì `tree_traversals` được cộng thêm 1 cho
             mỗi lần đi theo node-link trên FP-tree `t`

Support của Y lấy từ `t.item_count[item]`.
"""
function conditional_tree(t::FPTree, item::Int, minsup::Int,
                          cfg::Union{FPArrayConfig,Nothing} = nothing;
                          stats = nothing)
    base = sort!(vcat(t.base, item))
    base_count = t.item_count[item]

    if has_row(t, item)
        counts = tail_counts(t, item, minsup)
    else
        stats === nothing || (stats.tree_traversals += 1)      # lần đi node-link để đếm
        counts = Dict{Int,Int}()
        for n in nodelink(t, item)
            p = n.parent
            while p !== nothing && p.item != ROOT_ITEM
                counts[p.item] = get(counts, p.item, 0) + n.count
                p = p.parent
            end
        end
        filter!(p -> p.second >= minsup, counts)
    end

    ty = FPTree(base, base_count, counts)
    m = length(ty.items)
    levels = cfg === nothing ? nothing : zeros(Int, m)
    # Chỉ điền FP-array cho cây mới khi cây cha không dày và cây mới đủ lớn nhưng không quá lớn
    fill = cfg !== nothing && !t.dense && cfg.skip_items < m <= cfg.max_items
    A = fill ? new_fparray(m) : nothing
    path = Int[]
    ranks = Int[]
    stats === nothing || (stats.tree_traversals += 1)          # lần đi node-link để chèn
    for n in nodelink(t, item)
        prefix_items!(path, ty, n)
        isempty(path) && continue
        insert_path!(ty, path, n.count, levels)
        if fill
            resize!(ranks, length(path))
            for (k, x) in enumerate(path)
                ranks[k] = ty.rank[x]
            end
            accumulate_pairs!(A, ranks, n.count, cfg.skip_items)   # cộng theo count của nút, không cộng 1
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
