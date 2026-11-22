# Cấu trúc dữ liệu cho FPClose
#   FPNode / FPTree   : FP-tree và conditional FP-tree T_X   
#   CFINode / CFITree : CFI-tree C_X dùng để kiểm tra đóng  
#
# File này chỉ định nghĩa kiểu dữ liệu và các thao tác trên cây
# (tạo nút con, nối node-link, duyệt node-link, in cây).
# Logic thuật toán nằm ở src/algorithm/.
#
# Quy ước:
#   - Item là số nguyên dương như định dạng SPMF. Item 0 dành cho nút gốc.
#   - Mỗi cây có một thứ tự item (header). `rank[item] = 1` là item phổ biến nhất.
#     Trong một nhánh, item luôn xuất hiện theo rank tăng dần từ gốc xuống lá.

const ROOT_ITEM = 0

# FP-tree
"""
Một nút của FP-tree.
- `item`     : item của nút.
- `count`    : số giao dịch đi qua nút (CỘNG DỒN khi chèn).
- `parent`   : nút cha (`nothing` với gốc).
- `children` : con của nút, tra theo item.
- `next`     : node-link, nút kế tiếp có cùng item trong cây.
"""
mutable struct FPNode
    item::Int 
    count::Int 
    parent::Union{FPNode, Nothing}
    children::Dict{Int, FPNode}
    next::Union{FPNode, Nothing}
end

FPNode(item::Int, count::Int, parent::Union{FPNode, Nothing}) =
    FPNode(item, count, parent, Dict{Int, FPNode}(), nothing)

"""
FP-tree T_X: conditional FP-tree của itemset X (`base`).
Cây của cả CSDL là T_∅ (`base` rỗng).

- `base`, `base_count` : itemset X và support của X.
- `items`      : các item trong header, theo thứ tự giảm dần count.
- `rank`       : item => vị trí trong `items` (1 = phổ biến nhất).
- `item_count` : item => tổng count của item trong cây
                 (bằng support của X ∪ {item}).
- `head`, `tail` : đầu và cuối danh sách node-link của mỗi item
                   (giữ `tail` để nối nút mới vào cuối trong O(1)).
- `fparray`    : FP-array A_X (Section 2.2), `nothing` nếu không tính. Chỉ lưu nửa tam giác
                 dưới, xếp phẳng (xem fparray.jl): count của cặp item hạng r > c nằm ở
                 `fparray[tri_index(r, c)]`. Dùng Int32 như bài báo giả định số nguyên 4 byte
                 (Sec 2.3 tr. 1349).
- `fparray_skip` : hàng của `skip` item đầu header không được tính trong `fparray`
                 (Sec 2.3 tr. 1351); item đó phải đếm bằng cách duyệt cây.
- `dense`      : kết quả heuristic "1/4 trên của cây chứa < 15% số nút" (Sec 2.3 tr. 1351);
                 `true` thì không tính FP-array cho các cây con dựng từ cây này.
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

Tham số của kỹ thuật FP-array (Sec 2.2–2.3). Truyền `nothing` thay cho cấu hình
để tắt hẳn FP-array.

- `dense_ratio` : nếu 1/4 trên của cây chứa ít hơn tỉ lệ này tổng số nút thì coi dữ liệu
                  là dày và không tính FP-array cho tầng sau (bài báo: 15%).
- `skip_items`  : dữ liệu thưa thì không tính hàng của `skip_items` item đầu header
                  (bài báo: 15).
- `max_items`    : không tính FP-array cho cây có nhiều hơn số item này. Bài báo (tr. 1350)
                  nêu giới hạn kích thước n(n-1)/2 và đề xuất bỏ kỹ thuật khi n quá lớn,
                  nhưng không cho con số; 5000 item ≈ 50 MB Int32 là lựa chọn của nhóm.
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

Tạo một FP-tree rỗng (chỉ có gốc và header).
`item_counts` là các cặp `item => count` của những item phổ biến.
Header xếp theo count giảm dần; bằng count thì item nhỏ đứng trước
để kết quả luôn giống nhau giữa các lần chạy.
"""
# Constructor (hàm tạo) của FPTree. Nhận 3 tham số:
#   base        : itemset X mà cây này là T_X. Cây của cả CSDL thì base = Int[] (rỗng).
#   base_count  : support của X. Cây gốc thì bằng số giao dịch (Fig. 1: 7).
#   item_counts : các item phổ biến kèm count, ví dụ Dict(1=>5, 2=>5, 4=>5, 7=>4, 3=>2, 5=>2, 6=>2).
function FPTree(base::Vector{Int}, base_count::Int, item_counts)
    # Đổi item_counts thành mảng các cặp item => count rồi sắp xếp, đây là header table.
    #   collect(Pair{Int,Int}, item_counts): đổi Dict thành Vector{Pair{Int,Int}} (Dict không có thứ tự, cần mảng mới sort được).
    #   sort!(...): sắp xếp ngay trên mảng đó (dấu ! nghĩa là sửa trực tiếp, không tạo mảng mới).
    #   by = p -> (-p.second, p.first): khóa so sánh cho mỗi cặp p = item => count.
    #     p.second là count, đặt dấu trừ để count LỚN đứng trước (sort mặc định là tăng dần).
    #     p.first là item: nếu count bằng nhau thì item số nhỏ đứng trước (phá hòa cố định).
    #   Kết quả Fig. 1: [1=>5, 2=>5, 4=>5, 7=>4, 3=>2, 5=>2, 6=>2]
    pairs = sort!(collect(Pair{Int,Int}, item_counts); by = p -> (-p.second, p.first))

    # Lấy riêng phần item theo đúng thứ tự trên (array comprehension).
    #   Kết quả: items = [1, 2, 4, 7, 3, 5, 6]
    items = Int[p.first for p in pairs]

    # Tạo bảng tra item => thứ hạng. enumerate(items) cho ra (1, 1), (2, 2), (3, 4), (4, 7), ...
    # tức là (vị trí r, item). Ta đảo lại thành item => r.
    #   Kết quả: rank = Dict(1=>1, 2=>2, 4=>3, 7=>4, 3=>5, 5=>6, 6=>7)
    #   Dùng khi chèn giao dịch: sắp item theo rank để luôn đi từ item phổ biến nhất xuống.
    rank = Dict{Int,Int}(item => r for (r, item) in enumerate(items))

    # Bảng tra item => count, để hỏi nhanh "item này có count bao nhiêu" (O(1)).
    #   Kết quả: item_count = Dict(1=>5, 2=>5, 4=>5, 7=>4, 3=>2, 5=>2, 6=>2)
    #   Đây là support của base ∪ {item}, FPclose dùng làm count của Y ở dòng 7–8 Fig. 8.
    item_count = Dict{Int,Int}(pairs)

    # Tạo nút gốc: item = ROOT_ITEM (= 0, vì item thật luôn > 0), count 0, không có cha.
    root = FPNode(ROOT_ITEM, 0, nothing)

    # Gọi constructor mặc định của struct FPTree, truyền đủ 9 trường theo đúng thứ tự khai báo:
    #   root, base, base_count, items, rank, item_count,
    #   head = Dict rỗng   (chưa có nút nào nên chưa có node-link)
    #   tail = Dict rỗng
    #   fparray = nothing  (chưa tính FP-array), fparray_skip = 0, dense = false
    return FPTree(root, base, base_count, items, rank, item_count,
                  Dict{Int,FPNode}(), Dict{Int,FPNode}(), nothing, 0, false)
end

# CFI-tree
"""
Một nút của CFI-tree.
- `count` : count LỚN NHẤT trong các CFI đi qua nút (lấy MAX khi chèn, không cộng).
- `level` : độ sâu của nút (gốc = 0). Đường từ gốc tới nút có đúng `level`
            item, dùng để cắt sớm trong closed_checking.
Các trường còn lại giống FPNode.
"""
mutable struct CFINode
    item::Int
    count::Int
    level::Int
    parent::Union{CFINode,Nothing}
    children::Dict{Int,CFINode}
    next::Union{CFINode,Nothing}
end

CFINode(item::Int, count::Int, parent::CFINode) =
    CFINode(item, count, parent.level + 1, parent, Dict{Int,CFINode}(), nothing)

"""
CFI-tree C_X, đi kèm FP-tree T_X.

Lưu mọi CFI đã tìm được có chứa X, nhưng BỎ phần X. CFI `X ∪ Z` được lưu
dưới dạng `Z` với count của nó. Lý do: header của C_X dùng thứ tự item của
T_X, mà T_X không chứa item của X (xem Section 3.2: chèn B ∪ (Y_j − Y_k) vào
cây của Y_k).

`rank` dùng chung (cùng một Dict, không copy) với T_X, vì hai cây có cùng
thứ tự item và thứ tự này không đổi sau khi tạo cây.
"""
mutable struct CFITree
    root::CFINode
    base::Vector{Int}
    rank::Dict{Int,Int}
    head::Dict{Int,CFINode}
    tail::Dict{Int,CFINode}
end

"""
    CFITree(t::FPTree)

Tạo CFI-tree rỗng đi kèm FP-tree `t` (cùng base, cùng thứ tự item).
"""
function CFITree(t::FPTree)
    root = CFINode(ROOT_ITEM, 0, 0, nothing, Dict{Int,CFINode}(), nothing)
    return CFITree(root, t.base, t.rank, Dict{Int,CFINode}(), Dict{Int,CFINode}())
end

# ---------------------------------------------------------------------------
# Thao tác chung cho cả hai loại cây (multiple dispatch)
# ---------------------------------------------------------------------------

const AnyTree = Union{FPTree,CFITree}
const AnyNode = Union{FPNode,CFINode}

nodetype(::FPTree) = FPNode
nodetype(::CFITree) = CFINode

"""
    link!(t, node)

Nối `node` vào cuối danh sách node-link của item của nó.
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
    add_child!(t, parent, item, count)

Tạo nút con mới cho `parent`, gắn vào cây và nối vào node-link.
Gọi khi không có sẵn con mang `item` (việc kiểm tra này do code chèn làm).
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

# Duyệt node-link: `for n in nodelink(t, item) ... end`
struct NodeLink{N<:AnyNode}
    first::Union{N,Nothing}
end

Base.iterate(l::NodeLink, n = l.first) = n === nothing ? nothing : (n, n.next)
Base.IteratorSize(::Type{<:NodeLink}) = Base.SizeUnknown()
Base.eltype(::Type{NodeLink{N}}) where {N} = N

"""
    nodelink(t, item)

Mọi nút mang `item` trong cây `t`, theo thứ tự node-link.
"""
nodelink(t::AnyTree, item::Int) =
    NodeLink{nodetype(t)}(get(t.head, item, nothing))

"""
    prefix_path(node)

Các item trên đường từ gốc tới CHA của `node` (không gồm `node`), theo thứ tự
từ gốc xuống. Với FP-tree, cùng `node.count`, đây chính là một dòng trong
conditional pattern base của `node.item`.
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

Nếu `t` chỉ có một nhánh, trả về các nút trên nhánh đó từ trên xuống.
Ngược lại trả về `nothing`. Cây rỗng cho nhánh rỗng.
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

Base.isempty(t::AnyTree) = isempty(t.root.children)

# ---------------------------------------------------------------------------
# In cây để debug (theo ký hiệu trong bài báo)
#   FP-tree  : item:count        (Fig. 1)
#   CFI-tree : item:level:count  (Fig. 7)
# ---------------------------------------------------------------------------

label(n::FPNode) = "$(n.item):$(n.count)"
label(n::CFINode) = "$(n.item):$(n.level):$(n.count)"

function print_subtree(io::IO, t::AnyTree, n::AnyNode, indent::Int)
    kids = sort!(collect(values(n.children)); by = c -> t.rank[c.item])
    for c in kids
        println(io, "  "^indent, label(c))
        print_subtree(io, t, c, indent + 1)
    end
end

function Base.show(io::IO, ::MIME"text/plain", t::FPTree)
    println(io, "FPTree base=", t.base, " (count ", t.base_count, ")")
    println(io, "header: ", join(("$i:$(t.item_count[i])" for i in t.items), ", "))
    print_subtree(io, t, t.root, 1)
end

function Base.show(io::IO, ::MIME"text/plain", t::CFITree)
    println(io, "CFITree base=", t.base)
    print_subtree(io, t, t.root, 1)
end