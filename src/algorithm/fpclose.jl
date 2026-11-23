# Thuật toán FPClose: khai thác mọi tập phổ biến đóng (closed frequent itemset, CFI).
#   FPCloseStats   : bộ đếm thống kê khi chạy
#   FPCloseOptions : các công tắc bật/tắt tối ưu
#   fpclose        : hàm gọi từ bên ngoài
#   run_fpclose    : chạy thuật toán, trả thêm CFI-tree gốc
#   record!        : ghi nhận một CFI mới
#   fpclose!       : thân đệ quy của thuật toán

"""
    FPCloseStats(; keep_pruned = false)

Bộ đếm thống kê trong quá trình chạy. Nếu dùng lại cùng một đối tượng cho nhiều lần
chạy thì các bộ đếm được cộng dồn.

- `calls`         : số lần gọi đệ quy `fpclose!`
- `pruned_line8`  : số nhánh bị cắt vì Y đã nằm trong một CFI có cùng count
- `closed_checks` : số lần gọi `closed_checking`
- `cfis`          : số CFI tìm được
- `fparray_hits`  : số lần lấy tail từ FP-array thay vì duyệt cây
- `early_stops`   : số lần gọi đệ quy kết thúc sớm
- `tree_traversals` : số lần đi theo một node-link trên FP-tree khi dựng cây điều kiện
                      (2 lần nếu phải đếm item bằng cách duyệt cây, 1 lần nếu lấy tail từ FP-array)
- `subset_tests`    : số nút CFI-tree vượt qua bộ lọc count và level, phải đi ngược lên kiểm tra tập con
- `cfi_nodes`       : tổng số nút của mọi CFI-tree đã tạo, tính theo kích thước lúc cây bị bỏ đi
                      (gồm cả cây gốc ở cuối); đo mức tốn bộ nhớ của CFI-tree
- `root_cfi_nodes`  : số nút của CFI-tree gốc ở cuối quá trình chạy
- `keep_pruned`   : `true` thì lưu lại các Y bị cắt (chỉ dùng khi test)
- `pruned_sets`   : danh sách các Y bị cắt
"""
mutable struct FPCloseStats
    calls::Int
    pruned_line8::Int
    closed_checks::Int
    cfis::Int
    fparray_hits::Int
    early_stops::Int
    tree_traversals::Int
    subset_tests::Int
    cfi_nodes::Int
    root_cfi_nodes::Int
    keep_pruned::Bool
    pruned_sets::Vector{Vector{Int}}
end

# Khởi tạo mọi bộ đếm bằng 0
FPCloseStats(; keep_pruned::Bool = false) =
    FPCloseStats(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, keep_pruned, Vector{Int}[])

"""
    FPCloseOptions(; prune_line8 = true, fparray = true, early_termination = true, exact_count = true,
                   reduced_cfitree = true, dense_ratio = 0.15, skip_items = 15, max_items = 5000)

Các công tắc tối ưu. Bật hay tắt công tắc nào thì kết quả cũng không đổi, chỉ thay đổi
tốc độ và bộ nhớ.

- `prune_line8`       : cắt nhánh khi Y đã nằm trong một CFI có cùng count
- `fparray`           : dùng FP-array để bỏ bớt một lần duyệt cây
- `early_termination` : cho phép dừng sớm một lời gọi đệ quy
- `exact_count`       : khi kiểm tra đóng chỉ xét nút CFI-tree có count đúng bằng count cần kiểm tra
                        (`false`: xét count ≥, chậm hơn nhưng cùng kết quả)
- `reduced_cfitree`   : CFI-tree rút gọn: khi ghi một CFI vào cây của X, bỏ item đang mở rộng xuống tầng
                        dưới vì phần còn lại của lời gọi không bao giờ hỏi tới item đó. Cây nhỏ hơn nên
                        tốn ít bộ nhớ hơn, nhưng cây gốc không còn chứa đủ mọi CFI (kết quả lấy từ `results`)
- `dense_ratio`       : ngưỡng tỉ lệ node để coi cây là dày (không tính FP-array)
- `skip_items`        : số item đầu header không cần tính trong FP-array
- `max_items`         : số item tối đa để còn tạo FP-array (tránh tốn bộ nhớ)
"""
struct FPCloseOptions
    prune_line8::Bool
    early_termination::Bool
    fparray::Union{FPArrayConfig,Nothing}   # `nothing` nghĩa là không dùng FP-array
    exact_count::Bool
    reduced_cfitree::Bool
end

function FPCloseOptions(; prune_line8::Bool = true, fparray::Bool = true,
                        early_termination::Bool = true, exact_count::Bool = true,
                        reduced_cfitree::Bool = true, dense_ratio::Real = 0.15,
                        skip_items::Integer = 15, max_items::Integer = 5000)
    # Chỉ tạo cấu hình FP-array khi công tắc fparray được bật
    cfg = fparray ? FPArrayConfig(; dense_ratio, skip_items, max_items) : nothing
    return FPCloseOptions(prune_line8, early_termination, cfg, exact_count, reduced_cfitree)
end

"""
    fpclose(db, minsup; stats = nothing, kwargs...)

Khai thác mọi tập phổ biến đóng của cơ sở dữ liệu.

- `db`     : danh sách giao dịch, mỗi giao dịch là một `Vector{Int}`
- `minsup` : số nguyên = số giao dịch tối thiểu; số thực = tỉ lệ (ví dụ 0.2 = 20%)
- `stats`  : một `FPCloseStats` nếu muốn đếm thống kê
- `kwargs` : các tùy chọn của `FPCloseOptions`

Trả về `Vector{Pair{Vector{Int},Int}}`, mỗi phần tử là `itemset => support`,
itemset được sắp tăng dần.
"""
function fpclose(db::Vector{Vector{Int}}, minsup::Int;
                 stats::Union{FPCloseStats,Nothing} = nothing, kwargs...)
    results, _ = run_fpclose(db, minsup, stats, FPCloseOptions(; kwargs...))
    return results
end

# minsup dạng tỉ lệ: đổi sang số giao dịch rồi gọi bản số nguyên
fpclose(db::Vector{Vector{Int}}, minsup::Float64; kwargs...) =
    fpclose(db, minsup_count(minsup, length(db)); kwargs...)

"""
    run_fpclose(db, minsup, stats, opts) -> (results, C_∅)

Chạy FPClose và trả về cả danh sách CFI lẫn CFI-tree gốc C_∅ (dùng để kiểm tra
cấu trúc cây trong test).

- `db`, `minsup`, `stats` : như `fpclose`
- `opts` : một `FPCloseOptions`, hoặc một `Bool` (= `prune_line8`, mọi tối ưu khác tắt)
"""
function run_fpclose(db::Vector{Vector{Int}}, minsup::Int, stats, opts::FPCloseOptions)
    tree = build_fptree(db, minsup, opts.fparray)   # xây FP-tree gốc T_∅ (2 lần quét DB)
    croot = CFITree(tree)                           # CFI-tree gốc C_∅, ban đầu rỗng
    results = Pair{Vector{Int},Int}[]               # nơi lưu kết quả
    stack = CFITree[croot]                          # các CFI-tree đang mở trên đường đệ quy
    fpclose!(tree, croot, minsup, stack, results, stats, opts)
    if stats !== nothing
        n = node_count(croot)
        stats.cfi_nodes += n
        stats.root_cfi_nodes += n
    end
    return results, croot
end

# Bản cơ bản: chỉ chọn có cắt nhánh hay không, tắt mọi tối ưu khác
run_fpclose(db, minsup::Int, stats, prune_line8::Bool) =
    run_fpclose(db, minsup, stats,
                FPCloseOptions(; prune_line8, fparray = false, early_termination = false,
                               exact_count = false, reduced_cfitree = false))

"""
    check!(stats, C, items, count; exact_count = true) -> Bool

Gọi `closed_checking` và đếm số lần gọi (và số lần kiểm tra tập con nếu có `stats`).
Trả về `true` nếu trong `C` đã có một CFI chứa `items` với cùng `count`,
tức là `items` KHÔNG đóng.

- `C`     : CFI-tree cần so sánh
- `items` : itemset cần kiểm tra (tính tương đối, không gồm base của `C`)
- `count` : support của itemset
- `exact_count` : xem `closed_checking`
"""
@inline function check!(stats, C::CFITree, items::Vector{Int}, count::Int; exact_count::Bool = true)
    stats === nothing || (stats.closed_checks += 1)
    return closed_checking(C, items, count; exact_count = exact_count, stats = stats)
end

"""
    record!(results, stack, itemset, count, stats, reduced)

Ghi nhận một CFI mới: thêm vào danh sách kết quả và chèn vào MỌI CFI-tree đang mở
trên đường đệ quy, để các lần kiểm tra sau ở mọi tầng đều thấy CFI này.

- `results` : danh sách kết quả
- `stack`   : các CFI-tree đang mở
- `itemset` : CFI đầy đủ (gồm cả base)
- `count`   : support của CFI
- `stats`   : bộ đếm thống kê hoặc `nothing`
- `reduced` : `true` thì với mỗi cây còn bỏ thêm item đang mở rộng xuống tầng dưới (`child_item`):
              phần còn lại của lời gọi ở tầng đó chỉ hỏi về itemset không chứa item này nên không cần lưu nó.
              Count của gốc vẫn được cập nhật kể cả khi phần chèn vào rỗng
"""
function record!(results, stack::Vector{CFITree}, itemset::Vector{Int}, count::Int, stats,
                 reduced::Bool)
    push!(results, sort(itemset) => count)                   # lưu kết quả, itemset sắp tăng dần
    stats === nothing || (stats.cfis += 1)
    for C in stack
        items = relative_items(C, itemset)                   # mỗi cây nhận phần itemset bỏ đi base của nó
        reduced && C.child_item != ROOT_ITEM && filter!(!=(C.child_item), items)
        insert_cfi!(C, items, count)
    end
    return results
end

"""
    fpclose!(T, C, minsup, stack, results, stats, opts)

Thân đệ quy của FPClose: tìm mọi CFI có chứa X = `T.base`.

- `T`       : conditional FP-tree của X
- `C`       : CFI-tree của X (đỉnh của `stack`), chứa các CFI đã tìm có chứa X
- `minsup`  : ngưỡng support (số giao dịch)
- `stack`   : các CFI-tree đang mở trên đường đệ quy
- `results` : danh sách kết quả
- `stats`   : bộ đếm thống kê hoặc `nothing`
- `opts`    : các công tắc tối ưu
"""
function fpclose!(T::FPTree, C::CFITree, minsup::Int, stack::Vector{CFITree},
                  results, stats, opts::FPCloseOptions)
    stats === nothing || (stats.calls += 1)

    path = single_path(T)                    # trả về nhánh duy nhất nếu T chỉ có một nhánh, ngược lại `nothing`

    if path !== nothing
        # ---- TRƯỜNG HỢP 1: T chỉ có một nhánh (i1:c1, ..., ip:cp), count giảm dần ----
        # Ứng viên CFI là X ∪ {i1..ij} tại những chỗ count thay đổi (cj ≠ cj+1),
        # và luôn có cả nhánh đầy đủ (j = p).
        for j in eachindex(path)
            cj = path[j].count
            if j == length(path) || cj != path[j+1].count
                rel = Int[path[x].item for x in 1:j]                     # các item i1..ij
                if !check!(stats, C, rel, cj; exact_count = opts.exact_count)                            # chưa có CFI nào bao trùm nó
                    record!(results, stack, vcat(T.base, rel), cj, stats, opts.reduced_cfitree) # ghi nhận CFI = X ∪ {i1..ij}
                end
            end
        end
    else
        # ---- TRƯỜNG HỢP 2: T có nhiều nhánh, xét từng item trong header ----

        # m0 = số item đầu header có count bằng count của X
        # (các item này xuất hiện trong MỌI giao dịch chứa X)
        m0 = 0
        if opts.early_termination
            while m0 < length(T.items) && T.item_count[T.items[m0+1]] == T.base_count
                m0 += 1
            end
        end

        # Duyệt header từ item ít phổ biến nhất lên, để superset luôn được tìm trước tập con
        for m in length(T.items):-1:1
            i = T.items[m]

            # Kết thúc sớm: nếu X ∪ {i1..im} đã nằm trong một CFI cùng count
            # thì mọi item còn lại chắc chắn sẽ bị cắt, nên dừng luôn
            if m <= m0 && check!(stats, C, T.items[1:m], T.base_count; exact_count = opts.exact_count)
                stats === nothing || (stats.early_stops += 1)
                break
            end

            c = T.item_count[i]              # support của Y = X ∪ {i}

            # Cắt nhánh: nếu Y đã nằm trong một CFI có cùng count thì Y không đóng
            # và mọi mở rộng của Y cũng bị CFI đó bao trùm, nên bỏ qua cả nhánh
            if !opts.prune_line8 || !check!(stats, C, [i], c; exact_count = opts.exact_count)
                stats === nothing || !has_row(T, i) || (stats.fparray_hits += 1)
                ty = conditional_tree(T, i, minsup, opts.fparray; stats = stats)   # xây T_Y (lấy tail từ FP-array nếu có, không thì duyệt cây)
                cy = init_cfitree(C, i, ty)                        # tạo C_Y: chỉ giữ các CFI trong C có chứa i
                C.child_item = i                                   # cho record! biết item đang mở rộng xuống C_Y
                push!(stack, cy)                                   # mở C_Y
                fpclose!(ty, cy, minsup, stack, results, stats, opts)   # đệ quy với Y
                pop!(stack)                                        # đóng C_Y (CFI mới đã được record! chèn vào C)
                C.child_item = ROOT_ITEM
                stats === nothing || (stats.cfi_nodes += node_count(cy))
            else
                stats === nothing || (stats.pruned_line8 += 1;
                    stats.keep_pruned && push!(stats.pruned_sets, sort(vcat(T.base, i))))
            end
        end
    end

    # Kiểm tra chính X = T.base: X đóng nếu chưa có CFI nào chứa X với cùng count.
    # Làm sau cùng để mọi superset của X trong lời gọi này đã được tìm ra trước.
    if !isempty(T.base) && !check!(stats, C, Int[], T.base_count; exact_count = opts.exact_count)
        record!(results, stack, T.base, T.base_count, stats, opts.reduced_cfitree)
    end
    return results
end