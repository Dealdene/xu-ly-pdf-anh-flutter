// Đo chất lượng làm sạch trên máy: độ đen của chữ, đốm nhiễu, nền trắng, giữ dấu đỏ, nhận dạng chữ.
// mau1: ảnh chụp tốt; mau4-chup-kem: cùng trang nhưng chữ nhạt, nhiễu hạt, đốm bụi, nén JPEG mạnh.
// Chạy:  bash integration_test/chay_kiem_thu.sh lam_sach_test.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'package:xu_ly_pdf_anh/du_lieu/kho.dart';
import 'package:xu_ly_pdf_anh/loi/anh.dart';
import 'package:xu_ly_pdf_anh/loi/quy_trinh.dart';

import 'nhan_dang_test.dart' show tiLeDung;

class ChiSo {
  ChiSo(this.denChu, this.dom, this.nenTrang, this.doDo, this.ocr, this.ms);
  final double denChu; // trung vị độ sáng các điểm chữ (càng thấp chữ càng đen, tương phản càng cao)
  final int dom; // số đốm tối nhỏ đứng riêng (nhiễu)
  final double nenTrang, ocr; // tỉ lệ
  final int doDo, ms;

  @override
  String toString() => 'chữ ${denChu.toStringAsFixed(0)}, đốm $dom, nền trắng ${(nenTrang * 100).toStringAsFixed(1)}%, '
      'điểm đỏ $doDo, OCR ${(ocr * 100).toStringAsFixed(1)}%, $ms ms';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late String thuMuc, tam, dapAn;

  setUpAll(() async {
    thuMuc = '${(await getApplicationDocumentsDirectory()).path}/kiem_thu';
    tam = (await getTemporaryDirectory()).path;
    dapAn = (await File('$thuMuc/mau1.txt').readAsString()).trim().replaceAll(RegExp(r'\s+'), ' ');
  });

  Future<ChiSo> do_(String tep, TuyChon tc) async {
    final sw = Stopwatch()..start();
    final kq = xuLyAnh(await File('$thuMuc/$tep').readAsBytes(), tc);
    final ms = sw.elapsedMilliseconds;
    final anh = giaiMa(kq.trang.first);
    final xam = cv.cvtColor(anh, cv.COLOR_BGR2GRAY);
    final d = anh.data, x = xam.data;
    final chu = <int>[];
    var sang = 0, trang = 0, doDo = 0;
    for (var p = 0; p < x.length; p++) {
      final v = x[p];
      if (v < 160) chu.add(v);
      if (v > 200) sang++;
      if (v > 245) trang++;
      final b = d[p * 3], g = d[p * 3 + 1], r = d[p * 3 + 2];
      if (r > 150 && g < 120 && b < 120) doDo++;
    }
    chu.sort();
    // đốm: thành phần tối diện tích ≤ 12 điểm ảnh
    final toi = cv.threshold(xam, 160, 255, cv.THRESH_BINARY_INV).$2;
    final nhan = cv.Mat.empty(), tk = cv.Mat.empty(), tam_ = cv.Mat.empty();
    final n = cv.connectedComponentsWithStats(toi, nhan, tk, tam_, 8, cv.MatType.CV_32S, cv.CCL_DEFAULT);
    var dom = 0;
    for (var i = 1; i < n; i++) {
      if (tk.at<int>(i, cv.CC_STAT_AREA) <= 12) dom++;
    }
    final duongDan = '$tam/ls_$tep';
    await File(duongDan).writeAsBytes(kq.trang.first, flush: true);
    final vb = (await nhanDangAnh(duongDan)).vanBan.replaceAll(RegExp(r'\s+'), ' ');
    return ChiSo(chu.isEmpty ? 255 : chu[chu.length ~/ 2].toDouble(), dom, trang / math.max(sang, 1), doDo, tiLeDung(vb, dapAn), ms);
  }

  // Số đo trước khi thêm khử nhiễu, tăng tương phản (2026-10-29), cùng phép đo:
  //   mau1: chữ 50, đốm 26, nền trắng 99,4%, OCR 99,4%;  mau4: chữ 55, đốm 743, nền trắng 99,1%, OCR 71,0%.
  test('làm sạch ảnh chụp tốt và ảnh chụp kém', () async {
    for (final tep in ['mau1-chup-nghieng.jpg', 'mau4-chup-kem.jpg']) {
      final khong = await do_(tep, TuyChon(khuNhieu: 0, catSatChu: false));
      final mac = await do_(tep, TuyChon(catSatChu: false));
      // ignore: avoid_print
      print('KQ $tep không khử nhiễu: $khong');
      // ignore: avoid_print
      print('KQ $tep mặc định:       $mac');
      expect(mac.nenTrang, greaterThan(0.97));
      expect(mac.doDo, greaterThan(1000)); // vẫn giữ dấu đỏ
      expect(mac.denChu, lessThan(48)); // chữ đen hơn bản cũ (50, 55)
      if (tep.startsWith('mau1')) {
        expect(mac.ocr, greaterThan(0.97)); // không làm mất dấu thanh trên ảnh tốt
      } else {
        expect(mac.dom, lessThan(250));
        expect(mac.ocr, greaterThan(0.85));
      }
    }
  });
}
