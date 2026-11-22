# recovery.jl
# Khôi phục MỌI frequent itemset (kèm support) từ các closed frequent itemset.
#
# KHÔNG thuộc bài báo Grahne & Zhu: đây là module nhóm bổ sung, vì đề bài yêu cầu "xuất ra tất
# cả frequent itemset và support tương ứng" còn FPClose chỉ xuất tập đóng
# (xem docs/DEVIATIONS.md, mục "Recovery và luật kết hợp").
#
#   recover_all_frequent : closed => mọi frequent itemset

"""
Ngoại lệ do `recover_all_frequent(...; limit = n)` ném ra khi số frequent itemset vượt `n`.
"""
struct RecoveryLimitExceeded <: Exception
    limit::Int
end

Base.showerror(io::IO, e::RecoveryLimitExceeded) =
    print(io, "recover_all_frequent: số frequent itemset vượt giới hạn ", e.limit,
          " (dữ liệu quá dày hoặc minsup quá thấp để khôi phục)")

"""
    recover_all_frequent(closed; limit = nothing, visits = nothing)
        -> Vector{Pair{Vector{Int},Int}}

Từ tập các closed frequent itemset `closed` (mỗi phần tử `itemset => support`, đúng định dạng
`fpclose` trả về), khôi phục mọi frequent itemset khác rỗng kèm support. Kết quả sắp theo độ
dài rồi từ điển (`sort_results!`), mỗi itemset sắp tăng dần.

# Cơ sở lý thuyết

Gọi 𝒞 là tập các CFI (đã lọc theo minsup), sup(X) là support của X.

1. *Mọi FI là tập con của ít nhất một CFI, và mọi tập con khác rỗng của một CFI đều phổ biến.*
   Chiều thuận: với FI X, đặt cl(X) là giao của mọi giao dịch chứa X. cl(X) ⊇ X, nằm trong cùng
   các giao dịch nên sup(cl(X)) = sup(X) ≥ minsup, và không có tập cha thực sự nào của cl(X) giữ
   nguyên support, nên cl(X) là một CFI. Chiều ngược: nếu X ⊆ C với C ∈ 𝒞 thì mọi giao dịch
   chứa C đều chứa X, nên sup(X) ≥ sup(C) ≥ minsup.

2. *sup(X) = max{ sup(C) : C ∈ 𝒞, X ⊆ C }* (cũng là support của CFI nhỏ nhất chứa X, tức cl(X)).
   Với C ⊇ X thì sup(C) ≤ sup(X) (giao dịch chứa C thì chứa X). Dấu bằng đạt tại C = cl(X) ∈ 𝒞
   (theo ý 1). Vậy lấy max trên mọi CFI chứa X cho đúng sup(X).

# Thuật toán

Sắp 𝒞 theo support GIẢM dần. Với mỗi CFI C (theo thứ tự đó), duyệt các tập con của C, gán
support(C) cho tập con CHƯA có trong bảng, không bao giờ ghi đè. Vì các CFI được xử lý theo
support giảm dần, tập con X lần đầu được gán bởi CFI C đầu tiên chứa X, và đó chính là CFI có
support lớn nhất trong các CFI chứa X: giá trị gán đúng bằng max ở ý 2 (không cần so sánh lại).

Duyệt tập con theo DFS *xuống* mạng con (xuất phát từ C, mỗi bước bỏ một item). Khi gặp tập con S
đã có trong bảng thì bỏ qua cả nhánh dưới S: S đã được gán từ một CFI C' xử lý trước đó (support
≥ support(C)), và khi đó mọi tập con của S cũng là tập con của C', nên đã được gán từ lúc xử lý
C' (hoặc sớm hơn) với support ≥. Cắt nhánh này chỉ đúng với cách duyệt xuống: nếu duyệt
"thêm item theo thứ tự tăng dần" thì tập cha của S trong C không nhất thiết đã được gán, nên
không thể bỏ qua nhánh. Mỗi frequent itemset bị gán đúng một lần; số lần gọi hàm duyệt không
vượt tổng độ dài các frequent itemset cộng với |𝒞|.

# Cảnh báo kích thước

Số frequent itemset có thể lớn hơn số CFI theo cấp số mũ: một CFI độ dài ℓ sinh ra tới 2^ℓ − 1
tập con. Với dữ liệu dày (Chess, Accidents, Mushroom ở minsup thấp) recovery hết bộ nhớ hoặc rất
chậm, nên chỉ khả thi ở minsup đủ cao. Tham số `limit` (tuỳ chọn) ném `RecoveryLimitExceeded`
khi số FI vượt `limit` để tránh hết bộ nhớ.

`visits` (tuỳ chọn, `Ref{Int}`): cộng dồn số lần gọi hàm duyệt, dùng để kiểm tra cắt nhánh.
"""
function recover_all_frequent(closed;
                              limit::Union{Int,Nothing} = nothing,
                              visits::Union{Base.RefValue{Int},Nothing} = nothing)
    sorted = sort!([sort(collect(p.first)) => p.second for p in closed]; by = p -> -p.second)
    table = Dict{Vector{Int},Int}()
    for (items, sup) in sorted
        isempty(items) && continue
        descend!(table, items, sup, limit, visits)
    end
    return sort_results!([k => v for (k, v) in table])
end

# DFS xuống mạng con: gán `sup` cho `s` nếu chưa có, rồi thử từng tập con bỏ một item.
# Dùng ngăn xếp tường minh thay cho đệ quy để chịu được CFI dài.
function descend!(table::Dict{Vector{Int},Int}, root::Vector{Int}, sup::Int,
                  limit::Union{Int,Nothing}, visits::Union{Base.RefValue{Int},Nothing})
    stack = Vector{Int}[root]
    while !isempty(stack)
        s = pop!(stack)
        visits === nothing || (visits[] += 1)
        haskey(table, s) && continue          # đã có từ CFI có support ≥: bỏ cả nhánh dưới s
        table[s] = sup
        limit === nothing || length(table) <= limit || throw(RecoveryLimitExceeded(limit))
        length(s) == 1 && continue
        for i in eachindex(s)
            child = Vector{Int}(undef, length(s) - 1)
            copyto!(child, 1, s, 1, i - 1)
            copyto!(child, i, s, i + 1, length(s) - i)
            push!(stack, child)
        end
    end
    return table
end
