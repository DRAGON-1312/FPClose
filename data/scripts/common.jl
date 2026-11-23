# Hàm dùng chung cho các script chuẩn bị dữ liệu benchmark.
# Chỉ dùng thư viện chuẩn của Julia (SHA), không cần thêm gói nào.

using SHA

"""
    sha256_file(path) -> String

SHA-256 (hex, chữ thường) của file, đọc theo luồng nên không tốn RAM với file lớn.
"""
sha256_file(path::AbstractString) = open(io -> bytes2hex(sha256(io)), path)

"""
    parse_options(args, defaults) -> Dict

Bộ đọc tham số dạng `--tên giá trị` tối giản. Tham số lạ hoặc thiếu giá trị thì báo lỗi.
"""
function parse_options(args::AbstractVector{<:AbstractString}, defaults::Dict{String,String})
    opts = copy(defaults)
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg in ("-h", "--help")
            println("Tham số (mặc định):")
            for (k, v) in sort!(collect(defaults))
                println("  --", k, "  (", v, ")")
            end
            exit(0)
        end
        startswith(arg, "--") || error("Tham số không hợp lệ: $arg")
        key = arg[3:end]
        haskey(opts, key) || error("Không có tham số --$key. Có: " * join("--" .* sort!(collect(keys(defaults))), ", "))
        i + 1 <= length(args) || error("Thiếu giá trị cho --$key")
        opts[key] = args[i+1]
        i += 2
    end
    return opts
end

"""
    read_csv_rows(path) -> Vector{Dict{String,String}}

Đọc CSV đơn giản (không có dấu phẩy trong ô), đủ cho các file trong `data/results/`.
"""
function read_csv_rows(path::AbstractString)
    lines = filter(!isempty, strip.(readlines(path)))
    header = split(lines[1], ',')
    return [Dict(String(h) => String(v) for (h, v) in zip(header, split(l, ','))) for l in lines[2:end]]
end

"""
    write_csv(path, header, rows)

Ghi CSV với xuống dòng LF. `rows` là danh sách vector giá trị theo đúng thứ tự `header`.
"""
function write_csv(path::AbstractString, header::Vector{String}, rows)
    mkpath(dirname(abspath(path)))
    open(path, "w") do io
        println(io, join(header, ','))
        for r in rows
            println(io, join(string.(r), ','))
        end
    end
end

"Thư mục gốc repo (data/scripts/../..)."
repo_root() = normpath(joinpath(@__DIR__, "..", ".."))
