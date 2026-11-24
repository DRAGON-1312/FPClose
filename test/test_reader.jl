# So sánh read_spmf (đọc theo byte) với read_spmf_simple (bản gốc): cùng kết quả, cùng lỗi (cùng thông báo,
# tức cùng tên file, cùng số dòng, cùng token) trên dữ liệu toy và các file tạm cho trường hợp biên.

"Kết quả đọc dạng so sánh được: (:ok, db) hoặc (:err, thông báo ArgumentError). Lỗi kiểu khác được ném tiếp."
function reader_outcome(f, path)
    try
        return (:ok, f(path))
    catch e
        e isa ArgumentError || rethrow()
        return (:err, e.msg)
    end
end

"Ghi `content` (byte nguyên văn) ra file tạm trong `dir`, trả đường dẫn."
function write_tmp(dir, name, content)
    p = joinpath(dir, name)
    write(p, content)
    return p
end

@testset "reader: read_spmf ≡ read_spmf_simple" begin
    @testset "dữ liệu toy" begin
        toy = joinpath(@__DIR__, "..", "data", "toy")
        files = String[]
        for d in (toy, joinpath(toy, "extra"))
            isdir(d) || continue
            append!(files, filter(f -> endswith(f, ".txt"), readdir(d; join = true)))
        end
        @test !isempty(files)
        for f in files
            a, b = reader_outcome(read_spmf, f), reader_outcome(read_spmf_simple, f)
            @test a == b
            @test a[1] == :ok
        end
    end

    mktempdir() do dir
        cases = [
            "lf"            => "1 2 3\n4 5\n",
            "crlf"          => "1 2 3\r\n4 5\r\n",
            "crlf_no_end"   => "1 2 3\r\n4 5",
            "cr_end_no_lf"  => "1 2\r",
            "cr_only"       => "1 2\r3 4\r",                   # bản gốc: '\r' là khoảng trắng, cả file là MỘT dòng
            "tabs"          => "1\t2\t\t3\n\t4\t\n",
            "many_spaces"   => "   1    2     3   \n  4  \n",
            "vt_ff"         => "1\v2\f3\n",
            "blank_lines"   => "1 2\n\n   \n\t\n3\n\n",
            "no_trailing"   => "1 2\n3 4",
            "empty_file"    => "",
            "only_newline"  => "\n",
            "only_blank"    => "\n\n  \n",
            "item0"         => "0 1\n0\n0 0 0\n",
            "dup_unsorted"  => "3 1 3 2\n5 5\n2 1\n",
            "leading_zeros" => "007 0007 1\n",
            "metadata"      => "# x\n% y\n@CONVERTED_FROM_TEXT\n1 2\n  # thụt lề\n\t@z\n3\n",
            "typemax"       => "9223372036854775807 1\n",
            "big_unicode"   => " 1 2\n1 2\n # chú thích\n",   # khoảng trắng Unicode
            "plus_sign"     => "+5 1\n",
            "minus_zero"    => "-0 1\n",
            "hex"           => "0x10 1\n",
            # lỗi: phải trùng thông báo (cùng dòng, cùng token)
            "bad_token"     => "1 2\n3 x 4\n",
            "bad_after_meta"=> "# c\n\n1\n2,3\n",
            "negative"      => "1\n2\n-3\n",
            "overflow"      => "1\n99999999999999999999\n",
            "float"         => "1.5 2\n",
            "comment_tail"  => "1 2 #SUP: 3\n",
            "bom"           => "﻿1 2\n",
            "nul"           => "1\0 2\n",
            "bad_last_line" => "1 2\n3 a",
        ]
        for (name, content) in cases
            p = write_tmp(dir, name * ".txt", content)
            a, b = reader_outcome(read_spmf, p), reader_outcome(read_spmf_simple, p)
            @test a == b
            a == b || @info "khác nhau ở case $name" a b
        end

        # kiểm tra cụ thể vài trường hợp
        @test read_spmf(joinpath(dir, "crlf.txt")) == [[1, 2, 3], [4, 5]]
        @test read_spmf(joinpath(dir, "item0.txt")) == [[0, 1], [0], [0]]
        @test read_spmf(joinpath(dir, "dup_unsorted.txt")) == [[1, 2, 3], [5], [1, 2]]
        @test read_spmf(joinpath(dir, "empty_file.txt")) == Vector{Int}[]
        @test read_spmf(joinpath(dir, "item0.txt")) isa Vector{Vector{Int}}
        @test occursin("dòng 2", reader_outcome(read_spmf, joinpath(dir, "bad_token.txt"))[2])
        @test occursin("dòng 4", reader_outcome(read_spmf, joinpath(dir, "bad_after_meta.txt"))[2])
        @test occursin("dòng 3", reader_outcome(read_spmf, joinpath(dir, "negative.txt"))[2])
        @test occursin("dòng 2", reader_outcome(read_spmf, joinpath(dir, "bad_last_line.txt"))[2])

        # chuỗi ngẫu nhiên trên bảng ký tự nhỏ (gồm ký tự gây lỗi) để bắt mọi lệch hành vi còn sót
        rng = MersenneTwister(20261124)
        alphabet = collect("0123456789     \t\r\n\n\n#%@-+ax ")
        nfuzz = 0
        for t in 1:2000
            s = String(rand(rng, alphabet, rand(rng, 0:40)))
            # mỗi chuỗi một file riêng: trên Windows, eachline của read_spmf_simple còn giữ file mở khi ném lỗi
            # giữa chừng, nên không ghi đè được file cũ
            p = write_tmp(dir, "fuzz_$(t).txt", s)
            a, b = reader_outcome(read_spmf, p), reader_outcome(read_spmf_simple, p)
            a == b || (nfuzz += 1; @info "fuzz khác nhau" repr(s) a b)
        end
        @test nfuzz == 0
        GC.gc()   # đóng các file mà eachline còn giữ (Windows) trước khi mktempdir xóa thư mục tạm
    end
end
