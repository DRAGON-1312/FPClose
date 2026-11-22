# cfitree.jl
# CFI-tree và kiểm tra đóng (Grahne & Zhu 2005, Section 4.1 tr. 1352–1354, Fig. 7;
# cách khởi tạo và chèn nằm ở Section 3.2 tr. 1352–1353).
#
#   insert_cfi!      : chèn một CFI vào CFI-tree (count lấy MAX)
#   closed_checking  : đã có CFI cha cùng count chưa? (TRUE = đã có = KHÔNG đóng)
#   init_cfitree     : khởi tạo C_Y từ C_X cho lời gọi đệ quy (Fig. 8, dòng 15)
#   cfi_list         : liệt kê các CFI đang lưu trong cây (để kiểm thử/đối chiếu Fig. 7)
#
# Quy ước "tương đối": C_X lưu mỗi CFI S ⊇ X dưới dạng phần còn lại của S,
# chỉ giữ các item có trong header của C_X (tức header của T_X). Các item
# khác không bao giờ xuất hiện trong ứng viên sẽ kiểm tra ở C_X, nên bỏ đi
# không làm sai phép thử "S ⊇ ứng viên" (xem docs/DEVIATIONS.md, mục 6).
# Gốc của C_X giữ count lớn nhất trong mọi CFI đã chèn: đó là câu trả lời cho
# câu hỏi "X có tập cha nào cùng count không?" (ứng viên rỗng).

"""
    relative_items(C, itemset)

Phần của `itemset` mà `C` lưu được: giữ item có trong header của `C`,
sắp theo thứ tự header. Item của `C.base` không nằm trong header nên tự bị bỏ.
Tương ứng "B ∪ (Y_j − Y_k)" chèn vào cây của Y_k (Sec 3.2, tr. 1353).
"""
relative_items(C::CFITree, itemset) =
    sort!([i for i in itemset if haskey(C.rank, i)]; by = i -> C.rank[i])

"""
    insert_cfi!(C, items, count)

Sec 4.1, tr. 1354: "The insertion of a CFI into a CFI-tree is similar to the insertion
of a transaction into an FP-tree, except now the count of a node is not incremented,
but replaced by the maximal count up-to-date."

Chèn `items` (dạng tương đối, sắp theo `C.rank`) với `count` vào `C`. Count của mỗi
nút trên đường đi là max(count cũ, count mới), không cộng dồn (Fig. 7a: nút d từ 2
lên 3). Gốc cũng được cập nhật để trả lời ứng viên rỗng.
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
    closed_checking(C, items, count) -> Bool

Hàm `closed_checking(Y, C)` của Fig. 8 (dòng 4 và 8), mô tả ở Sec 4.1 tr. 1354.
`items` là phần tương đối của Y = C.base ∪ items, sắp theo `C.rank`.

**Trả `true` khi ĐÃ CÓ trong `C` một CFI Z ⊇ Y với count(Z) = `count`, tức Y KHÔNG đóng**;
trả `false` khi chưa có, tức Y đóng so với các CFI đã tìm.

Vì sao chọn cực tính này (bài báo tự mâu thuẫn):
- Fig. 8 viết `if not closed_checking(Y, C)` rồi mới chèn Y (dòng 4) hoặc mới đệ quy
  (dòng 8). Chỉ đọc được nếu hàm trả true khi Y KHÔNG đóng.
- `maximality_checking` ở Sec 3.2 (tr. 1352) cũng trả true khi itemset là tập con của
  một MFI đã có, và FPmax* dùng `if not maximality_checking` y như vậy.
- Ngược lại, câu chữ Sec 4.1 ("returns true only when there is no existing CFI Z …")
  nói true khi Y đóng. Ta theo Fig. 8 và Sec 3.2 để code đọc giống mã giả.
- Cùng câu đó còn viết "the count of Y is equal to or greater than the count of Z",
  bị ngược: tập cha Z không thể có count lớn hơn Y. Điều kiện thực chất là bằng nhau;
  so với count của nút trong cây thì là `count(nút) ≥ count(Y)` như câu trước đó của
  bài báo ("check if its count is equal to or greater than c").

Cách làm (Sec 4.1, giống `maximality_checking`):
1. Mọi tập cha phải chứa item cuối ik, nên chỉ xét các nút trên node-link của ik.
2. Bỏ nút có count < `count`: mọi CFI đi qua nút đều có count ≤ count của nút.
3. Bỏ nút có level < k: đường từ gốc không đủ dài để chứa k item ("level" dùng để
   tiết kiệm phép so sánh, tr. 1354).
4. Đi ngược lên cha, tìm lần lượt i(k-1), ..., i1. Rank giảm dần khi đi lên,
   nên gặp nút có rank nhỏ hơn item đang cần tìm là biết chắc không có.
`items` rỗng: hỏi về chính base X, câu trả lời nằm ở count của gốc.
"""
function closed_checking(C::CFITree, items::Vector{Int}, count::Int)
    k = length(items)
    k == 0 && return C.root.count >= count
    for n in nodelink(C, items[k])
        n.count < count && continue
        n.level < k && continue
        idx = k - 1
        p = n.parent
        while idx > 0 && p.item != ROOT_ITEM
            p.level < idx && break
            if p.item == items[idx]
                idx -= 1
            elseif C.rank[p.item] < C.rank[items[idx]]
                break
            end
            p = p.parent
        end
        idx == 0 && return true         # tìm thấy tập cha cùng count: Y không đóng
    end
    return false
end

"""
    init_cfitree(C, item, ty)

Fig. 8 dòng 15: "initialize Y's conditional CFI-tree C_Y"; Sec 4.1 tr. 1354 nói
"CFI-trees are initialized similarly to MFI-trees, described in Section 3.2".
Sec 3.2 tr. 1353: "The initialization can be done by following the linked list for
i_j from the header table of M_{Y_{j-1}} and extracting the maximal frequent itemsets
containing i_j. Each such found itemset I is sorted according to the order of items in
M_{Y_j}.header … and then inserted into M_{Y_j}."

Ở đây: tạo C_Y cho T_Y (Y = C.base ∪ {item}) rồi nạp mọi CFI đã biết có chứa Y.
Các CFI chứa `item` là các đường đi qua một nút của `item` trong `C`. Với mỗi
nút n trên node-link của `item`, xét mọi nút m trong cây con của n (kể cả n):
tập = (tổ tiên của n) ∪ (đường từ n xuống m) bỏ `item`, count = count của m.
Chỉ cần chèn khi m là lá hoặc count(m) lớn hơn count mọi con của m; các
trường hợp còn lại đã được một nhánh con dài hơn với cùng count bao trùm.
(Bài báo "extract" từ danh sách CFI; ở đây đọc lại từ cây, tương đương vì cây
chứa đủ thông tin, xem docs/DEVIATIONS.md mục 6.) Việc sắp "theo header mới" do
`relative_items(cy, …)` làm: thứ tự item của T_Y có thể khác T_X (Sec 2.1 tr. 1349).
"""
function init_cfitree(C::CFITree, item::Int, ty::FPTree)
    cy = CFITree(ty)
    for n in nodelink(C, item)
        above = prefix_path(n)
        collect_paths!(cy, n, above)
    end
    return cy
end

function collect_paths!(cy::CFITree, m::CFINode, path::Vector{Int})
    best_child = 0
    for c in values(m.children)
        best_child = max(best_child, c.count)
        collect_paths!(cy, c, push!(copy(path), c.item))
    end
    if m.count > best_child
        insert_cfi!(cy, relative_items(cy, path), m.count)
    end
    return cy
end

"""
    cfi_list(C) -> Vector{Pair{Vector{Int},Int}}

Liệt kê các CFI (dạng tương đối) đang lưu trong `C`, mỗi CFI kèm count.
Một CFI kết thúc đúng tại nút có count lớn hơn count mọi con (hoặc nút lá): nếu
có con cùng count thì tập con dài hơn đó là CFI cha cùng support, mâu thuẫn tính
đóng. Dùng để đối chiếu với Fig. 7b (C_∅ của CSDL Fig. 1 có 14 CFI).
"""
function cfi_list(C::CFITree)
    out = Pair{Vector{Int},Int}[]
    walk(m, path) = begin
        best_child = 0
        for c in values(m.children)
            best_child = max(best_child, c.count)
            walk(c, push!(copy(path), c.item))
        end
        m.count > best_child && push!(out, copy(path) => m.count)
    end
    walk(C.root, Int[])
    return out
end
