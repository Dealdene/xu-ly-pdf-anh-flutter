// Kiểm thử đoán chiều chữ và xoay trang trên máy: Tesseract psm 1 với trang xoay 4 góc; luồng trong kho
// (nhập trang ngược → tự phát hiện → Xoay toàn bộ → đúng chiều; xoay giữ khung cắt tay).
// Chạy:  bash integration_test/chay_kiem_thu.sh chieu_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'package:xu_ly_pdf_anh/du_lieu/kho.dart';
import 'package:xu_ly_pdf_anh/loi/anh.dart';
import 'package:xu_ly_pdf_anh/loi/nan_phang.dart';
import 'package:xu_ly_pdf_anh/loi/quy_trinh.dart';
import 'package:xu_ly_pdf_anh/main.dart' show kho;

Future<void> cho(bool Function() xong, {int giay = 60}) async {
  for (var i = 0; i < giay * 10 && !xong(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(xong(), isTrue, reason: 'quá $giay giây');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late String thuMuc, tam;

  setUpAll(() async {
    thuMuc = '${(await getApplicationDocumentsDirectory()).path}/kiem_thu';
    tam = (await getTemporaryDirectory()).path;
  });

  test('đoán chiều chữ trang xoay 0°, 90°, 180°, 270°', () async {
    final kq = xuLyAnh(await File('$thuMuc/mau1-chup-nghieng.jpg').readAsBytes(), TuyChon(catSatChu: false));
    final trang = giaiMa(kq.trang.first);
    for (final goc in [0, 90, 180, 270]) {
      // xoay ngược chiều kim đồng hồ `goc` độ: cần xoay lại `goc` độ cùng chiều kim đồng hồ
      final lech = xoay90(trang, (360 - goc) % 360);
      final tep = '$tam/chieu_$goc.jpg', nho = '$tam/chieu_${goc}_nho.png';
      cv.imwrite(tep, lech);
      final sw = Stopwatch()..start();
      ghiAnhKiemChieu(tep, nho);
      final (doan, soTu) = (await nhanDangAnh(nho, psm: 1)).gocXoay;
      // ignore: avoid_print
      print('KQ chieu: lệch $goc°, đoán $doan°, $soTu từ, ${sw.elapsedMilliseconds} ms');
      expect(doan, goc);
      expect(soTu, greaterThan(50));
    }
  });

  test('kho: trang ngược, trang chụp cầm máy ngang tự xoay đúng chiều; người dùng tự xoay thì giữ; xoay giữ khung cắt tay',
      () async {
    await kho.mo();
    final h = await kho.taoHoSo();
    final goc = cv.imread('$thuMuc/mau1-chup-nghieng.jpg');
    late TrangTL t;
    for (final g in [90, 270, 180]) {
      t = await kho.themAnh(h, maHoa(xoay90(goc, g)));
      // tự xoay: dòng chữ dọc xoay về ngang khi xử lý; ngược thì kho tự lật sau khi Tesseract đoán chiều
      await cho(() => t.daKiemChieu && t.goiYXoay == 0);
      final xoayChu = t.xoayChu, daTuLat = t.daTuLat;
      t.pbGoiY = -1; // đoán lại thật trên ảnh kết quả cuối
      await kho.kiemChieu(h, t);
      // ignore: avoid_print
      print('KQ kho lệch $g°: tự xoay dọc $xoayChu°, tự lật $daTuLat, đoán lại ${t.goiYXoay}°, ${t.rongKq}x${t.caoKq}');
      expect(t.goiYXoay, 0);
      expect(h.canhBao(t), isEmpty);
      expect(t.caoKq, greaterThan(t.rongKq));
      if (g == 180) expect(daTuLat, isTrue);
      if (g != 180) expect(xoayChu, 90);
    }
    expect(await kho.xoayToanBo(h, 'chu'), 0);

    // khung cắt tay xoay theo trang: kết quả vẫn là trang A4 đúng chữ, chỉ đổi chiều
    // (đo trên trang không cắt sát chữ: vùng chữ dựng trên trang nằm ngang khác trang đứng vài phần trăm)
    t.tc.catSatChu = false;
    kho.xuLy(h, t);
    await cho(() => t.daKiemChieu);
    final (rong, cao) = (t.rongKq, t.caoKq);
    t.khungTay = [...t.khungDung!];
    kho.xoayTrang(h, t, 90);
    await cho(() => t.trangThai == 'xong');
    // ignore: avoid_print
    print('KQ khung tay: trước ${rong}x$cao, sau xoay 90° ${t.rongKq}x${t.caoKq}, gợi ý ${t.goiYXoay}°');
    expect((t.rongKq - cao).abs(), lessThan(cao * 0.02));
    expect((t.caoKq - rong).abs(), lessThan(rong * 0.02));
    expect(t.goiYXoay, 270); // đã biết chiều: không đoán lại, suy ra từ góc vừa xoay
    expect(h.canhBao(t), contains('Chữ nằm nghiêng 90°'));

    // ép khổ dọc: trang đang nằm ngang (chữ nghiêng) xoay về đứng thẳng, không còn cảnh báo
    expect(await kho.xoayToanBo(h, 'doc'), 1);
    await cho(() => t.trangThai == 'xong');
    expect(t.caoKq, greaterThan(t.rongKq));
    expect(h.canhBao(t), isEmpty);
    await kho.xoaHoSo(h);
  });
}
