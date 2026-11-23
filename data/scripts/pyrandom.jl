# Cài lại bằng Julia đúng bộ sinh số ngẫu nhiên `random.Random` của CPython.
#
# Vì sao cần: Retail subsets và synthetic datasets đã công bố được sinh bằng
# `random.Random(2026)` của Python. `MersenneTwister(2026)` của Julia cho dãy số
# khác, nên muốn tái tạo đúng từng byte (cùng SHA-256) phải chép lại:
#   - MT19937 và cách CPython khởi tạo seed số nguyên (init_by_array),
#   - random(), getrandbits(k), _randbelow(n),
#   - shuffle, randint, sample (trên range), choices (có weights).
# Thuật toán theo mã nguồn CPython 3.x (Modules/_randommodule.c, Lib/random.py).

const _MT_N = 624
const _MT_M = 397
const _MATRIX_A = 0x9908b0df
const _UPPER_MASK = 0x80000000
const _LOWER_MASK = 0x7fffffff

"""
    PyRandom(seed)

Tương đương `random.Random(seed)` của Python với `seed` là số nguyên.
"""
mutable struct PyRandom
    mt::Vector{UInt32}
    mti::Int
end

function PyRandom(seed::Integer)
    # CPython: seed nguyên -> abs(seed) -> mảng các từ 32 bit, little-endian.
    s = abs(BigInt(seed))
    key = UInt32[]
    if s == 0
        push!(key, UInt32(0))
    else
        while s > 0
            push!(key, UInt32(s & 0xffffffff))
            s >>= 32
        end
    end

    # init_genrand(19650218)
    mt = zeros(UInt32, _MT_N)
    mt[1] = UInt32(19650218)
    for i in 1:_MT_N-1
        prev = mt[i]
        mt[i+1] = UInt32(1812433253) * (prev ⊻ (prev >> 30)) + UInt32(i)
    end

    # init_by_array(key). i, j là chỉ số 0-based như mã C; mt[i+1] là mt[i] của C.
    i, j = 1, 0
    klen = length(key)
    for _ in 1:max(_MT_N, klen)
        prev = mt[i]
        mt[i+1] = (mt[i+1] ⊻ ((prev ⊻ (prev >> 30)) * UInt32(1664525))) + key[j+1] + UInt32(j)
        i += 1
        j += 1
        if i >= _MT_N
            mt[1] = mt[_MT_N]
            i = 1
        end
        j >= klen && (j = 0)
    end
    for _ in 1:_MT_N-1
        prev = mt[i]
        mt[i+1] = (mt[i+1] ⊻ ((prev ⊻ (prev >> 30)) * UInt32(1566083941))) - UInt32(i)
        i += 1
        if i >= _MT_N
            mt[1] = mt[_MT_N]
            i = 1
        end
    end
    mt[1] = 0x80000000
    return PyRandom(mt, _MT_N)
end

@inline _mag01(y::UInt32) = (y & 0x00000001) == 0 ? UInt32(0) : _MATRIX_A

"genrand_uint32 của CPython: một số nguyên 32 bit."
function genrand_uint32!(r::PyRandom)
    mt = r.mt
    if r.mti >= _MT_N
        for kk in 0:_MT_N-_MT_M-1
            y = (mt[kk+1] & _UPPER_MASK) | (mt[kk+2] & _LOWER_MASK)
            mt[kk+1] = mt[kk+_MT_M+1] ⊻ (y >> 1) ⊻ _mag01(y)
        end
        for kk in _MT_N-_MT_M:_MT_N-2
            y = (mt[kk+1] & _UPPER_MASK) | (mt[kk+2] & _LOWER_MASK)
            mt[kk+1] = mt[kk+(_MT_M-_MT_N)+1] ⊻ (y >> 1) ⊻ _mag01(y)
        end
        y = (mt[_MT_N] & _UPPER_MASK) | (mt[1] & _LOWER_MASK)
        mt[_MT_N] = mt[_MT_M] ⊻ (y >> 1) ⊻ _mag01(y)
        r.mti = 0
    end
    y = mt[r.mti+1]
    r.mti += 1
    y ⊻= y >> 11
    y ⊻= (y << 7) & 0x9d2c5680
    y ⊻= (y << 15) & 0xefc60000
    y ⊻= y >> 18
    return y
end

"`random.random()`: số thực trong [0, 1) với 53 bit ngẫu nhiên."
function pyrandom!(r::PyRandom)
    a = genrand_uint32!(r) >> 5
    b = genrand_uint32!(r) >> 6
    return (Float64(a) * 67108864.0 + Float64(b)) * (1.0 / 9007199254740992.0)
end

"`getrandbits(k)` với 1 ≤ k ≤ 32 (đủ cho mọi n dùng ở đây)."
function getrandbits!(r::PyRandom, k::Integer)
    1 <= k <= 32 || throw(ArgumentError("getrandbits chỉ hỗ trợ 1 ≤ k ≤ 32, nhận $k"))
    return Int(genrand_uint32!(r) >> (32 - k))
end

"`_randbelow(n)`: số nguyên đều trong [0, n), phương pháp loại bỏ như CPython."
function randbelow!(r::PyRandom, n::Integer)
    n > 0 || throw(ArgumentError("n phải dương"))
    k = ndigits(n; base = 2)          # n.bit_length()
    x = getrandbits!(r, k)
    while x >= n
        x = getrandbits!(r, k)
    end
    return x
end

"`random.shuffle(x)` (tại chỗ), cùng thứ tự gọi số ngẫu nhiên như Python."
function pyshuffle!(r::PyRandom, x::AbstractVector)
    for i in length(x)-1:-1:1         # i là chỉ số 0-based
        j = randbelow!(r, i + 1)
        x[i+1], x[j+1] = x[j+1], x[i+1]
    end
    return x
end

"`random.randint(a, b)`: số nguyên trong [a, b]."
pyrandint!(r::PyRandom, a::Integer, b::Integer) = a + randbelow!(r, b - a + 1)

"""
    pysample_range!(r, start, stop, k)

`random.sample(range(start, stop), k)`.
"""
function pysample_range!(r::PyRandom, start::Integer, stop::Integer, k::Integer)
    n = stop - start
    0 <= k <= n || throw(ArgumentError("k nằm ngoài [0, n]"))
    setsize = 21
    if k > 5
        setsize += 4^ceil(Int, log(3k) / log(4))
    end
    result = Vector{Int}(undef, k)
    if n <= setsize
        pool = collect(start:stop-1)
        for i in 0:k-1
            j = randbelow!(r, n - i)
            result[i+1] = pool[j+1]
            pool[j+1] = pool[n-i]
        end
    else
        selected = Set{Int}()
        for i in 0:k-1
            j = randbelow!(r, n)
            while j in selected
                j = randbelow!(r, n)
            end
            push!(selected, j)
            result[i+1] = start + j
        end
    end
    return result
end

"Cộng dồn trái sang phải như `itertools.accumulate`."
function cumulative(weights)
    cum = Vector{Float64}(undef, length(weights))
    acc = 0.0
    for (i, w) in enumerate(weights)
        acc += Float64(w)
        cum[i] = acc
    end
    return cum
end

"""
    pychoice_index!(r, cum_weights) -> Int

Một lần chọn của `random.choices(population, weights=..., k=1)`; trả về chỉ số 0-based
trong population. `cum_weights` lấy từ `cumulative(weights)`.
"""
function pychoice_index!(r::PyRandom, cum_weights::Vector{Float64})
    total = cum_weights[end] + 0.0
    x = pyrandom!(r) * total
    lo, hi = 0, length(cum_weights) - 1   # bisect_right(cum, x, 0, n-1)
    while lo < hi
        mid = (lo + hi) ÷ 2
        if x < cum_weights[mid+1]
            hi = mid
        else
            lo = mid + 1
        end
    end
    return lo
end

"""
    cpow(x, y)

`x ** y` của Python gọi hàm `pow` của thư viện C. Dùng cùng hàm đó (nếu gọi được) để
trọng số khớp từng bit với dữ liệu sinh trên Colab; nếu không thì dùng `^` của Julia.
"""
const cpow = try
    ccall(:pow, Float64, (Float64, Float64), 2.0, 0.5)
    (x::Float64, y::Float64) -> ccall(:pow, Float64, (Float64, Float64), x, y)
catch
    (x::Float64, y::Float64) -> x^y
end
