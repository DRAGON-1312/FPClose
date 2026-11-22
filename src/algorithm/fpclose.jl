# fpclose.jl
# Thủ tục FPclose (Grahne & Zhu 2005, Section 4.1 tr. 1353–1355, Fig. 8 tr. 1354).
#
#   FPCloseStats : bộ đếm thống kê (số lời gọi, số lần cắt dòng 8, ...)
#   fpclose      : hàm gọi từ bên ngoài, trả về mọi closed frequent itemset
#   fpclose!     : thân đệ quy, đúng theo Fig. 8
#   record!      : lưu một CFI mới và chèn nó vào mọi CFI-tree trên đường đệ quy
#
# Các chỗ khác hoặc bổ sung so với bài báo được liệt kê đầy đủ ở docs/DEVIATIONS.md.

"""
    FPCloseStats(; keep_pruned = false)

Bộ đếm cộng dồn qua các lần chạy nếu dùng lại cùng một đối tượng. Truyền vào
`fpclose(...; stats = FPCloseStats())`; không truyền thì không đếm gì.

- `calls`         : số lời gọi `fpclose!` (số lần FPclose(T, C) được gọi, Fig. 8).
- `pruned_line8`  : số lần dòng 8 cắt nhánh (Y đã có CFI cha cùng count).
- `closed_checks` : số lần gọi `closed_checking` (dòng 4, dòng 8, bước kiểm X).
- `cfis`          : số CFI tìm được.
- `fparray_hits`  : số lần `conditional_tree` đọc tail từ FP-array thay vì duyệt cây.
- `early_stops`   : số lời gọi `fpclose!` kết thúc sớm (Sec 4.1 tr. 1355).
- `pruned_sets`   : các Y bị cắt ở dòng 8, chỉ lưu khi `keep_pruned = true`
                    (dùng cho test; không bật khi benchmark vì tốn bộ nhớ).
"""
mutable struct FPCloseStats
    calls::Int
    pruned_line8::Int
    closed_checks::Int
    cfis::Int
    fparray_hits::Int
    early_stops::Int
    keep_pruned::Bool
    pruned_sets::Vector{Vector{Int}}
end

FPCloseStats(; keep_pruned::Bool = false) =
    FPCloseStats(0, 0, 0, 0, 0, 0, keep_pruned, Vector{Int}[])

"""
    FPCloseOptions(; prune_line8 = true, fparray = true, early_termination = true,
                   dense_ratio = 0.15, skip_items = 15, max_items = 5000)

Các công tắc tối ưu của `fpclose`. Tắt cả ba công tắc cho "bản cơ bản" của Fig. 8
(không FP-array, không kết thúc sớm; `prune_line8` là dòng 8 của chính Fig. 8 nhưng chỉ
là tối ưu, xem docs/DEVIATIONS.md mục 3). Kết quả mọi tổ hợp đều giống nhau.

- `prune_line8`       : cắt nhánh ở dòng 8.
- `fparray`           : dùng FP-array (Sec 2.2–2.3), tham số `dense_ratio`, `skip_items`,
                        `max_items` xem `FPArrayConfig`.
- `early_termination` : kết thúc sớm một lời gọi (Sec 4.1 tr. 1355).
"""
struct FPCloseOptions
    prune_line8::Bool
    early_termination::Bool
    fparray::Union{FPArrayConfig,Nothing}
end

function FPCloseOptions(; prune_line8::Bool = true, fparray::Bool = true,
                        early_termination::Bool = true, dense_ratio::Real = 0.15,
                        skip_items::Integer = 15, max_items::Integer = 5000)
    cfg = fparray ? FPArrayConfig(; dense_ratio, skip_items, max_items) : nothing
    return FPCloseOptions(prune_line8, early_termination, cfg)
end

"""
    fpclose(db, minsup::Int; stats = nothing, prune_line8 = true, fparray = true,
            early_termination = true, dense_ratio = 0.15, skip_items = 15, max_items = 5000)
    fpclose(db, minsup::Float64; kwargs...)

Khai thác mọi closed frequent itemset của `db` (Fig. 8, gọi lần đầu với T_∅ và C_∅
rỗng, Sec 4.1 tr. 1354).
`minsup` là số nguyên = ngưỡng tuyệt đối (số giao dịch), là số thực = tỉ lệ
(ví dụ 0.2 = 20%, đổi sang số giao dịch bằng `minsup_count`).

- `stats`       : một `FPCloseStats` để đếm (xem docstring của nó).
- `prune_line8`, `fparray`, `early_termination` và các tham số FP-array: xem
  `FPCloseOptions`. Tắt công tắc nào cũng không đổi kết quả, chỉ đổi tốc độ và bộ nhớ;
  dùng để đo lợi ích từng kỹ thuật ở Chương 2.

Trả về `Vector{Pair{Vector{Int},Int}}`: mỗi phần tử là `itemset => support`,
itemset sắp tăng dần.
"""
function fpclose(db::Vector{Vector{Int}}, minsup::Int;
                 stats::Union{FPCloseStats,Nothing} = nothing, kwargs...)
    results, _ = run_fpclose(db, minsup, stats, FPCloseOptions(; kwargs...))
    return results
end

fpclose(db::Vector{Vector{Int}}, minsup::Float64; kwargs...) =
    fpclose(db, minsup_count(minsup, length(db)); kwargs...)

"""
    run_fpclose(db, minsup, stats, opts) -> (results, C_∅)

Như `fpclose` nhưng trả thêm CFI-tree gốc C_∅ sau khi chạy xong (Sec 4.1 tr. 1354:
"At the end of the execution of FPclose, the CFI-tree C_∅ contains all CFIs mined").
Dùng để đối chiếu với Fig. 7b trong test. `opts` là `FPCloseOptions`, hoặc một `Bool` =
`prune_line8` (mọi tối ưu khác tắt, như bản cơ bản).
"""
function run_fpclose(db::Vector{Vector{Int}}, minsup::Int, stats, opts::FPCloseOptions)
    tree = build_fptree(db, minsup, opts.fparray)   # T_∅
    croot = CFITree(tree)                           # C_∅, rỗng
    results = Pair{Vector{Int},Int}[]
    stack = CFITree[croot]                          # các CFI-tree đang mở trên đường đệ quy
    fpclose!(tree, croot, minsup, stack, results, stats, opts)
    return results, croot
end

run_fpclose(db, minsup::Int, stats, prune_line8::Bool) =
    run_fpclose(db, minsup, stats,
                FPCloseOptions(; prune_line8, fparray = false, early_termination = false))

# closed_checking có đếm. Không có `stats` thì không tốn thêm gì ngoài một phép so sánh.
@inline function check!(stats, C::CFITree, items::Vector{Int}, count::Int)
    stats === nothing || (stats.closed_checks += 1)
    return closed_checking(C, items, count)
end

"""
    record!(results, stack, itemset, count, stats)

Fig. 8 dòng 5 (insert X into C) kết hợp dòng 17 (merge C_Y with C).
Sec 4.1 tr. 1354: "Note that line 17 is not implemented as such. As in algorithm
FPmax*, we found it more efficient to do the insertion of lines 3-5 into all CFI-trees
currently in memory." Sec 3.2 tr. 1352–1353 giải thích cách này cho FPmax*: chèn vào
"all preceding MFI-trees that the implementation of the recursion needs to store in
memory in any case", cây của Y_k nhận B ∪ (Y_j − Y_k).

Ở đây: lưu CFI `itemset` rồi chèn vào MỌI CFI-tree trong `stack`, mỗi cây nhận phần
tương đối của nó (`relative_items`). Hợp lệ vì base của cây trong cùng chứa base của mọi
cây trên stack, nên `itemset` luôn chứa base của chúng.
"""
function record!(results, stack::Vector{CFITree}, itemset::Vector{Int}, count::Int, stats)
    push!(results, sort(itemset) => count)
    stats === nothing || (stats.cfis += 1)
    for C in stack
        insert_cfi!(C, relative_items(C, itemset), count)
    end
    return results
end

"""
    fpclose!(T, C, minsup, stack, results, stats, opts)

Một lời gọi FPclose(T, C) của Fig. 8 (tr. 1354). `T` là conditional FP-tree của
X = T.base, `C` là CFI-tree đi kèm (đỉnh của `stack`). Số trong comment là số dòng của
Fig. 8. FP-array (dòng 9–10, 14) nằm trong `conditional_tree`; kết thúc sớm (Sec 4.1
tr. 1355) nằm ngay trong vòng lặp dòng 6. Chưa cài: CFI-tree rút gọn (docs/DEVIATIONS.md
mục 8).

Kết thúc sớm. Sec 4.1 tr. 1355: "Suppose an FP-tree for itemset Y has multiple branches,
the count of Y is c and the order of items in its header table is i1, i2, ..., ik. Starting
from ik, for each item in the header table, we may need to do the work from line 7 to
line 17. If for any item, say im, where m ≤ k, Y ∪ {i1, i2, ..., im} is a closed itemset
with count c, FPclose can terminate the current call. This is because closed_checking
would always return true for the remaining items." (Y của bài báo là `T.base`.)
Cài đặt: `T.items[1:m]` đã có count c khi và chỉ khi `m ≤ m0`, với m0 là số item của header
có count bằng `T.base_count` (header giảm dần theo count). Với mỗi m ≤ m0, nếu
`closed_checking` báo đã có CFI ⊇ X ∪ {i1..im} cùng count c thì dừng. Điều kiện "đã có
trong C" bao gồm cả trường hợp X ∪ {i1..im} chính là một CFI đã ghi và trường hợp nó là
tập con cùng count của một CFI đã ghi; cả hai đều khiến dòng 8 loại mọi item còn lại.
"""
function fpclose!(T::FPTree, C::CFITree, minsup::Int, stack::Vector{CFITree},
                  results, stats, opts::FPCloseOptions)
    stats === nothing || (stats.calls += 1)

    path = single_path(T)
    if path !== nothing                                        # 1. if T only contains a single branch B
        # 2. generate all CFI's from B. Nhánh (i1:c1, ..., ip:cp), count giảm dần
        # (Sec 4.1 tr. 1354). X ∪ {i1..ij} là ứng viên khi cj ≠ cj+1 hoặc j = p.
        # Bài báo chỉ nói "cj ≠ cj+1", bỏ sót tiền tố đầy đủ (docs/DEVIATIONS.md mục 2).
        for j in eachindex(path)
            cj = path[j].count
            if j == length(path) || cj != path[j+1].count
                rel = Int[path[x].item for x in 1:j]           # đã theo thứ tự header
                # 3. for each CFI X generated
                # 4. if not closed_checking(X, C)
                if !check!(stats, C, rel, cj)
                    record!(results, stack, vcat(T.base, rel), cj, stats)   # 5. insert X into C
                end
            end
        end
    else
        # 6. else for each i in T.header do begin
        # Duyệt từ item ít phổ biến nhất lên. Sec 3.2 tr. 1352 (FPmax*): "The items in
        # the header table of T are processed in increasing order of frequency, so that
        # maximal frequent itemsets will be found before any of their frequent subsets."
        # Sec 4.1 tr. 1355 cũng nói "Starting from i_k, for each item in the header table".
        # Hệ quả: tập tìm sau chỉ có thể là tập con của CFI tìm trước.
        m0 = 0                                     # số item đầu header có count = count(X)
        if opts.early_termination
            while m0 < length(T.items) && T.item_count[T.items[m0+1]] == T.base_count
                m0 += 1
            end
        end
        for m in length(T.items):-1:1
            i = T.items[m]
            # Kết thúc sớm (Sec 4.1 tr. 1355), xem docstring.
            if m <= m0 && check!(stats, C, T.items[1:m], T.base_count)
                stats === nothing || (stats.early_stops += 1)
                break
            end
            c = T.item_count[i]                    # count của Y; 7. set Y = T.base ∪ {i}
            # 8. if not closed_checking(Y, C): đã có CFI chứa Y với cùng count thì Y không
            # đóng và mọi mở rộng của Y bị CFI đó bao trùm, nên cắt cả nhánh.
            # `prune_line8 = false` bỏ qua phép kiểm này (chỉ để đo; kết quả không đổi).
            if !opts.prune_line8 || !check!(stats, C, [i], c)
                # 9–12. tail = item phổ biến trong pattern base của i: có hàng FP-array của i
                # thì đọc từ FP-array (9–10), không thì duyệt T theo node-link của i (11–12)
                # 13. sort tail giảm dần theo count; 14. construct T_Y và có thể cả A_Y
                # (cả 9–14 nằm trong conditional_tree; header của T_Y được sắp ở FPTree(...))
                stats === nothing || !has_row(T, i) || (stats.fparray_hits += 1)
                ty = conditional_tree(T, i, minsup, opts.fparray)
                cy = init_cfitree(C, i, ty)                    # 15. initialize C_Y
                push!(stack, cy)
                fpclose!(ty, cy, minsup, stack, results, stats, opts)   # 16. call FPclose(T_Y, C_Y)
                pop!(stack)
                # 17. merge C_Y with C: không làm ở đây, record! đã chèn mọi CFI mới vào
                # mọi cây trên stack (Sec 4.1 tr. 1354, "line 17 is not implemented as such").
            else
                stats === nothing || (stats.pruned_line8 += 1;
                    stats.keep_pruned && push!(stats.pruned_sets, sort(vcat(T.base, i))))
            end
        end
    end                                                        # 18. end

    # Chính X = T.base: Fig. 8 không ghi bước này nhưng bắt buộc (docs/DEVIATIONS.md
    # mục 3). X đóng khi không có CFI nào chứa X với cùng count. Tập cha có item của T
    # đã được tìm ở trên và chèn vào C; tập cha có item khác đã bị dòng 8 ở lời gọi cha
    # loại trừ, hoặc không phổ biến (support bằng X thì cũng phổ biến).
    if !isempty(T.base) && !check!(stats, C, Int[], T.base_count)
        record!(results, stack, T.base, T.base_count, stats)
    end
    return results
end
