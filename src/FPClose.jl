"""
    FPClose

Cài đặt lại thuật toán FPClose khai thác closed frequent itemsets theo
G. Grahne, J. Zhu, "Fast Algorithms for Frequent Itemset Mining Using FP-Trees",
IEEE TKDE 17(10), 2005. DOI 10.1109/TKDE.2005.166
"""
module FPClose

include("structures.jl")
include("utils.jl")
include("algorithm/fptree.jl")
include("algorithm/fparray.jl")
include("algorithm/cfitree.jl")
include("algorithm/fpclose.jl")
include("recovery.jl")
include("rules.jl")

export fpclose, FPCloseStats, read_spmf, write_spmf, minsup_count, sort_results!, parse_cli_args, parse_cli_options, resolve_minsup
export FPTree, CFITree, build_fptree, conditional_tree, pattern_base
export closed_checking, insert_cfi!, init_cfitree
export recover_all_frequent, RecoveryLimitExceeded
export AssociationRule, generate_rules, rank_rules!, top_rules, write_rules

end # module
