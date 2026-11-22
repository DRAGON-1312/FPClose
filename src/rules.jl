# rules.jl
# Sinh luật kết hợp (association rules) từ mọi frequent itemset.
#
# KHÔNG thuộc bài báo Grahne & Zhu: module nhóm bổ sung cho Chương 3 (phân tích giỏ hàng).
#
#   AssociationRule  : một luật X → Y kèm support, confidence, lift
#   generate_rules   : mọi luật đạt minconf
#   rank_rules!      : xếp hạng theo lift
#   top_rules        : k luật đứng đầu
#   write_rules      : ghi luật ra file/IO

"""
    AssociationRule

Luật `antecedent → consequent` (X → Y):
- `antecedent`, `consequent` : X và Y, hai itemset khác rỗng, rời nhau, mỗi cái sắp tăng dần;
- `count`      : sup(X ∪ Y), số giao dịch chứa cả X và Y;
- `support`    : support(X → Y) = sup(X ∪ Y) / N;
- `confidence` : confidence(X → Y) = sup(X ∪ Y) / sup(X);
- `lift`       : lift(X → Y) = confidence(X → Y) / (sup(Y) / N).

Ở đây N là tổng số giao dịch và sup(·) là số giao dịch chứa itemset đó. Ý nghĩa: confidence là
xác suất có điều kiện P(Y | X); lift so P(Y | X) với P(Y): lift > 1 nghĩa là mua X làm tăng khả
năng mua Y so với mức nền, lift = 1 là độc lập, lift < 1 là X làm giảm khả năng mua Y.
"""
struct AssociationRule
    antecedent::Vector{Int}
    consequent::Vector{Int}
    count::Int
    support::Float64
    confidence::Float64
    lift::Float64
end

"""
    generate_rules(frequent, n; minconf) -> Vector{AssociationRule}

Sinh mọi luật X → Y với X, Y khác rỗng, X ∩ Y = ∅, X ∪ Y là frequent itemset và
confidence ≥ `minconf` (`0 ≤ minconf ≤ 1`).

- `frequent` : MỌI frequent itemset (`itemset => support`), tức kết quả của
  `recover_all_frequent`, không phải chỉ tập đóng. Lý do: sup(X) và sup(Y) của vế trái và vế phải
  thường không phải tập đóng, nên không có trong kết quả của `fpclose`.
- `n`        : tổng số giao dịch N của CSDL (mẫu số của support và lift).
- confidence được tính bằng phép chia số nguyên `sup(X ∪ Y) / sup(X)` rồi so `≥ minconf`, không
  nhân với `minconf`, để ngưỡng viết dạng thập phân (0.6) khớp chính xác khi confidence đúng
  bằng ngưỡng (3/5 cho đúng giá trị `0.6`).

Kết quả đã xếp theo `rank_rules!` (lift giảm dần). Số luật tăng theo cấp số mũ với độ dài
itemset (itemset độ dài ℓ cho 2^ℓ − 2 cách chọn X); dùng minsup đủ cao. Itemset dài quá 62 item
không được hỗ trợ (và recovery cũng không thể liệt kê nổi).
"""
function generate_rules(frequent, n::Integer; minconf::Real)
    0 <= minconf <= 1 || throw(ArgumentError("minconf phải nằm trong [0, 1], nhận $minconf"))
    n >= 1 || throw(ArgumentError("số giao dịch n phải ≥ 1, nhận $n"))
    sup = Dict{Vector{Int},Int}(sort(collect(p.first)) => p.second for p in frequent)
    rules = AssociationRule[]
    for (z, sz) in sup
        k = length(z)
        k >= 2 || continue
        k <= 62 || throw(ArgumentError("itemset dài $k item, vượt giới hạn 62 của generate_rules"))
        for mask in 1:(Int64(1) << k) - 2         # mọi tập con thực sự khác rỗng của z làm X
            x = Int[z[b] for b in 1:k if (mask >> (b - 1)) & 1 == 1]
            y = Int[z[b] for b in 1:k if (mask >> (b - 1)) & 1 == 0]
            sx = get(sup, x, 0)
            sy = get(sup, y, 0)
            (sx > 0 && sy > 0) ||
                throw(ArgumentError("thiếu support của $(x) hoặc $(y): `frequent` phải chứa mọi " *
                                    "frequent itemset (dùng recover_all_frequent)"))
            conf = sz / sx
            conf >= minconf || continue
            push!(rules, AssociationRule(x, y, sz, sz / n, conf, conf / (sy / n)))
        end
    end
    return rank_rules!(rules)
end

"""
    rank_rules!(rules)

Sắp luật theo lift giảm dần; bằng lift thì confidence giảm dần, rồi support giảm dần, rồi theo
thứ tự từ điển của (antecedent, consequent) để kết quả ổn định giữa các lần chạy.
"""
rank_rules!(rules::Vector{AssociationRule}) =
    sort!(rules; by = r -> (-r.lift, -r.confidence, -r.support, r.antecedent, r.consequent))

"""
    top_rules(rules, k) -> Vector{AssociationRule}

`k` luật có lift cao nhất (xếp theo `rank_rules!`); ít hơn `k` luật thì trả hết.
"""
function top_rules(rules::Vector{AssociationRule}, k::Integer)
    k >= 1 || throw(ArgumentError("k phải là số nguyên dương, nhận $k"))
    ranked = rank_rules!(copy(rules))
    return ranked[1:min(k, length(ranked))]
end

"""
    write_rules(io, rules)
    write_rules(path, rules)

Mỗi luật một dòng, theo kiểu của SPMF (`1 2 ==> 3 #SUP: 0.4 #CONF: 0.75 #LIFT: 1.25 #COUNT: 2`):
`#SUP` là support tương đối sup(X ∪ Y)/N, `#CONF` là confidence, `#LIFT` là lift, `#COUNT` là
số giao dịch chứa X ∪ Y.
"""
function write_rules(io::IO, rules)
    for r in rules
        println(io, join(r.antecedent, ' '), " ==> ", join(r.consequent, ' '),
                " #SUP: ", r.support, " #CONF: ", r.confidence, " #LIFT: ", r.lift,
                " #COUNT: ", r.count)
    end
end

write_rules(path::AbstractString, rules) = open(io -> write_rules(io, rules), path, "w")
