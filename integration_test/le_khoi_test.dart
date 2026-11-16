// Nắn vuông khối chữ (góp ý 15/11/2026: "một số trang bị cắt lẹm vào chữ, có cách nào chỉnh méo, nắn vuông lại khối
// văn bản không?"): đo độ lệch lề trái, lề phải của khối chữ so với hai đường thẳng vuông góc dòng chữ (% bề ngang
// trang) trên 11 trang sách người dùng chụp bằng bản 0.7.2 (xlpdf_kiemthu/sach2), trước và sau quy trình xử lý (như
// nhập lại PDF vào ứng dụng). Giống ung-dung/kiem_thu/do_le.py.
// Chạy:  bash integration_test/chay_kiem_thu.sh le_khoi_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'package:xu_ly_pdf_anh/loi/anh.dart';
import 'package:xu_ly_pdf_anh/loi/chieu_chu.dart';
import 'package:xu_ly_pdf_anh/loi/nan_cong.dart';
import 'package:xu_ly_pdf_anh/loi/nan_phang.dart';
import 'package:xu_ly_pdf_anh/loi/quy_trinh.dart';

import 'ra.dart';

List<double?> _do(cv.Mat anh) {
  if (chuDoc(anh)) anh = xoay90(anh, 90);
  final gay = timGay(anh);
  final cac = gay == null
      ? [anh]
      : [anh.region(cv.Rect(0, 0, gay, anh.rows)).clone(), anh.region(cv.Rect(gay, 0, anh.cols - gay, anh.rows)).clone()];
  return [for (final t in cac) doLechLe(t)];
}

double _tv(List<double> a) {
  final b = [...a]..sort();
  return b.length.isOdd ? b[b.length ~/ 2] : (b[b.length ~/ 2 - 1] + b[b.length ~/ 2]) / 2;
}

String _chu(List<double?> v) => v.map((x) => x == null ? '—' : '${x.toStringAsFixed(1)}%').join(' ');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('nắn vuông khối chữ trên 11 trang sách chụp thật', () async {
    final thuMuc = '${(await getApplicationDocumentsDirectory()).path}/kiem_thu/sach2';
    final truoc = <double>[], sau = <double>[];
    for (var i = 0; i < 11; i++) {
      final goc = await File('$thuMuc/doc$i.jpg').readAsBytes();
      final t = _do(giaiMa(goc));
      final kq = xuLyAnh(goc, TuyChon());
      final s = <double?>[];
      for (final r in kq.trang) {
        s.addAll(_do(giaiMa(r)));
      }
      await ghiRa('le_doc$i.jpg', kq.trang.first);
      // ignore: avoid_print
      print('LE doc$i trước ${_chu(t)}  sau ${_chu(s)}');
      truoc.addAll(t.whereType<double>());
      sau.addAll(s.whereType<double>());
    }
    final tt = _tv(truoc), ts = _tv(sau);
    // ignore: avoid_print
    print('KQ trung vị lệch lề: trước ${tt.toStringAsFixed(2)}%, sau ${ts.toStringAsFixed(2)}%');
    await xongRa();
    expect(ts, lessThan(0.5));
    expect(ts, lessThan(0.5 * tt));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
