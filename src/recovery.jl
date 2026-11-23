# Khôi phục mọi tập phổ biến (kèm support) từ các tập phổ biến đóng. Đây là phần nhóm bổ sung,
# vì FPClose chỉ xuất tập đóng.
#   RecoveryLimitExceeded : lỗi khi số tập phổ biến vượt giới hạn
#   recover_all_frequent  : hàm chính
#   descend!              : duyệt các tập con của một CFI và gán support

"""
    RecoveryLimitExceeded

Lỗi do `recover_all_frequent` ném ra khi số tập phổ biến vượt `limit`.

- `limit` : giới hạn đã đặt
"""
struct RecoveryLimitExceeded <: Exception
    limit::Int
end

# Thông báo hiển thị khi lỗi vượt giới hạn không được bắt
Base.showerror(io::IO, e::RecoveryLimitExceeded) =
    print(io, "recover_all_frequent: số frequent itemset vượt giới hạn ", e.limit,
          " (dữ liệu quá dày hoặc minsup quá thấp để khôi phục)")

"""
    recover_all_frequent(closed; limit = nothing, visits = nothing)
        -> Vector{Pair{Vector{Int},Int}}

Từ các tập phổ biến đóng (CFI) khôi phục mọi tập phổ biến khác rỗng kèm support.

- `closed` : danh sách `itemset => support` của các CFI (kết quả của `fpclose`)
- `limit`  : nếu có, ném `RecoveryLimitExceeded` khi số tập phổ biến vượt mức này
- `visits` : nếu có (`Ref{Int}`), cộng dồn số lần duyệt tập con, dùng để kiểm tra việc cắt nhánh

Trả về danh sách `itemset => support`, itemset sắp tăng dần, danh sách sắp theo độ dài rồi từ điển.

Cơ sở: (1) mọi tập phổ biến X là tập con của CFI cl(X) có cùng support, và mọi tập con của một
CFI đều phổ biến. (2) support(X) = max support của các CFI chứa X, vì CFI chứa X có support không
lớn hơn support(X) và cl(X) đạt đúng bằng.

Cách làm: xử lý CFI theo support giảm dần; với mỗi CFI duyệt các tập con và gán support cho tập
con chưa có trong bảng, không bao giờ ghi đè. Nhờ thứ tự đó, lần gán đầu tiên chính là giá trị max.
Duyệt theo hướng đi xuống (mỗi bước bỏ một item): gặp tập con đã có thì bỏ cả nhánh phía dưới,
vì mọi tập con của nó đã được gán từ CFI trước đó với support không nhỏ hơn.

Lưu ý: số tập phổ biến có thể lớn hơn số CFI theo cấp số mũ (CFI dài ℓ item sinh tới 2^ℓ − 1 tập
con), nên chỉ khả thi khi minsup đủ cao; dùng `limit` để tránh hết bộ nhớ.
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

"""
    descend!(table, root, sup, limit, visits) -> table

Duyệt các tập con của `root` theo hướng đi xuống, gán `sup` cho tập con chưa có trong `table`.
Dùng ngăn xếp thay cho đệ quy để chịu được CFI dài.

- `table`  : bảng `itemset => support` đang xây
- `root`   : CFI cần duyệt, sắp tăng dần
- `sup`    : support của `root`
- `limit`  : giới hạn số tập phổ biến hoặc `nothing`
- `visits` : bộ đếm số lần duyệt hoặc `nothing`
"""
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
