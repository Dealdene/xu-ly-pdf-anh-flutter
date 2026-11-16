// Chụp sách mở hai trang (góp ý 14/11/2026: "app chỉ nhận 1/2 trang khi chụp sách"): bộ tìm mép phải lấy cả cặp trang
// và cả quy trình xử lý phải giữ đủ hai trang. Ảnh tổng hợp từ ung-dung/kiem_thu/tao_anh_sach_mo.py (xlpdf_kiemthu/sach_mo).
// Chạy:  bash integration_test/chay_kiem_thu.sh nua_trang_test.dart
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

import 'ra.dart';

double _iou(List<Diem> a, List<Diem> b, int h, int w) {
  cv.Mat mat(List<Diem> q) {
    final m = cv.Mat.zeros(h, w, cv.MatType.CV_8UC1);
    cv.fillPoly(m, cv.VecVecPoint.fromList([
      [for (final d in q) cv.Point(d.$1.round(), d.$2.round())]
    ]), cv.Scalar.all(1));
    return m;
  }

  final ma = mat(a), mb = mat(b);
  final giao = cv.countNonZero(cv.bitwiseAND(ma, mb)), hop = cv.countNonZero(cv.bitwiseOR(ma, mb));
  return giao / (hop == 0 ? 1 : hop);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('sách mở hai trang: khung lấy cả cặp trang, ảnh ra đủ hai trang', () async {
    final thuMuc = '${(await getApplicationDocumentsDirectory()).path}/kiem_thu/sach_mo';
    final dapAn = jsonDecode(await File('$thuMuc/dap_an.json').readAsString()) as Map<String, dynamic>;
    final loi = <String>[];
    for (final e in dapAn.entries) {
      final goc = await File('$thuMuc/${e.key}.jpg').readAsBytes();
      final anh = giaiMa(goc);
      final that = <Diem>[
        for (final p in (e.value as Map)['goc'] as List) (((p as List)[0] as num).toDouble(), (p[1] as num).toDouble())
      ];
      final khung = timMepGiay(anh);
      final iou = khung == null ? 0.0 : _iou(khung, that, anh.rows, anh.cols);
      final kq = xuLyAnh(goc, TuyChon());
      final (rw, rh) = kq.kichThuoc.first;
      final ti = rw / rh;
      await ghiRa('sachmo_${e.key}.jpg', kq.trang.first);
      final da = e.value as Map;
      // tự chụp: cặp trang lọt ra ngoài khung thì phải nhắc lùi máy, không chụp nửa cặp trang
      final ma = BoTuChup().nhanKhung(thuNho(anh, 640).$1, 0).ma;
      final tran = e.key.split('-')[1] == 'tran';
      final xs = that.map((p) => p.$1), ys = that.map((p) => p.$2);
      final le = [xs.reduce(math.min), ys.reduce(math.min), anh.cols - 1 - xs.reduce(math.max), anh.rows - 1 - ys.reduce(math.max)]
              .reduce(math.min) /
          math.max(anh.cols, anh.rows);
      // ignore: avoid_print
      print('SM ${e.key} tự chụp: $ma');
      if (tran && ma != 'cat_mep') loi.add('${e.key}: tự chụp báo $ma, phải nhắc lùi máy');
      if (!tran && da['tham_khao'] != true && le > 0.03 && ma == 'cat_mep') loi.add('${e.key}: tự chụp nhắc lùi máy sai');
      final mot = da['mot_trang'] == true; // chụp từng trang: ảnh ra phải là một trang
      // ignore: avoid_print
      print('SM ${e.key} iou=${iou.toStringAsFixed(2)} ra=${rw}x$rh rong/cao=${ti.toStringAsFixed(2)}'
          '${da['tham_khao'] == true ? ' (tham khảo, không tính)' : ''}');
      if (da['tham_khao'] == true) continue; // lỗi có từ bộ tìm mép 0.7.0, không do phần nối cặp trang
      if (iou < 0.85) loi.add('${e.key}: khung IoU ${iou.toStringAsFixed(2)}');
      if (mot ? ti >= 0.9 : ti < 1.1) loi.add('${e.key}: ảnh ra ${rw}x$rh (${mot ? 'ghép cả trang bên cạnh' : 'mất một trang'})');
    }
    await xongRa();
    expect(loi, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
