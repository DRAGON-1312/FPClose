# Chạy FPClose từ dòng lệnh: khai thác tập phổ biến đóng, tùy chọn khôi phục mọi tập phổ biến
# và sinh luật kết hợp, rồi ghi kết quả theo định dạng SPMF.
#   fail : in lỗi ra stderr rồi thoát với mã 2
#   main : đọc tham số, chạy từng giai đoạn (mining, recovery, rules) và in thời gian riêng
# Ví dụ:
#   julia --project=. demo.jl --minsup 40% data/toy/pasquier99.txt
#   julia --project=. demo.jl --minsup 40% --output-closed out/closed.txt --output-all out/all.txt <input>
#   julia --project=. demo.jl --minsup 40% --rules out/rules.txt --minconf 0.6 --top 10 <input>
# Recovery chạy khi có --output-all hoặc --rules. Không có tham số ghi file nào thì in tập đóng ra màn hình.

using FPClose

"""
    fail(msg)

In `Lỗi: msg` ra stderr rồi thoát với mã 2.

- `msg` : nội dung lỗi
"""
fail(msg) = (println(stderr, "Lỗi: ", msg); exit(2))

"""
    main(args)

Chạy chương trình với tham số dòng lệnh `args`: đọc cơ sở dữ liệu, khai thác tập đóng, và tùy theo
tham số thì khôi phục mọi tập phổ biến và sinh luật; ghi các file kết quả và in số lượng cùng
thời gian của từng giai đoạn ra stderr.

- `args` : danh sách tham số dòng lệnh (xem `parse_cli_options`)
"""
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
        e isa ArgumentError && fail(e.msg)
        e isa MethodError || rethrow()
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

    # Recovery cần cho --output-all và cho --rules (luật cần support của mọi tập con)
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
