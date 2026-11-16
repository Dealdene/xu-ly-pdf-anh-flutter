// Kiểm thử tìm mép giấy kiểu CamScanner và nắn trang cong trên máy Android, cùng bộ ảnh tổng hợp với bản Python
// (ung-dung/kiem_thu/anh_mau_mep, tạo bằng tao_anh_mep.py; chép vào xlpdf_kiemthu/mep).
// Chạy:  bash integration_test/chay_kiem_thu.sh mep_cong_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'package:xu_ly_pdf_anh/loi/anh.dart';
import 'package:xu_ly_pdf_anh/loi/nan_cong.dart';
import 'package:xu_ly_pdf_anh/loi/nan_phang.dart';
import 'package:xu_ly_pdf_anh/loi/tu_chup.dart';

import 'ra.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late String thuMuc;
  late Map<String, dynamic> dapAn;

  setUpAll(() async {
    thuMuc = '${(await getApplicationDocumentsDirectory()).path}/kiem_thu/mep';
    dapAn = jsonDecode(await File('$thuMuc/dap_an.json').readAsString()) as Map<String, dynamic>;
  });

  List<Diem> goc(String ten) => [
        for (final p in dapAn[ten]['goc'] as List) ((p[0] as num).toDouble(), (p[1] as num).toDouble())
      ];

  test('tìm mép giấy trên 17 ảnh khó (bàn trắng, nền lộn xộn, giấy chồng giấy, sách cong…)', () async {
    var dat = 0, tongMs = 0;
    final truot = <String>[];
    for (final ten in dapAn.keys) {
      final anh = giaiMa(await File('$thuMuc/$ten.jpg').readAsBytes());
      final w = anh.cols, h = anh.rows;
      final sw = Stopwatch()..start();
      final k = timMepGiay(anh);
      tongMs += sw.elapsedMilliseconds;
      final that = [for (final (x, y) in goc(ten)) (x.clamp(0.0, w - 1.0), y.clamp(0.0, h - 1.0))];
      bool ok;
      String sai;
      if (k == null) {
        final khungAnh = [(0.0, 0.0), (w - 1.0, 0.0), (w - 1.0, h - 1.0), (0.0, h - 1.0)];
        var m = 0.0;
        for (var i = 0; i < 4; i++) {
          m = math.max(m, math.max((that[i].$1 - khungAnh[i].$1).abs(), (that[i].$2 - khungAnh[i].$2).abs()));
        }
        ok = m < 0.02 * h;
        sai = '-';
      } else {
        var m = 0.0;
        for (var i = 0; i < 4; i++) {
          m = math.max(m, math.sqrt(math.pow(k[i].$1 - that[i].$1, 2) + math.pow(k[i].$2 - that[i].$2, 2)));
        }
        ok = m < 0.012 * math.sqrt(w * w + h * h);
        sai = '${m.toStringAsFixed(1)} px';
      }
      if (ok) {
        dat++;
      } else {
        truot.add(ten);
      }
      // ignore: avoid_print
      print('KQ mep $ten: ${ok ? 'ĐẠT' : 'TRƯỢT'} lệch $sai, ${sw.elapsedMilliseconds} ms');
    }
    // ignore: avoid_print
    print('KQ mep: đạt $dat/${dapAn.length}, trung bình ${tongMs ~/ dapAn.length} ms/ảnh; trượt: $truot');
    expect(dat, dapAn.length);
  });

  test('nắn trang cong: dòng chữ thẳng lại, trang phẳng để nguyên', () async {
    for (final ten in dapAn.keys) {
      final anh = giaiMa(await File('$thuMuc/$ten.jpg').readAsBytes());
      final trang = lamPhang(anh, goc(ten).map((p) => (p.$1.clamp(0.0, anh.cols - 1.0), p.$2.clamp(0.0, anh.rows - 1.0))).toList());
      final truoc = doVongDong(trang);
      final sw = Stopwatch()..start();
      final sau = nanTrangCong(trang);
      final ms = sw.elapsedMilliseconds;
      final cong = (dapAn[ten]['cong'] as num) > 0;
      final kq = doVongDong(sau);
      // ignore: avoid_print
      print('KQ cong $ten: võng ${truoc.$1.toStringAsFixed(2)}% → ${kq.$1.toStringAsFixed(2)}% '
          '(lớn nhất ${truoc.$2.toStringAsFixed(2)}% → ${kq.$2.toStringAsFixed(2)}%), '
          '${identical(sau, trang) ? 'không nắn' : 'đã nắn'}, $ms ms');
      if (!cong) {
        expect(identical(sau, trang), isTrue, reason: '$ten là trang phẳng, không được nắn');
      } else if (truoc.$1 > 0.2) {
        expect(kq.$1, lessThan(0.35 * truoc.$1), reason: '$ten còn cong');
      }
      if (ten.startsWith('17')) {
        final ghep = cv.hconcat(cv.resize(trang, (600, 850)), cv.resize(sau, (600, 850)));
        await ghiRa('nan-cong-$ten.jpg', maHoa(ghep, chatLuong: 85));
      }
    }
  });

  test('tự chụp: trang trọn khung sát mép không bị báo lùi máy; trang bị cắt thì báo', () async {
    for (final ten in ['01-go-nghieng', '02-ban-trang', '05-ngon-tay']) {
      final anh = giaiMa(await File('$thuMuc/$ten.jpg').readAsBytes());
      final g = goc(ten);
      final x0 = g.map((p) => p.$1).reduce(math.min), x1 = g.map((p) => p.$1).reduce(math.max);
      final y0 = g.map((p) => p.$2).reduce(math.min), y1 = g.map((p) => p.$2).reduce(math.max);
      // khung hình ôm sát trang, mép giấy cách mép khung 0,4% (trước đây: < 1% là báo "lùi máy")
      final le = 0.004 * math.max(x1 - x0, y1 - y0);
      final r = cv.Rect((x0 - le).round().clamp(0, anh.cols - 1), (y0 - le).round().clamp(0, anh.rows - 1), 0, 0);
      final sat = anh.region(cv.Rect(r.x, r.y, ((x1 + le).round() - r.x).clamp(1, anh.cols - r.x),
          ((y1 + le).round() - r.y).clamp(1, anh.rows - r.y))).clone();
      // khung hình cắt mất 12% bề rộng trang bên phải, các mép kia chừa lề 4% (sát cả 3 mép thì coi là giấy phủ kín khung)
      final l4 = 0.04 * math.max(x1 - x0, y1 - y0);
      final cx = (x0 - l4).round().clamp(0, anh.cols - 1), cy = (y0 - l4).round().clamp(0, anh.rows - 1);
      final cat = anh.region(cv.Rect(cx, cy, (x1 - 0.12 * (x1 - x0)).round() - cx,
          ((y1 + l4).round() - cy).clamp(1, anh.rows - cy))).clone();
      final maSat = <String>{}, maCat = <String>{};
      for (final (khung, ma) in [(sat, maSat), (cat, maCat)]) {
        final bo = BoTuChup();
        final (nho, _) = thuNho(khung, 640);
        for (var i = 0; i < 6; i++) {
          ma.add(bo.nhanKhung(nho, i * 0.25).ma);
        }
      }
      // ignore: avoid_print
      print('KQ tu_chup $ten: sát mép $maSat, bị cắt $maCat');
      expect(maSat.contains('cat_mep'), isFalse, reason: '$ten: trang trọn khung mà vẫn báo lùi máy');
      expect(maSat.contains('da_chup') || maSat.contains('dang_giu'), isTrue, reason: '$ten: trang trọn khung không chụp');
      expect(maCat.contains('cat_mep'), isTrue, reason: '$ten: trang bị cắt mà không báo');
    }
  });

  test('đo ảnh chụp mờ (lấy nét hụt)', () async {
    for (final ten in ['01-go-nghieng', '11-kin-khung']) {
      final xam0 = cv.cvtColor(giaiMa(await File('$thuMuc/$ten.jpg').readAsBytes()), cv.COLOR_BGR2GRAY);
      final xam = cv.resize(xam0, (xam0.cols * 2, xam0.rows * 2), interpolation: cv.INTER_CUBIC); // cỡ ảnh chụp 12 MP
      final net = tiLeNet(xam);
      final mo = tiLeNet(cv.gaussianBlur(xam, (0, 0), 4));
      final nho = tiLeNet(cv.resize(xam0, (900, 1200))); // ảnh nhỏ: không đo
      // ignore: avoid_print
      print('KQ net $ten: nét ${net.toStringAsFixed(2)}, mờ ${mo.toStringAsFixed(2)}, ảnh nhỏ ${nho.toStringAsFixed(2)}');
      expect(net, greaterThan(nguongTiLeNet));
      expect(mo, lessThan(nguongTiLeNet));
      expect(nho, 1.0);
    }
    await xongRa();
  });
}
