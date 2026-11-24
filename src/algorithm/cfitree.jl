# CFI-tree và kiểm tra tính đóng của itemset.
#   relative_items  : phần của một itemset mà một CFI-tree lưu được
#   insert_cfi!     : chèn một CFI vào CFI-tree
#   closed_checking : kiểm tra đã có CFI nào bao trùm itemset với cùng count chưa
#   init_cfitree    : tạo CFI-tree con từ CFI-tree cha cho lời gọi đệ quy
#   cfi_list        : liệt kê các CFI đang lưu trong cây (dùng khi test)
#   node_count      : đếm số nút của cây (không tính gốc)
# Quy ước "tương đối": CFI-tree của X lưu mỗi CFI dưới dạng phần còn lại sau khi bỏ X, và chỉ
# giữ các item có trong header của cây. Các item khác không bao giờ xuất hiện trong itemset
# cần kiểm tra ở cây này nên bỏ đi không làm sai kết quả. Count của gốc là count lớn nhất
# trong mọi CFI đã chèn, dùng để kiểm tra chính X.

"""
    relative_items(C, itemset) -> Vector{Int}

Phần của `itemset` mà `C` lưu được: giữ các item có trong header của `C` (item của `C.base`
không nằm trong header nên tự bị bỏ), sắp theo thứ tự header.

- `C`       : CFI-tree
- `itemset` : itemset đầy đủ
"""
relative_items(C::CFITree, itemset) =
    sort!([i for i in itemset if haskey(C.rank, i)]; by = i -> C.rank[i])

"""
    insert_cfi!(C, items, count) -> C

Chèn một CFI vào CFI-tree. Count của mỗi nút trên đường đi là max(count cũ, `count`), KHÔNG
cộng dồn như FP-tree. Count của gốc cũng được cập nhật theo cách đó.

- `C`     : CFI-tree
- `items` : CFI ở dạng tương đối, sắp theo `C.rank`
- `count` : support của CFI
"""
function insert_cfi!(C::CFITree, items::Vector{Int}, count::Int)
    node = C.root
    node.count = max(node.count, count)
    for item in items
        child = get(node.children, item, nothing)
        if child === nothing
            child = add_child!(C, node, item, count)
        else
            child.count = max(child.count, count)
        end
        node = child
    end
    return C
end

"""
    closed_checking(C, items, count; exact_count = true, stats = nothing) -> Bool

Kiểm tra trong `C` đã có CFI nào chứa itemset đang xét với cùng count chưa.
Trả về `true` nếu đã có, tức itemset KHÔNG đóng; `false` nếu chưa có.

- `C`           : CFI-tree
- `items`       : phần tương đối của itemset (itemset = `C.base` ∪ `items`), sắp theo `C.rank`;
                  rỗng nghĩa là hỏi về chính `C.base`
- `count`       : support của itemset
- `exact_count` : `true` thì chỉ xét nút có count đúng bằng `count`; `false` xét nút có count ≥ `count`
- `stats`       : một `FPCloseStats` hoặc `nothing`; nếu có thì `subset_tests` được cộng thêm 1 cho
                  mỗi nút phải đi ngược lên kiểm tra tập con

Cách làm: mọi tập cha phải chứa item cuối của `items` nên chỉ duyệt node-link của item đó.
Count của nút là count lớn nhất trong các CFI đi qua nút. Nếu đường từ gốc tới nút chứa itemset
thì mọi CFI đi qua nút đều là tập cha của itemset, nên count của chúng không vượt `count`; vì vậy
nút khớp chỉ có thể có count đúng bằng `count`, và nút có count lớn hơn bị loại ngay mà không cần
kiểm tra tập con (kết quả không đổi so với `>=`, chỉ bớt việc). Cũng bỏ nút có `level` nhỏ hơn số
item cần tìm. Từ mỗi nút còn lại đi ngược lên cha để tìm các item còn lại; rank giảm dần khi đi
lên nên gặp rank nhỏ hơn item đang cần là biết chắc không có.
"""
function closed_checking(C::CFITree, items::Vector{Int}, count::Int;
                         exact_count::Bool = true, stats = nothing)
    k = length(items)
    k == 0 && return exact_count ? C.root.count == count : C.root.count >= count
    # Hạng của items[1:k-1], tính MỘT lần mỗi lần gọi, chỉ khi có nút đầu tiên phải kiểm tra tập con.
    # 0 = item không có trong C.rank: khi cần so sánh thì tra lại Dict (ném KeyError như bản cũ).
    rk = nothing
    for n in nodelink(C, @inbounds items[k])
        (exact_count ? n.count != count : n.count < count) && continue
        n.level < k && continue
        stats === nothing || (stats.subset_tests += 1)
        if rk === nothing
            rk = Vector{Int}(undef, k - 1)
            @inbounds for j in 1:(k - 1)
                rk[j] = get(C.rank, items[j], 0)
            end
        end
        rv = rk::Vector{Int}
        idx = k - 1
        p = n.parent
        @inbounds while idx > 0 && p.item != ROOT_ITEM      # 1 ≤ idx ≤ k-1 trong thân vòng lặp
            p.level < idx && break
            if p.item == items[idx]
                idx -= 1
            elseif _node_rank(C, p) < _item_rank(C, items[idx], rv[idx])
                break
            end
            p = p.parent
        end
        idx == 0 && return true         # tìm thấy tập cha cùng count: itemset không đóng
    end
    return false
end

# Hạng lưu trong nút CFI (gán khi chèn); 0 nghĩa là item không có trong C.rank, tra lại Dict như bản cũ.
@inline _node_rank(C::CFITree, p::CFINode) = p.rank > 0 ? p.rank : C.rank[p.item]
# Hạng đã tính trước của một item cần tìm; 0 thì tra lại Dict như bản cũ.
@inline _item_rank(C::CFITree, item::Int, r::Int) = r > 0 ? r : C.rank[item]

"""
    init_cfitree(C, item, ty) -> CFITree

Tạo CFI-tree cho cây điều kiện `ty` của Y = `C.base` ∪ {`item`}, nạp sẵn mọi CFI đã biết có chứa Y.

- `C`    : CFI-tree cha
- `item` : item mở rộng thêm vào `C.base`
- `ty`   : FP-tree điều kiện của Y (cho thứ tự item của cây mới)

Các CFI chứa `item` là những đường đi qua một nút của `item` trong `C`; với mỗi nút đó duyệt
cây con của nó để lấy lại các CFI, sắp theo thứ tự item của `ty` (có thể khác `C`) rồi chèn.
"""
function init_cfitree(C::CFITree, item::Int, ty::FPTree)
    cy = CFITree(ty)
    for n in nodelink(C, item)
        above = prefix_path(n)
        collect_paths!(cy, n, above)
    end
    return cy
end

"""
    collect_paths!(cy, m, path) -> cy

Duyệt cây con của `m` và chèn các CFI tìm được vào `cy`. Một CFI kết thúc đúng tại nút có count
lớn hơn count của mọi con (nút lá cũng vậy); các nút còn lại đã được nhánh con dài hơn cùng
count bao trùm nên không cần chèn.

- `cy`   : CFI-tree đích
- `m`    : nút đang xét
- `path` : các item từ gốc đến `m` (bỏ item đang mở rộng). Dùng chung một mảng cho cả cuộc duyệt:
           thêm item trước khi đệ quy xuống con và bỏ đi sau đó, nên khi trả về mảng giữ nguyên
           như lúc vào; không giữ tham chiếu tới `path` sau khi chèn
"""
function collect_paths!(cy::CFITree, m::CFINode, path::Vector{Int})
    best_child = 0
    for c in values(m.children)
        best_child = max(best_child, c.count)
        push!(path, c.item)
        collect_paths!(cy, c, path)
        pop!(path)
    end
    if m.count > best_child
        insert_cfi!(cy, relative_items(cy, path), m.count)
    end
    return cy
end

"""
    cfi_list(C) -> Vector{Pair{Vector{Int},Int}}

Liệt kê các tập đang lưu trong `C` (dạng tương đối) kèm count. Một tập kết thúc tại nút có
count lớn hơn count của mọi con, vì nếu có con cùng count thì tập dài hơn đó bao trùm nó.
Với CFI-tree đầy đủ đó chính là các CFI; với CFI-tree rút gọn, mỗi tập đã bị bỏ bớt item dùng để
mở rộng xuống tầng dưới nên không phải CFI nguyên vẹn.

- `C` : CFI-tree
"""
function cfi_list(C::CFITree)
    out = Pair{Vector{Int},Int}[]
    # `path` dùng chung cho cả cuộc duyệt (thêm trước khi đệ quy, bỏ sau đó); chỉ sao chép khi lưu vào `out`
    walk(m, path) = begin
        best_child = 0
        for c in values(m.children)
            best_child = max(best_child, c.count)
            push!(path, c.item)
            walk(c, path)
            pop!(path)
        end
        m.count > best_child && push!(out, copy(path) => m.count)
    end
    walk(C.root, Int[])
    return out
end

"""
    node_count(C) -> Int

Số nút của CFI-tree `C`, không tính nút gốc.

- `C` : CFI-tree
"""
function node_count(C::CFITree)
    total = 0
    for item in keys(C.head)
        for _ in nodelink(C, item)
            total += 1
        end
    end
    return total
end
