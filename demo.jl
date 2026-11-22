# Chạy FPClose từ dòng lệnh:
#   julia --project=. demo.jl --minsup 0.4 <file input>
#   julia --project=. demo.jl --minsup 40% --output-closed out/closed.txt <file input>
#   julia --project=. demo.jl --minsup 40% --output-all out/all.txt <file input>
#   julia --project=. demo.jl --minsup 40% --rules out/rules.txt --minconf 0.6 --top 10 <file input>
#   julia --project=. demo.jl --minsup-count 2 <file input>
#
# --minsup nhận tỉ lệ (0.4) hoặc phần trăm (40%) như SPMF; --minsup-count nhận số giao
# dịch tuyệt đối. Phải có đúng một trong hai.
# --output-closed (hoặc tên cũ --output): ghi closed frequent itemset, định dạng SPMF "1 2 #SUP: 3".
# --output-all: ghi MỌI frequent itemset (chạy thêm bước recovery, xem src/recovery.jl).
# --rules + --minconf [+ --top]: ghi luật kết hợp (cũng chạy recovery vì cần support của mọi tập con).
# Không có tham số ghi file nào thì closed itemsets được in ra màn hình.
# Thời gian của từng giai đoạn (mining, recovery, rules) in riêng ra stderr.

using FPClose

fail(msg) = (println(stderr, "Lỗi: ", msg); exit(2))

function main(args)
    opts = try
        parse_cli_options(args)
    catch e
        e isa ArgumentError || rethrow()
        fail(e.msg)
    end
    isfile(opts.input) || fail("không thấy file input: $(opts.input)")
    db = try
        read_spmf(opts.input)
    catch e
        e isa ArgumentError || e isa MethodError || rethrow()
        fail("không đọc được $(opts.input) theo định dạng SPMF (mỗi dòng là các số nguyên cách nhau dấu cách)")
    end
    isempty(db) && fail("file input không có giao dịch nào: $(opts.input)")
    n = length(db)
    minsup = resolve_minsup(opts, n)

    t_mining = @elapsed closed = sort_results!(fpclose(db, minsup))
    info = Pair{Symbol,Any}[:input => opts.input, :transactions => n, :minsup_count => minsup,
                            :closed_itemsets => length(closed), :mining_seconds => round(t_mining; digits = 4)]

    write_out(path, results) = (mkpath(dirname(abspath(path))); write_spmf(path, results))
    wrote_file = opts.output_closed !== nothing || opts.output_all !== nothing || opts.rules !== nothing
    if opts.output_closed !== nothing
        write_out(opts.output_closed, closed)
    elseif !wrote_file
        write_spmf(stdout, closed)          # không có tham số ghi file nào: in ra màn hình như trước
    end

    if opts.output_all !== nothing || opts.rules !== nothing
        t_recovery = @elapsed all_fi = recover_all_frequent(closed)
        push!(info, :frequent_itemsets => length(all_fi), :recovery_seconds => round(t_recovery; digits = 4))
        opts.output_all === nothing || write_out(opts.output_all, all_fi)

        if opts.rules !== nothing
            t_rules = @elapsed rules = generate_rules(all_fi, n; minconf = opts.minconf)
            total = length(rules)
            opts.top === nothing || (rules = top_rules(rules, opts.top))
            mkpath(dirname(abspath(opts.rules)))
            write_rules(opts.rules, rules)
            push!(info, :rules_generated => total, :rules_written => length(rules),
                  :rules_seconds => round(t_rules; digits = 4))
        end
    end
    @info "FPClose" info...
end

main(ARGS)
