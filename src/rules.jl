# Sinh luật kết hợp (association rules) từ mọi tập phổ biến. Đây là phần nhóm bổ sung.
#   AssociationRule : một luật X → Y kèm support, confidence, lift
#   generate_rules  : sinh mọi luật đạt ngưỡng confidence
#   rank_rules!     : xếp hạng luật theo lift
#   top_rules       : lấy k luật đứng đầu
#   write_rules     : ghi luật ra file hoặc luồng

"""
    AssociationRule

Luật X → Y. Gọi N là tổng số giao dịch, sup(·) là số giao dịch chứa một itemset.

- `antecedent` : vế trái X (khác rỗng, sắp tăng dần)
- `consequent` : vế phải Y (khác rỗng, rời X, sắp tăng dần)
- `count`      : sup(X ∪ Y)
- `support`    : sup(X ∪ Y) / N
- `confidence` : sup(X ∪ Y) / sup(X), tức xác suất có Y khi đã có X
- `lift`       : confidence / (sup(Y) / N); lớn hơn 1 là có X làm tăng khả năng có Y so với mức nền,
                 bằng 1 là độc lập, nhỏ hơn 1 là làm giảm
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

Sinh mọi luật X → Y với X, Y khác rỗng, rời nhau, X ∪ Y phổ biến và confidence ≥ `minconf`.

- `frequent` : MỌI tập phổ biến (`itemset => support`), tức kết quả của `recover_all_frequent`,
               không phải chỉ tập đóng, vì sup(X) và sup(Y) thường không phải tập đóng
- `n`        : tổng số giao dịch N của cơ sở dữ liệu
- `minconf`  : ngưỡng confidence, trong [0, 1]

Trả về các luật đã xếp theo `rank_rules!`. Báo `ArgumentError` nếu `minconf` hoặc `n` ngoài miền,
nếu thiếu support của một vế (truyền nhầm tập đóng), hoặc nếu có itemset dài quá 62 item.

Confidence được tính bằng phép chia số nguyên rồi mới so với `minconf` (không nhân với `minconf`)
để ngưỡng dạng thập phân khớp chính xác khi confidence đúng bằng ngưỡng (3/5 so với 0.6).
Số luật tăng theo cấp số mũ với độ dài itemset.
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
    rank_rules!(rules) -> rules

Sắp luật tại chỗ theo lift giảm dần; bằng lift thì theo confidence giảm dần, rồi support giảm dần,
rồi thứ tự từ điển của (vế trái, vế phải) để kết quả ổn định.

- `rules` : danh sách luật
"""
rank_rules!(rules::Vector{AssociationRule}) =
    sort!(rules; by = r -> (-r.lift, -r.confidence, -r.support, r.antecedent, r.consequent))

"""
    top_rules(rules, k) -> Vector{AssociationRule}

Lấy `k` luật có lift cao nhất (không làm thay đổi `rules`); ít hơn `k` luật thì trả hết.

- `rules` : danh sách luật
- `k`     : số luật cần lấy, số nguyên dương
"""
function top_rules(rules::Vector{AssociationRule}, k::Integer)
    k >= 1 || throw(ArgumentError("k phải là số nguyên dương, nhận $k"))
    ranked = rank_rules!(copy(rules))
    return ranked[1:min(k, length(ranked))]
end

"""
    write_rules(io, rules)
    write_rules(path, rules)

Ghi mỗi luật một dòng, ví dụ `1 2 ==> 3 #SUP: 0.4 #CONF: 0.75 #LIFT: 1.25 #COUNT: 2`, trong đó
`#SUP` là support tương đối, `#CONF` là confidence, `#LIFT` là lift, `#COUNT` là số giao dịch
chứa X ∪ Y.

- `io` / `path` : nơi ghi (luồng hoặc đường dẫn file)
- `rules`       : danh sách luật
"""
function write_rules(io::IO, rules)
    for r in rules
        println(io, join(r.antecedent, ' '), " ==> ", join(r.consequent, ' '),
                " #SUP: ", r.support, " #CONF: ", r.confidence, " #LIFT: ", r.lift,
                " #COUNT: ", r.count)
    end
end

write_rules(path::AbstractString, rules) = open(io -> write_rules(io, rules), path, "w")
