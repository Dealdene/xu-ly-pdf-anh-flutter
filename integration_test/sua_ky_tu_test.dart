// Kiểm thử Sửa ký tự giữ nguyên bản gốc trên máy (như kiem_sua_ky_tu của bản PC, ung-dung/kiem_thu/kiem_thu_sua_pdf.py):
// - công văn mau1-chup-nghieng.jpg (qua xuLyAnh): "ngày 15 tháng 12" → "ngày 20 tháng 12", ngoài dải dòng và phần dòng
//   trước chỗ sửa giữ nguyên từng điểm ảnh, "2", "0" chép từ chính trang, phần sau dời đúng bằng chênh bề rộng;
// - trang mục lục mau5-muc-luc.png (như trang_muc_luc() của bản PC): dãy chấm dẫn nhận theo hình dạng, bỏ số cuối
//   "156" → "15" thì số trang vẫn căn phải, dãy chấm giãn ra; chèn "các " trước "Mục tiêu" thì số trang đứng nguyên chỗ,
//   chữ chèn đúng cỡ, đúng đường chân;
// - mẫu từ trang khác, mẫu tay, vẽ bằng phông; dòng có mực màu; luồng trong kho (lưu, đệm, ghi chú PDF, hoàn tác);
// - trang chụp lệch mau6-dong-nghieng.png (như trang_nghieng() của bản PC, dòng sát nhau xoay 2,5°): đo độ nghiêng,
//   chèn chữ thì nét dòng trên, dòng dưới không đổi, ký tự chèn đứng đúng đường chân xiên, sửa tiếp được;
// - nhãn hàng mờ mau7-dam-nhat.png (như trang_dam_nhat() bản PC, dòng chữ thường xen dòng chữ đậm): gõ tiếng Việt kiểu
//   dấu rời, chữ chèn cùng độ đậm chữ thường quanh chỗ chèn (không lấy mẫu ở dòng đậm), "é" thiếu thì ghép dấu.
// Chạy:  bash integration_test/chay_kiem_thu.sh sua_ky_tu_test.dart
// Ảnh trước, sau được lấy ra build/kiem_thu_ra/sk_* (ra.dart) để xem bằng mắt.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xu_ly_pdf_anh/du_lieu/kho.dart';
import 'package:xu_ly_pdf_anh/loi/quy_trinh.dart';
import 'package:xu_ly_pdf_anh/loi/sua_ky_tu.dart';
import 'package:xu_ly_pdf_anh/loi/ve_chu.dart';
import 'package:xu_ly_pdf_anh/loi/xuat_pdf.dart';
import 'package:xu_ly_pdf_anh/main.dart' show kho;

import 'chieu_test.dart' show cho;
import 'ra.dart';

// ignore: avoid_print
void inKq(String s) => print('KQ $s');

String gon(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Số điểm ảnh khác nhau giữa hai ảnh cùng cỡ trong hàng [y0, y1), cột [x0, x1) (ảnh [b] lệch ngang [dx]).
int soKhac(AnhBgr a, AnhBgr b, int y0, int y1, int x0, int x1, {int dx = 0}) {
  var n = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final p = (y * a.w + x) * 3, q = (y * b.w + x + dx) * 3;
      if (a.bgr[p] != b.bgr[q] || a.bgr[p + 1] != b.bgr[q + 1] || a.bgr[p + 2] != b.bgr[q + 2]) n++;
    }
  }
  return n;
}

/// Số điểm mực (xám < 160) của [a] trong hàng [y0, y1), cột [x0, x1) không còn nguyên ở chỗ lệch (dx, dy) trên [b]:
/// khi dời, chỉ nét chữ đi theo, nền giữ tại chỗ.
int soKhacNet(AnhBgr a, AnhBgr b, int y0, int y1, int x0, int x1, {int dx = 0, int dy = 0}) {
  var n = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      if (a.xam(x, y) >= 160) continue;
      final p = (y * a.w + x) * 3, q = ((y + dy) * b.w + x + dx) * 3;
      if (a.bgr[p] != b.bgr[q] || a.bgr[p + 1] != b.bgr[q + 1] || a.bgr[p + 2] != b.bgr[q + 2]) n++;
    }
  }
  return n;
}

/// Khung mực (xám < 128) trong vùng: (x0, y0, x1, y1) không gồm cạnh phải, dưới; null nếu không có mực.
(int, int, int, int)? khungMuc(AnhBgr a, int x0, int y0, int x1, int y1) {
  var l = 1 << 30, t = 1 << 30, r = -1, b = -1;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      if (a.xam(x, y) < 128) {
        l = math.min(l, x);
        r = math.max(r, x);
        t = math.min(t, y);
        b = math.max(b, y);
      }
    }
  }
  return r < 0 ? null : (l, t, r + 1, b + 1);
}

/// Ghép dọc các ảnh cùng bề rộng (ảnh trước, sau để xem bằng mắt).
AnhBgr ghepDoc(List<AnhBgr> ds) {
  final b = BytesBuilder();
  for (final a in ds) {
    b.add(a.bgr);
  }
  return AnhBgr(ds.first.w, ds.fold(0, (s, a) => s + a.h), b.toBytes());
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late String thuMuc, tam;
  late Uint8List maCv;
  late AnhBgr cv, ml;
  late TrangKyTu ktCv, ktMl;

  /// Nhận dạng lại (Tesseract thật) một ảnh: văn bản thuần, gọn khoảng trắng.
  Future<String> docLai(String ten, AnhBgr a, {int psm = 3}) async {
    final tep = '$tam/$ten';
    await File(tep).writeAsBytes(a.png(), flush: true);
    return gon((await nhanDangAnh(tep, psm: psm)).vanBan);
  }

  DongAnh dongCo(TrangKyTu t, String chu) =>
      t.dong.firstWhere((d) => d.chu.contains(chu), orElse: () => throw StateError('không thấy dòng "$chu"'));

  setUpAll(() async {
    thuMuc = '${(await getApplicationDocumentsDirectory()).path}/kiem_thu';
    tam = (await getTemporaryDirectory()).path;
    maCv = xuLyAnh(await File('$thuMuc/mau1-chup-nghieng.jpg').readAsBytes(), TuyChon(catSatChu: false)).trang.first;
    await File('$tam/sk_trang.jpg').writeAsBytes(maCv, flush: true);
    var sw = Stopwatch()..start();
    ktCv = await docKyTuAnh('$tam/sk_trang.jpg');
    inKq('nhận dạng khung ký tự công văn ${ktCv.rong}×${ktCv.cao}: ${ktCv.dong.length} dòng, khe ${ktCv.khe}, ${sw.elapsedMilliseconds} ms');
    cv = AnhBgr.giaiMa(maCv);
    sw = Stopwatch()..start();
    ktMl = await docKyTuAnh('$thuMuc/mau5-muc-luc.png');
    inKq('nhận dạng khung ký tự mục lục ${ktMl.rong}×${ktMl.cao}: ${ktMl.dong.length} dòng, ${sw.elapsedMilliseconds} ms');
    ml = AnhBgr.docTep('$thuMuc/mau5-muc-luc.png');
    for (final d in [...ktCv.dong, ...ktMl.dong]) {
      inKq('  dòng [${d.x0},${d.y0}–${d.x1},${d.y1}] dải ${d.dai0}–${d.dai1} chân ${d.chan.toStringAsFixed(1)} cỡ ${d.co.toStringAsFixed(1)} '
          'đậm ${d.dam.toStringAsFixed(3)}${d.mucMau ? ' MỰC MÀU' : ''}: ${d.chu}');
    }
  });

  test('(a) đọc hOCR có khung ký tự, quy tọa độ về ảnh gốc', () {
    const hocr = '''<span class='ocr_line' id='line_1_1' title="bbox 100 200 500 260; baseline 0 -10; x_size 40">
<span class='ocrx_word' id='word_1_1' title='bbox 100 200 220 250; x_wconf 95'>
<span class='ocrx_cinfo' title='x_bboxes 100 210 140 250; x_conf 98.5'>n</span><span class='ocrx_cinfo' title='x_bboxes 150 200 190 250; x_conf 97'>g</span></span>
<span class='ocrx_word' id='word_1_2' title='bbox 300 205 500 250; x_wconf 91'>
<span class='ocrx_cinfo' title='x_bboxes 300 205 340 249; x_conf 80'>&amp;</span></span></span>''';
    final d = docHocrKyTu(hocr, 1000, 2.0);
    expect(d.length, 1);
    expect(d.first.tu.length, 2);
    expect(d.first.chu, 'ng &');
    final n = d.first.tu.first.first;
    expect((n.x0, n.y0, n.x1, n.y1), (50, 105, 71, 126)); // chia 2, cạnh phải, dưới +1 rồi mới chia
    expect(n.tinCay, 98.5);
    expect(d.first.dai0 < d.first.y0 && d.first.dai1 > d.first.y1, isTrue);
    final ngay = dongCo(ktCv, 'tháng 12');
    expect(ngay.chu, contains('ngày 15 tháng 12'));
    for (final dd in ktCv.dong) {
      expect(dd.dai0 < dd.dai1 && dd.dai0 >= 0 && dd.dai1 <= ktCv.cao, isTrue);
    }
  });

  test('(b) "ngày 15 tháng 12" → "ngày 20 tháng 12": giữ nguyên điểm ảnh ngoài chỗ sửa, "2", "0" chép từ chính trang', () async {
    final d = dongCo(ktCv, 'tháng 12');
    final p = PhienSuaDong(cv, ktCv, d);
    final so15 = [for (var i = 1; i < p.manh.length; i++) i].firstWhere((i) => p.manh[i].chu == '5' && p.manh[i - 1].chu == '1');
    p.conTro = so15 + 1;
    p.xoaLui();
    p.xoaLui();
    final sw = Stopwatch()..start();
    await p.go('20');
    final ms = sw.elapsedMilliseconds;
    final tt = p.thaoTac();
    final ra = tt.ap(cv);
    final y0 = d.dai0, y1 = d.dai1;
    final ngoai = soKhac(cv, ra, 0, y0, 0, cv.w) + soKhac(cv, ra, y1, cv.h, 0, cv.w);
    final xSua = p.x0 + p.goc.take(so15 - 1).fold<int>(0, (s, m) => s + m.rong);
    final truoc = soKhac(cv, ra, y0, y1, 0, xSua);
    final moi = [for (final m in tt.manh) if (m.loai != 'goc') m];
    final xSau = xSua + p.goc.skip(so15 - 1).take(2).fold<int>(0, (s, m) => s + m.rong);
    final lech = tt.manh.skip(so15 - 1).take(2).fold<int>(0, (s, m) => s + m.rong) - (xSau - xSua);
    final sau = soKhacNet(cv, ra, y0, y1, xSau, p.x1Cu, dx: lech, dy: (d.nghieng * lech).round());
    final vb = await docLai('sk_b.png', ra.cat(0, y0, ra.w, y1));
    inKq('(b) chèn "20" $ms ms; khác ngoài dải dòng $ngoai, khác phần trước chỗ sửa $truoc (x < $xSua), mảnh mới '
        '${[for (final m in moi) '${m.chu}:${m.loai}${m.chuaChac ? '?' : ''}×${m.tiLe.toStringAsFixed(2)}']}, phần sau dời $lech px khác $sau; '
        'đọc lại "$vb"');
    await ghiRa('sk_b_ngay.png', ghepDoc([cv.cat(0, y0, cv.w, y1), ra.cat(0, y0, cv.w, y1)]).png());
    expect(ngoai, 0);
    expect(truoc, 0);
    expect(moi.map((m) => m.chu).join(), '20');
    expect(moi.every((m) => m.loai == 'chep' && !m.chuaChac), isTrue);
    expect(sau, 0);
    expect(vb, contains('ngày 20 tháng 12'));
  });

  test('(c) mục lục: dãy chấm theo hình dạng; "156" → "15" số trang vẫn căn phải, dãy chấm giãn ra', () async {
    final d = dongCo(ktMl, 'Phương');
    final p = PhienSuaDong(ml, ktMl, d);
    final soCham = p.goc.where((m) => m.chu == '.').length;
    p.cuoiDong();
    p.xoaLui();
    final tt = p.thaoTac();
    final ra = tt.ap(ml);
    final y0 = d.dai0, y1 = d.dai1;
    final cu = khungMuc(ml, 0, y0, ml.w, y1)!, moi = khungMuc(ra, 0, y0, ra.w, y1)!;
    final soChamMoi = tt.manh.where((m) => m.chu == '.').length;
    // Tesseract bỏ qua số đứng lẻ ở mép phải khi đọc cả dòng: đọc riêng vùng số trang (sau chấm cuối dãy)
    final cuoiCham = tt.manh.lastIndexWhere((m) => m.chu == '.');
    final xSo = tt.x0 + tt.manh.take(cuoiCham + 1).fold<int>(0, (s, m) => s + m.rong);
    final vb = await docLai('sk_c.png', ra.cat(xSo, y0, ra.w, y1), psm: 7);
    inKq('(c) "${d.chu}": $soCham chấm → $soChamMoi, mép phải mực ${cu.$3} → ${moi.$3} (lệch ${moi.$3 - cu.$3} px), '
        'đọc lại số trang "$vb", con trỏ ở x ${p.xConTro()}');
    expect(soCham, greaterThanOrEqualTo(20));
    expect((moi.$3 - cu.$3).abs(), lessThanOrEqualTo(2));
    expect(soChamMoi, greaterThan(soCham));
    expect(vb.replaceAll(' ', ''), '15');
    expect((p.xConTro() - moi.$3).abs(), lessThanOrEqualTo(3)); // con trỏ cuối dòng ở ngay sau số trang
    await ghiRa('sk_c_muc_luc.png', ghepDoc([ml, ra]).png());
  });

  test('(d) mục lục: chèn "các " trước "Mục tiêu": số trang đứng nguyên, chữ chèn đúng cỡ, đúng đường chân', () async {
    final d = dongCo(ktMl, 'Mục');
    final p = PhienSuaDong(ml, ktMl, d);
    final k0 = p.manh.indexWhere((m) => m.chu == 'M');
    p.conTro = k0;
    await p.go('các ');
    final tt = p.thaoTac();
    final ra = tt.ap(ml);
    final y0 = d.dai0, y1 = d.dai1;
    final cu = khungMuc(ml, 0, y0, ml.w, y1)!, moi = khungMuc(ra, 0, y0, ra.w, y1)!;
    // chữ "c" chèn so với chữ "c" gốc của "Mục"
    final xc = tt.x0 + tt.manh.take(k0).fold<int>(0, (s, m) => s + m.rong);
    final cMoi = khungMuc(ra, xc, y0, xc + tt.manh[k0].rong, y1)!;
    final mc = p.goc.firstWhere((m) => m.chu == 'c');
    final cGoc = khungMuc(ml, mc.x0, y0, mc.x1, y1)!;
    final vb = await docLai('sk_d.png', ra.cat(0, y0, ra.w, y1));
    final nguon = [for (final m in tt.manh.skip(k0).take(4)) '${m.chu}:${m.loai}${m.chuaChac ? '?' : ''}'];
    inKq('(d) mép phải ${cu.$3} → ${moi.$3}; "c" chèn cao ${cMoi.$4 - cMoi.$2} đáy ${cMoi.$4}, "c" gốc cao ${cGoc.$4 - cGoc.$2} '
        'đáy ${cGoc.$4}; mảnh $nguon; đọc lại "$vb"');
    expect((moi.$3 - cu.$3).abs(), lessThanOrEqualTo(2));
    expect(((cMoi.$4 - cMoi.$2) - (cGoc.$4 - cGoc.$2)).abs(), lessThanOrEqualTo(2));
    expect((cMoi.$4 - cGoc.$4).abs(), lessThanOrEqualTo(2));
    expect(vb, contains('1.1. các Mục tiêu'));
    await ghiRa('sk_d_chen.png', ghepDoc([ml.cat(0, y0, ml.w, y1), ra.cat(0, y0, ml.w, y1)]).png());
  });

  test('(e) ký tự trang không có: chép từ trang khác (chưa chắc), mẫu tay, vẽ bằng phông', () async {
    final d = dongCo(ktMl, 'Mục');
    final khac = [TrangNguon(ktCv.dong, tai: () async => cv)];
    final p = PhienSuaDong(ml, ktMl, d, trangKhac: khac, taoBoVe: () async => boVeKyTu(await File('$thuMuc/mau5-muc-luc.png').readAsBytes(), d));
    p.conTro = p.manh.indexWhere((m) => m.chu == 't'); // trước "tiêu"
    await p.go('y');
    final y = p.manh[p.conTro - 1];
    final xy = p.x0 + p.manh.take(p.conTro - 1).fold<int>(0, (s, m) => s + m.rong);
    final ra = p.thaoTac().ap(ml);
    final kY = khungMuc(ra, xy, d.dai0, xy + y.rong, d.dai1);
    inKq('(e) "y" từ trang khác: ${y.loai}, chưa chắc ${y.chuaChac}, tỉ lệ cỡ ${y.tiLe.toStringAsFixed(2)}, khung mực $kY, '
        'cỡ dòng ${d.co.toStringAsFixed(1)}');
    expect(y.loai, 'chep');
    expect(y.chuaChac, isTrue);
    expect(kY, isNotNull);
    // mẫu tay: chọn chữ "u" của chính trang làm mẫu cho "y" (chỉ để thử cơ chế): mọi "y" đã chèn đổi theo, hết chưa chắc
    final u = d.kyTu.firstWhere((c) => c.chu == 'u');
    p.datMau('y', ml, d, u);
    final y2 = p.manh[p.conTro - 1];
    expect(y2.loai, 'chep');
    expect(y2.chuaChac, isFalse);
    expect(y2.mau!.w, lessThan(2 * u.rong + 10));
    // cả hồ sơ không có: vẽ bằng phông, đánh dấu chưa chắc
    await p.go('Ỹ');
    final v = p.manh[p.conTro - 1];
    inKq('(e) "Ỹ": ${v.loai}, chưa chắc ${v.chuaChac}, cỡ ${v.coVe.toStringAsFixed(1)} px, rộng ${v.rong}, thiếu ${p.thieu}');
    expect(v.loai, 've');
    expect(v.chuaChac, isTrue);
    expect(v.hinh, isNotNull);
    expect(p.thieu, contains('Ỹ'));
    final ra2 = p.thaoTac().ap(ml);
    await ghiRa('sk_e_mau.png', ghepDoc([ml.cat(0, d.dai0, ml.w, d.dai1), ra.cat(0, d.dai0, ml.w, d.dai1), ra2.cat(0, d.dai0, ml.w, d.dai1)]).png());
  });

  test('(g) trang chụp lệch: nét dòng bên cạnh giữ nguyên, ký tự chèn đúng đường chân xiên, sửa tiếp được', () async {
    final tep = '$thuMuc/mau6-dong-nghieng.png';
    final anh = AnhBgr.docTep(tep);
    final kt = await docKyTuAnh(tep);
    final d = dongCo(kt, 'Melamine');
    final p = PhienSuaDong(anh, kt, d);
    p.conTro = p.manh.indexWhere((m) => m.chu == ':') + 1;
    final xSua = p.xConTro();
    await p.go(' nhựa ăn');
    final tt = p.thaoTac();
    final ra = tt.ap(anh);
    final y0 = d.dai0, y1 = d.dai1;
    final ngoai = soKhac(anh, ra, 0, y0, 0, anh.w) + soKhac(anh, ra, y1, anh.h, 0, anh.w);
    final (_, khac) = netCuaDong(anh, kt.dong, d, 0, anh.w);
    var dongKhac = 0;
    for (var y = y0; y < y1; y++) {
      for (var x = 0; x < anh.w; x++) {
        if (khac[(y - y0) * anh.w + x] == 0) continue;
        final q = (y * anh.w + x) * 3;
        if (anh.bgr[q] != ra.bgr[q] || anh.bgr[q + 1] != ra.bgr[q + 1] || anh.bgr[q + 2] != ra.bgr[q + 2]) dongKhac++;
      }
    }
    final truoc = soKhac(anh, ra, 0, anh.h, 0, xSua);
    final dai = tt.apDai(anh);
    final xemDung = soKhac(dai, ra.cat(0, y0, ra.w, y1), 0, dai.h, 0, dai.w);
    // đọc lại cả trang: dòng mới đủ chữ, chân ký tự chèn sát đường chân xiên của dòng
    await File('$tam/sk_g.png').writeAsBytes(ra.png(), flush: true);
    final kt2 = await docKyTuAnh('$tam/sk_g.png');
    final d2 = dongCo(kt2, 'Melamine');
    final xHet = xSua + tt.manh.skip(p.conTro - ' nhựa ăn'.length).take(' nhựa ăn'.length).fold<int>(0, (s, m) => s + m.rong);
    final lechChan = [
      for (final c in d2.kyTu)
        if (c.x0 >= xSua && c.x1 <= xHet && 'nhaăn'.contains(c.chu)) c.y1 - d.chanTai((c.x0 + c.x1) / 2)
    ];
    // sửa tiếp trên dòng vừa dựng lại: xóa " ăn"
    final dongMoi = dongSauSua(d, tt);
    final p2 = PhienSuaDong(ra, trangSauSua(kt, d, dongMoi), dongMoi);
    p2.datConTro(xHet.toDouble());
    for (var i = 0; i < 3; i++) {
      p2.xoaLui();
    }
    final ra2 = p2.thaoTac().ap(ra);
    final ngoai2 = soKhac(ra, ra2, 0, y0, 0, ra.w) + soKhac(ra, ra2, y1, ra.h, 0, ra.w);
    await File('$tam/sk_g2.png').writeAsBytes(ra2.png(), flush: true);
    final d3 = dongCo(await docKyTuAnh('$tam/sk_g2.png'), 'Melamine');
    inKq('(g) độ nghiêng ${d.nghieng.toStringAsFixed(4)} (thật −0,0437), dải ${d.dai0}–${d.dai1}; khác ngoài dải $ngoai, '
        'nét dòng khác bị đổi $dongKhac, khác trước chỗ sửa $truoc, xem trước lệch $xemDung; đọc lại "${d2.chu}"; '
        'chân ký tự chèn lệch ${[for (final v in lechChan) v.toStringAsFixed(1)]}; sửa tiếp: khác ngoài dải $ngoai2, đọc lại "${d3.chu}"');
    await ghiRa('sk_g_nghieng.png', ghepDoc([anh.cat(0, 60, anh.w, 420), ra.cat(0, 60, anh.w, 420), ra2.cat(0, 60, anh.w, 420)]).png());
    expect((d.nghieng + 0.0437).abs(), lessThan(0.004));
    expect(ngoai, 0);
    expect(dongKhac, 0);
    expect(truoc, 0);
    expect(xemDung, 0);
    expect(d2.chu, contains('nhựa ăn nhựa Melamine'));
    expect(lechChan.length, greaterThanOrEqualTo(4));
    expect(lechChan.every((v) => v.abs() <= 2.5), isTrue);
    expect(ngoai2, 0);
    expect(d3.chu, contains('nhựa nhựa Melamine'));
  });

  test('(h) gõ tiếng Việt: dấu rời, chữ chèn cùng kiểu nét, đậm nhạt với chữ quanh; chữ có dấu thiếu thì ghép dấu', () async {
    expect(ghepDauRoi('o', '̂'), 'ô');
    expect(ghepDauRoi('ô', '̣'), 'ộ');
    expect(ghepDauRoi('ư', '́'), 'ứ');
    expect(ghepDauRoi('a', '̆'), 'ă');
    expect(tachDau('ố'), ('o', '̂́', ''));
    expect(tachDau('ợ'), ('ơ', '', '̣'));
    final tep = '$thuMuc/mau7-dam-nhat.png';
    final anh = AnhBgr.docTep(tep);
    final kt = await docKyTuAnh(tep);
    final d = dongCo(kt, 'Melamine');
    final p = PhienSuaDong(anh, kt, d);
    p.conTro = p.manh.indexWhere((m) => m.chu == ':') + 1;
    final xSua = p.xConTro();
    final sw = Stopwatch()..start();
    await p.go(' bé dưới bộ');
    final ms = sw.elapsedMilliseconds;
    final moi = [for (final m in p.manh) if (m.loai != 'goc' && m.chu.trim().isNotEmpty) m];
    final tt = p.thaoTac();
    final ra = tt.ap(anh);
    final xHet = p.xConTro();
    await File('$tam/sk_h.png').writeAsBytes(ra.png(), flush: true);
    final kt2 = await docKyTuAnh('$tam/sk_h.png');
    final d2 = dongCo(kt2, 'Melamine');
    final chen = [for (final c in d2.kyTu) if ((c.x0 + c.x1) / 2 >= xSua && (c.x0 + c.x1) / 2 <= xHet && laChuSo(c.chu)) damKyTu(ra, d2, c)];
    final cu = [for (final c in d2.kyTu) if ((c.x0 + c.x1) / 2 > xHet + 5 && laChuSo(c.chu)) damKyTu(ra, d2, c)];
    double trungVi(List<double> v) {
      final t = [...v]..sort();
      return t.isEmpty ? 0 : (t[(t.length - 1) ~/ 2] + t[t.length ~/ 2]) / 2;
    }

    final chuan = trungVi(cu), tv = trungVi(chen);
    final damDam = damDong(dongCo(kt, 'BÁO'), anh);
    inKq('(h) chèn ${moi.map((m) => '${m.chu}:${m.loai}${m.chuaChac ? '?' : ''}').join(' ')} $ms ms; nét chữ chèn '
        '${[for (final v in chen) v.toStringAsFixed(1)]} (trung vị ${tv.toStringAsFixed(1)}) so với chữ thường ${chuan.toStringAsFixed(1)}, '
        'dòng đậm ${damDam.toStringAsFixed(1)}; đọc lại "${d2.chu}"');
    final y0 = d.dai0, y1 = d.dai1;
    await ghiRa('sk_h_go_tieng_viet.png', ghepDoc([anh.cat(0, y0 - 100, anh.w, y1), ra.cat(0, y0 - 100, anh.w, y1)]).png());
    expect(moi.map((m) => m.chu).join(), 'bédướibộ');
    expect(moi.every((m) => m.loai == 'chep'), isTrue);
    expect(chen.length, greaterThanOrEqualTo(6));
    expect((tv / chuan - 1).abs(), lessThanOrEqualTo(0.12));
    expect(chen.every((v) => v < 0.9 * damDam), isTrue);
    expect(d2.chu, contains('bé dư'));
    expect(d2.chu, contains('bộ nhựa'));
  });

  test('(i) đổi cỡ (giữ nét gốc), đổi phông đoạn bôi chọn trên dòng nghiêng', () async {
    final tep = '$thuMuc/mau6-dong-nghieng.png';
    final anh = AnhBgr.docTep(tep);
    final kt = await docKyTuAnh(tep);
    final d = dongCo(kt, 'Melamine');
    final p = PhienSuaDong(anh, kt, d, taoBoVe: () async => boVeKyTu(await File(tep).readAsBytes(), d));
    p.conTro = p.manh.indexWhere((m) => m.chu == ':') + 2; // sau ": "
    for (var i = 0; i < 4; i++) {
      p.phai(chon: true);
    }
    final chon = p.chuChon;
    final kq = await p.kieuDoanChon();
    final (xa0, xa1) = p.xDoanChon();
    final y0 = d.dai0, y1 = d.dai1;
    await p.dinhDangChon(tiLe: 1.5);
    final tt = p.thaoTac();
    final ra = tt.ap(anh);
    final (xb0, xb1) = p.xDoanChon();
    final (v0, v1) = tt.vungVe(anh.h);
    final dai = tt.apDai(anh);
    final xemDung = soKhac(dai, ra.cat(0, v0, ra.w, v1), 0, dai.h, 0, dai.w);
    final truoc = soKhac(anh, ra, 0, anh.h, 0, xa0 - 2);
    final (_, khac) = netCuaDong(anh, kt.dong, d, 0, anh.w);
    var dongKhac = 0;
    for (var y = y0; y < y1; y++) {
      for (var x = 0; x < anh.w; x++) {
        if (khac[(y - y0) * anh.w + x] == 0) continue;
        final q = (y * anh.w + x) * 3;
        if (anh.bgr[q] != ra.bgr[q] || anh.bgr[q + 1] != ra.bgr[q + 1] || anh.bgr[q + 2] != ra.bgr[q + 2]) dongKhac++;
      }
    }
    final h0 = khungMuc(anh, xa0, y0, xa1, y1), h1 = khungMuc(ra, xb0, v0, xb1, v1);
    final coChep = p.manh.sublist(p.doanChon().$1, p.doanChon().$2).every((m) => m.loai == 'chep' && m.coDoi == 1.5);
    await p.dinhDangChon(tiLe: 1.0);
    final traVe = !p.daDoi;
    final (kc, _, _) = kq!;
    final arial = DinhDangVe(5, kc.co, kc.mau, vien: kc.vien); // Liberation Sans đậm
    await p.dinhDangChon(kieu: arial);
    final coPhong = p.manh.sublist(p.doanChon().$1, p.doanChon().$2).every((m) => m.loai == 've' && m.hinh != null);
    p.phai();
    await p.go('X');
    final theoPhong = identical(p.manh[p.conTro - 1].kieuVe, arial);
    final ra2 = p.thaoTac().ap(anh);
    final truoc2 = soKhac(anh, ra2, 0, anh.h, 0, xa0 - 2);
    await File('$tam/sk_i.png').writeAsBytes(ra2.png(), flush: true);
    final d2 = dongCo(await docKyTuAnh('$tam/sk_i.png'), 'Melamine');
    inKq('(i) chọn "$chon"; đoán ${PhongChu.tatCa[kc.phong].ten} ${(kc.co * 72 * 8.2677 / anh.w).toStringAsFixed(1)} pt; '
        'phóng 1,5: rộng ${xa1 - xa0} → ${xb1 - xb0}, cao ${h0 == null ? '?' : h0.$4 - h0.$2} → ${h1 == null ? '?' : h1.$4 - h1.$2}, '
        'vùng vẽ $v0–$v1 (dải $y0–$y1), xem trước lệch $xemDung, khác trước đoạn chọn $truoc, nét dòng khác đổi $dongKhac; '
        'trả về cỡ gốc: ${traVe ? 'như chưa sửa' : 'CÒN KHÁC'}; đổi phông, gõ "X": đọc lại "${d2.chu}", khác trước đoạn chọn $truoc2');
    await ghiRa('sk_i_doi_co_phong.png', ghepDoc([anh.cat(0, 60, anh.w, 420), ra.cat(0, 60, anh.w, 420), ra2.cat(0, 60, anh.w, 420)]).png());
    expect(chon, 'nhựa');
    expect(kq.$3, isFalse);
    expect(coChep, isTrue);
    expect((xb1 - xb0) / (xa1 - xa0), inInclusiveRange(1.3, 1.7));
    expect(v0, lessThan(y0));
    expect(xemDung, 0);
    expect(truoc, 0);
    expect(dongKhac, 0);
    expect(traVe, isTrue);
    expect(coPhong, isTrue);
    expect(theoPhong, isTrue);
    expect(truoc2, 0);
    expect(d2.chu, contains('nhựaX Melamine'));
  });

  test('(f) dòng có mực màu (bút phê, con dấu) bị khóa', () {
    final khoa = [for (final d in ktCv.dong) if (d.mucMau) d.chu];
    inKq('(f) dòng bị khóa: $khoa');
    expect(khoa.any((c) => c.contains('giao Thư viện')), isTrue); // dòng bút phê "Đồng ý, giao Thư viện
    expect(dongCo(ktCv, 'tháng 12').mucMau, isFalse);
    expect(dongCo(ktCv, 'Kính gửi').mucMau, isFalse);
  });

  test('kho: đệm khung ký tự, lưu ảnh sửa, ghi chú PDF "chỗ sửa ký tự", hoàn tác', () async {
    await kho.mo();
    final h = await kho.taoHoSo();
    final t = await kho.themAnh(h, await File('$thuMuc/mau1-chup-nghieng.jpg').readAsBytes());
    await cho(() => t.trangThai == 'xong');
    final tep0 = t.tepKq.first;
    final kt = await kho.nhanDangKyTu(h, tep0);
    expect(await File(kho.duongDan(h, Kho.tepKyTu(tep0))).exists(), isTrue);
    final sw = Stopwatch()..start();
    final kt2 = await kho.nhanDangKyTu(h, tep0); // lần hai đọc đệm
    expect(sw.elapsedMilliseconds, lessThan(1500));
    expect(kt2.dong.length, kt.dong.length);
    final anh = AnhBgr.docTep(kho.duongDan(h, tep0));
    final d = dongCo(kt, 'tháng 12');
    final p = PhienSuaDong(anh, kt, d);
    p.conTro = [for (var i = 1; i < p.manh.length; i++) i].firstWhere((i) => p.manh[i].chu == '5' && p.manh[i - 1].chu == '1') + 1;
    p.xoaLui();
    p.xoaLui();
    await p.go('20');
    final tt = p.thaoTac();
    final moi = dongSauSua(d, tt);
    final chu = await kho.nhanDang(h, tep0);
    await kho.ghiSuaChu(h, t, 0, tt.ap(anh).png(), chuSauSua(chu, d, moi), kyTu: true, dongKyTu: trangSauSua(kt, d, moi));
    final tep1 = t.tepKq.first;
    expect(tep1, endsWith('.png'));
    expect(h.soChoSua, 1);
    expect(h.soSuaKyTu, 1);
    expect((await kho.kyTuDaCo(h, tep1))!.dong.any((x) => x.chu.contains('ngày 20 tháng 12')), isTrue);
    expect((await kho.nhanDang(h, tep1)).vanBan, contains('ngày 20 tháng 12'));
    final luu = HoSo.fromJson(jsonDecode(await File(kho.duongDan(h, 'ho_so.json')).readAsString()) as Map);
    expect(luu.trang.first.suaKyTu, [true]);
    expect(luu.soSuaKyTu, 1);
    expect(ghiChuSua(1, kyTu: 1), 'Đã chỉnh sửa nội dung bằng Xử lý PDF ảnh: 1 chỗ sửa ký tự');
    expect(ghiChuSua(3, kyTu: 2), 'Đã chỉnh sửa nội dung bằng Xử lý PDF ảnh: 2 chỗ sửa ký tự, 1 chỗ sửa chữ');
    final pdf = await taoPdf([await File(kho.duongDan(h, tep1)).readAsBytes()], soChoSua: h.soChoSua, soSuaKyTu: h.soSuaKyTu);
    expect(latin1.decode(pdf), contains('/Subject'));
    // sửa tiếp ngay trên dòng mới dựng (không nhận dạng lại): đổi "20" → "21"
    final kt1 = (await kho.kyTuDaCo(h, tep1))!;
    final anh1 = AnhBgr.docTep(kho.duongDan(h, tep1));
    final d1 = dongCo(kt1, 'tháng 12');
    final p1 = PhienSuaDong(anh1, kt1, d1);
    p1.conTro = [for (var i = 1; i < p1.manh.length; i++) i].firstWhere((i) => p1.manh[i].chu == '0' && p1.manh[i - 1].chu == '2') + 1;
    p1.xoaLui();
    await p1.go('1');
    final vb = await docLai('sk_kho.png', p1.thaoTac().apDai(anh1));
    inKq('(kho) sửa tiếp "20" → "21" trên dòng dựng lại: đọc "$vb"');
    expect(vb, contains('ngày 21 tháng 12'));

    await kho.hoanTacSua(h, t);
    expect(t.tepKq.first, tep0);
    expect(h.soSuaKyTu, 0);
    expect(await File(kho.duongDan(h, Kho.tepKyTu(tep1))).exists(), isFalse);
    await kho.xoaHoSo(h);
    await xongRa();
  });
}
