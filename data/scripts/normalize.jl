# Chuẩn hóa một file giao dịch thô (SPMF/FIMI) về định dạng chuẩn của nhóm.
#
#   julia data/scripts/normalize.jl --src data/raw/pumsb_star.dat.gz --dst data/benchmark/pumsb_star.txt --offset 1
#
# Quy tắc (giống MANIFEST.md):
#   - Nhận diện gzip theo magic bytes 1f 8b, KHÔNG theo đuôi file
#     (T40I10D100K.dat tải từ FIMI thực chất là gzip).
#   - Bỏ BOM UTF-8 và các dòng metadata bắt đầu bằng #, @, %.
#   - Dòng trống hoặc item ≤ 0 (sau khi cộng offset) thì báo lỗi, không tự bỏ qua.
#   - Cộng offset vào mọi item ID (1 khi nguồn có ID 0), khử item trùng, sắp tăng dần.
#   - Ghi UTF-8, mỗi giao dịch một dòng, xuống dòng LF.
# Offset đã dùng: 0 cho chess, mushrooms, retail, T10I4D100K, accidents, connect, kosarak;
#                 1 cho pumsb_star, T40I10D100K.

isdefined(@__MODULE__, :sha256_file) || include(joinpath(@__DIR__, "common.jl"))
using Zlib_jll: libz

"File có phải gzip không (2 byte đầu là 1f 8b)."
is_gzip(path::AbstractString) = open(io -> read(io, 2) == UInt8[0x1f, 0x8b], path)

"""
    gunzip(path) -> IOBuffer

Giải nén file gzip bằng zlib đi kèm Julia (`Zlib_jll`), không cần lệnh `gzip` của hệ điều hành
(Windows thường không có).
"""
function gunzip(path::AbstractString)
    gz = ccall((:gzopen, libz), Ptr{Cvoid}, (Cstring, Cstring), path, "rb")
    gz == C_NULL && error("Không mở được file gzip: $path")
    out = IOBuffer()
    buf = Vector{UInt8}(undef, 1 << 20)
    try
        while true
            n = ccall((:gzread, libz), Cint, (Ptr{Cvoid}, Ptr{UInt8}, Cuint), gz, buf, length(buf))
            n < 0 && error("Lỗi giải nén gzip: $path")
            n == 0 && break
            write(out, view(buf, 1:n))
        end
    finally
        ccall((:gzclose, libz), Cint, (Ptr{Cvoid},), gz)
    end
    return seekstart(out)
end

"Mở file thô để đọc text; file gzip (nhận theo magic bytes) được giải nén trước."
open_raw(path::AbstractString) = is_gzip(path) ? gunzip(path) : open(path)

"""
    normalize_transactions(src, dst; offset = 0) -> (n_transactions, n_dedup_rows, n_metadata)

Chuẩn hóa `src` vào `dst`. Trả về số giao dịch ghi ra, số dòng có item trùng đã khử, số dòng metadata đã bỏ.
"""
function normalize_transactions(src::AbstractString, dst::AbstractString; offset::Integer = 0)
    mkpath(dirname(abspath(dst)))
    count = 0
    dedup_rows = 0
    metadata = 0
    input = open_raw(src)
    try
        open(dst, "w") do out
            for (line_number, raw) in enumerate(eachline(input))
                line = line_number == 1 ? lstrip(raw, '﻿') : raw
                line = strip(line)
                if startswith(line, '#') || startswith(line, '@') || startswith(line, '%')
                    metadata += 1
                    continue
                end
                isempty(line) && error("Giao dịch trống tại $src:$line_number")
                values = parse.(Int, split(line))
                minimum(values) + offset > 0 || error("Item ID không hợp lệ tại $src:$line_number")
                items = sort!(unique!(values .+ offset))
                length(items) < length(values) && (dedup_rows += 1)
                println(out, join(items, ' '))
                count += 1
            end
        end
    finally
        close(input)
    end
    return (n_transactions = count, n_dedup_rows = dedup_rows, n_metadata = metadata)
end

function main(args)
    opts = parse_options(args, Dict("src" => "", "dst" => "", "offset" => "0"))
    (isempty(opts["src"]) || isempty(opts["dst"])) && error("Cần --src và --dst")
    r = normalize_transactions(opts["src"], opts["dst"]; offset = parse(Int, opts["offset"]))
    println("transactions=", r.n_transactions, "  dedup_rows=", r.n_dedup_rows,
        "  metadata_removed=", r.n_metadata, "  sha256=", sha256_file(opts["dst"]))
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
