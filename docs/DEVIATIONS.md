# Những chỗ code khác hoặc bổ sung so với bài báo

Bài báo: G. Grahne, J. Zhu, "Fast Algorithms for Frequent Itemset Mining Using FP-Trees",
IEEE TKDE 17(10), 2005, tr. 1347–1362. Số trang dưới đây là số trang in của tạp chí.
"Dòng N" là dòng của mã giả FPclose (Fig. 8, tr. 1354).

Nguyên tắc: code bám bài báo; chỗ nào khác hoặc bổ sung đều được liệt kê ở đây kèm lý do
và tác động lên kết quả. Mọi con số trong tài liệu này đo thật bằng code trong repo
(cách chạy ghi ngay tại mục).

| # | Nội dung | Loại | Ảnh hưởng kết quả |
|---|---|---|---|
| 1 | Cực tính của `closed_checking` | Chọn một trong hai cách đọc mâu thuẫn | Không |
| 2 | Nhánh đơn: thêm tiền tố đầy đủ i1..ip | Bài báo thiếu, code bổ sung | Có (thiếu thì sai) |
| 3 | Ghi chính X = T.base ở cuối mỗi lời gọi | Bài báo thiếu, code bổ sung | Có (thiếu thì sai) |
| 4 | Dòng 17 thay bằng chèn vào mọi CFI-tree trên stack | Theo Sec 3.2 / tr. 1354 | Không |
| 5 | Thứ tự duyệt header: ít phổ biến nhất trước | Bài báo chỉ nói ở Sec 3.2 | Có (đổi thứ tự thì sai) |
| 6 | C_X chỉ lưu item thuộc header, gốc giữ count lớn nhất, C_Y đọc lại từ C_X | Cách cài | Không |
| 7 | Phá hòa khi bằng count: item số nhỏ trước | Bài báo không quy định | Không |
| 8 | CFI-tree rút gọn (Fig. 9): đã cài, mặc định bật; count nút khác Fig. 9 | Theo Sec 3.3 / tr. 1355, có chỗ tự quyết | Không (chỉ bộ nhớ, tốc độ) |
| 9 | Các bổ sung nhỏ (tập rỗng, item trùng, làm tròn minsup, cây T_Y rỗng) | Bổ sung | Xem từng ý |
| 10 | FP-array: thời điểm quyết định dày/thưa, cách tính cho T_∅, giới hạn kích thước | Bài báo chưa đủ chi tiết, code chọn | Không (chỉ tốc độ/bộ nhớ) |
| 11 | Kết thúc sớm: kiểm tra bằng "đã có CFI ⊇ ... cùng count" | Diễn giải câu của bài báo | Không |
| 12 | (Số đo các tối ưu trên CSDL tổng hợp, đã đo lại sau các lần sửa) | Số đo | Không |
| 13 | Recovery và luật kết hợp | **Nhóm bổ sung, không thuộc bài báo** | Không đổi FPClose; thêm đầu ra |
| 14 | `closed_checking` lọc count bằng `==` thay `>=` (`exact_count`) | **Khác bài báo** (bài báo viết `>=`) | Không; trên FPClose thật là không-làm-gì |
| 15 | Số đo ba cải tiến CFI-tree (bỏ cấp phát thừa, `exact_count`, rút gọn) | Số đo | Không |

## 1. Cực tính của `closed_checking`

**Bài báo.** Mâu thuẫn trong chính Sec 4.1 (tr. 1354):
- Fig. 8 viết `if not closed_checking(X, C)` rồi mới chèn X (dòng 4) và
  `if not closed_checking(Y, C)` rồi mới đệ quy (dòng 8). Chỉ đọc được nếu hàm trả
  **true khi X/Y không đóng**.
- Phần chữ ngay dưới: hàm "returns true only when there is no existing CFI Z … such that
  Z is a superset of Y …" tức trả **true khi Y đóng**. Câu này còn viết "the count of Y is
  equal to or greater than the count of Z", bị ngược: tập cha Z không thể có count lớn
  hơn Y, nên điều kiện thực chất là bằng nhau. (Câu trước đó của bài báo viết đúng:
  "check if its count is equal to or greater than c", so count của nút với count của Y.)
- `maximality_checking` ở Sec 3.2 (tr. 1352) trả true khi itemset *là tập con* của một MFI
  đã có, và FPmax* (Fig. 5, dòng 10) dùng `if not maximality_checking`.

**Code.** Theo Fig. 8 và Sec 3.2: `closed_checking(C, items, count)` trả **true khi đã có
CFI Z ⊇ Y với count(Z) = count(Y), tức Y không đóng**. Mọi chỗ gọi viết đúng như mã giả
(`if !check!(…)`, [fpclose.jl](../src/algorithm/fpclose.jl)).

**Ảnh hưởng.** Không. Đây chỉ là quy ước cực tính của một hàm nội bộ; mọi chỗ gọi đã đổi
theo và test so với vét cạn vẫn pass.

## 2. Nhánh đơn (dòng 1–5): thêm tiền tố đầy đủ i1..ip

**Bài báo (tr. 1354).** Với nhánh (i1:c1, …, ip:cp): "Starting from i1, comparing the counts
of every two adjacent items ij : cj and ij+1 : cj+1 … if cj ≠ cj+1, we list i1, i2, …, ij as a
candidate closed frequent itemset with count cj."

**Vấn đề.** Đọc đúng chữ thì chỉ có cặp liền kề (j = 1..p−1) mới được xét, nên tiền tố đầy đủ
i1..ip (ứng viên cuối, count cp) không bao giờ được liệt kê. Ví dụ CSDL `{1 2}, {1 2}`,
minsup 1: nhánh 1:2 → 2:2 không có cặp nào khác count, nhưng {1,2} (support 2) là tập đóng.

**Code.** Thêm điều kiện `j == p` ([fpclose.jl](../src/algorithm/fpclose.jl), nhánh đơn):
ứng viên là X ∪ {i1..ij} khi `j == p` hoặc `cj ≠ cj+1`. Tương đương coi c_{p+1} = 0.

**Ảnh hưởng.** Có: thiếu điều kiện này thì mất CFI. Test `[[1,2],[1,2],[1,2]] → {1 2}:3` và
các test so với vét cạn bao phủ trường hợp này.

## 3. Ghi chính X = T.base ở cuối mỗi lời gọi

**Bài báo.** Fig. 8 chỉ chèn CFI ở dòng 5 (nhánh đơn). Với T nhiều nhánh (dòng 6–17) thì
Y = T.base ∪ {i} không bao giờ được chèn trực tiếp. Khi T_Y là nhánh đơn, danh sách ứng viên
(mục 2) bắt đầu từ tiền tố i1 nên không có ứng viên "tiền tố rỗng", tức chính Y.

**Code.** Cuối `fpclose!`: nếu `T.base` khác rỗng và `!closed_checking(C, [], T.base_count)`
thì ghi X ([fpclose.jl](../src/algorithm/fpclose.jl), cuối hàm). Gặp khi:
- T_Y nhiều nhánh;
- T_Y rỗng (Y không có item mở rộng phổ biến);
- T_Y nhánh đơn nhưng c1 < count(Y). Ví dụ: Fig. 1 với header của bài báo (b a d g f e c), {a}
  có support 5, pattern base của a chỉ có b:3, nên T_{a} là nhánh đơn b:3 với 3 < 5. Tập đóng {a}:5
  chỉ được ghi nhờ bước này.

Vì sao điều kiện kiểm là count của gốc C_X (mục 6): X đóng khi không có CFI nào chứa X với
cùng count. Cha chứa item của T đã được tìm trong lời gọi này và chèn vào C; cha chứa item
ngoài T hoặc đã bị dòng 8 ở lời gọi cha loại, hoặc không phổ biến (support bằng X thì cũng
phổ biến).

**Ảnh hưởng và số đo.** Bắt buộc. Test đột biến [test/mutation_record_x.jl](../test/mutation_record_x.jl)
sao chép `src/`, tắt bước này ở bản sao, rồi so với vét cạn trên 13.741 ca (4000 CSDL ngẫu nhiên,
2–11 item, ≤ 40 giao dịch, mật độ từ thưa đến dày, nhiều mức minsup, seed cố định):

> **Bỏ bước ghi X: 10.559 / 13.741 ca sai** (chạy `julia --project test/mutation_record_x.jl`).

Script không sửa `src/`.

**Bonus: dòng 8 chỉ là tối ưu.** Tắt cắt nhánh dòng 8 (`fpclose(db, m; prune_line8 = false)`)
cho kết quả y hệt: đo 0/13.741 ca sai trên đúng tập CSDL ngẫu nhiên của mục này (chạy một
lần bằng script tạm ngoài repo; cả hai chế độ đều 0 sai); test cố định trong repo kiểm 200
CSDL ngẫu nhiên và ví dụ 5 giao dịch. Lý do: bước ghi X ở trên đã bảo đảm
tính đóng, dòng 8 chỉ tránh đệ quy vô ích. Số đo bộ đếm (`FPCloseStats`) trên 3 ví dụ nhỏ:

| CSDL | Lời gọi `fpclose!` có cắt / tắt cắt | Lần cắt dòng 8 | Số lần `closed_checking` có cắt / tắt cắt | Số CFI |
|---|---|---|---|---|
| 5 giao dịch, minsup 2 | 7 / 8 | 1 (Y = {3,5}) | 16 / 10 | 7 |
| Pasquier99, minsup 40% | 4 / 5 | 1 | 12 / 9 | 5 |
| Fig. 1, minsup 20% | 13 / 13 | 0 | 29 / 17 | 14 |

Nhận xét: trên ví dụ nhỏ, cắt tiết kiệm tối đa 1 lời gọi nhưng thêm vài lần `closed_checking`;
lợi ích thật chỉ đo được trên dữ liệu lớn (Chương 2), không suy ra từ bảng này.

## 4. Dòng 17 thay bằng chèn vào mọi CFI-tree trên đường đệ quy

**Bài báo (tr. 1354).** "Note that line 17 is not implemented as such. As in algorithm
FPmax*, we found it more efficient to do the insertion of lines 3-5 into all CFI-trees
currently in memory." Cách làm cho FPmax* ở Sec 3.2 (tr. 1352–1353): chèn "into all
preceding MFI-trees that the implementation of the recursion needs to store in memory in
any case"; với cây của Y_k chèn B ∪ (Y_j − Y_k).

**Code.** `record!` chèn mỗi CFI mới vào mọi cây trong `stack` (đường đệ quy hiện tại), mỗi
cây nhận phần tương đối của CFI ([fpclose.jl](../src/algorithm/fpclose.jl)).

**Ảnh hưởng.** Không: đây đúng là cách bài báo nói cài thật. Tính hợp lệ: base của cây trong
cùng chứa base của mọi cây trên stack nên CFI vừa tìm luôn chứa base đó.

## 5. Thứ tự duyệt header: item ít phổ biến nhất trước

**Bài báo.** Fig. 8 dòng 6 chỉ viết "for each i in T.header", không nêu thứ tự. Thứ tự
nằm ở Sec 3.2 (tr. 1352, cho FPmax*): "The items in the header table of T are processed in
increasing order of frequency, so that maximal frequent itemsets will be found before any of
their frequent subsets"; và Sec 4.1 (tr. 1355): "Starting from i_k, for each item in the
header table …". Sec 4 (tr. 1353) nói FPclose "works similarly to FPmax*".

**Code.** `for i in reverse(T.items)`: item cuối header (ít phổ biến nhất) trước.

**Ảnh hưởng.** Có, đây là điều kiện đúng đắn: pattern base của i chỉ chứa item xếp trước i, nên
tập tìm sau luôn là tập con của CFI tìm trước, đúng điều `closed_checking` cần. Đảo thứ tự thì
sai.

## 6. C_X chỉ lưu item thuộc header của T_X; gốc giữ count lớn nhất; C_Y đọc lại từ C_X

**Bài báo.** Sec 4.1 (tr. 1353): "The CFI-tree C_X always stores all already found CFIs
containing itemset X and their counts"; header cùng thứ tự với header của FP-tree tương ứng.
Khởi tạo (Sec 3.2, tr. 1353): đi theo node-link của i_j, "extracting the maximal frequent
itemsets containing i_j", sắp theo header của cây mới rồi chèn. Bài báo không mô tả gốc cây
hay cách kiểm tra chính X.

**Code.**
- Mỗi CFI S ⊇ X được lưu dưới dạng phần tương đối: chỉ giữ item có trong header của C_X
  (xem `relative_items`), nên không chứa X.
- Gốc C_X giữ **count lớn nhất** trong mọi CFI đã chèn; trả lời "X có tập cha cùng count
  không?" (ứng viên rỗng).
- `init_cfitree` không giữ danh sách CFI rời mà đọc lại từ cây C_X: với mỗi nút n của i,
  duyệt cây con của n và chèn (đường đi bỏ i, count của nút) khi nút có count lớn hơn mọi con.

**Vì sao không làm sai phép kiểm tra đóng.**
1. Phép kiểm cần trả lời "∃ CFI Z ⊇ Y với count(Z) = count(Y)". Với mọi Z ⊇ Y thì
   count(Z) ≤ count(Y), nên có thể hỏi "count(Z) ≥ count(Y)" mà không đổi đáp án.
2. Ứng viên Y ở C_X chỉ gồm X và item trong header của T_X, nên Z ⊇ Y chỉ phụ thuộc phần
   giao của Z với header; bỏ item ngoài header không đổi đáp án. Item ngoài header là item
   không phổ biến trong pattern base của X (nếu Z chứa nó mà cùng count với Y thì
   X ∪ {item} cũng có support ≥ minsup, nên nó không thể bị loại vì tần suất), hoặc item
   đã xử lý ở nhánh trước và bị dòng 8 loại.
3. Giữ count lớn nhất tại nút là đủ: cặp (tập, count) bị cặp khác có tập chứa nó và count
   không nhỏ hơn "trội" thì bỏ đi không đổi câu trả lời. Một CFI kết thúc đúng tại nút có
   count lớn hơn mọi con (nếu có con cùng count thì tập con dài hơn là CFI cha cùng support,
   mâu thuẫn). Vì vậy `init_cfitree` chỉ cần chèn các nút như thế và không mất thông tin;
   `cfi_list` ([cfitree.jl](../src/algorithm/cfitree.jl)) dùng chính tính chất này để
   liệt kê CFI trong cây.

**Đối chiếu Fig. 7b.** (Các test này chạy với `reduced_cfitree = false`, vì CFI-tree rút gọn của mục 8
không còn chứa đủ mọi CFI.) Test "Fig. 1: C_∅ chứa đúng 14 CFI" kiểm C_∅ chứa đúng 14 CFI trùng
kết quả. Test "nhãn item:level:count khớp Fig. 7b" đánh số lại item để tie-break cho ra đúng
thứ tự header của bài báo (b a d g f e c), rồi so tập 14 nhãn `item:level:count` của cây với
14 nhãn đọc được ở Fig. 7b: khớp hoàn toàn (4 nút mức 1, 8 nút mức 2, 2 nút mức 3). Chú ý:
tr. 1355 viết cây đầy đủ ở Fig. 7b có "15 nodes"; cây dựng được và các nhãn đọc ở hình đều
là 14 nút, nên 15 có thể tính cả nút gốc. Chưa thể xác nhận từ văn bản bài báo.

**Ảnh hưởng.** Không (so với vét cạn trên 13.741 ca: 0 sai). Đây là chỗ khác về cách cài,
không khác về kết quả.

## 7. Phá hòa khi bằng count: item số nhỏ trước

**Bài báo.** Header xếp theo count giảm dần (Sec 2.1, tr. 1348; Fig. 8 dòng 13 "sort tail in
decreasing order of items' counts"); không quy định khi bằng count.

**Code.** Khóa sắp `(-count, item)` ([structures.jl](../src/structures.jl), `FPTree`): khi bằng count thì item số nhỏ trước, để kết
quả ổn định giữa các lần chạy.

**Ảnh hưởng.** Không về tính đúng: thuật toán chỉ cần một thứ tự toàn phần cố định trên mỗi
cây, và C_Y dùng đúng thứ tự của T_Y. Có thể ảnh hưởng hình dạng cây và tốc độ. Fig. 1 của
bài báo dùng thứ tự b a d g f e c, nên test đối chiếu đánh số lại item để ép ra thứ tự đó.

## 8. CFI-tree rút gọn (Sec 3.3 tr. 1353, cuối Sec 4.1 tr. 1355, Fig. 9)

**Bài báo.** Sec 3.3 (cho FPmax*): với MFI X ∪ {jk} ∪ Z tìm được khi đệ quy với jk, thay vì chèn nhánh
{jk} ∪ Z vào cây của X thì chỉ chèn Z, vì "none of the candidate MFIs X ∪ Z' generated from the rest
of the current call contain jk". Cuối Sec 4.1 áp dụng cho CFI-tree ("by inserting only part of the CFI
into CFI-trees, less memory is used and the implementation is faster"), Fig. 9 vẽ cây C_∅ của CSDL
Fig. 1 chỉ còn 6 nút thay cho 15 nút của Fig. 7b.

**Code** (`record!` và `fpclose!` trong [fpclose.jl](../src/algorithm/fpclose.jl), trường `child_item` của
`CFITree`; tùy chọn `reduced_cfitree`, mặc định `true`, để khớp cách tác giả chạy thực nghiệm):
- Khi `fpclose!` mở rộng cây C của X xuống C_Y bằng item i, nó ghi `C.child_item = i` (và đặt lại 0 khi
  đệ quy xong).
- `record!` chèn CFI vào mọi cây trên stack như cũ, nhưng với mỗi cây còn bỏ thêm `child_item` của nó: cây
  ở tầng k nhận (Y_j − Y_{k+1}) ∪ B thay vì (Y_j − Y_k) ∪ B. Count của gốc vẫn được cập nhật bằng max kể cả khi
  phần chèn vào rỗng (nên phép kiểm tra chính X vẫn đúng).
- `reduced_cfitree = false` giữ cách cũ (cây đầy đủ).

**Vì sao không làm sai phép kiểm tra đóng.** Header được duyệt từ item ít phổ biến nhất lên, nên khi item i
đã mở rộng xong thì mọi truy vấn còn lại của lời gọi ở tầng đó (`[i']` của dòng 8 với i' xếp trước i, tiền tố
`T.items[1:m]` của kết thúc sớm, và chính X) đều không chứa i. Bỏ i khỏi các tập lưu trong C chỉ làm các tập đó
nhỏ lại ở phần không bao giờ bị hỏi. `init_cfitree` dựng C_Y từ C: header của C_Y chỉ gồm item xếp trước i,
nên `relative_items` cũng đã bỏ i. Cắt tỉa theo "trội" ở `collect_paths!` vẫn đúng với tập rút gọn (một cặp
bị cặp khác có tập chứa nó và count không nhỏ hơn trội thì bỏ không đổi đáp án).

**Chỗ khác bài báo.**
1. *Count trên nút khác Fig. 9.* Với CSDL Fig. 1 ở 20%, C_∅ rút gọn có đúng **5 nút + gốc = 6 nút** (cây đầy đủ
   có 14 nút + gốc = 15; vậy "6" và "15" của bài báo đếm cả gốc), cùng hình dạng với Fig. 9 (gốc có ba con d, a, b;
   b có hai con a, d) và cùng nhãn item:level (d:1, a:1, b:1, a:2, d:2). Nhưng count trên nút của code là
   d:1:3, a:1:3, b:1:3, a:2:2, d:2:2 (count lớn nhất của các tập đã chèn, đã bỏ item mở rộng; ví dụ
   {a,b,f}:2 chèn thành {b,a}:2, {b,g}:3 thành {b}:3), còn Fig. 9 ghi d:1:5, a:1:5, b:1:5, a:2:3, d:2:3. Năm
   nhãn của Fig. 9 trùng đúng nhãn của Fig. 7b nên có vẻ hình được cắt từ Fig. 7b, không tính lại count.
   (Cần xác nhận: nếu bài báo thật sự lưu count 5/3 như hình thì cách đó khác code; code không thể làm vậy,
   vì nút b:1:5 sẽ khẳng định có tập {b} count 5 trong C_∅ trong khi tập đó chưa hề được chèn.)
2. *C_∅ không còn chứa đủ mọi CFI.* Kết quả lấy từ danh sách `results`, không đọc lại từ cây; các test so C_∅
   với Fig. 7b chạy với `reduced_cfitree = false`. `cfi_list` trên cây rút gọn trả các tập đã bỏ bớt item.
3. *Bài báo không nêu* cách khởi tạo cây rút gọn của Y từ cây cha; code dùng lại `init_cfitree` như cây đầy đủ
   (đúng nhờ lập luận ở trên).

**Ảnh hưởng và số đo.** Không đổi tập CFI: 48 tổ hợp tùy chọn (gồm `reduced_cfitree` bật/tắt) so với bản cơ bản và
vét cạn trên CSDL toy, CSDL vừa và 150 CSDL ngẫu nhiên. Kiểm test bắt được lỗi: tạm bỏ thêm một item nữa khi chèn làm
1.085 test fail; tạm bỏ việc cập nhật count gốc khi phần chèn rỗng làm 1.081 test fail. Số đo ở mục 15: tổng số nút
CFI-tree giảm 29% (CSDL thưa) và 55% (CSDL dày), số nút của C_∅ giảm 55% và 67%.

**Ghi chú về SPMF.** Theo tài liệu SPMF mà nhóm đã đọc, FPClose của SPMF không cài FP-array
và CFI-tree cục bộ. Repo này chưa tự kiểm chứng điều đó; khi so sánh hiệu năng với SPMF ở
Chương 2 cần nhớ rằng hai cài đặt có thể khác nhau về cấu trúc, không chỉ về ngôn ngữ.

## 9. Các bổ sung nhỏ

- **Không xuất tập rỗng.** Bài báo không nói. Nếu không item nào có mặt ở mọi giao dịch thì ∅
  về lý thuyết là tập đóng; code không xuất nó. Đã đối chiếu SPMF trên CSDL `{1}`, `{2}` (∅ có support 2 và là tập đóng), minsup 50%: SPMF cũng chỉ xuất `{1}` và `{2}`, không xuất ∅ (`scripts/compare_spmf.jl`: khớp); `fpclose!` chỉ ghi X
  khi `T.base` khác rỗng.
  Ảnh hưởng: chỉ ở tập rỗng.
- **Item trùng trong giao dịch.** `build_fptree` bỏ item trùng (một giao dịch là một tập, Sec 1,
  tr. 1347). Không bỏ thì đếm hai lần và `insert_path!` chèn một item hai lần trên một đường.
  `read_spmf` cũng bỏ item trùng. Ảnh hưởng: chỉ với CSDL có item trùng.
- **Làm tròn minsup.** Bài báo dùng tỉ lệ phần trăm (Sec 1, tr. 1347); code đổi sang số giao dịch
  bằng `ceil(minsup × n)`, tối thiểu 1, không dung sai (ví dụ `0.07 × 100 = 7.000000000000001`
  cho 8). Cách làm tròn nằm ở một chỗ duy nhất, hằng `MINSUP_ROUNDING` ([utils.jl](../src/utils.jl)).
  **Đã đối chiếu với SPMF** bằng `data/toy/rounding_test.txt` (7 dòng `1 2`, 8 dòng `2 3`,
  85 dòng `2`):
  ```
  java -jar tools/spmf.jar run FPClose data/toy/rounding_test.txt out/spmf_rounding.txt 7%
  ```
  SPMF xuất đúng hai itemset `2 #SUP: 100` và `2 3 #SUP: 8`, **không có** `1 2 #SUP: 7`: SPMF cũng
  dùng ceil thuần (0.07 × 100 = 7.000000000000001 → ngưỡng 8), nên giữ nguyên `MINSUP_ROUNDING`.
  Test `SPMF: làm tròn minsup` ([test_optimizations.jl](../test/test_optimizations.jl)) kiểm bản
  của nhóm cho đúng hai itemset đó; `scripts/compare_spmf.jl data/toy/rounding_test.txt 7%`
  báo khớp hoàn toàn. Hai chi tiết về định dạng output của SPMF khi đối chiếu: file có các dòng
  metadata bắt đầu bằng `@` (`@FILETYPE=...`, `@SOURCE=...`), và các item trong một itemset
  không được sắp tăng dần; `compare_spmf.jl` chuẩn hóa cả hai trước khi so. Ảnh hưởng: ở các
  ngưỡng mà `minsup × n` rơi sát số nguyên.
- **T_Y rỗng vẫn gọi đệ quy.** Fig. 8 không có điều kiện "T_Y ≠ ∅" (khác FPgrowth*, Fig. 3 dòng
  10). Code gọi luôn; T_Y rỗng coi như nhánh đơn rỗng, rồi bước ghi X ở mục 3 xử lý Y.
- **CLI.** `--minsup` chỉ nhận tỉ lệ (`0.4`) hoặc phần trăm (`40%`) như SPMF; `--minsup-count`
  nhận số giao dịch. Không thuộc bài báo.

## 10. FP-array (Sec 2.2–2.3, tr. 1350–1351)

**Bài báo.** FP-array A_X là ma trận đếm cặp item của T_X, điền song song khi dựng T_X; hàng của
item i cho tail (item phổ biến trong pattern base của i) mà không phải duyệt T_X
(Fig. 3 dòng 6–9, Fig. 8 dòng 9–10 và 14). Heuristic tr. 1351: đếm số nút từng mức khi dựng
cây; "if the upper quarter of the tree contains less than 15 percent of the total number of
nodes" thì coi là dày và không tính FP-array cho tầng sau, nếu thưa thì không tính ô của
15 item đầu header.

**Code** ([fparray.jl](../src/algorithm/fparray.jl), `conditional_tree`/`build_fptree` trong
[fptree.jl](../src/algorithm/fptree.jl)):
- Chỉ lưu nửa tam giác dưới (đúng như bài báo, tr. 1350), xếp phẳng, `Int32`: ô (r, c) với hạng
  r > c ở `tri_index(r, c)`. Hàng r gồm đúng các item xếp trước item hạng r, tức đúng tập item có
  thể nằm trong pattern base của nó, nên hàng r thay thế hoàn toàn lần duyệt đầu của T_X.
- Khi chèn một đường vào T_Y (mỗi nút của `item` trên node-link, trọng số = count của nút), cộng count đó
  vào mọi cặp trong đường (`accumulate_pairs!`, có `@inbounds`), không cộng 1.
- `conditional_tree` không còn dựng sẵn pattern base trong bộ nhớ mà đi theo node-link của `item` trực tiếp
  với một buffer dùng lại: có hàng FP-array thì đi **1 lần** (chỉ để chèn), không có thì đi **2 lần** (đếm rồi
  chèn). Bộ đếm `FPCloseStats.tree_traversals` ghi số lần đó; test kiểm chặt tắt FP-array thì
  `tree_traversals == 2·(calls−1)`, bật thì trừ thêm `fparray_hits`.
- Hàng của `skip_items` = 15 item đầu header không tính (`has_row` sai cho chúng, tail của chúng
  đếm bằng cách duyệt như thường). Không cấp phát FP-array khi cây có ≤ 15 item.
- `is_dense`: đếm số nút từng mức (`levels`), "1/4 trên" = `cld(D, 4)` mức đầu, D là số mức; dày khi
  số nút ở đó < 15% tổng. Hai ngưỡng (0.15 và 15) là tham số của `FPArrayConfig`.
- Tắt/bật bằng `fpclose(...; fparray = false)`.

**Chỗ code tự quyết định (bài báo chưa nói đủ).**
1. *Thời điểm quyết định.* Dòng 9 của Fig. 3 đếm nút theo mức trong lúc dựng T_Y để "estimate
   whether we shall really calculate the FP-array", nhưng A_Y phải được cộng dồn ngay trong lúc dựng,
   khi độ dày của T_Y chưa biết. Code theo câu ở tr. 1351 ("do not calculate the FP-array for the next
   level of the FP-tree"): A_Y được điền khi **cây cha T không dày** (`t.dense`), còn độ dày của chính T_Y
   được đo trong lúc dựng và lưu lại để quyết định cho các cây con của nó.
2. *T_∅ không có cây cha.* `build_fptree` quét CSDL đúng 2 lần như bài báo: nếu kích thước hợp lệ
   (`skip_items < m ≤ max_items`) thì cấp phát A_∅ trước lần quét 2 và đếm cặp ngay khi chèn từng giao dịch;
   sau lần quét 2 mới đo độ dày của T_∅, nếu dày thì bỏ mảng. Hệ quả: với dữ liệu dày, A_∅ vẫn bị cấp phát
   (tối đa khoảng 50 MB cho `max_items = 5000`) và đếm rồi bỏ đi, tốn thêm thời gian cộng cặp.
3. *"Upper quarter".* Bài báo không định nghĩa chính xác; code dùng `cld(D, 4)` mức đầu.
4. *Giới hạn kích thước.* Bài báo (tr. 1350) nói nên bỏ kỹ thuật khi n(n−1)/2 quá lớn nhưng không nêu
   ngưỡng; code đặt `max_items = 5000` (≈ 50 MB cho `Int32`). Không dùng phương án "tập ứng viên
   2-itemset nhỏ hơn" ở [25] mà bài báo nhắc.

**Ảnh hưởng kết quả.** Không. Kiểm tra: (a) mỗi hàng FP-array bằng đúng count đếm từ pattern base,
trên 40 CSDL ngẫu nhiên, mọi item, cả T_∅ lẫn các cây con; (b) các ô của A_∅ trên CSDL Fig. 1 khớp số đếm tính tay từ 7 giao dịch (chưa đối chiếu trực tiếp với hình Fig. 2a);
(c) mọi tổ hợp công tắc (nay gồm cả `exact_count` và `reduced_cfitree`) bằng bản cơ bản trên mọi file `data/toy`, một CSDL ngẫu nhiên vừa (600 giao dịch,
60 item) và 150 CSDL nhỏ so với vét cạn, với cả hai cấu hình (`skip_items = 0, dense_ratio = 0` để FP-array
luôn chạy, và mặc định 15/0.15). Test đột biến tạm thời (cộng 1 thay vì `count` vào ô) làm 341 test fail.
Cài đặt mặc định có `skip_items = 15` nên CSDL ≤ 15 item không bao giờ dùng FP-array; vì vậy test ép
`skip_items = 0`.

## 11. Kết thúc sớm (Sec 4.1, tr. 1355)

**Bài báo.** "Suppose an FP-tree for itemset Y has multiple branches, the count of Y is c and the order of
items in its header table is i1, ..., ik. Starting from ik, for each item in the header table, we may need
to do the work from line 7 to line 17. If for any item, say im, where m ≤ k, Y ∪ {i1, ..., im} is a closed
itemset with count c, FPclose can terminate the current call. This is because closed_checking would always
return true for the remaining items."

**Code** (vòng lặp dòng 6 của `fpclose!`): Y của bài báo là `T.base`. Gọi m0 là số item đầu header có
count bằng `T.base_count` (header giảm dần theo count nên đó là một tiền tố). Với mỗi m ≤ m0 (duyệt từ
cuối về), nếu `closed_checking(C, [i1..im], T.base_count)` là true thì thoát vòng lặp. Sau đó bước ghi X
(mục 3) vẫn chạy như thường. Tắt/bật bằng `early_termination`.

**Chỗ diễn giải.** Bài báo nói "Y ∪ {i1..im} là tập đóng với count c". Code kiểm tra "trong C đã có CFI
⊇ X ∪ {i1..im} với count c", gồm cả trường hợp nó là tập con cùng count của một CFI đã ghi. Cả hai đều
đủ để dòng 8 loại mọi item còn lại (mỗi item ij, j ≤ m, có support đúng bằng c vì c = count(Z) ≤
count(X ∪ {ij}) ≤ c, và Z ⊇ X ∪ {ij}). Một hệ quả: mọi CFI chứa X với count c đều chứa closure(X) ⊇
X ∪ {i1..im0}, nên kiểm tiền tố [i1..im] cho cùng đáp án với chỉ kiểm [i1] (thử đổi code sang kiểm
[i1]: toàn bộ test vẫn pass). Code giữ dạng tiền tố cho đúng bài báo.

**Ảnh hưởng kết quả.** Không. Kiểm tra bằng cùng các test ở mục 10 (mọi tổ hợp công tắc, so với bản cơ bản và
vét cạn) và một ví dụ dựng sẵn thực sự kích hoạt kết thúc sớm (`early_stops ≥ 1`). Đột biến tạm thời (kiểm
với count − 1) làm 132 test fail.

## 12. Số đo các tối ưu trên CSDL tổng hợp (đo lại)

Số đo cũ của mục này (trước các lần sửa FP-array, bỏ cấp phát thừa, `exact_count`, CFI-tree rút gọn) đã lỗi
thời nên được thay bằng số đo mới. Chạy: `julia --project scripts/benchmark.jl --synthetic --minsups 0.05,0.02,0.01 --reps 3 --combos all`
(CSV: `out/benchmark_synthetic_v2.csv`, không commit). CSDL: 20.000 giao dịch, 200 item, 40 pattern cài sẵn
kiểu IBM Quest, độ dài trung bình 14,1, seed 2026. Thời gian = nhỏ nhất của 3 lần, mỗi cấu hình một tiến trình
Julia riêng có warm-up. "L8" = cắt dòng 8, "FA" = FP-array, "ET" = kết thúc sớm. `exact_count` và
`reduced_cfitree` ở giá trị mặc định (bật) trong mọi ô. Số itemset giống nhau ở mọi tổ hợp (4.988 / 25.658 / 417.016).

| minsup | Cơ bản (L8) | L8 + FA | L8 + ET | L8 + FA + ET | Không L8 |
|---|---|---|---|---|---|
| 5% (1000) | 0,174 s / 126 MB | 0,157 s / 126 MB | 0,186 s / 126 MB | 0,136 s / 126 MB | 0,147 s / 126 MB |
| 2% (400) | 0,430 s / 305 MB | 0,389 s / 307 MB | 0,397 s / 305 MB | 0,387 s / 307 MB | 0,400 s / 304 MB |
| 1% (200) | 7,160 s / 4500 MB | 6,854 s / 4527 MB | 5,257 s / 4500 MB | 7,016 s / 4528 MB | 6,913 s / 4486 MB |

Mỗi ô: thời gian / tổng byte cấp phát. RSS đỉnh của tiến trình ở 1%: 1418–1515 MB.

**Nhận xét (chỉ về CSDL này).** 
- Cấp phát giảm mạnh so với số đo cũ của mục này (cấu hình cơ bản: 5% 182 → 126 MB, 2% 467 → 305 MB, 1% 7.835 → 4.500 MB,
  tức −31% đến −43%). Đây là tác dụng gộp của các thay đổi từ lần đo cũ (bỏ pattern base dựng sẵn, bỏ cấp phát thừa trong
  CFI-tree, CFI-tree rút gọn), không tách riêng từng thay đổi ở bảng này (mục 15 tách riêng hai việc sau).
- FP-array không còn tốn thêm bộ nhớ cấp phát đáng kể: +0 đến +2 MB ở 5% và 2%, +27 MB (+0,6%) ở 1% (trước đây +33 đến
  +70 MB), vì pattern base không còn được dựng sẵn.
- Thời gian giữa các tổ hợp vẫn nằm trong nhiễu đo: cùng một mã cho các ô ở 1% từ 4,8 đến 7,2 s không theo quy luật (ví dụ
  "không L8 + FA" 4,778 s nhưng "không L8 + FA + ET" 7,031 s), nên không kết luận được tối ưu nào nhanh hơn. Thời gian cơ bản
  ở 1% là 7,16 s so với 7,84 s trước đây, cũng chưa phân biệt được với nhiễu.
- Số lần cắt dòng 8 và kết thúc sớm không đổi so với số đo cũ (ở 1%: 2.347 lần kết thúc sớm thay phần lớn 2.360 lần cắt dòng 8;
  ở 5% và 2% cả hai bằng 0, tức hai kỹ thuật không có việc làm). Kết luận về lợi ích thật cần dữ liệu benchmark thật (Chương 2).

## 13. Recovery và luật kết hợp: phần nhóm bổ sung, không thuộc bài báo

([recovery.jl](../src/recovery.jl), [rules.jl](../src/rules.jl); không sửa `fpclose.jl`, `cfitree.jl`,
`fptree.jl`, `fparray.jl`.)

**Vì sao cần.** Đề yêu cầu Chương 1 "xuất ra tất cả frequent itemset và support tương ứng", còn FPClose
chỉ xuất closed frequent itemset (CFI). Bài báo (Sec 1, tr. 1347) nhận xét tập đóng giữ đủ thông tin để sinh
luật kết hợp ("Any frequent itemset has the support of its smallest closed superset") nhưng không mô tả cách
khôi phục. Luật kết hợp (Chương 3, phân tích giỏ hàng) cần support của vế trái và vế phải, vốn thường không
phải tập đóng. Nên nhóm thêm hai module tách khỏi phần lõi.

**Cơ sở lý thuyết** (chứng minh ngắn nằm trong docstring của `recover_all_frequent`). (a) Mọi FI là tập con
của ít nhất một CFI (đó là closure cl(X), cùng support với X) và mọi tập con khác rỗng của CFI đều phổ biến.
(b) sup(X) = max{sup(C) : C là CFI chứa X}, đạt tại C = cl(X).

**Thuật toán và một chỗ khác với đặc tả ban đầu.** Sắp CFI theo support giảm dần; với mỗi CFI duyệt các tập con
và gán support cho tập con chưa có trong bảng, không bao giờ ghi đè. Vì xử lý theo support giảm dần nên giá
trị gán lần đầu chính là max. Cắt nhánh "gặp tập con đã có thì bỏ cả nhánh dưới nó" chỉ đúng khi duyệt
**xuống** mạng con (mỗi bước bỏ một item): khi đó mọi tập con của S cũng là tập con của CFI đã gán S, nên
đã có trong bảng. Nếu duyệt theo kiểu "thêm item theo thứ tự tăng dần" thì cắt nhánh là SAI (ví dụ CFI
{1,2,3} sau {1,2,4}: gặp {1,2} đã có nhưng {1,2,3} chưa có), nên code duyệt xuống. Số lần gọi duyệt bị
chặn bởi tổng độ dài các FI cộng số CFI (test kiểm chặn này).

**Luật.** `generate_rules` nhận MỌI frequent itemset (kết quả recovery), sinh X → Y với X, Y khác rỗng, rời
nhau, X ∪ Y phổ biến: support = sup(X ∪ Y)/N, confidence = sup(X ∪ Y)/sup(X), lift = confidence/(sup(Y)/N).
Lọc `confidence ≥ minconf` bằng phép chia số nguyên rồi so với `minconf`, nên 3/5 so với ngưỡng thập phân
0.6 cho kết quả đúng (test kiểm biên này). Xếp hạng theo lift giảm dần, bằng lift thì confidence, rồi
support, rồi từ điển. Truyền nhầm tập đóng thay cho mọi FI thì báo `ArgumentError` thay vì sinh luật sai.

**Chi phí.** Số FI có thể lớn hơn số CFI theo cấp số mũ (CFI độ dài ℓ sinh tới 2^ℓ − 1 tập con), số luật còn
lớn hơn nữa. `recover_all_frequent(...; limit = n)` ném `RecoveryLimitExceeded` khi vượt `n`; benchmark dùng nó
(`--max-fi`). Trên CSDL tổng hợp của mục 12 ở minsup 1%: 417.016 CFI → 471.280 FI, recovery mất 1,9 s so
với 11,3 s mining. Ở 5% và 2% số FI bằng số CFI (4.988 và 25.658) vì không có tập con nào không đóng.

**Cách kiểm chứng.**
- So tuyệt đối với bộ vét cạn `brute_force_frequent` (liệt kê 2^k tập con) trên Fig. 1 (20% ra đúng 19 FI,
  trong khi chỉ có 14 CFI), bài tập 5 giao dịch (12 FI), `pasquier99` (15 FI), `rounding_test`, và 300 CSDL ngẫu
  nhiên seed cố định. Luật: tính tay trên bài 5 giao dịch, so với bộ sinh luật độc lập (đếm support thẳng
  trên CSDL) trên 60 CSDL ngẫu nhiên, kiểm không luật nào vi phạm minconf, top-k đúng thứ tự lift.
- Tự kiểm test bắt được lỗi (tạm sửa `recovery.jl` rồi khôi phục): sắp support tăng thay vì giảm (max → min)
  làm 5304 test fail; ghi đè bằng support của CFI sau làm 5307 test fail; bỏ cắt nhánh (vẫn đúng kết quả
  nhưng thăm lại tập con) làm 3 test fail, nhờ test chặn số lần duyệt.
- So với SPMF (`scripts/compare_spmf.jl`): chế độ closed với SPMF `FPClose`, chế độ all với SPMF
  `FPGrowth_itemsets`. Trên `data/toy/*.txt` ở 60%, 40%, 20%, 7%, và ba CSDL bổ sung (Fig. 1, bài 5 giao dịch,
  một CSDL ngẫu nhiên 200 giao dịch seed 2026) ở 60%, 40%, 20%, 10%, 2%: khớp 100% cả closed lẫn all-FI.
  Số liệu trong `out/compare_table.csv` và `out/compare_table_extra.csv` (không commit; chạy lại bằng
  `--table`).

## 14. `closed_checking` lọc count bằng `==` (`exact_count`): khác bài báo

**Bài báo (Sec 4.1, tr. 1354).** Với mỗi nút trên node-link của item cuối, "we first check if its count is equal to
or greater than c".

**Code** (`closed_checking` trong [cfitree.jl](../src/algorithm/cfitree.jl); tùy chọn `exact_count`, mặc định
`true`): chỉ xét nút có count **đúng bằng** `count` (và với truy vấn chính X thì `C.root.count == count`).
`exact_count = false` giữ cách của bài báo (`>=`).

**Lý do.** Count của nút là count lớn nhất trong các CFI đi qua nút. Nếu đường từ gốc tới nút chứa itemset Y thì
mọi CFI đi qua nút đều là tập cha của Y nên count ≤ count(Y); vậy nút khớp chỉ có thể có count == count(Y), còn nút
có count > count(Y) chắc chắn không khớp và được loại ngay thay vì đi ngược lên kiểm tra tập con. Kết quả không đổi.
Thêm bộ đếm `FPCloseStats.subset_tests` (số nút vượt bộ lọc count và level, phải kiểm tra tập con).

**Số đo: trên FPClose thật, lợi ích bằng 0, và lý do.** `subset_tests` bằng nhau giữa `==` và `>=` trên mọi CSDL
đã thử (CSDL thưa 0/0, CSDL dày nhỏ 29/29, và năm CSDL ngẫu nhiên khác đều 0/0). Nguyên nhân: mọi lần gọi
`closed_checking` trong FPClose đều hỏi itemset Y = X ∪ items mà item cuối của `items` có count đúng bằng count(Y)
(truy vấn một item `[i]`; tiền tố của kết thúc sớm có mọi item cùng count của X; nhánh đơn thì item thứ j có count cj).
Mà mọi CFI đi qua một nút của item cuối đó chứa X ∪ {item cuối}, nên count của nút ≤ count(X ∪ {item cuối}) = count(Y):
trường hợp "count > count(Y)" mà `==` loại bỏ không bao giờ xảy ra khi chạy thuật toán. Bộ lọc chỉ có tác dụng với
truy vấn tùy ý ngoài FPClose (không nhất quán với dữ liệu). `subset_tests` còn rất nhỏ so với số lần gọi
`closed_checking` (29 so với hàng chục nghìn lần ở CSDL dày nhỏ), tức hầu hết lần kiểm tra bị loại bởi node-link
trống hoặc bộ lọc count/level; nhóm chưa tách riêng các nguyên nhân đó.

**Kiểm tra.** Mọi tổ hợp tùy chọn (gồm `exact_count` bật/tắt) cho cùng kết quả với vét cạn; `subset_tests` khi `==`
không bao giờ nhiều hơn khi `>=`; test đơn vị trên một CFI-tree dựng tay (nút count 5, hỏi count 3) cho thấy `==` loại
nút (0 phép kiểm tra tập con) còn `>=` phải kiểm tra (1 phép).

## 15. Số đo ba cải tiến CFI-tree

CSDL (seed cố định, `julia --project` với tùy chọn mặc định trừ công tắc đang đo): **thưa** = kiểu IBM Quest
20.000 giao dịch, 200 item, minsup 400 (25.658 CFI); **dày nhỏ** = 400 giao dịch, 20 item, mỗi item có mặt với xác
suất 0,55, minsup 12 (44.443 CFI). Cấp phát đo bằng `@allocated` (xác định, đáng tin); thời gian dao động ±20% giữa các
lần chạy cùng một mã trên máy này nên chỉ coi là xu hướng.

| Việc | Đại lượng | CSDL thưa: trước → sau | CSDL dày nhỏ: trước → sau |
|---|---|---|---|
| 1. Bỏ cấp phát thừa (`collect_paths!`, `cfi_list` dùng backtracking) | Byte cấp phát | 372,9 → 320,8 MB (−14,0%) | 463,3 → 371,8 MB (−19,8%) |
| 1. (cùng việc) | Thời gian, min của 7 lần, đo xen kẽ hai bản | 0,352 / 0,498 → 0,345 / 0,533 s | 0,332 / 0,573 → 0,378 / 0,447 s |
| 2. `exact_count` (`>=` → `==`) | `subset_tests` | 0 → 0 | 29 → 29 |
| 2. (cùng việc) | Byte cấp phát | 320,8 → 320,8 MB | 371,8 → 371,8 MB |
| 3. CFI-tree rút gọn | Tổng số nút mọi CFI-tree (`cfi_nodes`) | 130.153 → 92.817 (−28,7%) | 240.344 → 108.786 (−54,7%) |
| 3. (cùng việc) | Số nút C_∅ (`root_cfi_nodes`) | 25.658 → 11.609 (−54,8%) | 44.452 → 14.908 (−66,5%) |
| 3. (cùng việc) | Byte cấp phát | 321,1 → 306,6 MB (−4,5%) | 372,4 → 316,0 MB (−15,1%) |
| 3. (cùng việc) | Thời gian, 3 lần chạy liên tiếp | 0,338 / 0,329 / 0,462 → 0,295 / 0,228 / 0,304 s | 0,312 / 0,441 / 0,535 → 0,214 / 0,286 / 0,296 s |

Nhận xét: Việc 1 giảm rõ cấp phát (14–20%) nhưng thời gian chưa phân biệt được với nhiễu. Việc 2 không có tác dụng đo
được (xem mục 14). Việc 3 giảm mạnh số nút CFI-tree (nhất là cây gốc) và cả ba lần đo đều cho thời gian nhanh hơn, nhưng mức
giảm cấp phát tổng chỉ 4–15% vì phần lớn bộ nhớ nằm ở FP-tree và `results`. Kết luận về lợi ích thật cần dữ liệu benchmark
thật ở Chương 2.
