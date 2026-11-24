"""Tiền xử lý cho Ứng dụng 1 (Market Basket Analysis, Chương 3): UCI Online Retail -> giao dịch định dạng SPMF.

Dữ liệu: UCI Online Retail (id 352), giấy phép CC BY 4.0.
Chen, D. (2015). Online Retail [Dataset]. UCI Machine Learning Repository. https://doi.org/10.24432/C5BW33

Module chỉ biến đổi dữ liệu thành giao dịch; mọi itemset và luật kết hợp được sinh bằng cài đặt FPClose của nhóm
(demo.jl hoặc các hàm trong src/), không dùng thư viện khai thác tập phổ biến nào khác.

Hai nhóm hàm:
- Hàm THUẦN (không I/O, không trạng thái toàn cục, nhận tham số tường minh, trả kết quả):
  normalize, diagnose, clean, to_transactions, validate_transactions, transaction_stats.
- Hàm có TÁC DỤNG PHỤ (tải, đọc/ghi file, vẽ hình):
  find_root, sha256_file, load_raw, write_spmf, plot_basket_length, save_results, run_preprocessing.

Quy ước id item: `read_spmf` của nhóm nhận mọi số nguyên >= 0 (item 0 hợp lệ), tự bỏ item trùng và sắp tăng dần
trong mỗi giao dịch. Module dùng id liên tục bắt đầu từ ID_START = 1 (giống các file benchmark đã chuẩn hóa và quy
ước của SPMF, để có thể đối chiếu với SPMF khi cần), và vẫn ghi item tăng dần, không trùng.
"""

from __future__ import annotations

import hashlib
import re
import shutil
import urllib.request
import zipfile
from pathlib import Path

import pandas as pd

# ---------------------------------------------------------------------------
# Tham số mặc định (notebook có thể ghi đè ở ô cấu hình)
# ---------------------------------------------------------------------------

#: Mã StockCode không phải sản phẩm (phí, bưu phí, điều chỉnh, ...), so sau khi strip().upper().
NON_PRODUCT = ('POST', 'DOT', 'M', 'D', 'C2', 'CRUK', 'PADS', 'S', 'B', 'BANK CHARGES', 'AMAZONFEE')
#: Tiền tố mã không phải sản phẩm (phiếu quà tặng, mã nội bộ).
NON_PRODUCT_PREFIXES = ('GIFT_', 'DCGS')
#: Mẫu StockCode của một sản phẩm thông thường: 5 chữ số, có thể thêm tối đa 2 chữ cái. Chỉ dùng để THỐNG KÊ.
STOCK_CODE_PATTERN = r'^\d{5}[A-Z]{0,2}$'
#: Id của item đầu tiên (read_spmf nhận >= 0; chọn 1 cho khớp benchmark và SPMF).
ID_START = 1

UCI_URL = 'https://archive.ics.uci.edu/static/public/352/online+retail.zip'
RAW_FILENAME = 'Online Retail.xlsx'
RAW_SHA256 = '43465A06F2CCF7C8B5BD2892BC7DEFB52F97487934FE93B16AE4C3936424676D'
CACHE_FILENAME = 'online_retail.pkl'
CACHE_SHA_FILENAME = 'online_retail.pkl.sha256'   # SHA-256 của file xlsx đã dùng để tạo cache

COLUMNS = ['InvoiceNo', 'StockCode', 'Description', 'Quantity', 'InvoiceDate', 'UnitPrice', 'CustomerID', 'Country']
STEP_COLUMNS = ['bước', 'mô tả', 'số dòng bị loại', 'số dòng còn lại']


# ===========================================================================
# Hàm có tác dụng phụ: đường dẫn, tải và đọc dữ liệu
# ===========================================================================

def find_root(colab_dir: str = '/content/FPClose', start: str | Path | None = None) -> Path:
    """Tìm thư mục gốc của repo (TÁC DỤNG PHỤ: đọc hệ thống file).

    Trả `colab_dir` nếu thư mục này tồn tại (đang chạy trên Colab); ngược lại trả thư mục cha gần nhất có
    `Project.toml`, tìm lần lượt từ `start` (mặc định: thư mục chứa module này) rồi từ thư mục làm việc hiện tại.
    """
    if Path(colab_dir).is_dir():
        return Path(colab_dir)
    starts = [Path(start).resolve()] if start is not None else [Path(__file__).resolve().parent]
    starts.append(Path.cwd().resolve())
    for s in starts:
        for d in [s, *s.parents]:
            if (d / 'Project.toml').is_file():
                return d
    raise FileNotFoundError('Không tìm thấy thư mục gốc repo (thư mục có Project.toml)')


def sha256_file(path: str | Path) -> str:
    """SHA-256 (chữ hoa) của một file (TÁC DỤNG PHỤ: đọc file)."""
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest().upper()


def _download(url: str, dest: Path) -> None:
    """Tải `url` về `dest` qua file tạm (TÁC DỤNG PHỤ)."""
    tmp = dest.with_name(dest.name + '.part')
    with urllib.request.urlopen(url, timeout=120) as r, open(tmp, 'wb') as f:
        shutil.copyfileobj(r, f)
    tmp.replace(dest)


def _fetch_raw(xlsx: Path, uci_url: str, hf_url: str = '') -> None:
    """Lấy file xlsx gốc: thử `hf_url` (file xlsx trực tiếp) nếu có, không được thì tải zip của UCI và giải nén."""
    if hf_url:
        try:
            print('Tải từ', hf_url)
            _download(hf_url, xlsx)
            return
        except Exception as e:                       # thử nguồn UCI
            print('Không tải được từ hf_url:', e)
    zpath = xlsx.with_name('online_retail.zip')
    print('Tải từ', uci_url)
    _download(uci_url, zpath)
    with zipfile.ZipFile(zpath) as z:
        members = [m for m in z.namelist() if m.lower().endswith('.xlsx')]
        if not members:
            raise ValueError(f'Không có file .xlsx trong {zpath}')
        with z.open(members[0]) as src, open(xlsx, 'wb') as dst:
            shutil.copyfileobj(src, dst)
    zpath.unlink()


def load_raw(app_dir: str | Path, uci_url: str, sha256: str, hf_url: str = '') -> pd.DataFrame:
    """Tải (nếu chưa có), kiểm SHA-256 và đọc dữ liệu gốc (TÁC DỤNG PHỤ: mạng, đọc/ghi file).

    - File gốc: `<app_dir>/data/raw/Online Retail.xlsx`. Chưa có thì thử `hf_url` (nếu khác rỗng), rồi `uci_url`
      (zip của UCI, giải nén lấy file xlsx).
    - SHA-256 của file gốc phải bằng `sha256` (so không phân biệt hoa/thường), không thì báo lỗi.
    - InvoiceNo, StockCode, Description đọc kiểu chuỗi.
    - Cache `<app_dir>/data/online_retail.pkl` gắn với SHA-256 của file gốc (lưu ở `online_retail.pkl.sha256`);
      SHA không khớp hoặc thiếu thì đọc lại từ xlsx và ghi lại cache.
    """
    app_dir = Path(app_dir)
    data_dir = app_dir / 'data'
    raw_dir = data_dir / 'raw'
    raw_dir.mkdir(parents=True, exist_ok=True)
    xlsx = raw_dir / RAW_FILENAME
    if not xlsx.exists():
        _fetch_raw(xlsx, uci_url, hf_url)
    got = sha256_file(xlsx)
    if got.lower() != sha256.lower():
        raise ValueError(f'SHA-256 của {xlsx} là {got}, khác giá trị mong đợi {sha256.upper()}')

    cache, tag = data_dir / CACHE_FILENAME, data_dir / CACHE_SHA_FILENAME
    if cache.exists() and tag.exists() and tag.read_text(encoding='utf-8').strip().lower() == got.lower():
        return pd.read_pickle(cache)
    df = pd.read_excel(xlsx, engine='openpyxl',
                       dtype={'InvoiceNo': str, 'StockCode': str, 'Description': str})
    missing = [c for c in COLUMNS if c not in df.columns]
    if missing:
        raise ValueError(f'Thiếu cột {missing} trong {xlsx}')
    df.to_pickle(cache)
    tag.write_text(got, encoding='utf-8')
    return df


# ===========================================================================
# Hàm thuần: chuẩn hóa, chẩn đoán, làm sạch
# ===========================================================================

def normalize(df: pd.DataFrame) -> pd.DataFrame:
    """Chuẩn hóa văn bản (THUẦN, trả bản sao).

    InvoiceNo: strip; StockCode: strip().upper(); Description: strip và gộp nhiều khoảng trắng liên tiếp thành một.
    Giá trị thiếu của ba cột này thành chuỗi rỗng ''. Không loại dòng nào.
    """
    out = df.copy()
    out['InvoiceNo'] = out['InvoiceNo'].fillna('').astype(str).str.strip()
    out['StockCode'] = out['StockCode'].fillna('').astype(str).str.strip().str.upper()
    out['Description'] = (out['Description'].fillna('').astype(str)
                          .str.replace(r'\s+', ' ', regex=True).str.strip())
    return out


def _is_cancelled(invoice: pd.Series) -> pd.Series:
    """Hóa đơn hủy: InvoiceNo bắt đầu bằng 'C' hoặc 'c'."""
    return invoice.str.upper().str.startswith('C')


def _has_prefix(codes: pd.Series, prefixes) -> pd.Series:
    """Mã bắt đầu bằng một trong các tiền tố (không có tiền tố nào thì toàn False)."""
    if not prefixes:
        return pd.Series(False, index=codes.index)
    return codes.str.match('(?:' + '|'.join(re.escape(p) for p in prefixes) + ')')


def _top_description(df: pd.DataFrame) -> pd.Series:
    """StockCode -> Description (khác rỗng) xuất hiện nhiều dòng nhất; hòa thì lấy chuỗi nhỏ nhất theo thứ tự từ điển."""
    x = df[df['Description'] != '']
    c = x.groupby(['StockCode', 'Description']).size().reset_index(name='n')
    c = c.sort_values(['StockCode', 'n', 'Description'], ascending=[True, False, True], kind='mergesort')
    return c.drop_duplicates('StockCode').set_index('StockCode')['Description']


def diagnose(df: pd.DataFrame, pattern: str = STOCK_CODE_PATTERN) -> dict[str, pd.DataFrame]:
    """Bảng chẩn đoán dữ liệu gốc, CHƯA loại dòng nào (THUẦN).

    Trả dict:
    - 'summary': chỉ số -> số lượng (hóa đơn hủy, Quantity <= 0, UnitPrice <= 0, Description rỗng, InvoiceNo/StockCode
      thiếu, CustomerID thiếu, số mã lệch mẫu, số mã có nhiều Description).
    - 'irregular_codes': MỌI StockCode (đã strip().upper(), khác rỗng) không khớp `pattern`, kèm Description phổ biến
      nhất và số dòng, sắp số dòng giảm dần (hòa theo mã).
    - 'multi_description': 5 ví dụ mã có > 1 Description phân biệt (nhiều Description nhất trước).
    """
    d = normalize(df)
    cancelled = _is_cancelled(d['InvoiceNo'])
    codes = d.loc[d['StockCode'] != '', 'StockCode']
    irregular_mask = ~codes.str.match(pattern)
    irr = codes[irregular_mask].value_counts().rename_axis('stock_code').reset_index(name='n_rows')
    top = _top_description(d)
    irr['description'] = irr['stock_code'].map(top).fillna('')
    irr = irr.sort_values(['n_rows', 'stock_code'], ascending=[False, True], kind='mergesort')
    irr = irr[['stock_code', 'description', 'n_rows']].reset_index(drop=True)

    x = d[(d['StockCode'] != '') & (d['Description'] != '')]
    nd = x.groupby('StockCode')['Description'].nunique()
    multi = nd[nd > 1]
    ex = (multi.rename('n_descriptions').rename_axis('stock_code').reset_index()
          .sort_values(['n_descriptions', 'stock_code'], ascending=[False, True], kind='mergesort').head(5))
    descs = x.groupby('StockCode')['Description'].agg(lambda s: ' | '.join(sorted(set(s))))
    ex['descriptions'] = ex['stock_code'].map(descs)
    ex = ex.reset_index(drop=True)

    rows = [
        ('Tổng số dòng', len(d)),
        ('Số hóa đơn phân biệt', d.loc[d['InvoiceNo'] != '', 'InvoiceNo'].nunique()),
        ("Số hóa đơn hủy (InvoiceNo bắt đầu bằng 'C'/'c')", d.loc[cancelled, 'InvoiceNo'].nunique()),
        ('Số dòng thuộc hóa đơn hủy', int(cancelled.sum())),
        ('Số dòng Quantity <= 0 hoặc thiếu', int((~(d['Quantity'] > 0)).sum())),
        ('Số dòng UnitPrice <= 0 hoặc thiếu', int((~(d['UnitPrice'] > 0)).sum())),
        ('Số dòng Description rỗng', int((d['Description'] == '').sum())),
        ('Số dòng InvoiceNo thiếu/rỗng', int((d['InvoiceNo'] == '').sum())),
        ('Số dòng StockCode thiếu/rỗng', int((d['StockCode'] == '').sum())),
        ('Số dòng thiếu CustomerID (không loại)', int(d['CustomerID'].isna().sum())),
        ('Số StockCode không khớp mẫu (chỉ thống kê)', len(irr)),
        ('Số StockCode có > 1 Description', len(multi)),
    ]
    summary = pd.DataFrame(rows, columns=['chỉ số', 'số lượng'])
    return {'summary': summary, 'irregular_codes': irr, 'multi_description': ex}


def clean(df: pd.DataFrame, non_product=NON_PRODUCT,
          prefixes=NON_PRODUCT_PREFIXES) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Làm sạch theo thứ tự cố định (THUẦN). Trả (df_sạch đã chuẩn hóa, bảng bước làm sạch).

    Các bước (mỗi bước áp lên kết quả của bước trước):
      1. bỏ dòng thiếu/rỗng InvoiceNo hoặc StockCode;
      2. bỏ hóa đơn hủy (InvoiceNo bắt đầu bằng 'C'/'c');
      3. bỏ Quantity <= 0 (hoặc thiếu);
      4. bỏ UnitPrice <= 0 (hoặc thiếu);
      5. bỏ Description rỗng;
      6. bỏ mã không phải sản phẩm: StockCode thuộc `non_product` hoặc bắt đầu bằng một tiền tố trong `prefixes`.
    StockCode được strip().upper() trước khi đối chiếu. KHÔNG loại dòng thiếu CustomerID (khách vãng lai vẫn là
    hóa đơn hợp lệ) và KHÔNG loại các mã lệch STOCK_CODE_PATTERN ngoài chính sách ở bước 6.
    """
    d = normalize(df)
    np_set = {str(c).strip().upper() for c in non_product}
    pref = tuple(str(p).strip().upper() for p in prefixes)
    steps = [('0', 'Dữ liệu gốc', 0, len(d))]
    rules = [
        ('1', 'InvoiceNo hoặc StockCode thiếu/rỗng', lambda x: (x['InvoiceNo'] == '') | (x['StockCode'] == '')),
        ('2', "Hóa đơn hủy (InvoiceNo bắt đầu bằng 'C'/'c')", lambda x: _is_cancelled(x['InvoiceNo'])),
        ('3', 'Quantity <= 0 hoặc thiếu', lambda x: ~(x['Quantity'] > 0)),
        ('4', 'UnitPrice <= 0 hoặc thiếu', lambda x: ~(x['UnitPrice'] > 0)),
        ('5', 'Description rỗng', lambda x: x['Description'] == ''),
        ('6', f'Mã không phải sản phẩm ({", ".join(sorted(np_set))}; tiền tố {", ".join(pref)})',
         lambda x: x['StockCode'].isin(np_set) | _has_prefix(x['StockCode'], pref)),
    ]
    for step, desc, rule in rules:
        mask = rule(d).fillna(True).astype(bool)
        d = d[~mask]
        steps.append((step, desc, int(mask.sum()), len(d)))
    return d.reset_index(drop=True), pd.DataFrame(steps, columns=STEP_COLUMNS)


# ===========================================================================
# Hàm thuần: giao dịch, kiểm tra, thống kê
# ===========================================================================

def to_transactions(df_clean: pd.DataFrame, id_start: int = ID_START):
    """Biến dữ liệu đã làm sạch thành giao dịch (THUẦN). Trả (transactions, item_map, info).

    - Giao dịch = tập StockCode PHÂN BIỆT của mỗi InvoiceNo (bỏ Quantity; giữ cả hóa đơn chỉ có 1 sản phẩm).
    - transactions: list các (InvoiceNo, [id tăng dần]), hóa đơn sắp theo InvoiceNo (chuỗi).
    - Ánh xạ StockCode -> id tất định: mã sắp tăng dần (chuỗi), id liên tục từ `id_start`; song ánh.
    - item_map: DataFrame (id, stock_code, description, n_transactions, support_pct) với description = Description
      phổ biến nhất của mã (hòa thì nhỏ nhất theo thứ tự từ điển), n_transactions = số hóa đơn phân biệt chứa mã,
      support_pct = 100 * n_transactions / tổng số hóa đơn.
    - info: số dòng đầu vào, số dòng trùng (InvoiceNo, StockCode) đã gộp, số giao dịch, số item.
    """
    d = normalize(df_clean)
    n_dup = int(d.duplicated(['InvoiceNo', 'StockCode']).sum())
    pairs = d[['InvoiceNo', 'StockCode']].drop_duplicates()
    codes = sorted(pairs['StockCode'].unique())
    code_to_id = {c: i + id_start for i, c in enumerate(codes)}
    assert len(set(code_to_id.values())) == len(code_to_id), 'id không duy nhất'

    pairs = pairs.assign(item=pairs['StockCode'].map(code_to_id))
    grouped = pairs.groupby('InvoiceNo', sort=False)['item'].apply(lambda s: sorted({int(v) for v in s}))
    invoices = sorted(grouped.index)
    transactions = [(inv, list(grouped[inv])) for inv in invoices]

    n_tx = len(transactions)
    counts = pairs.groupby('StockCode')['InvoiceNo'].nunique()
    top = _top_description(d)
    item_map = pd.DataFrame({'id': [code_to_id[c] for c in codes], 'stock_code': codes})
    item_map['description'] = item_map['stock_code'].map(top).fillna('')
    item_map['n_transactions'] = item_map['stock_code'].map(counts).astype(int)
    item_map['support_pct'] = 100.0 * item_map['n_transactions'] / n_tx
    info = {'n_rows': len(d), 'n_duplicate_rows_merged': n_dup, 'n_transactions': n_tx, 'n_items': len(codes),
            'id_start': id_start}
    validate_transactions(transactions, item_map, id_start=id_start)
    return transactions, item_map, info


def validate_transactions(transactions, item_map: pd.DataFrame, id_start: int = ID_START) -> bool:
    """Kiểm tra tính nhất quán của giao dịch và bảng ánh xạ (THUẦN; báo AssertionError nếu sai).

    Không có giao dịch rỗng; không item trùng; item tăng ngặt trong mỗi giao dịch; hóa đơn sắp theo InvoiceNo và
    không trùng; id duy nhất, liên tục từ `id_start`; StockCode <-> id là song ánh; mọi id của item_map đều xuất hiện
    và ngược lại; n_transactions khớp số giao dịch chứa item; 0 < support_pct <= 100.
    """
    invoices = [inv for inv, _ in transactions]
    assert invoices == sorted(invoices) and len(set(invoices)) == len(invoices), 'hóa đơn chưa sắp hoặc bị trùng'
    used: dict[int, int] = {}
    for inv, items in transactions:
        assert len(items) > 0, f'giao dịch rỗng: {inv}'
        assert all(a < b for a, b in zip(items, items[1:])), f'item trùng hoặc chưa tăng dần: {inv}'
        for i in items:
            used[i] = used.get(i, 0) + 1
    ids = list(item_map['id'])
    assert len(set(ids)) == len(ids), 'id trùng trong item_map'
    assert sorted(ids) == list(range(id_start, id_start + len(ids))), 'id không liên tục'
    assert item_map['stock_code'].is_unique, 'StockCode trùng trong item_map (không phải song ánh)'
    assert set(ids) == set(used), 'tập item trong item_map khác tập item xuất hiện trong giao dịch'
    assert all(used[i] == n for i, n in zip(item_map['id'], item_map['n_transactions'])), 'n_transactions sai'
    sp = item_map['support_pct']
    assert ((sp > 0) & (sp <= 100)).all(), 'support_pct ngoài (0, 100]'
    return True


def transaction_stats(transactions, item_map: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Thống kê giao dịch (THUẦN). Trả (bảng chỉ số, top-10 sản phẩm theo support %).

    Chỉ số: số giao dịch, số item, độ dài giỏ trung bình / trung vị / p90 / lớn nhất, tỷ lệ hóa đơn 1 sản phẩm,
    mật độ = độ dài trung bình / số item. Top-10 sắp theo n_transactions giảm dần, hòa theo id.
    """
    lengths = pd.Series([len(items) for _, items in transactions], dtype=float)
    n_items = len(item_map)
    rows = [
        ('Số giao dịch (hóa đơn)', len(lengths)),
        ('Số item (sản phẩm)', n_items),
        ('Độ dài giỏ trung bình', round(lengths.mean(), 3)),
        ('Độ dài giỏ trung vị', lengths.median()),
        ('Độ dài giỏ p90', lengths.quantile(0.9)),
        ('Độ dài giỏ lớn nhất', lengths.max()),
        ('Tỷ lệ hóa đơn 1 sản phẩm (%)', round(100.0 * (lengths == 1).mean(), 3)),
        ('Mật độ (%) = độ dài TB / số item', round(100.0 * lengths.mean() / n_items, 4)),
    ]
    stats = pd.DataFrame(rows, columns=['chỉ số', 'giá trị'])
    top10 = (item_map.sort_values(['n_transactions', 'id'], ascending=[False, True], kind='mergesort')
             .head(10).reset_index(drop=True))
    return stats, top10


# ===========================================================================
# Hàm có tác dụng phụ: ghi file, vẽ hình
# ===========================================================================

def write_spmf(transactions, item_map: pd.DataFrame, app_dir: str | Path, id_start: int = ID_START) -> dict:
    """Ghi giao dịch định dạng SPMF và bảng ánh xạ (TÁC DỤNG PHỤ: ghi file). Trả dict đường dẫn.

    - `<app_dir>/data/transactions.txt`: mỗi dòng một hóa đơn (theo thứ tự InvoiceNo), item tăng dần cách nhau
      dấu cách.
    - `<app_dir>/data/item_map.csv`: id, stock_code, description, n_transactions, support_pct.
    Sau khi ghi, đọc lại file để kiểm tra: số dòng = số giao dịch, không dòng rỗng, không item trùng, item tăng dần,
    tập item trong file = tập id của item_map.
    """
    validate_transactions(transactions, item_map, id_start=id_start)
    data_dir = Path(app_dir) / 'data'
    data_dir.mkdir(parents=True, exist_ok=True)
    tx_path, map_path = data_dir / 'transactions.txt', data_dir / 'item_map.csv'
    with open(tx_path, 'w', encoding='utf-8', newline='\n') as f:
        for _, items in transactions:
            f.write(' '.join(map(str, items)) + '\n')
    item_map.to_csv(map_path, index=False, encoding='utf-8')

    lines = tx_path.read_text(encoding='utf-8').splitlines()
    assert len(lines) == len(transactions), 'số dòng transactions.txt khác số giao dịch'
    seen = set()
    for k, line in enumerate(lines, 1):
        items = [int(t) for t in line.split()]
        assert items, f'dòng {k} rỗng'
        assert all(a < b for a, b in zip(items, items[1:])), f'dòng {k}: item trùng hoặc chưa tăng dần'
        seen.update(items)
    assert seen == set(item_map['id']), 'số item trong item_map khác số item xuất hiện trong file'
    return {'transactions': tx_path, 'item_map': map_path}


def plot_basket_length(transactions, path: str | Path) -> Path:
    """Vẽ histogram độ dài giỏ hàng, cắt ở phân vị 99 (TÁC DỤNG PHỤ: ghi PNG). Trả đường dẫn file."""
    import matplotlib.pyplot as plt

    lengths = pd.Series([len(items) for _, items in transactions])
    p99 = int(lengths.quantile(0.99))
    shown = lengths[lengths <= p99]
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fig, ax = plt.subplots(figsize=(6.4, 3.6), dpi=150)
    ax.hist(shown, bins=range(1, p99 + 2), color='#4169e1', edgecolor='white', linewidth=0.4, align='left')
    ax.set_xlabel('Số sản phẩm phân biệt trong hóa đơn')
    ax.set_ylabel('Số hóa đơn')
    ax.set_title(f'Phân bố độ dài giỏ hàng (≤ p99 = {p99}; bỏ {len(lengths) - len(shown)} hóa đơn dài hơn)',
                 fontsize=9)
    ax.grid(axis='y', alpha=0.3)
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)
    return path


def save_results(app_dir: str | Path, cleaning_steps: pd.DataFrame, transaction_stats: pd.DataFrame) -> dict:
    """Ghi bảng kết quả được commit vào `<app_dir>/results/` (TÁC DỤNG PHỤ). Trả dict đường dẫn."""
    res = Path(app_dir) / 'results'
    res.mkdir(parents=True, exist_ok=True)
    paths = {'cleaning_steps': res / 'cleaning_steps.csv', 'transaction_stats': res / 'transaction_stats.csv'}
    cleaning_steps.to_csv(paths['cleaning_steps'], index=False, encoding='utf-8')
    transaction_stats.to_csv(paths['transaction_stats'], index=False, encoding='utf-8')
    return paths


def run_preprocessing(app_dir: str | Path, uci_url: str = UCI_URL, sha256: str = RAW_SHA256, hf_url: str = '',
                      non_product=NON_PRODUCT, prefixes=NON_PRODUCT_PREFIXES, id_start: int = ID_START,
                      pattern: str = STOCK_CODE_PATTERN) -> dict:
    """Chạy toàn bộ tiền xử lý (TÁC DỤNG PHỤ): tải/đọc -> chẩn đoán -> làm sạch -> giao dịch -> ghi SPMF ->
    thống kê -> histogram; ghi results/cleaning_steps.csv, results/transaction_stats.csv,
    results/figures/basket_length.png. Trả dict mọi bảng và đường dẫn (dùng cho demo.ipynb mục 7.1).
    """
    app_dir = Path(app_dir)
    raw = load_raw(app_dir, uci_url, sha256, hf_url=hf_url)
    diag = diagnose(raw, pattern=pattern)
    df_clean, steps = clean(raw, non_product=non_product, prefixes=prefixes)
    transactions, item_map, info = to_transactions(df_clean, id_start=id_start)
    files = write_spmf(transactions, item_map, app_dir, id_start=id_start)
    stats, top10 = transaction_stats(transactions, item_map)
    fig = plot_basket_length(transactions, app_dir / 'results' / 'figures' / 'basket_length.png')
    saved = save_results(app_dir, steps, stats)
    return {'diagnosis': diag, 'cleaning_steps': steps, 'info': info, 'item_map': item_map, 'stats': stats,
            'top10': top10, 'files': {**files, **saved, 'basket_length': fig}}


if __name__ == '__main__':
    out = run_preprocessing(find_root() / 'applications' / 'application_01')
    print(out['cleaning_steps'].to_string(index=False))
    print(out['stats'].to_string(index=False))
    for k, v in out['files'].items():
        print(f'{k}: {v}')
