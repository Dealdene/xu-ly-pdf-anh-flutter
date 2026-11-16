// Kiểm thử đánh số trang khi xuất PDF. Trên máy: quy tắc số và căn (DanhSo), tạo PDF; vị trí số trong PDF
// kiểm trên PC bằng PDFium: build/kiem_thu_ra/so_trang_*.pdf (xem chay_kiem_thu.sh, kiem_so_trang.py).
// Chạy:  bash integration_test/chay_kiem_thu.sh so_trang_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xu_ly_pdf_anh/loi/quy_trinh.dart';
import 'package:xu_ly_pdf_anh/loi/xuat_pdf.dart';

import 'ra.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('quy tắc số và căn', () {
    final ds = DanhSo(tuTrang: 2, soDau: 1, can: 'so_le', chanTrai: true);
    expect([for (var i = 0; i < 4; i++) ds.soCua(i)], [null, 1, 2, 3]);
    expect([for (final so in [1, 2, 3]) ds.canCua(so)], ['phai', 'trai', 'phai']);
    ds.chanTrai = false;
    expect([for (final so in [1, 2]) ds.canCua(so)], ['trai', 'phai']);
    final theoTrang = DanhSo(tuTrang: 3, soDau: 3, can: 'giua');
    expect([for (var i = 0; i < 4; i++) theoTrang.soCua(i)], [null, null, 3, 4]);
    expect(theoTrang.canCua(3), 'giua');
  });

  test('tạo PDF có số trang', () async {
    final thuMuc = '${(await getApplicationDocumentsDirectory()).path}/kiem_thu';
    final anh = xuLyAnh(await File('$thuMuc/mau1-chup-nghieng.jpg').readAsBytes(), TuyChon(catSatChu: false)).trang.first;
    final bon = [anh, anh, anh, anh];
    // 1: lề 10 mm, từ trang 2 in số 1, lề trên, so le chẵn trái
    await ghiRa('so_trang_1.pdf',
        await taoPdf(bon, leMm: 10, chatLuong: 'nho', danhSo: DanhSo(tuTrang: 2, soDau: 1, viTri: 'tren', can: 'so_le', chanTrai: true)));
    // 2: không lề, từ trang 1, lề dưới, giữa
    await ghiRa('so_trang_2.pdf', await taoPdf(bon, chatLuong: 'nho', danhSo: DanhSo(viTri: 'duoi', can: 'giua')));
    // 3: lề 25 mm, từ trang 3 in số 3, lề dưới, phải
    await ghiRa('so_trang_3.pdf',
        await taoPdf(bon, leMm: 25, chatLuong: 'nho', danhSo: DanhSo(tuTrang: 3, soDau: 3, viTri: 'duoi', can: 'phai')));
    await xongRa();
  });
}
