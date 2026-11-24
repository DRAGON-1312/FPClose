"""
    FPClose

Cài đặt thuật toán FPClose (Grahne & Zhu) khai thác tập phổ biến đóng bằng FP-tree, kèm phần
khôi phục mọi tập phổ biến và sinh luật kết hợp do nhóm bổ sung.
"""
module FPClose

# Cấu trúc dữ liệu và tiện ích dùng chung
include("structures.jl")
include("utils.jl")
# Thuật toán: FP-tree, FP-array, CFI-tree, FPClose
include("algorithm/fptree.jl")
include("algorithm/fparray.jl")
include("algorithm/cfitree.jl")
include("algorithm/fpclose.jl")
# Phần bổ sung: khôi phục mọi tập phổ biến, luật kết hợp
include("recovery.jl")
include("rules.jl")

# Hàm chính, đọc/ghi dữ liệu, tham số dòng lệnh
export fpclose, FPCloseStats, read_spmf, read_spmf_simple, write_spmf, minsup_count, sort_results!, parse_cli_args, parse_cli_options, resolve_minsup
# Cấu trúc cây và thao tác (dùng khi test)
export FPTree, CFITree, build_fptree, conditional_tree, pattern_base
export closed_checking, insert_cfi!, init_cfitree
# Recovery và luật kết hợp
export recover_all_frequent, RecoveryLimitExceeded
export AssociationRule, generate_rules, rank_rules!, top_rules, write_rules

end # module
