# FIM benchmark dataset MANIFEST — 9 datasets

Updated (UTC): 2026-11-20T22:16:01+00:00
Previous five-dataset MANIFEST creation: 2026-11-20T22:15:26+00:00

## Dataset preparation
- Original raw files are kept unchanged in `data/raw/`.
- Clean files are UTF-8, LF-separated SPMF transactions (one per line).
- Item IDs are sorted unique positive integers separated by one ASCII space.
- `#`, `@`, `%` source metadata lines are removed; blank/invalid transaction rows are rejected.
- When source item IDs include zero, all IDs are shifted by +1 (bijection); this is recorded below.
- Only use CLEAN files on **both** the group implementation and SPMF.
- Reference transaction counts are approximate/version-dependent; measured counts are authoritative.
- These are third-party benchmark datasets. Original sources retain attribution.

## Dataset statistics

| Dataset | Transactions | Items | Avg length | Max length | Density % | Matches reference? |
|---|---:|---:|---:|---:|---:|---|
| chess | 3,196 | 75 | 37.0000 | 37 | 49.333333 | True |
| mushrooms | 8,416 | 119 | 23.0000 | 23 | 19.327731 | True |
| retail | 88,162 | 16,470 | 10.3058 | 76 | 0.062573 | True |
| T10I4D100K | 100,000 | 870 | 10.1023 | 29 | 1.161182 | True |
| accidents | 340,183 | 468 | 33.8079 | 51 | 7.223908 | True |
| connect | 67,557 | 129 | 43.0000 | 43 | 33.333333 | True |
| kosarak | 990,002 | 41,270 | 8.1000 | 2497 | 0.019627 | True |
| pumsb_star | 49,046 | 2,088 | 50.4821 | 63 | 2.417727 | True |
| T40I10D100K | 100,000 | 942 | 39.6051 | 77 | 4.204360 | True |

## Source files and SHA-256

### chess
- Raw file: `data/raw/chess.txt`
- Normalized file: `data/benchmark/chess.txt`
- Original URL: https://www.philippe-fournier-viger.com/spmf/publicdatasets/chess.txt
- Raw SHA-256: `a12ea887df58a396709430af5bf0a9a32d1f6eba8e7c13dd41f28b98572c5db2`
- Normalized SHA-256: `341d0ff8676e053dd3b417d61f84c732736154f987ce56975a099b07460957f5`
- Item-ID offset: `0` (verified by reproduction — see "Item-ID offset of the first five datasets" below)
- Measured transactions: `3196`
- Preparation: inherited from the original 5-dataset notebook; original file retained.

### mushrooms
- Raw file: `data/raw/mushrooms.txt`
- Normalized file: `data/benchmark/mushrooms.txt`
- Original URL: https://www.philippe-fournier-viger.com/spmf/publicdatasets/mushrooms.txt
- Raw SHA-256: `3bc1159b06baa231932810d1d58cbb958684be88b6daa8e3672f8d76c5f0eb98`
- Normalized SHA-256: `37a11571574d74bd1659c830a1e30e120485c6994b79f32e3b6635621a229bf7`
- Item-ID offset: `0` (verified by reproduction — see "Item-ID offset of the first five datasets" below)
- Measured transactions: `8416`
- Preparation: inherited from the original 5-dataset notebook; original file retained.

### retail
- Raw file: `data/raw/retail.txt`
- Normalized file: `data/benchmark/retail.txt`
- Original URL: https://www.philippe-fournier-viger.com/spmf/publicdatasets/retail.txt
- Raw SHA-256: `732c26de19888cb570d3fbb97e47206a9b1c0ce064f85dc1403314ba38f04eaa`
- Normalized SHA-256: `417563fb5feb3711d4f761230ca78b76d100fe2ee0d3178fcc4fbb000d8d1c36`
- Item-ID offset: `0` (verified by reproduction — see "Item-ID offset of the first five datasets" below)
- Measured transactions: `88162`
- Preparation: inherited from the original 5-dataset notebook; original file retained.

### T10I4D100K
- Raw file: `data/raw/T10I4D100K.txt`
- Normalized file: `data/benchmark/T10I4D100K.txt`
- Original URL: https://www.philippe-fournier-viger.com/spmf/publicdatasets/T10I4D100K.txt
- Raw SHA-256: `949983f61aa976d1b774474fadd31c5f15775b24728a5e7c8b79801822ab3f89`
- Normalized SHA-256: `fb2dd118ff822ff88d724e47d5a4cea6531c0bd6294397db4d36890c1450f1a7`
- Item-ID offset: `0` (verified by reproduction — see "Item-ID offset of the first five datasets" below)
- Measured transactions: `100000`
- Preparation: inherited from the original 5-dataset notebook; original file retained.

### accidents
- Raw file: `data/raw/accidents.txt`
- Normalized file: `data/benchmark/accidents.txt`
- Original URL: https://www.philippe-fournier-viger.com/spmf/publicdatasets/accidents.txt
- Raw SHA-256: `8c2275550966e3cb4b6066f2bb168489a9566c500af559fa3925f1b11d97f0cd`
- Normalized SHA-256: `c2b3762e3f8f0ca241c35359b24e3015fd34ea241d09f94b42ae44ed42914726`
- Item-ID offset: `0` (verified by reproduction — see "Item-ID offset of the first five datasets" below)
- Measured transactions: `340183`
- Preparation: inherited from the original 5-dataset notebook; original file retained.

### connect
- Raw file: `data/raw/connect.txt`
- Normalized file: `data/benchmark/connect.txt`
- Original URL: https://www.philippe-fournier-viger.com/spmf/publicdatasets/connect.txt
- Raw SHA-256: `7a23cb64573f12b6d967bdc44a81d6acdb89b00edf2ff46cc970ead6cc67b8e2`
- Normalized SHA-256: `650a92d7803c465fb08fc0e58de087ceab84cd5f0de4c6816b523774dcd6a2c9`
- Item-ID offset: `0`
- Measured transactions: `67557`
- Metadata removed: `0`
- Transaction rows with duplicated item IDs before cleaning: `0`
- Retrieval time (UTC, this notebook): `2026-11-20T22:15:28+00:00`

### kosarak
- Raw file: `data/raw/kosarak.dat.gz`
- Normalized file: `data/benchmark/kosarak.txt`
- Original URL: https://cs.rpi.edu/~zaki/Workshops/FIMI/data/kosarak.dat.gz
- Raw SHA-256: `b7f575183ba6e7f61e9a7b51ec386d33ce503a14227832ad5986bb57baaf0102`
- Normalized SHA-256: `cb4270629d786207143bb3c4002c36aedc3824f55294c7b3d5538c8023cec314`
- Item-ID offset: `0`
- Measured transactions: `990002`
- Metadata removed: `0`
- Transaction rows with duplicated item IDs before cleaning: `27`
- Retrieval time (UTC, this notebook): `2026-11-20T22:15:29+00:00`

### pumsb_star
- Raw file: `data/raw/pumsb_star.dat.gz`
- Normalized file: `data/benchmark/pumsb_star.txt`
- Original URL: https://cs.rpi.edu/~zaki/Workshops/FIMI/data/pumsb_star.dat.gz
- Raw SHA-256: `7386d5bd0b56611942a365958003430478d3d47cd920199736b602776005aada`
- Normalized SHA-256: `a9ecd5c882ffff9e0042703253d0eef3453f747537e0027c9be275a8aaf38f2f`
- Item-ID offset: `1`
- Measured transactions: `49046`
- Metadata removed: `0`
- Transaction rows with duplicated item IDs before cleaning: `0`
- Retrieval time (UTC, this notebook): `2026-11-20T22:15:30+00:00`

### T40I10D100K
- Raw file: `data/raw/T40I10D100K.dat` (note: despite the `.dat` name, the downloaded file is gzip-compressed; detect by magic bytes `1f 8b`, not by extension)
- Normalized file: `data/benchmark/T40I10D100K.txt`
- Original URL: https://cs.rpi.edu/~zaki/Workshops/FIMI/data/T40I10D100K.dat
- Raw SHA-256: `3939b939cba8380de51a00e9831d975639678f7b4115e4a6f29ca50d3d695339`
- Normalized SHA-256: `e3d86e8cf6eec0093528e238ab8a4ba10471375c00a9298144edb462caadb28c`
- Item-ID offset: `1`
- Measured transactions: `100000`
- Metadata removed: `0`
- Transaction rows with duplicated item IDs before cleaning: `0`
- Retrieval time (UTC, this notebook): `2026-11-20T22:15:31+00:00`

## Item-ID offset of the first five datasets

The historical records of chess, mushrooms, retail, T10I4D100K and accidents say
`unknown_original_not_logged`. On 2026-11-23 all 9 raw files were downloaded again from
the URLs above and re-normalized with `data/notebooks/data_setup.ipynb`
(Julia): 9/9 raw SHA-256 matched, and with offset `0` for these five datasets the
normalized SHA-256 and transaction counts matched the values above byte for byte.

## Public copy

- Hugging Face (public): https://huggingface.co/datasets/hytrang/fpclose-fim-benchmarks
- 9/9 public files were downloaded back and matched the normalized SHA-256 above (verified 2026-11-22).
- Direct download pattern: `https://huggingface.co/datasets/hytrang/fpclose-fim-benchmarks/resolve/main/<name>.txt`

## Derived datasets

- `data/scalability/retail_p010..p100.txt`: nested Retail subsets (seed 2026, size `n*p//100`).
- `data/synthetic/len05..len30.txt`: 6 correlated synthetic datasets (10,000 transactions, 500 items, seed 2026);
  statistics in `data/synthetic/synthetic_statistics.csv`.
- SHA-256 and line counts: `data/results/derived_hashes.csv`. These files are not committed; regenerate them with `data/notebooks/data_setup.ipynb`.

## License and attribution

The group did not create these datasets. They are redistributed only to make the experiments reproducible.
- chess, mushrooms, retail, T10I4D100K, accidents, connect: SPMF public datasets (Philippe Fournier-Viger), converted from the FIMI Repository / UCI originals.
- kosarak, pumsb_star, T40I10D100K: FIMI Repository (http://fimi.uantwerpen.be/data/, mirror cs.rpi.edu/~zaki).
- Original licenses and citations of each source apply.

## Reproducibility
- `data/notebooks/data_setup.ipynb` (Julia, self-contained) reproduces every file from the original
  sources: download and normalization of the 9 datasets, statistics, Retail subsets and synthetic datasets
  (with a port of Python's `random.Random`, so the published subsets and synthetic files are reproduced exactly).
  Each file is checked against the recorded hashes. Verified 2026-11-23: 9/9 normalized datasets,
  9/9 statistics, 6/6 synthetic and 5/5 Retail subsets identical.
- `data/notebooks/reference_check.ipynb` (Julia, self-contained) runs SPMF FPClose and the original FIMI
  FPclose (Grahne & Zhu, `fimi06b.tgz`) on the 56 configurations of `data/results/benchmark_config.csv`.
  Verified 2026-11-23: SPMF matched `reference_closed_itemsets` in 56/56 configurations, and SPMF and FIMI
  produced identical closed itemsets and supports in 56/56. This validates the data and the reference tools,
  not the group's implementation.
