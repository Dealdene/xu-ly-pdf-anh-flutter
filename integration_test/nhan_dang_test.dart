// Kiểm thử nhận dạng chữ chạy thật trên máy Android (hoặc máy ảo): đọc hOCR, Tesseract trên máy, lớp chữ PDF.
// Chuẩn bị: chép thư mục xlpdf_kiemthu vào <thư mục tài liệu của ứng dụng>/kiem_thu (xem README).
// mau1.hocr, mau1.txt: kết quả `tesseract -l vie --psm 3` trên PC cho ảnh mau1 đã xử lý, dùng làm đáp án.
// Chạy:  flutter test integration_test/nhan_dang_test.dart
// PDF có lớp chữ được lấy ra build/kiem_thu_ra/lop_chu.pdf (ra.dart) để kiểm bằng PDFium trên PC.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xu_ly_pdf_anh/du_lieu/kho.dart';
import 'package:xu_ly_pdf_anh/loi/nhan_dang.dart';
import 'package:xu_ly_pdf_anh/loi/quy_trinh.dart';
import 'package:xu_ly_pdf_anh/loi/xuat_pdf.dart';

import 'ra.dart';

/// Tỉ lệ ký tự đúng = 1 − khoảng cách Levenshtein / độ dài đáp án.
double tiLeDung(String kq, String dapAn) {
  var truoc = List<int>.generate(kq.length + 1, (i) => i);
  for (var i = 1; i <= dapAn.length; i++) {
    final nay = List<int>.filled(kq.length + 1, 0)..[0] = i;
    for (var j = 1; j <= kq.length; j++) {
      nay[j] = [truoc[j] + 1, nay[j - 1] + 1, truoc[j - 1] + (dapAn[i - 1] == kq[j - 1] ? 0 : 1)].reduce(math.min);
    }
    truoc = nay;
  }
  return 1 - truoc[kq.length] / dapAn.length;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late String thuMuc;
  late TrangChu kqMay;
  late String tepTrang;

  setUpAll(() async {
    thuMuc = '${(await getApplicationDocumentsDirectory()).path}/kiem_thu';
  });

  test('đọc hOCR: vị trí từ, văn bản trùng Tesseract xuất thẳng, lưu JSON', () async {
    final t = TrangChu.docHocr(await File('$thuMuc/mau1.hocr').readAsString());
    expect((t.rong, t.cao), (1502, 2124));
    final d = t.dong.first;
    expect(d.vanBan, 'CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM');
    expect((d.coChu, d.chanChuTai(d.x0)), (43, 147));
    final w = d.tu.first;
    expect((w.chu, w.x0, w.y0, w.x1, w.y1, w.tinCay), ('CỘNG', 352, 117, 466, 155, 92));
    expect(t.vanBan, (await File('$thuMuc/mau1.txt').readAsString()).trim());
    final lai = TrangChu.fromJson(jsonDecode(jsonEncode(t.toJson())) as Map);
    expect(jsonEncode(lai.toJson()), jsonEncode(t.toJson()));
  });

  test('đọc hOCR: ký tự đặc biệt, thẻ lồng, dòng trống, nhiều trang', () {
    const mau = '''<div class='ocr_page' id='page_1' title='bbox 0 0 100 50'>
<p class='ocr_par' title="bbox 0 0 100 50"><span class='ocr_line' title="bbox 0 0 100 20; x_size 18">
<span class='ocrx_word' title='bbox 0 0 40 20; x_wconf 90'><strong>A&amp;B</strong></span>
<span class='ocrx_word' title='bbox 50 0 100 20; x_wconf 80'>&lt;1&gt;</span></span>
<span class='ocr_line' title="bbox 0 30 100 50; x_size 18"><span class='ocrx_word' title='bbox 0 30 10 50; x_wconf 0'> </span></span>
</p></div>''';
    final t = TrangChu.docHocr(mau);
    expect(t.dong.length, 1);
    expect(t.vanBan, 'A&B <1>');
    expect(vanBanNhieuTrang([t, TrangChu(10, 10, []), t]), 'A&B <1>\n\n\nA&B <1>');
  });

  test('nhận dạng chữ tiếng Việt trên máy (Tesseract4Android)', () async {
    final kq = xuLyAnh(await File('$thuMuc/mau1-chup-nghieng.jpg').readAsBytes(), TuyChon(catSatChu: false));
    tepTrang = '${(await getTemporaryDirectory()).path}/trang_ocr.jpg';
    await File(tepTrang).writeAsBytes(kq.trang.first, flush: true);
    final sw = Stopwatch()..start();
    kqMay = await nhanDangAnh(tepTrang); // lần đầu có chép dữ liệu vie.traineddata
    final lan1 = sw.elapsedMilliseconds;
    sw.reset();
    final lan2 = await nhanDangAnh(tepTrang);
    final ms = sw.elapsedMilliseconds;
    final vb = kqMay.vanBan;
    final dapAn = (await File('$thuMuc/mau1.txt').readAsString()).trim();
    final dung = tiLeDung(vb.replaceAll(RegExp(r'\s+'), ' '), dapAn.replaceAll(RegExp(r'\s+'), ' '));
    // ignore: avoid_print
    print('KQ ocr: ${kqMay.rong}x${kqMay.cao}, ${kqMay.dong.length} dòng, lần đầu $lan1 ms, lần sau $ms ms, '
        'trùng PC ${(dung * 100).toStringAsFixed(1)}%\n$vb');
    expect(lan2.vanBan, vb);
    expect(vb, contains('CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM'));
    expect(vb, allOf(contains('Độc lập'), contains('Tự do'), contains('Hạnh phúc')));
    expect(vb, contains('gửi: Thư viện Trường Đại học Hà Nội'));
    expect(vb, contains('searchable'));
    expect(dung, greaterThan(0.95));
  });

  test('PDF có lớp chữ ẩn', () async {
    final anh = await File(tepTrang).readAsBytes();
    final pdf = await taoPdf([anh], kho: 'a4', leMm: 10, chatLuong: 'vua', chu: [kqMay], phong: await phongLopChu());
    final khongChu = await taoPdf([anh], kho: 'a4', leMm: 10, chatLuong: 'vua');
    await ghiRa('lop_chu.pdf', pdf);
    await ghiRa('lop_chu.json', utf8.encode(jsonEncode(kqMay.toJson())));
    // ignore: avoid_print
    print('KQ lop_chu: ${pdf.length ~/ 1024} KB (không lớp chữ ${khongChu.length ~/ 1024} KB)');
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    expect(pdf.length - khongChu.length, lessThan(120 * 1024)); // phông chỉ nhúng các chữ đã dùng
    await xongRa();
  });
}
