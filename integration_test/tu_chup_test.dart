// Kiểm thử tự chụp trên đoạn quay màn hình chụp thật của người dùng (sách mở đặt trên nền đen, 6 cặp trang, bản 0.7.3):
// khung xem trước tách từ video (xlpdf_kiemthu/video, ~12 khung/giây, kèm thoi_gian.json). Bản 0.7.3 báo "Giữ yên máy"
// khi sách đã nằm yên và báo "Đã chụp trang này" với trang mới (giây 17–34), chụp chậm hoặc không chụp.
// Chạy:  bash integration_test/chay_kiem_thu.sh tu_chup_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'package:xu_ly_pdf_anh/loi/anh.dart';
import 'package:xu_ly_pdf_anh/loi/tu_chup.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('tự chụp trên video chụp thật: mỗi cặp trang chụp một lần, không đứng chờ', () async {
    final thuMuc = '${(await getApplicationDocumentsDirectory()).path}/kiem_thu/video';
    final j = jsonDecode(await File('$thuMuc/thoi_gian.json').readAsString()) as Map<String, dynamic>;
    final tg = (j['t'] as List).cast<num>();
    final cuaSo = [for (final w in j['cua_so'] as List) [(w as List)[0] as num, w[1] as num]];
    final bo = BoTuChup()..ch.thoiGianGiu = 0.5;
    final chup = <double>[];
    final dem = <String, int>{};
    var nghiDen = -1.0;
    final nhatKy = StringBuffer();
    for (var i = 0; i < tg.length; i++) {
      final t = tg[i].toDouble();
      if (t < nghiDen) continue; // đang chụp: ứng dụng tắt luồng khung hình, chụp xong đặt lại (nhớ trang vừa chụp)
      final kh = cv.imdecode(await File('$thuMuc/${i.toString().padLeft(4, '0')}.jpg').readAsBytes(), cv.IMREAD_COLOR);
      final lat0 = bo.tLat;
      final tt = bo.nhanKhung(thuNho(kh, 640).$1, t);
      dem[tt.ma] = (dem[tt.ma] ?? 0) + 1;
      nhatKy.write('${t.toStringAsFixed(1)} ${tt.ma} k${bo.khacCuoi.toStringAsFixed(2)} l${lat0.toStringAsFixed(1)}; ');
      if (tt.ma == 'da_chup') {
        chup.add(t);
        nghiDen = t + 1.0;
        bo.datLai(quenTrangCuoi: false);
      }
    }
    for (final dong in nhatKy.toString().split('; ').fold<List<List<String>>>([[]], (a, e) {
      if (a.last.length >= 8) a.add([]);
      a.last.add(e);
      return a;
    })) {
      // ignore: avoid_print
      print('NK ${dong.join(' | ')}');
    }
    // ignore: avoid_print
    print('KQ video: chụp lúc ${[for (final t in chup) t.toStringAsFixed(1)]}, mã $dem');
    // Mỗi cặp trang được chụp trong khoảng từ lúc sách nằm yên đến lúc bản cũ chụp được (hoặc sớm hơn): không đứng chờ.
    for (var k = 0; k < cuaSo.length; k++) {
      expect(chup.any((t) => t >= cuaSo[k][0] && t <= cuaSo[k][1]), isTrue,
          reason: 'cặp trang ${k + 1}: không chụp trong khoảng ${cuaSo[k]}');
    }
    // Không chụp khi tay đang đặt trên trang (vuốt phẳng, giữ trang).
    for (final t in (j['co_tay'] as List).cast<List>()) {
      expect(chup.any((c) => c >= (t[0] as num) && c <= (t[1] as num)), isFalse, reason: 'chụp khi tay trên trang $t');
    }
    // Chụp thừa: video quay màn hình (nén, khung màu vẽ đè) làm cùng một trang lệch nhau 0,2–0,27, sát ngưỡng 0,24, nên
    // vài lần chụp lại cùng trang ở đây không có trên ảnh camera thật (bản 0.7.3 không chụp trùng); chỉ chặn số lần quá nhiều.
    expect(chup.length, lessThanOrEqualTo(cuaSo.length + 2), reason: 'chụp thừa quá nhiều');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
