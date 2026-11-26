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
- Khai thác bằng FPClose của nhóm (mục 4–7 của notebook):
  run_fpclose, count_itemsets, read_itemsets, read_rules, minsup_survey, plot_minsup_survey (TÁC DỤNG PHỤ:
  chạy demo.jl, đọc/ghi file); item_labels, verify_rules, diverse_top_rules, compare_rule_sets (THUẦN).
- Hiển thị: styled (THUẦN, trả pandas Styler để căn lề bảng trong notebook).
- Kiểm chứng hóa đơn rất dài (mục 5.1): filter_long_transactions (THUẦN); long_invoice_check,
  long_invoice_rules_check (TÁC DỤNG PHỤ).

Quy ước id item: `read_spmf` của nhóm nhận mọi số nguyên >= 0 (item 0 hợp lệ), tự bỏ item trùng và sắp tăng dần
trong mỗi giao dịch. Module dùng id liên tục bắt đầu từ ID_START = 1 (giống các file benchmark đã chuẩn hóa và quy
ước của SPMF, để có thể đối chiếu với SPMF khi cần), và vẫn ghi item tăng dần, không trùng.
"""

from __future__ import annotations

import hashlib
import re
import shutil
import subprocess
import time
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


def transaction_stats(transactions, item_map: pd.DataFrame,
                      large_thresholds=(100, 200, 500)) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Thống kê giao dịch (THUẦN). Trả (bảng chỉ số, top-10 sản phẩm theo support %).

    Chỉ số: số giao dịch, số item, độ dài giỏ trung bình / trung vị / p90 / lớn nhất, tỷ lệ hóa đơn 1 sản phẩm,
    mật độ = độ dài trung bình / số item, số hóa đơn có >= `t` sản phẩm và tỷ lệ % của chúng với t trong
    `large_thresholds`. Top-10 sắp theo n_transactions giảm dần, hòa theo id.
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
    for t in large_thresholds:
        n_large = int((lengths >= t).sum())
        rows.append((f'Số hóa đơn có >= {t} sản phẩm', n_large))
        rows.append((f'Tỷ lệ hóa đơn có >= {t} sản phẩm (%)', round(100.0 * n_large / len(lengths), 3)))
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


# ===========================================================================
# Khai thác bằng FPClose của nhóm (demo.jl) và đọc kết quả
# ===========================================================================

_INFO_LINE = re.compile(r'(\w+) = (\S.*?)\s*$')
_ITEMSET_LINE = re.compile(r'^(.*?)\s*#SUP:\s*(\d+)\s*$')
_RULE_LINE = re.compile(r'^(.*?) ==> (.*?) #SUP: (\S+) #CONF: (\S+) #LIFT: (\S+) #COUNT: (\d+)\s*$')


def _parse_info(stderr: str) -> dict:
    """Đọc khối `@info "FPClose" ...` mà demo.jl in ra stderr thành dict (số nguyên/thực nếu đọc được)."""
    info = {}
    for line in stderr.splitlines():
        m = _INFO_LINE.search(line)
        if not m:
            continue
        key, val = m.group(1), m.group(2).strip().strip('"')
        for conv in (int, float):
            try:
                val = conv(val)
                break
            except ValueError:
                pass
        info[key] = val
    return info


def _fmt_minsup(minsup: float) -> str:
    """minsup dạng tỉ lệ cho tham số --minsup và tên file (0.015 -> '0.015')."""
    return repr(float(minsup))


def rules_path(out_dir: str | Path, minsup: float, minconf: float, top: int | None = None) -> Path:
    """Đường dẫn file luật mà `run_fpclose` ghi cho (minsup, minconf, top) trong `out_dir` (THUẦN)."""
    scope = 'all' if top is None else f'top{int(top)}'
    return Path(out_dir) / f'rules_ms{_fmt_minsup(minsup)}_mc{float(minconf)!r}_{scope}.txt'


class FPCloseTimeout(TimeoutError):
    """demo.jl chạy quá thời gian cho phép (tiến trình đã bị dừng)."""


def run_fpclose(root: str | Path, transactions_path: str | Path, minsup: float, out_dir: str | Path,
                minconf: float | None = None, top: int | None = None, timeout: float | None = None) -> dict:
    """Chạy FPClose của nhóm qua `demo.jl` (TÁC DỤNG PHỤ: tiến trình con, ghi file).

    Lệnh: `julia --project=<root> <root>/demo.jl --minsup <minsup> --output-closed ... --output-all ...
    [--rules ... --minconf <minconf> [--top <top>]] <transactions_path>`, chạy với cwd=root, không qua shell.
    Luôn ghi cả tập đóng và mọi tập phổ biến (recovery). `minsup` là tỉ lệ trong (0, 1].

    - Có `minconf` mà `top=None`: ghi TOÀN BỘ luật (không truyền --top), file `rules_ms<..>_mc<..>_all.txt`;
      có `top`: chỉ ghi `top` luật theo lift, file `rules_ms<..>_mc<..>_top<k>.txt`.
    - `timeout` (giây, None = không giới hạn): quá thời gian thì tiến trình bị dừng và báo `FPCloseTimeout`.

    Trả dict: closed, all, rules (đường dẫn; rules = None nếu không sinh luật), wall_s (thời gian wall clock của cả
    tiến trình, gồm khởi động Julia), returncode, info (các số demo.jl in ra stderr: transactions, minsup_count,
    closed_itemsets, frequent_itemsets, mining_seconds, recovery_seconds, rules_generated, rules_written, ...),
    stderr, cmd. Mã thoát khác 0 thì báo RuntimeError kèm stderr.
    """
    root, out_dir = Path(root), Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    tag = _fmt_minsup(minsup)
    paths = {'closed': out_dir / f'closed_ms{tag}.txt', 'all': out_dir / f'all_ms{tag}.txt', 'rules': None}
    cmd = ['julia', f'--project={root}', str(root / 'demo.jl'), '--minsup', tag,
           '--output-closed', str(paths['closed']), '--output-all', str(paths['all'])]
    if minconf is not None:
        paths['rules'] = rules_path(out_dir, minsup, minconf, top)
        cmd += ['--rules', str(paths['rules']), '--minconf', repr(float(minconf))]
        if top is not None:
            cmd += ['--top', str(int(top))]
    cmd.append(str(Path(transactions_path)))
    t0 = time.perf_counter()
    try:
        proc = subprocess.run(cmd, cwd=str(root), capture_output=True, text=True, encoding='utf-8',
                              errors='replace', timeout=timeout)
    except subprocess.TimeoutExpired as e:        # subprocess.run đã dừng tiến trình con
        raise FPCloseTimeout(f'demo.jl quá {timeout} s ở minsup = {tag} (đã dừng tiến trình)') from e
    wall = time.perf_counter() - t0
    if proc.returncode != 0:
        raise RuntimeError(f'demo.jl lỗi (mã thoát {proc.returncode}):\n{proc.stderr}')
    return {**paths, 'wall_s': wall, 'returncode': proc.returncode, 'info': _parse_info(proc.stderr),
            'stderr': proc.stderr, 'cmd': cmd}


def count_itemsets(path: str | Path, min_size: int = 1) -> int:
    """Số itemset có ít nhất `min_size` item trong một file output SPMF (`items #SUP: n`) (TÁC DỤNG PHỤ: đọc file)."""
    n = 0
    with open(path, encoding='utf-8') as f:
        for line in f:
            m = _ITEMSET_LINE.match(line.strip())
            if m and len(m.group(1).split()) >= min_size:
                n += 1
    return n


def styled(df: pd.DataFrame, hide_index: bool = True):
    """Định dạng bảng để hiển thị trong notebook, không đổi dữ liệu (THUẦN; trả pandas Styler, cần jinja2).

    - Cột chuỗi (dtype object/string): căn trái cả ô dữ liệu lẫn tiêu đề cột; cột số giữ căn phải mặc định.
    - Số thực hiển thị 6 chữ số thập phân (mặc định của Styler); số nguyên và chuỗi giữ nguyên.
    - `hide_index=True` thì ẩn cột chỉ số.
    """
    text_cols = [c for c in df.columns
                 if pd.api.types.is_object_dtype(df[c]) or pd.api.types.is_string_dtype(df[c])]
    st = df.style.format(precision=6)
    if text_cols:
        st = st.set_properties(subset=text_cols, **{'text-align': 'left'})
        st = st.set_table_styles(
            [{'selector': f'th.col_heading.col{df.columns.get_loc(c)}', 'props': [('text-align', 'left')]}
             for c in text_cols], overwrite=False)
    if hide_index:
        st = st.hide(axis='index') if hasattr(st, 'hide') else st.hide_index()
    return st


def item_labels(item_map: pd.DataFrame) -> dict:
    """id -> nhãn hiển thị "TÊN [StockCode]" (THUẦN)."""
    return {int(i): f'{d} [{c}]' for i, c, d in zip(item_map['id'], item_map['stock_code'], item_map['description'])}


def read_itemsets(path: str | Path, item_map: pd.DataFrame, n_transactions: int) -> pd.DataFrame:
    """Đọc file itemset `1 2 #SUP: 5` thành DataFrame (TÁC DỤNG PHỤ: đọc file).

    Cột: items (nhãn "TÊN [StockCode]" nối bằng ' + '), size, support_count, support_pct
    (= 100 * support_count / n_transactions), item_ids (các id cách nhau dấu cách). Sắp theo support giảm dần,
    rồi kích thước giảm dần, rồi id tăng dần.
    """
    labels = item_labels(item_map)
    rows = []
    with open(path, encoding='utf-8') as f:
        for line in f:
            m = _ITEMSET_LINE.match(line.strip())
            if not m:
                continue
            ids = sorted(int(t) for t in m.group(1).split())
            cnt = int(m.group(2))
            rows.append((' + '.join(labels[i] for i in ids), len(ids), cnt, 100.0 * cnt / n_transactions,
                         ' '.join(map(str, ids))))
    df = pd.DataFrame(rows, columns=['items', 'size', 'support_count', 'support_pct', 'item_ids'])
    key = df['item_ids'].map(lambda s: tuple(int(t) for t in s.split()))
    df = df.assign(_k=key).sort_values(['support_count', 'size', '_k'], ascending=[False, False, True],
                                       kind='mergesort').drop(columns='_k')
    return df.reset_index(drop=True)


def read_rules(path: str | Path, item_map: pd.DataFrame) -> pd.DataFrame:
    """Đọc file luật của demo.jl (`X ==> Y #SUP: s #CONF: c #LIFT: l #COUNT: n`) (TÁC DỤNG PHỤ: đọc file).

    Cột: rank (thứ tự trong file, đã xếp theo lift), antecedent, consequent (nhãn "TÊN [StockCode]" nối ' + '),
    support, confidence, lift, count (= sup(X ∪ Y)), antecedent_ids, consequent_ids (id cách nhau dấu cách).
    """
    labels = item_labels(item_map)
    rows = []
    with open(path, encoding='utf-8') as f:
        for line in f:
            m = _RULE_LINE.match(line.strip())
            if not m:
                continue
            a = [int(t) for t in m.group(1).split()]
            b = [int(t) for t in m.group(2).split()]
            rows.append((len(rows) + 1, ' + '.join(labels[i] for i in a), ' + '.join(labels[i] for i in b),
                         float(m.group(3)), float(m.group(4)), float(m.group(5)), int(m.group(6)),
                         ' '.join(map(str, a)), ' '.join(map(str, b))))
    return pd.DataFrame(rows, columns=['rank', 'antecedent', 'consequent', 'support', 'confidence', 'lift', 'count',
                                       'antecedent_ids', 'consequent_ids'])


SURVEY_COLUMNS = ['minsup_pct', 'minsup_count', 'status', 'n_closed', 'n_closed_size2plus', 'n_all', 'compression',
                  'time_s', 'mining_s', 'recovery_s']


def minsup_survey(root: str | Path, transactions_path: str | Path, minsups, out_dir: str | Path,
                  timeout: float | None = None) -> pd.DataFrame:
    """Khảo sát số tập đóng / mọi tập phổ biến theo minsup bằng demo.jl (TÁC DỤNG PHỤ: chạy tiến trình, ghi file).

    Các mức được chạy từ cao xuống thấp, mỗi mức một lần `run_fpclose` (không sinh luật) với giới hạn `timeout`
    giây. Mức nào quá thời gian được ghi một dòng `status = 'timeout'` (các cột số để trống) và các mức thấp hơn
    KHÔNG được chạy (số itemset chỉ tăng khi minsup giảm). Cột: minsup_pct, minsup_count, status ('ok'/'timeout'),
    n_closed, n_closed_size2plus (tập đóng có >= 2 item), n_all, compression (= n_all / n_closed), time_s (wall
    clock cả tiến trình, gồm khởi động Julia), mining_s, recovery_s (demo.jl tự đo). Số đếm từ file được đối chiếu
    với số demo.jl in ra.
    """
    rows = []
    for ms in sorted(minsups, reverse=True):
        try:
            r = run_fpclose(root, transactions_path, ms, out_dir, timeout=timeout)
        except FPCloseTimeout as e:
            print(e, '-> bỏ qua các mức minsup thấp hơn')
            rows.append({'minsup_pct': 100.0 * ms, 'status': 'timeout', 'time_s': timeout})
            break
        n_closed, n_all = count_itemsets(r['closed']), count_itemsets(r['all'])
        info = r['info']
        assert info.get('closed_itemsets', n_closed) == n_closed, 'số tập đóng trong file khác số demo.jl báo'
        assert info.get('frequent_itemsets', n_all) == n_all, 'số tập phổ biến trong file khác số demo.jl báo'
        rows.append({'minsup_pct': 100.0 * ms, 'minsup_count': info.get('minsup_count'), 'status': 'ok',
                     'n_closed': n_closed, 'n_closed_size2plus': count_itemsets(r['closed'], min_size=2),
                     'n_all': n_all, 'compression': n_all / n_closed if n_closed else float('nan'),
                     'time_s': round(r['wall_s'], 3), 'mining_s': info.get('mining_seconds'),
                     'recovery_s': info.get('recovery_seconds')})
    df = pd.DataFrame(rows, columns=SURVEY_COLUMNS)
    for c in ('minsup_count', 'n_closed', 'n_closed_size2plus', 'n_all'):
        df[c] = df[c].astype('Int64')               # số nguyên, cho phép ô trống ở dòng timeout
    return df


def filter_long_transactions(transactions, max_len: int):
    """Bỏ các giao dịch có >= `max_len` sản phẩm (THUẦN). Trả (giao dịch còn lại, số giao dịch bị loại).

    Giữ nguyên thứ tự hóa đơn và id item (không ánh xạ lại id).
    """
    kept = [(inv, items) for inv, items in transactions if len(items) < max_len]
    return kept, len(transactions) - len(kept)


def _write_transaction_file(transactions, path: Path) -> Path:
    """Ghi giao dịch định dạng SPMF (mỗi dòng các id tăng dần) và kiểm tra lại số dòng (TÁC DỤNG PHỤ)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        for _, items in transactions:
            assert items and all(a < b for a, b in zip(items, items[1:])), 'giao dịch rỗng hoặc item chưa tăng dần'
            f.write(' '.join(map(str, items)) + '\n')
    with open(path, encoding='utf-8') as f:
        assert sum(1 for _ in f) == len(transactions), f'số dòng {path} khác số giao dịch'
    return path


LONG_CHECK_COLUMNS = ['max_len', 'n_removed', 'n_transactions', 'minsup_pct', 'minsup_count', 'n_closed', 'n_all',
                      'compression', 'status']


def long_invoice_check(root: str | Path, app_dir: str | Path, transactions, item_map: pd.DataFrame, thresholds,
                       minsups, out_dir: str | Path, timeout: float | None = None,
                       baseline: pd.DataFrame | None = None) -> pd.DataFrame:
    """Kiểm chứng ảnh hưởng của hóa đơn rất dài lên số tập đóng / tập phổ biến (TÁC DỤNG PHỤ: ghi file, chạy demo.jl).

    - Dòng "gốc": khảo sát trên `<app_dir>/data/transactions.txt` (không lọc) ở `minsups`; nếu truyền `baseline`
      (bảng của `minsup_survey` đã chạy ở mục 5) thì lấy lại các dòng có minsup tương ứng, không chạy lại.
    - Với mỗi ngưỡng t trong `thresholds`: bỏ giao dịch có >= t sản phẩm (`filter_long_transactions`), ghi
      `<app_dir>/data/transactions_lt<t>.txt` (giữ nguyên id item), rồi chạy `minsup_survey` ở `minsups`
      (output thô vào `<out_dir>/lt<t>/`). minsup tương đối được tính trên số giao dịch còn lại.
    Cột: max_len ('gốc' hoặc t), n_removed, n_transactions, minsup_pct, minsup_count, n_closed, n_all,
    compression, status.
    """
    app_dir, out_dir = Path(app_dir), Path(out_dir)
    known = set(int(i) for i in item_map['id'])
    pcts = {round(100.0 * m, 10) for m in minsups}
    frames = []

    if baseline is not None:
        base = baseline[baseline['minsup_pct'].round(10).isin(pcts)].copy()
    else:
        base = minsup_survey(root, app_dir / 'data' / 'transactions.txt', minsups, out_dir / 'goc', timeout=timeout)
    frames.append(base.assign(max_len='gốc', n_removed=0, n_transactions=len(transactions)))

    for t in thresholds:
        kept, n_rem = filter_long_transactions(transactions, t)
        assert all(i in known for _, items in kept for i in items), 'id item không có trong item_map'
        path = _write_transaction_file(kept, app_dir / 'data' / f'transactions_lt{t}.txt')
        s = minsup_survey(root, path, minsups, out_dir / f'lt{t}', timeout=timeout)
        frames.append(s.assign(max_len=t, n_removed=n_rem, n_transactions=len(kept)))

    out = pd.concat(frames, ignore_index=True)
    out['max_len'] = out['max_len'].astype(str)
    return out[LONG_CHECK_COLUMNS]


def long_invoice_rules_check(root: str | Path, app_dir: str | Path, transactions, item_map: pd.DataFrame,
                             minsup: float, minconf: float, max_len: int, top_k: int, out_dir: str | Path,
                             timeout: float | None = None):
    """So sánh top-k luật theo lift trên dữ liệu gốc với toàn bộ luật khi bỏ hóa đơn >= `max_len` sản phẩm
    (TÁC DỤNG PHỤ: ghi file, chạy demo.jl hai lần).

    Chạy demo.jl ghi TOÀN BỘ luật ở (`minsup`, `minconf`) trên `<app_dir>/data/transactions.txt` và trên
    `<app_dir>/data/transactions_lt<max_len>.txt` (tạo lại từ `transactions` nếu chưa có), rồi
    `compare_rule_sets(top-k gốc, toàn bộ luật đã lọc)`. Một luật "không đạt ngưỡng" sau khi lọc có thể do support
    hoặc confidence giảm dưới ngưỡng. Trả (bảng so sánh, dict số luật ở hai phía, DataFrame toàn bộ luật đã lọc
    — kết quả read_rules của `<out_dir>/lt<max_len>/rules_ms<..>_mc<..>_all.txt`).
    """
    app_dir, out_dir = Path(app_dir), Path(out_dir)
    base_run = run_fpclose(root, app_dir / 'data' / 'transactions.txt', minsup, out_dir / 'goc',
                           minconf=minconf, timeout=timeout)
    base_rules = read_rules(base_run['rules'], item_map)
    kept, n_rem = filter_long_transactions(transactions, max_len)
    path = _write_transaction_file(kept, app_dir / 'data' / f'transactions_lt{max_len}.txt')
    lt_run = run_fpclose(root, path, minsup, out_dir / f'lt{max_len}', minconf=minconf, timeout=timeout)
    lt_rules = read_rules(lt_run['rules'], item_map)
    top = base_rules[base_rules['rank'] <= top_k].reset_index(drop=True)
    table = compare_rule_sets(top, lt_rules, 'gốc', f'lt{max_len}')
    info = {'n_rules_goc': len(base_rules), f'n_rules_lt{max_len}': len(lt_rules), 'n_removed': n_rem,
            'n_transactions_lt': len(kept)}
    return table, info, lt_rules


def plot_minsup_survey(survey: pd.DataFrame, path: str | Path) -> Path:
    """Vẽ số tập đóng và số mọi tập phổ biến theo minsup (trục tung trái, thang log) cùng tỷ lệ nén
    n_all / n_closed (trục tung phải, tuyến tính); bỏ các dòng timeout (TÁC DỤNG PHỤ: ghi PNG)."""
    import matplotlib.pyplot as plt

    s = survey[survey['status'] == 'ok'].sort_values('minsup_pct', ascending=False).reset_index(drop=True)
    x = list(range(len(s)))
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fig, ax = plt.subplots(figsize=(6.4, 3.8), dpi=150)
    l1 = ax.plot(x, s['n_closed'].astype(float), marker='o', color='#4169e1', label='Tập phổ biến đóng')
    l2 = ax.plot(x, s['n_all'].astype(float), marker='s', color='#ff8c00', label='Mọi tập phổ biến')
    ax.set_yscale('log')
    ax.set_xticks(x)
    ax.set_xticklabels([f'{v:g}'.replace('.', ',') for v in s['minsup_pct']])
    ax.set_xlabel('minsup (%)')
    ax.set_ylabel('Số itemset (thang log)')
    ax.grid(alpha=0.3)
    ax2 = ax.twinx()
    l3 = ax2.plot(x, s['compression'].astype(float), marker='^', linestyle='--', color='#555555',
                  label='Tỷ lệ nén n_all / n_closed (trục phải)')
    ax2.set_ylabel('Tỷ lệ nén n_all / n_closed')
    ax2.set_ylim(bottom=0)
    lines = l1 + l2 + l3
    ax.legend(lines, [ln.get_label() for ln in lines], fontsize=7, loc='upper left')
    n_to = int((survey['status'] == 'timeout').sum())
    note = f' ({n_to} mức quá thời gian, không vẽ)' if n_to else ''
    ax.set_title('Số tập phổ biến đóng, mọi tập phổ biến và tỷ lệ nén theo minsup' + note, fontsize=9)
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)
    return path


def verify_rules(rules_df: pd.DataFrame, transactions) -> pd.DataFrame:
    """Kiểm tra chéo luật bằng cách đếm trực tiếp trên giao dịch, không dùng FPClose (THUẦN).

    Với mỗi luật A -> B: đếm sup(A), sup(B), sup(A ∪ B) bằng phép bao hàm tập hợp trên `transactions`
    (list (InvoiceNo, [id])), tính lại support = sup(A ∪ B) / N, confidence = sup(A ∪ B) / sup(A),
    lift = confidence / (sup(B) / N). Cột `khớp` = True khi count bằng nhau và sai số tuyệt đối của support,
    confidence, lift đều < 1e-9.
    """
    sets = [frozenset(items) for _, items in transactions]
    n = len(sets)
    out = []
    for r in rules_df.itertuples(index=False):
        a = frozenset(int(t) for t in r.antecedent_ids.split())
        b = frozenset(int(t) for t in r.consequent_ids.split())
        ab = a | b
        sa = sum(1 for t in sets if a <= t)
        sb = sum(1 for t in sets if b <= t)
        sab = sum(1 for t in sets if ab <= t)
        sup, conf = sab / n, sab / sa
        lift = conf / (sb / n)
        ok = (sab == r.count and abs(sup - r.support) < 1e-9 and abs(conf - r.confidence) < 1e-9
              and abs(lift - r.lift) < 1e-9)
        out.append((r.rank, sa, sb, sab, r.count, sup, r.support, conf, r.confidence, lift, r.lift, ok))
    return pd.DataFrame(out, columns=['rank', 'sup_A', 'sup_B', 'sup_AB', 'count_fpclose', 'support_đếm',
                                      'support_fpclose', 'confidence_đếm', 'confidence_fpclose', 'lift_đếm',
                                      'lift_fpclose', 'khớp'])


def _ids(s: str) -> tuple:
    """Chuỗi id cách nhau dấu cách -> tuple số nguyên (giữ thứ tự)."""
    return tuple(int(t) for t in str(s).split())


def _itemset_label(a_ids, b_ids, a_label: str, b_label: str) -> tuple:
    """(id của Z = A ∪ B tăng dần, nhãn Z) từ id và nhãn hai vế; nhãn từng item tách theo ' + '."""
    pairs = list(zip(a_ids, a_label.split(' + '))) + list(zip(b_ids, b_label.split(' + ')))
    if len(pairs) != len(a_ids) + len(b_ids):        # tên sản phẩm có chứa ' + ': chỉ dùng id
        return tuple(sorted(a_ids + b_ids)), ' '.join(map(str, sorted(a_ids + b_ids)))
    pairs.sort()
    return tuple(i for i, _ in pairs), ' + '.join(lbl for _, lbl in pairs)


def _ordered_rules(rules_df: pd.DataFrame) -> pd.DataFrame:
    """Sắp luật như --top của demo.jl: lift giảm dần, rồi confidence giảm dần, rồi support giảm dần, rồi thứ tự từ
    điển của (antecedent_ids, consequent_ids). Sắp bằng khóa Python nên ổn định và tất định."""
    keys = [(-r.lift, -r.confidence, -r.support, _ids(r.antecedent_ids), _ids(r.consequent_ids), pos)
            for pos, r in enumerate(rules_df.itertuples(index=False))]
    order = [k[-1] for k in sorted(keys)]
    return rules_df.iloc[order].reset_index(drop=True)


def diverse_top_rules(rules_df: pd.DataFrame, k: int, mode: str) -> pd.DataFrame:
    """Chọn k luật "đa dạng" từ TOÀN BỘ luật (kết quả read_rules của file luật đầy đủ) (THUẦN).

    Thứ tự xét chung giống --top của demo.jl (xem `_ordered_rules`).
    - mode='itemset': với mỗi itemset Z = A ∪ B chỉ giữ luật đầu tiên theo thứ tự trên (bỏ các luật khác sinh từ
      cùng Z, trong đó có cặp đối xứng A→B / B→A), rồi lấy k luật đầu.
    - mode='item': duyệt tham lam theo thứ tự trên, chỉ nhận luật nếu không item nào của Z đã xuất hiện trong các
      luật đã nhận; dừng khi đủ k luật.
    Cột: rank (1..k trong bảng này), rank_all (rank gốc trong toàn bộ luật), itemset (nhãn Z), antecedent,
    consequent, support, confidence, lift, count, antecedent_ids, consequent_ids, itemset_ids.
    """
    if mode not in ('itemset', 'item'):
        raise ValueError("mode phải là 'itemset' hoặc 'item'")
    ordered = _ordered_rules(rules_df)
    chosen, seen_z, used_items = [], set(), set()
    for r in ordered.itertuples(index=False):
        a, b = _ids(r.antecedent_ids), _ids(r.consequent_ids)
        z_ids, z_label = _itemset_label(a, b, r.antecedent, r.consequent)
        if mode == 'itemset':
            if z_ids in seen_z:
                continue
            seen_z.add(z_ids)
        else:
            if used_items.intersection(z_ids):
                continue
            used_items.update(z_ids)
        chosen.append({'rank_all': int(r.rank), 'itemset': z_label, 'antecedent': r.antecedent,
                       'consequent': r.consequent, 'support': r.support, 'confidence': r.confidence,
                       'lift': r.lift, 'count': int(r.count), 'antecedent_ids': r.antecedent_ids,
                       'consequent_ids': r.consequent_ids, 'itemset_ids': ' '.join(map(str, z_ids))})
        if len(chosen) == k:
            break
    out = pd.DataFrame(chosen, columns=['rank_all', 'itemset', 'antecedent', 'consequent', 'support', 'confidence',
                                        'lift', 'count', 'antecedent_ids', 'consequent_ids', 'itemset_ids'])
    out.insert(0, 'rank', range(1, len(out) + 1))
    return out


def compare_rule_sets(rules_lo: pd.DataFrame, rules_hi: pd.DataFrame, label_lo: str, label_hi: str) -> pd.DataFrame:
    """Đối chiếu hai tập luật (THUẦN): với mỗi luật trong `rules_lo`, luật đó (cùng antecedent_ids và
    consequent_ids) có trong `rules_hi` không và đứng ở rank nào.

    Rank lấy từ cột `rank_all` nếu có, không thì `rank`. Cột: rank_<label_lo>, antecedent, consequent,
    support_<label_lo>, lift_<label_lo>, có trong <label_hi> (bool), rank_<label_hi> (số, hoặc "không đạt ngưỡng"
    nếu không có), lift_<label_hi>.
    """
    def rank_col(df):
        return 'rank_all' if 'rank_all' in df.columns else 'rank'

    hi = {(_ids(r.antecedent_ids), _ids(r.consequent_ids)): (getattr(r, rank_col(rules_hi)), r.lift)
          for r in rules_hi.itertuples(index=False)}
    rows = []
    for r in rules_lo.itertuples(index=False):
        found = hi.get((_ids(r.antecedent_ids), _ids(r.consequent_ids)))
        rows.append({f'rank_{label_lo}': getattr(r, rank_col(rules_lo)), 'antecedent': r.antecedent,
                     'consequent': r.consequent, f'support_{label_lo}': r.support, f'lift_{label_lo}': r.lift,
                     f'có trong {label_hi}': found is not None,
                     f'rank_{label_hi}': str(found[0]) if found else 'không đạt ngưỡng',
                     f'lift_{label_hi}': found[1] if found else None})
    return pd.DataFrame(rows)


if __name__ == '__main__':
    out = run_preprocessing(find_root() / 'applications' / 'application_01')
    print(out['cleaning_steps'].to_string(index=False))
    print(out['stats'].to_string(index=False))
    for k, v in out['files'].items():
        print(f'{k}: {v}')
