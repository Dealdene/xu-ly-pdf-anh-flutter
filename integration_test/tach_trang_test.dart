// Tách cặp trang sách mở (góp ý 15/11/2026, tệp Hồ sơ 15-11 19-33.pdf 214 trang: trang trái dính một dải chữ đầu dòng
// của trang phải, trang phải mất chữ cái đầu dòng). Đường cắt phải đi giữa khe trắng ở gáy: không nét chữ nào chạm
// đường cắt. So đường cắt với bản Python (ung-dung/kiem_thu/ghi_dap_an_tach.py → xlpdf_kiemthu/tach_trang_python.json).
// Giống ung-dung/kiem_thu/kiem_thu_tach_trang.py.
// Chạy:  bash integration_test/chay_kiem_thu.sh tach_trang_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'package:xu_ly_pdf_anh/loi/anh.dart';
import 'package:xu_ly_pdf_anh/loi/chieu_chu.dart';
import 'package:xu_ly_pdf_anh/loi/nan_phang.dart';
import 'package:xu_ly_pdf_anh/loi/quy_trinh.dart';

import 'ra.dart';

/// Số nét cỡ chữ chạm mép cắt ([phai]: mép phải của nửa trái; không thì mép trái của nửa phải).
int netChamMep(cv.Mat nua, bool phai) {
  final xam = cv.cvtColor(nua, cv.COLOR_BGR2GRAY);
  final h = xam.rows, w = xam.cols;
  final muc = cv.adaptiveThreshold(xam, 1, cv.ADAPTIVE_THRESH_MEAN_C, cv.THRESH_BINARY_INV, 31, 18);
  final nhanM = cv.Mat.empty(), tkM = cv.Mat.empty(), tamM = cv.Mat.empty();
  final n = cv.connectedComponentsWithStats(muc, nhanM, tkM, tamM, 8, cv.MatType.CV_32S, cv.CCL_DEFAULT);
  final nhan = i32Chep(nhanM), tk = i32Chep(tkM), xd = u8Chep(xam);
  final tongXam = Float64List(n);
  for (var i = 0; i < nhan.length; i++) {
    tongXam[nhan[i]] += xd[i];
  }
  final cao = <int>[];
  for (var i = 1; i < n; i++) {
    final ch = tk[i * 5 + 3], dt = tk[i * 5 + 4];
    if (ch > 6 && ch < 0.04 * h && dt > 15) cao.add(ch);
  }
  if (cao.length < 20) return 0;
  cao.sort();
  final c = cao[cao.length ~/ 2].toDouble();
  var dem = 0;
  for (var i = 1; i < n; i++) {
    final x = tk[i * 5], y = tk[i * 5 + 1], cw = tk[i * 5 + 2], ch = tk[i * 5 + 3], dt = tk[i * 5 + 4];
    final chu = ch > 0.4 * c && ch < 2.5 * c && cw < 4 * c && dt > 0.1 * c * c && tongXam[i] / dt > 45 && cw >= 0.2 * c;
    final cham = phai ? x + cw >= w - 2 : x <= 1;
    if (chu && cham && y > 0.04 * h && y + ch < 0.96 * h) dem++;
  }
  return dem;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('tách cặp trang sách mở: cắt giữa khe gáy, không cắt qua chữ', () async {
    final goc = '${(await getApplicationDocumentsDirectory()).path}/kiem_thu';
    final dapAn = jsonDecode(await File('$goc/tach_trang_python.json').readAsString()) as Map<String, dynamic>;
    final truot = <String>[], lechPy = <String>[];
    var tong = 0;
    for (final e in dapAn.entries) {
      final da = e.value as Map<String, dynamic>;
      var anh = giaiMa(await File('$goc/${e.key.replaceFirst('anh_sach_mo/', 'sach_mo/')}').readAsBytes());
      final khung = timMepGiay(anh);
      if (khung != null) anh = lamPhang(anh, khung, noi: noiKhung);
      if (chuDoc(anh)) anh = xoay90(anh, 90);
      final duong = anh.cols >= anh.rows ? kheGay(anh) : null;
      final cac = tachTrangDoi(anh);
      final py = da['duong'] as List?;
      final lech = duong == null || py == null
          ? (duong == null && py == null ? 0.0 : 999.0)
          : [((duong.$1 - (py[0] as num)).abs()), ((duong.$2 - (py[1] as num)).abs())].reduce((a, b) => a > b ? a : b);
      if (lech > 8) lechPy.add('${e.key} (${duong?.$1.round()},${duong?.$2.round()} / Python $py)');
      if (cac.length != 2) {
        // ignore: avoid_print
        print('TACH ${e.key}: không tách (một trang), Python ${(da['nua'] as List).length} nửa');
        if ((da['nua'] as List).length != 1) truot.add(e.key);
        continue;
      }
      tong++;
      final a = netChamMep(cac[0], true), b = netChamMep(cac[1], false);
      // tối đa 2 mảnh bóng gáy đen mảnh chạm mép; cắt qua chữ thì 18–24 nét chạm (cách tách cũ)
      if (a > 2 || b > 2) truot.add(e.key);
      if (e.key.startsWith('sach/')) {
        await ghiRa('tach_${e.key.split('/').last.split('.').first}_trai.jpg', maHoa(cac[0], chatLuong: 85));
        await ghiRa('tach_${e.key.split('/').last.split('.').first}_phai.jpg', maHoa(cac[1], chatLuong: 85));
      }
      // ignore: avoid_print
      print('TACH ${e.key}: nét chạm đường cắt trái $a, phải $b; đường ${duong?.$1.round()},${duong?.$2.round()} '
          '(Python $py)');
    }
    // cả quy trình (trang sách): mỗi nửa ra một trang dọc
    final kq = xuLyAnh(await File('$goc/sach/goc4.png').readAsBytes(), TuyChon(tachTrangDoi: true));
    // ignore: avoid_print
    print('TACH quy trình goc4: ${kq.kichThuoc}');
    await xongRa();
    // ignore: avoid_print
    print('KQ tách trang: đạt ${tong - truot.length}/$tong; trượt $truot; lệch Python > 8 px: $lechPy');
    expect(truot, isEmpty);
    expect(lechPy.length, lessThanOrEqualTo(2));
    expect(kq.kichThuoc.length, 2);
    for (final (w, h) in kq.kichThuoc) {
      expect(w, lessThan(h));
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
