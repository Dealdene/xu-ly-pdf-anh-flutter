// Kiểm thử lõi xử lý chạy thật trên máy Android (hoặc máy ảo), cùng ảnh mẫu với bộ kiểm thử Python.
// Chuẩn bị: chép thư mục xlpdf_kiemthu vào <thư mục tài liệu của ứng dụng>/kiem_thu (xem README).
// Chạy:  flutter test integration_test/loi_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'package:xu_ly_pdf_anh/loi/anh.dart';
import 'package:xu_ly_pdf_anh/loi/nan_phang.dart';
import 'package:xu_ly_pdf_anh/loi/quy_trinh.dart';
import 'package:xu_ly_pdf_anh/loi/tu_chup.dart';
import 'package:xu_ly_pdf_anh/loi/xuat_pdf.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late String thuMuc;

  setUpAll(() async {
    thuMuc = '${(await getApplicationDocumentsDirectory()).path}/kiem_thu';
  });

  test('tìm mép giấy ảnh chụp nghiêng', () async {
    final anh = giaiMa(await File('$thuMuc/mau1-chup-nghieng.jpg').readAsBytes());
    final sw = Stopwatch()..start();
    final khung = timMepGiay(anh);
    final dapAn = (jsonDecode(await File('$thuMuc/dap_an.json').readAsString())['mau1_goc'] as List)
        .map((p) => ((p[0] as num).toDouble(), (p[1] as num).toDouble()))
        .toList();
    expect(khung, isNotNull);
    var lech = 0.0;
    for (var i = 0; i < 4; i++) {
      lech = math.max(
        lech,
        math.sqrt(math.pow(khung![i].$1 - dapAn[i].$1, 2) + math.pow(khung[i].$2 - dapAn[i].$2, 2)),
      );
    }
    // ignore: avoid_print
    print('KQ tim_mep: lệch ${lech.toStringAsFixed(1)} px, ${sw.elapsedMilliseconds} ms');
    expect(lech, lessThan(12));
  });

  test('xử lý trọn trang: tỉ lệ A4, nền trắng, giữ dấu đỏ', () async {
    final goc = await File('$thuMuc/mau1-chup-nghieng.jpg').readAsBytes();
    final sw = Stopwatch()..start();
    final kq = xuLyAnh(goc, TuyChon(catSatChu: false)); // đo tỉ lệ A4 cả trang: không cắt sát chữ
    final ms = sw.elapsedMilliseconds;
    final anh = giaiMa(kq.trang.first);
    final tiLe = anh.rows / anh.cols;
    final d = anh.data;
    var trang = 0, sang = 0, doDo = 0;
    for (var i = 0; i < d.length; i += 3) {
      final b = d[i], g = d[i + 1], r = d[i + 2];
      if (b > 200 && g > 200 && r > 200) sang++;
      if (b > 245 && g > 245 && r > 245) trang++;
      if (r > 150 && g < 120 && b < 120) doDo++;
    }
    final n = d.length ~/ 3;
    // ignore: avoid_print
    print(
      'KQ xu_ly: ${anh.cols}x${anh.rows}, tỉ lệ ${tiLe.toStringAsFixed(3)}, nền trắng ${(trang / sang * 100).toStringAsFixed(1)}%, '
      'điểm đỏ ${(doDo / n * 100).toStringAsFixed(2)}%, $ms ms',
    );
    expect((tiLe - math.sqrt(2)).abs(), lessThan(0.03));
    expect(trang / sang, greaterThan(0.9));
    expect(doDo / n, greaterThan(0.002));
  });

  test('tách trang đôi', () async {
    final goc = await File('$thuMuc/mau3-trang-doi.jpg').readAsBytes();
    final kq = xuLyAnh(goc, TuyChon(tachTrangDoi: true, timMep: false));
    final a = giaiMa(kq.trang[0]), b = giaiMa(kq.trang[1]);
    final tl = a.cols / (a.cols + b.cols);
    // ignore: avoid_print
    print('KQ tach_trang: ${kq.trang.length} trang, cắt ở ${(tl * 100).toStringAsFixed(1)}%');
    expect(kq.trang.length, 2);
    expect((tl - 0.5).abs(), lessThan(0.05));
  });

  test('tự động chụp trên chuỗi khung hình mô phỏng', () async {
    final doan = (jsonDecode(await File('$thuMuc/khung/doan.json').readAsString()) as List).cast<String>();
    final bo = BoTuChup();
    final chup = <String>[];
    final tg = <int>[];
    for (var i = 0; i < doan.length; i++) {
      final kh = cv.imdecode(
        await File('$thuMuc/khung/${i.toString().padLeft(3, '0')}.jpg').readAsBytes(),
        cv.IMREAD_COLOR,
      );
      final sw = Stopwatch()..start();
      final nho = thuNho(kh, 640).$1;
      final tt = bo.nhanKhung(nho, i / 15);
      tg.add(sw.elapsedMilliseconds);
      if (tt.ma == 'da_chup') chup.add(doan[i]);
    }
    tg.sort();
    // ignore: avoid_print
    print('KQ tu_chup: chụp ở $chup, trung vị ${tg[tg.length ~/ 2]} ms/khung');
    expect(chup, ['giu_trang1', 'giu_trang2']);
  });

  test('xuất PDF', () async {
    final goc = await File('$thuMuc/mau1-chup-nghieng.jpg').readAsBytes();
    final pdf = await taoPdf([goc, goc], kho: 'a4', leMm: 10, chatLuong: 'nho');
    // ignore: avoid_print
    print('KQ pdf: ${pdf.length ~/ 1024} KB');
    expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
  });
}
