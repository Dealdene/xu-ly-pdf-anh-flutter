// Vẽ chữ mới khi sửa chữ theo khối: đoán phông trong 8 phông Liberation (cùng kích thước chữ với Times New Roman,
// Arial; giấy phép SIL OFL), dàn chữ trong bề ngang khối, vẽ bằng dart:ui thành độ phủ để phủ lên ảnh trang.
// Cần dart:ui nên chạy trên isolate chính; phần đo ảnh, xóa chữ cũ, ghi ảnh chạy trong isolate (sua_chu.dart).
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'nhan_dang.dart';
import 'sua_chu.dart';
import 'sua_ky_tu.dart';

/// Một phông trong tập đoán: họ phông khai báo trong pubspec (LiberationSerif | LiberationSans) × đậm × nghiêng.
class PhongChu {
  const PhongChu(this.ho, {this.dam = false, this.nghieng = false});

  final String ho;
  final bool dam, nghieng;

  static const tatCa = [
    PhongChu('LiberationSerif'),
    PhongChu('LiberationSerif', dam: true),
    PhongChu('LiberationSerif', nghieng: true),
    PhongChu('LiberationSerif', dam: true, nghieng: true),
    PhongChu('LiberationSans'),
    PhongChu('LiberationSans', dam: true),
    PhongChu('LiberationSans', nghieng: true),
    PhongChu('LiberationSans', dam: true, nghieng: true),
  ];

  bool get coChan => ho == 'LiberationSerif';

  String get ten =>
      '${coChan ? 'Liberation Serif' : 'Liberation Sans'} ${dam ? (nghieng ? 'đậm nghiêng' : 'đậm') : (nghieng ? 'nghiêng' : 'thường')}';

  /// Phông Windows cùng kích thước chữ.
  String get tuongDuong => coChan ? 'Times New Roman' : 'Arial';

  /// [vien] > 0: kiểu vẽ viền nét dày [vien] điểm ảnh (vẽ chồng lên chữ thường để chữ đậm hơn).
  TextStyle kieu(double co, {Color mau = const Color(0xFF000000), double? cao, double vien = 0}) => TextStyle(
        fontFamily: ho,
        fontSize: co,
        height: cao,
        fontWeight: dam ? FontWeight.w700 : FontWeight.w400,
        fontStyle: nghieng ? FontStyle.italic : FontStyle.normal,
        color: vien > 0 ? null : mau,
        foreground: vien > 0
            ? (Paint()
              ..color = mau
              ..style = PaintingStyle.stroke
              ..strokeWidth = vien
              ..strokeJoin = StrokeJoin.round)
            : null,
      );

  @override
  bool operator ==(Object other) => other is PhongChu && other.ho == ho && other.dam == dam && other.nghieng == nghieng;

  @override
  int get hashCode => Object.hash(ho, dam, nghieng);
}

/// Kiểu chữ đoán được của một khối.
class KieuChu {
  KieuChu({required this.phong, required this.co, required this.diem, required this.lechChan, required this.doKhoi, this.vien = 0});

  final PhongChu phong;
  final double co; // cỡ chữ (fontSize) theo điểm ảnh của trang
  final double diem; // độ khớp hình với nét thật (giao / hợp, trừ phần lệch bề rộng)
  final double lechChan; // đường chân chữ thật − đường chân hOCR của dòng đo
  final double vien; // viền thêm (điểm ảnh) cho chữ vẽ đậm bằng chữ thật
  final DoKhoi doKhoi;

  List<int> get mau => doKhoi.mau; // BGR
  Color get mauHien => Color.fromARGB(255, mau[2], mau[1], mau[0]);

  /// Cỡ chữ theo pt, ước theo trang rộng bằng A4 (210 mm).
  double coPt(int rongTrang) => co * 72 * 8.2677 / rongTrang;
}

// ---------------------------------------------------------------- vẽ

/// Độ phủ (kênh alpha) của một hình đã vẽ, kèm khung mực (độ phủ ≥ 96; cạnh phải, dưới không gồm; −1 nếu trống).
class _Ve {
  _Ve(this.w, this.h, this.a);
  final int w, h;
  final Uint8List a;
  int x0 = -1, y0 = -1, x1 = -1, y1 = -1;
}

Future<_Ve> _veHinh(int w, int h, void Function(Canvas c) ve) async {
  final ghi = ui.PictureRecorder();
  ve(Canvas(ghi));
  final hinh = ghi.endRecording();
  final anh = await hinh.toImage(math.max(1, w), math.max(1, h));
  final bd = await anh.toByteData(format: ui.ImageByteFormat.rawRgba);
  anh.dispose();
  hinh.dispose();
  final rgba = bd!.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
  final v = _Ve(anh.width, anh.height, Uint8List(anh.width * anh.height));
  var x0 = v.w, y0 = v.h, x1 = -1, y1 = -1;
  for (var y = 0; y < v.h; y++) {
    for (var x = 0; x < v.w; x++) {
      final al = rgba[(y * v.w + x) * 4 + 3];
      v.a[y * v.w + x] = al;
      if (al >= 96) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 >= 0) {
    v
      ..x0 = x0
      ..y0 = y0
      ..x1 = x1 + 1
      ..y1 = y1 + 1;
  }
  return v;
}

TextPainter _tp(String s, PhongChu p, double co, {double vien = 0}) =>
    TextPainter(text: TextSpan(text: s, style: p.kieu(co, vien: vien)), textDirection: TextDirection.ltr)..layout();

/// Vẽ chuỗi [s] với gốc bút ở (x, đường chân [chan]); [vien] > 0 thì vẽ thêm viền cho đậm.
void _veTp(Canvas c, String s, PhongChu p, double co, double vien, double x, double chan) {
  for (final v in [0.0, if (vien > 0) vien]) {
    final tp = _tp(s, p, co, vien: v);
    tp.paint(c, Offset(x, chan - tp.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
    tp.dispose();
  }
}

/// Vẽ một chuỗi; trả độ phủ cùng vị trí gốc bút (x, đường chân) trong hình.
Future<(_Ve, double, double)> _veChuoi(String s, PhongChu p, double co, {double vien = 0}) async {
  final tp = _tp(s, p, co);
  final le = (co * 0.6).ceilToDouble();
  final chan = le + tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  final w = (tp.width + 2 * le).ceil(), h = (tp.height + 2 * le).ceil();
  tp.dispose();
  final v = await _veHinh(w, h, (c) => _veTp(c, s, p, co, vien, le, chan));
  return (v, le, chan);
}

// ---------------------------------------------------------------- đoán phông

/// Đo nét mực của khối (trong isolate) rồi đoán phông, cỡ, màu. Khối có mực màu thì báo lỗi [LoiSuaChu].
/// [phong]: người dùng chọn phông thì chỉ đo cỡ theo phông đó. [xetMucMau] false: dòng đã được xét mực màu từ trước
/// (Sửa ký tự xét theo cả dòng), đo một đoạn ngắn không báo lỗi.
Future<KieuChu> doKieuChu(Uint8List anh, KhoiChu k, {PhongChu? phong, bool xetMucMau = true}) async {
  final dk = await _doKhoiNen(anh, k);
  if (dk.mucMau && xetMucMau) throw const LoiSuaChu(baoMucMau);
  return _doanPhong(dk, k, phong);
}

/// Đoán lại theo số đo đã có: [phong] khác null thì chỉ đo cỡ theo phông đó, null thì đoán trong cả 8 phông.
Future<KieuChu> doKieuChuTheoPhong(KieuChu cu, KhoiChu k, PhongChu? phong) => _doanPhong(cu.doKhoi, k, phong);

/// Vẽ thử chữ cũ của dòng dài nhất bằng từng phông, ở cỡ khớp bề rộng nét mực (bề rộng cả dòng ít phụ thuộc
/// chữ máy đọc sai dấu hơn chiều cao); so hình nét (giao / hợp độ phủ đã làm mờ nhẹ) và chiều cao với nét thật,
/// lấy phông khớp nhất. Sau đó đo độ đậm: viền thêm bao nhiêu cho lượng mực bằng chữ thật (chữ in, chữ đã
/// làm sạch thường đậm hơn phông gốc).
Future<KieuChu> _doanPhong(DoKhoi dk, KhoiChu k, PhongChu? chiPhong) async {
  final d = k.dong[dk.iDo];
  final chu = d.vanBan;
  final km = dk.khungMuc[dk.iDo];
  const coMau = 48.0;
  KieuChu? tot;
  if (km != null && chu.isNotEmpty) {
    final hDo = km[3] - km[1], wDo = km[2] - km[0];
    final kp = dk.khungPhu;
    final pw = kp[2] - kp[0], ph = kp[3] - kp[1];
    // trọng tâm dọc của mực thật; số điểm mực đậm quá nửa (thước đo độ đậm nét)
    var tongDo = 0, momen = 0.0, datDo = 0;
    for (var y = 0; y < ph; y++) {
      for (var x = 0; x < pw; x++) {
        final m = dk.phu[y * pw + x];
        tongDo += m;
        momen += m * (y + kp[1]);
        if (m >= 128) datDo++;
      }
    }
    final tamDo = momen / math.max(tongDo, 1);
    for (final p in chiPhong != null ? [chiPhong] : PhongChu.tatCa) {
      final (mau, _, _) = await _veChuoi(chu, p, coMau);
      if (mau.x1 < 0) continue;
      final co = coMau * wDo / (mau.x1 - mau.x0);
      final lechCao = ((mau.y1 - mau.y0) * co / coMau - hDo).abs() / hDo;
      if (lechCao > 0.35 && chiPhong == null) continue;
      final (v, _, chanVe) = await _veChuoi(chu, p, co);
      if (v.x1 < 0) continue;
      // đặt hình vẽ thử: giữa khung mực theo chiều ngang, trùng trọng tâm mực theo chiều dọc
      var tongVe = 0, momenVe = 0.0;
      for (var y = 0; y < v.h; y++) {
        for (var x = 0; x < v.w; x++) {
          tongVe += v.a[y * v.w + x];
          momenVe += v.a[y * v.w + x] * y;
        }
      }
      final ox = ((km[0] + km[2]) / 2 - (v.x0 + v.x1) / 2).round();
      final oy = (tamDo - momenVe / math.max(tongVe, 1)).round();
      final ve = Uint8List(pw * ph);
      var veTrong = 0;
      for (var y = 0; y < ph; y++) {
        final vy = y + kp[1] - oy;
        if (vy < 0 || vy >= v.h) continue;
        for (var x = 0; x < pw; x++) {
          final vx = x + kp[0] - ox;
          if (vx < 0 || vx >= v.w) continue;
          ve[y * pw + x] = v.a[vy * v.w + vx];
          veTrong += ve[y * pw + x];
        }
      }
      // làm mờ nhẹ cả hai cho phép so bớt nhạy với lệch dưới một nét
      final r = math.max(1, (co * 0.04).round());
      final mo1 = _moHop(dk.phu, pw, ph, r), mo2 = _moHop(ve, pw, ph, r);
      var giao = 0.0, hop = 0.0;
      for (var i = 0; i < mo1.length; i++) {
        giao += math.min(mo1[i], mo2[i]);
        hop += math.max(mo1[i], mo2[i]);
      }
      hop += (tongVe - veTrong) * 1.0; // nét vẽ thử rơi ra ngoài vùng đo
      final diem = giao / math.max(hop, 1) - 0.5 * math.max(0, lechCao - 0.05);
      var lech = oy + chanVe - d.chanChuTai((km[0] + km[2]) / 2);
      if (lech.abs() > 0.3 * co) lech = 0;
      if (tot == null || diem > tot.diem) tot = KieuChu(phong: p, co: co, diem: diem, lechChan: lech, doKhoi: dk);
    }
    if (tot != null) {
      // độ đậm: thử viền 0 … 0,15 cỡ chữ, chọn viền cho số điểm mực đậm quá nửa gần với chữ thật nhất
      var lechTot = double.infinity, vienTot = 0.0;
      for (final he in [0.0, 0.015, 0.03, 0.045, 0.06, 0.08, 0.1, 0.12, 0.15]) {
        final vien = he * tot.co;
        final (v, _, _) = await _veChuoi(chu, tot.phong, tot.co, vien: vien);
        final lech = (v.a.where((x) => x >= 128).length - datDo).abs().toDouble();
        if (lech < lechTot) {
          lechTot = lech;
          vienTot = vien;
        }
      }
      tot = KieuChu(phong: tot.phong, co: tot.co, diem: tot.diem, lechChan: tot.lechChan, doKhoi: dk, vien: vienTot);
    }
  }
  // không đo được (máy đọc sai quá, không thấy mực): Liberation Serif thường theo cỡ chữ hOCR
  return tot ?? KieuChu(phong: chiPhong ?? PhongChu.tatCa.first, co: k.coChu, diem: 0, lechChan: 0, doKhoi: dk);
}

/// Làm mờ hộp (2r + 1)² một ảnh độ phủ, trả số thực.
Float32List _moHop(Uint8List a, int w, int h, int r) {
  final ngang = Float32List(w * h), ra = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    var tong = 0.0;
    for (var x = -r; x < w + r; x++) {
      if (x + r < w) tong += a[y * w + x + r];
      if (x - r - 1 >= 0) tong -= a[y * w + x - r - 1];
      if (x >= 0 && x < w) ngang[y * w + x] = tong;
    }
  }
  for (var x = 0; x < w; x++) {
    var tong = 0.0;
    for (var y = -r; y < h + r; y++) {
      if (y + r < h) tong += ngang[(y + r) * w + x];
      if (y - r - 1 >= 0) tong -= ngang[(y - r - 1) * w + x];
      if (y >= 0 && y < h) ra[y * w + x] = tong;
    }
  }
  return ra;
}

// ---------------------------------------------------------------- dàn chữ

/// Chữ mới đã dàn và vẽ: độ phủ trên vùng [khungPhu] của trang, các dòng mới (vị trí từ để ghi lớp chữ PDF).
class BoCuc {
  BoCuc(this.phu, this.khungPhu, this.dong);
  final Uint8List phu;
  final List<int> khungPhu; // [x0, y0, x1, y1)
  final List<DongChu> dong;
}

/// Dàn [chuMoi] trong bề ngang khối: ngắt dòng theo từ (giữ dòng người dùng tự xuống), thụt đầu dòng, căn lề như cũ
/// (căn đều thì giãn khoảng cách từ, trừ dòng cuối đoạn), cùng cỡ, khoảng cách dòng; dòng đầu nằm đúng đường chân cũ.
Future<BoCuc> danChu(String chuMoi, KhoiChu k, KieuChu kc, int rongTrang, int caoTrang) async {
  final p = kc.phong, co = kc.co, vien = kc.vien;
  final doRong = <String, double>{};
  double rong(String s) => doRong[s] ??= () {
        final tp = _tp(s, p, co);
        final w = tp.width;
        tp.dispose();
        return w;
      }();
  final cach = rong('a a') - rong('aa');
  final ngang = k.xPhai - k.xTrai;
  final coThut = k.can == 'trai' || k.can == 'deu';
  // (các từ, đầu đoạn, cuối đoạn)
  final dong = <(List<String>, bool, bool)>[];
  for (final doan in chuMoi.split('\n')) {
    final tu = doan.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (tu.isEmpty) continue;
    var hien = <String>[];
    var w = 0.0, dau = true;
    for (final t in tu) {
      // thụt đầu dòng chỉ ở dòng đầu khối; các dòng người dùng tự xuống bắt đầu ở lề như bản cũ
      final cho = ngang - (coThut && dong.isEmpty ? k.thutDau : 0);
      final them = hien.isEmpty ? rong(t) : w + cach + rong(t);
      // chừa 2%: phông thay thế có thể rộng hơn chữ in một chút, tránh ngắt dòng khác bản cũ khi chữ không đổi
      if (hien.isNotEmpty && them > cho * 1.02) {
        dong.add((hien, dau, false));
        hien = [t];
        w = rong(t);
        dau = false;
      } else {
        hien.add(t);
        w = them;
      }
    }
    dong.add((hien, dau, true));
  }

  final dau0 = k.dong.first;
  final chan0 = dau0.chanChuTai(dau0.x0) + kc.lechChan;
  final ve = <(String, double, double)>[]; // (chuỗi, x gốc bút, đường chân)
  final dongMoi = <DongChu>[];
  for (var j = 0; j < dong.length; j++) {
    final (tu, _, cuoiDoan) = dong[j];
    final chan = chan0 + j * k.khoangDong;
    final chuoi = tu.join(' ');
    final (v, le, chanVe) = await _veChuoi(chuoi, p, co, vien: vien);
    final mucTrai = v.x1 < 0 ? 0.0 : v.x0 - le, mucPhai = v.x1 < 0 ? rong(chuoi) : v.x1 - le;
    final trai = k.xTrai + (coThut && j == 0 ? k.thutDau : 0);
    // đặt theo khung mực (không theo bề rộng bút) để căn giữa, căn phải chính xác
    final but = switch (k.can) {
      'giua' => (k.xTrai + k.xPhai) / 2 - (mucTrai + mucPhai) / 2,
      'phai' => k.xPhai - mucPhai,
      _ => trai - mucTrai,
    };
    final viTri = <double>[];
    var phaiDong = but + mucPhai;
    if (k.can == 'deu' && !cuoiDoan && tu.length > 1) {
      final (vc, lec, _) = await _veChuoi(tu.last, p, co, vien: vien);
      final phaiCuoi = vc.x1 < 0 ? rong(tu.last) : vc.x1 - lec;
      var tong = 0.0;
      for (final t in tu.take(tu.length - 1)) {
        tong += rong(t);
      }
      final khe = (k.xPhai - phaiCuoi - but - tong) / (tu.length - 1);
      var x = but;
      for (final t in tu) {
        viTri.add(x);
        ve.add((t, x, chan));
        x += rong(t) + khe;
      }
      phaiDong = k.xPhai;
    } else {
      var x = but;
      for (final t in tu) {
        viTri.add(x);
        x += rong(t) + cach;
      }
      ve.add((chuoi, but, chan));
    }
    final tren = v.x1 < 0 ? chan - co * 0.8 : chan - (chanVe - v.y0);
    final duoi = v.x1 < 0 ? chan + co * 0.2 : chan + (v.y1 - chanVe);
    dongMoi.add(DongChu(
      [for (var i = 0; i < tu.length; i++) TuChu(tu[i], viTri[i], tren, viTri[i] + rong(tu[i]), duoi, 96)],
      but + mucTrai,
      tren,
      phaiDong,
      duoi,
      coChu: k.coChu,
      lechChan: chan - duoi,
      doanMoi: j == 0,
    ));
  }
  if (dongMoi.isEmpty) return BoCuc(Uint8List(0), [0, 0, 0, 0], []);
  // vẽ tất cả lên một hình phủ vùng các dòng mới
  final le = (co * 0.5).ceil();
  final x0 = math.max(0, dongMoi.map((d) => d.x0).reduce(math.min).floor() - le);
  final y0 = math.max(0, dongMoi.map((d) => d.y0).reduce(math.min).floor() - le);
  final x1 = math.min(rongTrang, dongMoi.map((d) => d.x1).reduce(math.max).ceil() + le);
  final y1 = math.min(caoTrang, dongMoi.map((d) => d.y1).reduce(math.max).ceil() + le);
  final hinh = await _veHinh(x1 - x0, y1 - y0, (c) {
    for (final (s, x, chan) in ve) {
      _veTp(c, s, p, co, vien, x - x0, chan - y0);
    }
  });
  return BoCuc(hinh.a, [x0, y0, x0 + hinh.w, y0 + hinh.h], dongMoi);
}

// ---------------------------------------------------------------- áp sửa

class KetQuaSua {
  KetQuaSua(
      {required this.anh,
      required this.chu,
      required this.tran,
      required this.kieu,
      required this.soDongCu,
      required this.soDongMoi,
      required this.dy,
      required this.yCat});

  final Uint8List anh; // ảnh trang mới (PNG)
  final TrangChu chu; // chữ của trang mới: khối sửa thay bằng các dòng mới, phần bên dưới dời theo
  final bool tran; // phần cuối trang bị đẩy ra ngoài mép dưới
  final KieuChu kieu;
  final int soDongCu, soDongMoi;
  final int dy, yCat; // phần trang từ hàng yCat trở xuống đã dời dy hàng (dương: xuống)
}

/// Thay chữ của khối [k] trên ảnh trang [anh] (đã nhận dạng thành [trang]) bằng [chuMoi].
/// [kieu]: kiểu chữ đã đoán sẵn (khi người dùng chạm khối); [phong]: phông người dùng chọn.
Future<KetQuaSua> suaKhoi(Uint8List anh, TrangChu trang, KhoiChu k, String chuMoi, {KieuChu? kieu, PhongChu? phong}) async {
  var kc = kieu;
  if (kc == null) {
    kc = await doKieuChu(anh, k, phong: phong);
  } else if (phong != null && kc.phong != phong) {
    kc = await _doanPhong(kc.doKhoi, k, phong);
  }
  if (kc.doKhoi.mucMau) throw const LoiSuaChu(baoMucMau);
  final bc = await danChu(chuMoi, k, kc, trang.rong, trang.cao);
  final dy = ((bc.dong.length - k.dong.length) * k.khoangDong).round();
  // hàng bắt đầu phần trang được dời: giữa đáy nét mực của khối và đỉnh dòng gần nhất bên dưới
  final khung = kc.doKhoi.khungMuc.whereType<List<int>>();
  final day = khung.isEmpty ? k.y1 : khung.map((v) => v[3]).reduce(math.max).toDouble();
  final khac = [for (final d in trang.dong) if (!k.dong.contains(d)) d];
  final duoi = [for (final d in khac) if (d.y0 >= day - 0.2 * k.coChu) d.y0];
  final ke = duoi.isEmpty ? null : duoi.reduce(math.min);
  var cat = ke == null ? day + 0.25 * k.khoangDong : math.min(ke, math.max(day + 3, (day + ke) / 2));
  // dòng ở cột bên cạnh vắt qua đường cắt: hạ đường cắt xuống dưới dòng đó để không cắt đôi nét chữ
  for (var lap = true; lap;) {
    lap = false;
    for (final d in khac) {
      final benCanh = d.x1 < k.x0 || d.x0 > k.x1;
      if (benCanh && d.y0 < cat && d.y1 + 2 > cat && d.y1 < trang.cao) {
        cat = d.y1 + 2;
        lap = true;
      }
    }
  }
  final yCat = cat.round();
  final ra = await _apNen(anh, k, bc.phu, bc.khungPhu, kc.mau, dy, yCat);
  // chữ của trang mới, theo thứ tự cũ
  final dongMoi = <DongChu>[];
  var daChen = false;
  for (final d in trang.dong) {
    if (k.dong.contains(d)) {
      if (!daChen) dongMoi.addAll(bc.dong);
      daChen = true;
    } else if (dy != 0 && d.y0 >= yCat) {
      if (d.y0 + dy < trang.cao) dongMoi.add(_doiDong(d, dy.toDouble()));
    } else {
      dongMoi.add(d);
    }
  }
  return KetQuaSua(
      anh: ra.anh,
      chu: TrangChu(trang.rong, trang.cao, dongMoi),
      tran: ra.tran,
      kieu: kc,
      soDongCu: k.dong.length,
      soDongMoi: bc.dong.length,
      dy: dy,
      yCat: yCat);
}

DongChu _doiDong(DongChu d, double dy) => DongChu(
      [for (final t in d.tu) TuChu(t.chu, t.x0, t.y0 + dy, t.x1, t.y1 + dy, t.tinCay)],
      d.x0,
      d.y0 + dy,
      d.x1,
      d.y1 + dy,
      coChu: d.coChu,
      doDoc: d.doDoc,
      lechChan: d.lechChan,
      doanMoi: d.doanMoi,
      gocChu: d.gocChu,
    );

// Hàm cấp cao nhất: closure gửi sang isolate chỉ mang theo tham số.
Future<DoKhoi> _doKhoiNen(Uint8List anh, KhoiChu k) => Isolate.run(() => doKhoi(anh, k));
Future<AnhDaSua> _apNen(Uint8List anh, KhoiChu k, Uint8List phu, List<int> khungPhu, List<int> mau, int dy, int yCat) =>
    Isolate.run(() => apSua(anh, k, phu: phu, khungPhu: khungPhu, mau: mau, dy: dy, yCat: yCat));

/// Khối nào có mực màu (con dấu, chữ ký), chạy trong isolate.
Future<List<bool>> kiemMucMauNen(Uint8List anh, List<KhoiChu> khoi) => Isolate.run(() => kiemMucMau(anh, khoi));

// ---------------------------------------------------------------- Sửa ký tự: ký tự cả hồ sơ không có

/// Vẽ ký tự cả hồ sơ không có (Sửa ký tự, sua_ky_tu.dart) bằng phông đoán theo từ dài nhất của dòng.
class _BoVePhong implements BoVeKyTu {
  _BoVePhong(this.kieu, this.anh);
  final KieuChu kieu;
  final Uint8List anh; // ảnh trang (mã hóa): đoán phông đoạn bôi chọn

  @override
  double get coPx => kieu.co;

  @override
  Future<double> caoMuc(String ch, double co) async {
    final (v, _, _) = await _veChuoi(ch, kieu.phong, co, vien: kieu.vien);
    return v.y1 < 0 ? 0 : (v.y1 - v.y0).toDouble();
  }

  @override
  Future<HinhVe> ve(String ch, double co) async {
    final (v, gocX, chan) = await _veChuoi(ch, kieu.phong, co, vien: kieu.vien);
    final tp = _tp(ch, kieu.phong, co);
    final rong = tp.width;
    tp.dispose();
    return HinhVe(v.a, v.w, v.h, gocX, chan, kieu.mau, rong);
  }

  @override
  Future<DinhDangVe> doan(List<KyTu> ky) async {
    var kc = kieu;
    if (ky.isNotEmpty) kc = await doKieuChu(anh, _khoiKyTu(ky, kieu.co), xetMucMau: false);
    return DinhDangVe(math.max(0, PhongChu.tatCa.indexOf(kc.phong)), kc.co, kc.mau, vien: kc.vien);
  }

  @override
  Future<HinhVe> veTheo(String ch, DinhDangVe k) async {
    final p = PhongChu.tatCa[k.phong];
    final (v, gocX, chan) = await _veChuoi(ch, p, k.co, vien: k.vien);
    final tp = _tp(ch, p, k.co);
    final rong = tp.width;
    tp.dispose();
    return HinhVe(v.a, v.w, v.h, gocX, chan, k.mau, rong);
  }
}

/// Khối một dòng gồm các ký tự [ky] (cùng một dòng ảnh), để đo phông.
KhoiChu _khoiKyTu(List<KyTu> ky, double co) {
  final x0 = ky.map((c) => c.x0).reduce(math.min).toDouble(), x1 = ky.map((c) => c.x1).reduce(math.max).toDouble();
  final y0 = ky.map((c) => c.y0).reduce(math.min).toDouble(), y1 = ky.map((c) => c.y1).reduce(math.max).toDouble();
  final dong = DongChu([TuChu(ky.map((c) => c.chu).join(), x0, y0, x1, y1, 90)], x0, y0, x1, y1, coChu: co, lechChan: 0);
  return KhoiChu([dong], can: 'trai', thutDau: 0, khoangDong: 1.2 * co, xTrai: x0, xPhai: x1);
}

/// Đoán phông, cỡ, màu theo từ dài nhất của dòng [d] trên ảnh trang [anh] (mã hóa), để vẽ ký tự thiếu.
Future<BoVeKyTu> boVeKyTu(Uint8List anh, DongAnh d) async {
  final w = d.tu.reduce((a, b) => b.length > a.length ? b : a);
  final x0 = w.first.x0.toDouble(), x1 = w.last.x1.toDouble();
  final y0 = w.map((c) => c.y0).reduce(math.min).toDouble(), y1 = w.map((c) => c.y1).reduce(math.max).toDouble();
  final dong = DongChu([TuChu(w.map((c) => c.chu).join(), x0, y0, x1, y1, 90)], x0, y0, x1, y1, coChu: d.co, lechChan: d.chan - y1);
  final k = KhoiChu([dong], can: 'trai', thutDau: 0, khoangDong: 1.2 * d.co, xTrai: x0, xPhai: x1);
  return _BoVePhong(await doKieuChu(anh, k, xetMucMau: false), anh);
}
