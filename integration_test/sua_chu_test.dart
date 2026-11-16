// Kiểm thử sửa chữ theo khối trên máy: gộp khối, đoán phông, sửa khối dài ra (dời phần dưới), sửa tiêu đề căn giữa,
// đoạn thêm dòng, chặn khối có con dấu; luồng trong kho (lưu, hoàn tác, ghi chú PDF, xử lý lại thì bỏ sửa).
// Trang mẫu mau1-chup-nghieng.jpg in bằng Times New Roman.
// Chạy:  bash integration_test/chay_kiem_thu.sh sua_chu_test.dart
// Ảnh trước, sau khi sửa được lấy ra build/kiem_thu_ra/ (ra.dart) để xem bằng mắt.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'package:xu_ly_pdf_anh/du_lieu/kho.dart';
import 'package:xu_ly_pdf_anh/loi/nhan_dang.dart';
import 'package:xu_ly_pdf_anh/loi/quy_trinh.dart';
import 'package:xu_ly_pdf_anh/loi/sua_chu.dart';
import 'package:xu_ly_pdf_anh/loi/ve_chu.dart';
import 'package:xu_ly_pdf_anh/loi/xuat_pdf.dart';
import 'package:xu_ly_pdf_anh/main.dart' show kho;

import 'chieu_test.dart' show cho;
import 'nhan_dang_test.dart' show tiLeDung;
import 'ra.dart';

/// Ảnh giải mã đúng cỡ (không thu nhỏ): rộng, cao, dữ liệu BGR.
(int, int, Uint8List) docAnh(Uint8List maHoa) {
  final m = cv.imdecode(maHoa, cv.IMREAD_COLOR);
  return (m.cols, m.rows, Uint8List.fromList(m.data));
}

/// Số điểm ảnh khác nhau giữa hàng [y0, y1) của ảnh mới và hàng lệch [dy] của ảnh cũ.
int soKhac(Uint8List cu, Uint8List moi, int w, int y0, int y1, {int dy = 0}) {
  var n = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = 0; x < w * 3; x += 3) {
      final p = y * w * 3 + x, q = (y - dy) * w * 3 + x;
      if (cu[q] != moi[p] || cu[q + 1] != moi[p + 1] || cu[q + 2] != moi[p + 2]) n++;
    }
  }
  return n;
}

/// Khung mực (điểm tối, xám < 128) trong dải hàng [y0, y1): (x0, x1) hoặc null.
(int, int)? khungMucNgang(Uint8List bgr, int w, int y0, int y1) {
  var x0 = w, x1 = -1;
  for (var y = y0; y < y1; y++) {
    for (var x = 0; x < w; x++) {
      final p = (y * w + x) * 3;
      if (0.114 * bgr[p] + 0.587 * bgr[p + 1] + 0.299 * bgr[p + 2] < 128) {
        x0 = math.min(x0, x);
        x1 = math.max(x1, x);
      }
    }
  }
  return x1 < 0 ? null : (x0, x1 + 1);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late String thuMuc, tam;
  late Uint8List anh;
  late TrangChu trang;
  late List<KhoiChu> khoi;

  KhoiChu khoiCo(String chu) => khoi.firstWhere((k) => k.chu.contains(chu), orElse: () => throw StateError('không thấy khối "$chu"'));

  /// Chữ nhận dạng lại (Tesseract thật, không dùng đệm) của các dòng nằm trong dải hàng [y0, y1).
  Future<(TrangChu, String)> docLai(String ten, Uint8List png, double y0, double y1) async {
    final tep = '$tam/$ten';
    await File(tep).writeAsBytes(png, flush: true);
    final kq = await nhanDangAnh(tep);
    final vb = [for (final d in kq.dong) if ((d.y0 + d.y1) / 2 >= y0 && (d.y0 + d.y1) / 2 < y1) d.vanBan].join(' ');
    return (kq, vb);
  }

  setUpAll(() async {
    thuMuc = '${(await getApplicationDocumentsDirectory()).path}/kiem_thu';
    tam = (await getTemporaryDirectory()).path;
    final kq = xuLyAnh(await File('$thuMuc/mau1-chup-nghieng.jpg').readAsBytes(), TuyChon(catSatChu: false));
    anh = kq.trang.first;
    await File('$tam/sc_trang.jpg').writeAsBytes(anh, flush: true);
    trang = await nhanDangAnh('$tam/sc_trang.jpg');
    khoi = timKhoi(trang);
    await ghiRa('sc_0_goc.jpg', anh);
  });

  test('(a) gộp khối: tiêu đề căn giữa, đoạn nhiều dòng', () {
    for (final k in khoi) {
      // ignore: avoid_print
      print('KQ khối: ${k.dong.length} dòng, ${k.can}, thụt ${k.thutDau.toStringAsFixed(0)}, khoảng dòng '
          '${k.khoangDong.toStringAsFixed(1)}, ngang ${k.xTrai.round()}–${k.xPhai.round()} · ${k.chu}');
    }
    final tieuDe = khoiCo('CÔNG VĂN');
    expect(tieuDe.dong.length, 1);
    expect(tieuDe.can, 'giua');
    final quocHieu = khoiCo('CỘNG HÒA');
    expect(quocHieu.dong.length, 2);
    expect(quocHieu.can, 'giua');
    expect(quocHieu.chu, contains('NAM\nĐộc lập')); // hai dòng quốc hiệu ngắt cứng: giữ xuống dòng
    expect(khoiCo('gửi: Thư viện').dong.length, 1);
    expect(khoiCo('gửi: Thư viện').can, 'trai');
    final doan = khoiCo('Tài liệu gồm');
    expect(doan.dong.length, 3);
    expect(doan.chu, contains('Yêu cầu bản số hóa'));
    expect(doan.khoangDong, inInclusiveRange(1.2 * doan.coChu, 3 * doan.coChu));
  });

  test('(f) đoán phông: Liberation Serif (trang in Times New Roman)', () async {
    final kq = <String, KieuChu>{};
    for (final ten in ['gửi: Thư viện', 'Căn cứ', 'Tài liệu gồm', 'Trân trọng', 'CỘNG HÒA', 'CÔNG VĂN', 'NG PHÒNG']) {
      final sw = Stopwatch()..start();
      final kc = kq[ten] = await doKieuChu(anh, khoiCo(ten));
      // ignore: avoid_print
      print('KQ phông "$ten": ${kc.phong.ten}, cỡ ${kc.co.toStringAsFixed(1)} px ≈ ${kc.coPt(trang.rong).toStringAsFixed(1)} pt, '
          'khớp ${kc.diem.toStringAsFixed(3)}, viền ${kc.vien.toStringAsFixed(2)}, màu ${kc.mau}, lệch chân ${kc.lechChan.toStringAsFixed(1)}, '
          '${sw.elapsedMilliseconds} ms');
    }
    for (final MapEntry(key: ten, value: kc) in kq.entries) {
      expect(kc.phong.coChan, isTrue, reason: ten);
      expect(kc.phong.nghieng, isFalse, reason: ten);
      expect(kc.phong.dam, ten.toUpperCase() == ten, reason: ten); // trang mẫu: chữ hoa in đậm, thân bài in thường
    }
  });

  test('(b) sửa "Kính gửi" dài ra: đọc lại ra chữ mới, phần trên giữ nguyên, phần dưới dời nguyên vẹn', () async {
    final k = khoiCo('gửi: Thư viện');
    const moi = 'Kính gửi: Thư viện Trường Đại học Hà Nội và Phòng Quản trị Thiết bị, Trường Đại học Hà Nội';
    final sw = Stopwatch()..start();
    final kq = await suaKhoi(anh, trang, k, moi);
    final ms = sw.elapsedMilliseconds;
    await ghiRa('sc_b_kinh_gui.png', kq.anh);
    final (w, h, cu) = docAnh(anh);
    final (w2, h2, sau) = docAnh(kq.anh);
    expect((w2, h2), (w, h));
    final tren = (k.y0 - 0.6 * k.coChu).floor();
    final khacTren = soKhac(cu, sau, w, 0, tren);
    final khacDuoi = soKhac(cu, sau, w, kq.yCat + kq.dy, h, dy: kq.dy);
    final moiK = timKhoi(kq.chu).firstWhere((x) => x.chu.contains('gửi: '));
    final (doc, vb) = await docLai('sc_b.png', kq.anh, moiK.y0 - 5, moiK.y1 + 5);
    final dung = tiLeDung(vb, moi);
    // ignore: avoid_print
    print('KQ (b): ${kq.soDongCu} → ${kq.soDongMoi} dòng, dời ${kq.dy} px từ hàng ${kq.yCat}, ${kq.kieu.phong.ten}, $ms ms; '
        'khác phía trên $khacTren, khác phần dời $khacDuoi; đọc lại "$vb" (đúng ${(dung * 100).toStringAsFixed(1)}%)');
    expect(kq.soDongMoi, 2);
    expect(kq.dy, (k.khoangDong).round());
    expect(khacTren, 0);
    expect(khacDuoi, 0);
    expect(dung, greaterThan(0.95));
    // các khối bên dưới vẫn đọc như trước khi dời
    final duoiCu = [for (final d in trang.dong) if (d.y0 >= kq.yCat) d.vanBan].join(' ');
    final duoiMoi = [for (final d in doc.dong) if (d.y0 >= kq.yCat + kq.dy - 3) d.vanBan].join(' ');
    final dungDuoi = tiLeDung(duoiMoi, duoiCu);
    // ignore: avoid_print
    print('KQ (b) phần dời: đọc lại trùng bản cũ ${(dungDuoi * 100).toStringAsFixed(1)}%');
    expect(dungDuoi, greaterThan(0.97));
    // chữ của trang mới tự dựng (lưu đệm) khớp vị trí đọc lại
    final dongCan = kq.chu.dong.firstWhere((d) => d.vanBan.startsWith('Căn cứ'));
    final docCan = doc.dong.firstWhere((d) => d.vanBan.startsWith('Căn cứ'));
    expect((dongCan.y0 - docCan.y0).abs(), lessThan(4));
  });

  test('(c) sửa tiêu đề căn giữa: vẫn ở giữa', () async {
    final k = khoiCo('CÔNG VĂN');
    final dk = doKhoi(anh, k);
    final cuK = dk.khungMuc.first!;
    final kq = await suaKhoi(anh, trang, k, 'CÔNG VĂN ĐỀ NGHỊ SỐ HÓA TÀI LIỆU LƯU TRỮ');
    await ghiRa('sc_c_tieu_de.png', kq.anh);
    final (w, _, sau) = docAnh(kq.anh);
    final ngang = khungMucNgang(sau, w, (k.y0 - 0.5 * k.coChu).round(), (k.y1 + 0.3 * k.coChu).round())!;
    final tamCu = (cuK[0] + cuK[2]) / 2, tamMoi = (ngang.$1 + ngang.$2) / 2;
    // ignore: avoid_print
    print('KQ (c): tâm cũ ${tamCu.toStringAsFixed(1)} (${cuK[0]}–${cuK[2]}), tâm mới ${tamMoi.toStringAsFixed(1)} '
        '(${ngang.$1}–${ngang.$2}), lệch ${(tamMoi - tamCu).abs().toStringAsFixed(1)} px, ${kq.kieu.phong.ten}');
    expect(kq.dy, 0);
    expect(ngang.$2 - ngang.$1, greaterThan(cuK[2] - cuK[0] + 50));
    expect((tamMoi - tamCu).abs(), lessThanOrEqualTo(3));
  });

  test('(d) đoạn dài ra thêm dòng: phần dưới dời xuống, không chồng chữ', () async {
    final k = khoiCo('Tài liệu gồm');
    final moi = '${k.chu} Bản số hóa lưu ở dạng PDF/A.';
    final kq = await suaKhoi(anh, trang, k, moi);
    await ghiRa('sc_d_doan.png', kq.anh);
    final (w, h, cu) = docAnh(anh);
    final (_, _, sau) = docAnh(kq.anh);
    final khacDuoi = soKhac(cu, sau, w, kq.yCat + kq.dy, h, dy: kq.dy);
    final moiK = timKhoi(kq.chu).firstWhere((x) => x.chu.startsWith('Tài liệu gồm'));
    final (doc, vb) = await docLai('sc_d.png', kq.anh, moiK.y0 - 5, moiK.y1 + 5);
    final dung = tiLeDung(vb, moi.replaceAll('\n', ' '));
    // các dòng chữ đọc lại không chồng lên nhau theo chiều dọc
    final dong = [...doc.dong]..sort((a, b) => a.y0.compareTo(b.y0));
    var chong = 0;
    for (var i = 1; i < dong.length; i++) {
      final a = dong[i - 1], b = dong[i];
      final cungCot = math.min(a.x1, b.x1) > math.max(a.x0, b.x0);
      if (cungCot && b.y0 < a.y1 - 3) chong++;
    }
    // ignore: avoid_print
    print('KQ (d): ${kq.soDongCu} → ${kq.soDongMoi} dòng, dời ${kq.dy} px, khác phần dời $khacDuoi, chồng $chong, '
        'đọc lại đúng ${(dung * 100).toStringAsFixed(1)}%');
    expect(kq.soDongMoi, kq.soDongCu + 1);
    expect(kq.dy, k.khoangDong.round());
    expect(khacDuoi, 0);
    expect(chong, 0);
    expect(dung, greaterThan(0.93));
    expect(doc.vanBan, contains('Đề nghị hoàn thành'));
  });

  test('(e) khối có con dấu, chữ ký bị từ chối', () async {
    final khoa = kiemMucMau(anh, khoi);
    final biKhoa = [for (var i = 0; i < khoi.length; i++) if (khoa[i]) khoi[i].chu];
    // ignore: avoid_print
    print('KQ (e): khối bị khóa: $biKhoa');
    final but = khoiCo('giao Thư viện');
    expect(khoa[khoi.indexOf(but)], isTrue);
    expect(khoa[khoi.indexOf(khoiCo('gửi: Thư viện'))], isFalse);
    expect(khoa[khoi.indexOf(khoiCo('Tài liệu gồm'))], isFalse);
    await expectLater(suaKhoi(anh, trang, but, 'Không đồng ý'), throwsA(isA<LoiSuaChu>()));
  });

  test('kho: lưu ảnh sửa, đệm chữ, ghi chú PDF, hoàn tác, xử lý lại thì bỏ sửa', () async {
    await kho.mo();
    final h = await kho.taoHoSo();
    final t = await kho.themAnh(h, await File('$thuMuc/mau1-chup-nghieng.jpg').readAsBytes());
    await cho(() => t.trangThai == 'xong');
    final tep0 = t.tepKq.first, nho0 = t.tepNho;
    final chu = await kho.nhanDang(h, tep0);
    final k = timKhoi(chu).firstWhere((x) => x.chu.contains('gửi: '));
    final kq = await suaKhoi(await File(kho.duongDan(h, tep0)).readAsBytes(), chu, k, 'Kính gửi: Phòng Hành chính');
    await kho.ghiSuaChu(h, t, 0, kq.anh, kq.chu);
    final tep1 = t.tepKq.first;
    expect(tep1, isNot(tep0));
    expect(tep1, endsWith('.png'));
    expect(t.tepNho, isNot(nho0));
    expect(h.soChoSua, 1);
    final luu = HoSo.fromJson(jsonDecode(await File(kho.duongDan(h, 'ho_so.json')).readAsString()) as Map);
    expect(luu.trang.first.lichSuSua, [(0, tep0)]);
    expect((await kho.nhanDang(h, tep1)).vanBan, contains('Kính gửi: Phòng Hành chính'));
    final pdf = await taoPdf([await File(kho.duongDan(h, tep1)).readAsBytes()], soChoSua: h.soChoSua);
    final pdfChu = latin1.decode(pdf);
    expect(pdfChu, contains('/Subject'));
    expect(ghiChuSua(1), 'Đã chỉnh sửa nội dung bằng Xử lý PDF ảnh: 1 chỗ sửa chữ');

    await kho.hoanTacSua(h, t);
    expect(t.tepKq.first, tep0);
    expect(h.soChoSua, 0);
    expect(await File(kho.duongDan(h, tep1)).exists(), isFalse);

    // sửa lại rồi xử lý lại trang: chỗ sửa mất, tệp sửa bị xóa
    await kho.ghiSuaChu(h, t, 0, kq.anh, kq.chu);
    final tep2 = t.tepKq.first;
    kho.xuLy(h, t);
    await cho(() => t.trangThai == 'xong');
    expect(t.daSuaNoiDung, isFalse);
    expect(await File(kho.duongDan(h, tep2)).exists(), isFalse);
    expect(await File(kho.duongDan(h, tep0)).exists(), isFalse);
    await kho.xoaHoSo(h);
    await xongRa();
  });
}
