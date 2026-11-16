"""Kiểm vị trí số trang trong PDF do so_trang_test.dart tạo (chạy trên PC sau chay_kiem_thu.sh so_trang_test.dart).

Dùng:  python integration_test/kiem_so_trang.py   (cần pypdfium2)
Mỗi trang: đọc chữ và khung ký tự bằng PDFium, so với vị trí mong đợi (khổ A4 595,3 × 841,9 pt).
"""
import sys

import pypdfium2 as pdfium

sys.stdout.reconfigure(encoding="utf-8")
MM = 72 / 25.4
THU_MUC = "build/kiem_thu_ra/"

# (tệp, lề mm, [(số mong đợi hoặc None, vị trí, căn) cho 4 trang])
CA = [
    ("so_trang_1.pdf", 10, [(None, "", ""), ("1", "tren", "phai"), ("2", "tren", "trai"), ("3", "tren", "phai")]),
    ("so_trang_2.pdf", 0, [("1", "duoi", "giua"), ("2", "duoi", "giua"), ("3", "duoi", "giua"), ("4", "duoi", "giua")]),
    ("so_trang_3.pdf", 25, [(None, "", ""), (None, "", ""), ("3", "duoi", "phai"), ("4", "duoi", "phai")]),
]

loi = 0
for tep, le_mm, mong in CA:
    pdf = pdfium.PdfDocument(THU_MUC + tep)
    le = le_mm * MM
    for i, (so, vi_tri, can) in enumerate(mong):
        trang = pdf[i]
        w, h = trang.get_size()
        tp = trang.get_textpage()
        chu = tp.get_text_range().strip()
        if so is None:
            dat = chu == ""
            print(f"{tep} trang {i + 1}: không số -> {'đạt' if dat else 'SAI, có chữ ' + repr(chu)}")
            loi += not dat
            continue
        hop = [tp.get_charbox(j) for j in range(tp.count_chars()) if not tp.get_text_range(j, 1).isspace()]
        x0, y0 = min(b[0] for b in hop), min(b[1] for b in hop)
        x1, y1 = max(b[2] for b in hop), max(b[3] for b in hop)
        tam_x, tam_y = (x0 + x1) / 2, h - (y0 + y1) / 2  # tâm số, y tính từ mép trên
        ngang = max(le, 20 * MM)
        doc = max(le / 2, 8 * MM)
        mx = {"giua": w / 2, "trai": ngang + (x1 - x0) / 2, "phai": w - ngang - (x1 - x0) / 2}[can]
        my = doc if vi_tri == "tren" else h - doc
        dat = chu == so and abs(tam_x - mx) < 3 and abs(tam_y - my) < 4
        loi += not dat
        print(f"{tep} trang {i + 1}: số {chu!r} tâm ({tam_x:.1f}, {tam_y:.1f}) pt, mong đợi {so!r} ({mx:.1f}, {my:.1f}) "
              f"[{vi_tri}, {can}] -> {'đạt' if dat else 'SAI'}")
print("TẤT CẢ ĐẠT" if loi == 0 else f"{loi} TRANG SAI")
sys.exit(1 if loi else 0)
