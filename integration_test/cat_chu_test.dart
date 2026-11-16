// Kiểm thử cắt sát chữ, xóa vết (cat_chu.dart) và nắn cong tách theo gáy sách trên máy Android, với 8 ảnh trang sách
// người dùng chụp bằng bản 0.7.1 (xlpdf_kiemthu/sach, kèm kết quả bản Python dap_an_python.json) và ảnh công văn mẫu.
// Chạy:  bash integration_test/chay_kiem_thu.sh cat_chu_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'package:xu_ly_pdf_anh/loi/anh.dart';
import 'package:xu_ly_pdf_anh/loi/cat_chu.dart';
import 'package:xu_ly_pdf_anh/loi/chieu_chu.dart';
import 'package:xu_ly_pdf_anh/loi/nan_cong.dart';
import 'package:xu_ly_pdf_anh/loi/nan_phang.dart';
import 'package:xu_ly_pdf_anh/loi/quy_trinh.dart';

import 'ra.dart';

/// Tỉ lệ điểm ảnh tối (xám < 200) trên dải 4 điểm ảnh sát mép ảnh.
double _toiMep(cv.Mat anh) {
  final xam = u8Chep(cv.cvtColor(anh, cv.COLOR_BGR2GRAY));
  final h = anh.rows, w = anh.cols;
  var n = 0, toi = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (y < 4 || y >= h - 4 || x < 4 || x >= w - 4) {
        n++;
        if (xam[y * w + x] < 200) toi++;
      }
    }
  }
  return toi / n;
}

(int, int) _mauSac(cv.Mat anh) {
  final d = u8Chep(anh);
  var doDo = 0, xanh = 0;
  for (var i = 0; i < d.length; i += 3) {
    final b = d[i], g = d[i + 1], r = d[i + 2];
    if (r > 150 && g < 120 && b < 120) doDo++;
    if (b > 120 && r < 100 && g < 110) xanh++;
  }
  return (doDo, xanh);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late String thuMuc;

  setUpAll(() async {
    thuMuc = '${(await getApplicationDocumentsDirectory()).path}/kiem_thu';
  });

  test('cắt sát chữ, xóa vết trên 8 trang sách chụp thật', () async {
    final py = jsonDecode(await File('$thuMuc/sach/dap_an_python.json').readAsString()) as Map<String, dynamic>;
    for (var i = 0; i < 8; i++) {
      final a = giaiMa(await File('$thuMuc/sach/goc$i.png').readAsBytes());
      final sw = Stopwatch()..start();
      final b = catSatChu(a);
      final ms = sw.elapsedMilliseconds;
      final p = py['goc$i'] as Map;
      final (pw, ph) = ((p['cat'] as List)[0] as int, (p['cat'] as List)[1] as int);
      final mep = _toiMep(b);
      // ignore: avoid_print
      print('KQ cat goc$i: ${a.cols}x${a.rows} → ${b.cols}x${b.rows} (Python ${pw}x$ph), mép tối ${(mep * 100).toStringAsFixed(2)}%, $ms ms');
      expect((b.cols - pw).abs() < 0.03 * pw && (b.rows - ph).abs() < 0.03 * ph, isTrue, reason: 'goc$i lệch bản Python');
      expect(mep, lessThan(0.01), reason: 'goc$i còn vết tối sát mép');
      final gay = timGay(a);
      // ignore: avoid_print
      print('KQ gay goc$i: $gay (Python ${p['gay']})');
      if (p['gay'] == null) {
        expect(gay, isNull);
      } else {
        expect((gay! - (p['gay'] as int)).abs() < 25, isTrue); // đáy dải gáy phẳng: lệch vài chục điểm ảnh vẫn trong gáy
      }
      if (i == 0 || i == 6) {
        final sb = 480 / b.rows, sa = 480 / a.rows;
        await ghiRa('cat-goc$i.jpg',
            maHoa(cv.hconcat(cv.resize(a, ((a.cols * sa).round(), 480)), cv.resize(b, ((b.cols * sb).round(), 480))), chatLuong: 85));
      }
    }
  });

  test('ảnh chụp cầm máy ngang (lần hai): nhận dòng chữ dọc, cắt sát chữ, xóa ngón tay, gáy', () async {
    final py = jsonDecode(await File('$thuMuc/sach2/dap_an_python.json').readAsString()) as Map<String, dynamic>;
    for (var i = 0; i < 11; i++) {
      final p = py['doc$i'] as Map;
      final nam = giaiMa(await File('$thuMuc/sach2/doc$i.jpg').readAsBytes());
      final sw = Stopwatch()..start();
      final doc = chuDoc(nam);
      final msDoc = sw.elapsedMilliseconds;
      final a = xoay90(nam, 90);
      expect(doc, isTrue, reason: 'doc$i: không nhận ra dòng chữ dọc');
      expect(chuDoc(a), isFalse, reason: 'doc$i: xoay rồi vẫn báo dọc');
      sw.reset();
      final b = catSatChu(a);
      final ms = sw.elapsedMilliseconds;
      final (pw, ph) = ((p['cat'] as List)[0] as int, (p['cat'] as List)[1] as int);
      final gay = timGay(a);
      // ignore: avoid_print
      print('KQ doc$i: dọc ${msDoc}ms, cắt ${a.cols}x${a.rows} → ${b.cols}x${b.rows} (Python ${pw}x$ph) $ms ms, gáy $gay (Python ${p['gay']})');
      expect((b.cols - pw).abs() < 0.03 * pw && (b.rows - ph).abs() < 0.03 * ph, isTrue, reason: 'doc$i lệch bản Python');
      if (p['gay'] == null) {
        expect(gay, isNull);
      } else {
        expect((gay! - (p['gay'] as int)).abs() < 25, isTrue); // đáy dải gáy phẳng: lệch vài chục điểm ảnh vẫn trong gáy
      }
      if (i == 0 || i == 1 || i == 6) {
        final sb = 480 / b.rows, sa = 480 / a.rows;
        await ghiRa('cat-doc$i.jpg',
            maHoa(cv.hconcat(cv.resize(a, ((a.cols * sa).round(), 480)), cv.resize(b, ((b.cols * sb).round(), 480))), chatLuong: 85));
      }
    }
    // cả luồng: ảnh nằm ngang ra trang sách mở nằm ngang (dòng chữ ngang)
    final kq = xuLyAnh(await File('$thuMuc/sach2/doc6.jpg').readAsBytes(), TuyChon(timMep: false));
    final r = giaiMa(kq.trang.first);
    // ignore: avoid_print
    print('KQ luong doc6: xoayChu ${kq.xoayChu}, ${r.cols}x${r.rows}');
    expect(kq.xoayChu, 90);
    expect(r.cols > r.rows, isTrue);
  });

  test('cắt sát chữ trên công văn mẫu giữ trọn chữ, dấu đỏ, chữ ký', () async {
    final goc = await File('$thuMuc/mau1-chup-nghieng.jpg').readAsBytes();
    final day = giaiMa(xuLyAnh(goc, TuyChon(catSatChu: false)).trang.first);
    final sat = giaiMa(xuLyAnh(goc, TuyChon()).trang.first);
    final (do1, xanh1) = _mauSac(day);
    final (do2, xanh2) = _mauSac(sat);
    final mep = _toiMep(sat);
    // ignore: avoid_print
    print('KQ cong_van: ${day.cols}x${day.rows} → ${sat.cols}x${sat.rows}, đỏ $do1→$do2, xanh $xanh1→$xanh2, mép tối ${(mep * 100).toStringAsFixed(2)}%');
    expect(sat.cols * sat.rows < 0.8 * day.cols * day.rows, isTrue);
    // vùng chữ giữ nguyên, lề chỉ thêm nền trắng; số điểm xanh (chữ ký, ~430 điểm) dao động ±5% do nén JPEG lại (bản
    // Python trước khi nén: không mất điểm nào ở cả lề sát lẫn lề vừa)
    expect(do2 >= 0.97 * do1 && xanh2 >= 0.95 * xanh1, isTrue);
    expect(mep, lessThan(0.002));
    await xongRa();
  });
}
