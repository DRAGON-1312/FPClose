# Cấu trúc dữ liệu của FPClose: FP-tree, CFI-tree và các thao tác cơ bản trên cây.
#   FPNode, FPTree     : FP-tree (cây gốc T_∅ và các cây điều kiện T_X)
#   FPArrayConfig      : tham số của kỹ thuật FP-array
#   CFINode, CFITree   : CFI-tree C_X, dùng để kiểm tra một itemset có đóng hay không
#   link!, add_child!, nodelink, prefix_path, single_path : thao tác dùng chung cho cả hai loại cây
# Quy ước: item là số nguyên không âm (item 0 là item thật), nút gốc dùng ROOT_ITEM = -1. Mỗi cây có một thứ tự item
# (header), `rank[item] = 1` là item phổ biến nhất; trong một nhánh các item đi theo rank tăng dần.

# Item giả của nút gốc, cũng dùng làm giá trị "không có item"; item thật luôn ≥ 0 nên không trùng
const ROOT_ITEM = -1

"""
    FPNode

Một nút của FP-tree.

- `item`     : item của nút
- `count`    : số giao dịch đi qua nút (cộng dồn mỗi lần chèn thêm)
- `parent`   : nút cha (`nothing` với nút gốc)
- `children` : các nút con, tra theo item
- `next`     : node-link, trỏ tới nút kế tiếp có cùng item trong cây
"""
mutable struct FPNode
    item::Int
    count::Int
    parent::Union{FPNode, Nothing}
    children::Dict{Int, FPNode}
    next::Union{FPNode, Nothing}
end

# Nút mới chưa có con và chưa được nối node-link
FPNode(item::Int, count::Int, parent::Union{FPNode, Nothing}) =
    FPNode(item, count, parent, Dict{Int, FPNode}(), nothing)

"""
    FPTree

FP-tree T_X: conditional FP-tree của itemset X. Cây của cả cơ sở dữ liệu là T_∅ (X rỗng).

- `root`         : nút gốc
- `base`         : itemset X
- `base_count`   : support của X
- `items`        : các item trong header, theo thứ tự count giảm dần
- `rank`         : item => vị trí trong `items` (1 = phổ biến nhất)
- `item_count`   : item => tổng count của item trong cây (= support của X ∪ {item})
- `head`, `tail` : đầu và cuối danh sách node-link của mỗi item (giữ `tail` để nối thêm trong O(1))
- `fparray`      : FP-array của cây, `nothing` nếu không tính; chỉ lưu nửa tam giác dưới,
                   count của cặp item hạng r > c nằm ở `fparray[tri_index(r, c)]`
- `fparray_skip` : hàng của `fparray_skip` item đầu header không được tính trong `fparray`
- `dense`        : cây được coi là dày; nếu `true` thì không tính FP-array cho các cây con
"""
mutable struct FPTree
    root::FPNode
    base::Vector{Int}
    base_count::Int
    items::Vector{Int}
    rank::Dict{Int, Int}
    item_count::Dict{Int, Int}
    head::Dict{Int, FPNode}
    tail::Dict{Int, FPNode}
    fparray::Union{Vector{Int32},Nothing}
    fparray_skip::Int
    dense::Bool
end

"""
    FPArrayConfig(; dense_ratio = 0.15, skip_items = 15, max_items = 5000)

Tham số của kỹ thuật FP-array. Ở những hàm nhận cấu hình này, truyền `nothing` là tắt FP-array.

- `dense_ratio` : nếu một phần tư trên của cây chứa ít hơn tỉ lệ này tổng số nút thì coi cây là dày
- `skip_items`  : không tính hàng FP-array của chừng này item đầu header
- `max_items`   : không tính FP-array cho cây có nhiều item hơn mức này (tránh tốn bộ nhớ)
"""
struct FPArrayConfig
    dense_ratio::Float64
    skip_items::Int
    max_items::Int
end

FPArrayConfig(; dense_ratio::Real = 0.15, skip_items::Integer = 15, max_items::Integer = 5000) =
    FPArrayConfig(Float64(dense_ratio), Int(skip_items), Int(max_items))

"""
    FPTree(base, base_count, item_counts)

Tạo FP-tree rỗng (chỉ có nút gốc và header).

- `base`        : itemset X của cây (rỗng với cây gốc)
- `base_count`  : support của X (với cây gốc là số giao dịch)
- `item_counts` : các cặp `item => count` của những item phổ biến

Header xếp theo count giảm dần, bằng count thì item nhỏ đứng trước để kết quả ổn định.
"""
function FPTree(base::Vector{Int}, base_count::Int, item_counts)
    # Dict không có thứ tự nên chuyển thành mảng rồi sắp: count lớn trước, hòa thì item nhỏ trước
    pairs = sort!(collect(Pair{Int,Int}, item_counts); by = p -> (-p.second, p.first))

    items = Int[p.first for p in pairs]

    # item => vị trí trong header
    rank = Dict{Int,Int}(item => r for (r, item) in enumerate(items))

    # item => count, tra cứu O(1)
    item_count = Dict{Int,Int}(pairs)

    root = FPNode(ROOT_ITEM, 0, nothing)

    # Chưa có nút nào nên chưa có node-link; chưa tính FP-array
    return FPTree(root, base, base_count, items, rank, item_count,
                  Dict{Int,FPNode}(), Dict{Int,FPNode}(), nothing, 0, false)
end

"""
    CFINode

Một nút của CFI-tree.

- `item`     : item của nút
- `count`    : count LỚN NHẤT trong các CFI đi qua nút (lấy max khi chèn, không cộng dồn)
- `level`    : độ sâu của nút (gốc = 0), dùng để cắt sớm khi kiểm tra đóng
- `parent`   : nút cha (`nothing` với nút gốc)
- `children` : các nút con, tra theo item
- `next`     : node-link, trỏ tới nút kế tiếp có cùng item trong cây
"""
mutable struct CFINode
    item::Int
    count::Int
    level::Int
    parent::Union{CFINode,Nothing}
    children::Dict{Int,CFINode}
    next::Union{CFINode,Nothing}
end

# Nút mới nằm sâu hơn cha một mức, chưa có con và chưa được nối node-link
CFINode(item::Int, count::Int, parent::CFINode) =
    CFINode(item, count, parent.level + 1, parent, Dict{Int,CFINode}(), nothing)

"""
    CFITree

CFI-tree C_X đi kèm FP-tree T_X: lưu mọi CFI đã tìm được có chứa X.
Mỗi CFI X ∪ Z được lưu dưới dạng Z (bỏ phần X) cùng count của nó.

- `root` : nút gốc; count của gốc là count lớn nhất trong mọi CFI đã chèn
- `base` : itemset X
- `rank` : thứ tự item, dùng chung (không sao chép) với T_X
- `head`, `tail` : đầu và cuối danh sách node-link của mỗi item
- `child_item`   : item đang được mở rộng xuống cây con của cây này (`ROOT_ITEM` nếu không có); dùng cho CFI-tree
                   rút gọn, vì item đó không cần lưu trong cây này
"""
mutable struct CFITree
    root::CFINode
    base::Vector{Int}
    rank::Dict{Int,Int}
    head::Dict{Int,CFINode}
    tail::Dict{Int,CFINode}
    child_item::Int
end

"""
    CFITree(t::FPTree)

Tạo CFI-tree rỗng cho FP-tree `t` (cùng `base`, cùng thứ tự item).
"""
function CFITree(t::FPTree)
    root = CFINode(ROOT_ITEM, 0, 0, nothing, Dict{Int,CFINode}(), nothing)
    return CFITree(root, t.base, t.rank, Dict{Int,CFINode}(), Dict{Int,CFINode}(), ROOT_ITEM)
end

# Các thao tác dưới đây dùng chung cho cả FP-tree và CFI-tree
const AnyTree = Union{FPTree,CFITree}
const AnyNode = Union{FPNode,CFINode}

"""
    nodetype(t) -> Type

Kiểu nút của cây `t` (`FPNode` hoặc `CFINode`).
"""
nodetype(::FPTree) = FPNode
nodetype(::CFITree) = CFINode

"""
    link!(t, node) -> node

Nối `node` vào cuối danh sách node-link của item của nó trong cây `t`.

- `t`    : cây chứa nút
- `node` : nút vừa tạo
"""
function link!(t::AnyTree, node::AnyNode)
    last = get(t.tail, node.item, nothing)
    if last === nothing
        t.head[node.item] = node
    else
        last.next = node
    end
    t.tail[node.item] = node
    return node
end

"""
    add_child!(t, parent, item, count) -> child

Tạo nút con mới mang `item` cho `parent`, gắn vào cây và nối vào node-link.
Người gọi phải tự kiểm tra trước rằng `parent` chưa có con mang `item`.

- `t`      : cây (`FPTree` hoặc `CFITree`)
- `parent` : nút cha
- `item`   : item của nút mới
- `count`  : count ban đầu của nút mới
"""
function add_child!(t::FPTree, parent::FPNode, item::Int, count::Int)
    child = FPNode(item, count, parent)
    parent.children[item] = child
    return link!(t, child)
end

function add_child!(t::CFITree, parent::CFINode, item::Int, count::Int)
    child = CFINode(item, count, parent)
    parent.children[item] = child
    return link!(t, child)
end

"""
    NodeLink

Bộ duyệt danh sách node-link của một item: `for n in nodelink(t, item) ... end`.
"""
struct NodeLink{N<:AnyNode}
    first::Union{N,Nothing}
end

# Để dùng NodeLink trong vòng `for`
Base.iterate(l::NodeLink, n = l.first) = n === nothing ? nothing : (n, n.next)
Base.IteratorSize(::Type{<:NodeLink}) = Base.SizeUnknown()
Base.eltype(::Type{NodeLink{N}}) where {N} = N

"""
    nodelink(t, item) -> NodeLink

Duyệt mọi nút mang `item` trong cây `t`, theo thứ tự node-link.
"""
nodelink(t::AnyTree, item::Int) =
    NodeLink{nodetype(t)}(get(t.head, item, nothing))

"""
    prefix_path(node) -> Vector{Int}

Các item trên đường từ gốc tới CHA của `node` (không gồm `node`), theo thứ tự từ gốc xuống.
Trong FP-tree, kèm `node.count` thì đây là một dòng của conditional pattern base.
"""
function prefix_path(node::AnyNode)
    path = Int[]
    p = node.parent
    while p !== nothing && p.item != ROOT_ITEM
        push!(path, p.item)
        p = p.parent
    end
    return reverse!(path)
end

"""
    single_path(t::FPTree)

Nếu `t` chỉ có một nhánh thì trả về các nút của nhánh đó từ trên xuống, ngược lại trả về
`nothing`. Cây rỗng cho nhánh rỗng.
"""
function single_path(t::FPTree)
    path = FPNode[]
    n = t.root
    while true
        k = length(n.children)
        k == 0 && return path
        k > 1 && return nothing
        n = first(values(n.children))
        push!(path, n)
    end
end

# Cây rỗng khi gốc không có con
Base.isempty(t::AnyTree) = isempty(t.root.children)

"""
    label(n) -> String

Nhãn dùng khi in cây để debug: `item:count` với nút FP-tree, `item:level:count` với nút CFI-tree.
"""
label(n::FPNode) = "$(n.item):$(n.count)"
label(n::CFINode) = "$(n.item):$(n.level):$(n.count)"

"""
    print_subtree(io, t, n, indent)

In cây con gốc tại `n`, mỗi nút một dòng, con xếp theo rank, thụt vào `indent` cấp.
"""
function print_subtree(io::IO, t::AnyTree, n::AnyNode, indent::Int)
    kids = sort!(collect(values(n.children)); by = c -> t.rank[c.item])
    for c in kids
        println(io, "  "^indent, label(c))
        print_subtree(io, t, c, indent + 1)
    end
end

# In cây gọn trong REPL
function Base.show(io::IO, ::MIME"text/plain", t::FPTree)
    println(io, "FPTree base=", t.base, " (count ", t.base_count, ")")
    println(io, "header: ", join(("$i:$(t.item_count[i])" for i in t.items), ", "))
    print_subtree(io, t, t.root, 1)
end

function Base.show(io::IO, ::MIME"text/plain", t::CFITree)
    println(io, "CFITree base=", t.base)
    print_subtree(io, t, t.root, 1)
end