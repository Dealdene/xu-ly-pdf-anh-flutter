// Tự động chụp: xét từng khung hình xem trước, báo lời nhắc, kích hoạt chụp khi trang đủ điều kiện.
// Chuyển từ ung-dung/loi_xu_ly/tu_chup.py (bản Python đã kiểm thử; đặc tả: 03-tu-dong-chup.md).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'anh.dart';
import 'nan_phang.dart';
import 'tim_mep.dart';

const loiNhacTuChup = {
  'khong_thay': 'Chưa thấy trang giấy',
  'xa': 'Đưa máy lại gần trang',
  'cat_mep': 'Lùi máy ra cho thấy đủ trang',
  'nghieng': 'Cầm máy song song với trang',
  'toi': 'Thiếu sáng, bật thêm đèn',
  'loa': 'Bị lóa, nghiêng máy một chút',
  'rung': 'Giữ yên máy',
  'tay': 'Bỏ tay ra khỏi trang',
  'mo': 'Chưa nét, giữ yên để máy lấy nét',
  'cho_trang_moi': 'Đã chụp trang này, lật sang trang mới',
  'dang_giu': 'Giữ yên, sắp chụp…',
  'da_chup': 'Đã chụp',
};

class CauHinhTuChup {
  double dienTichToiThieu = 0.20;
  double leMep = 0.01;
  double lechCanhToiDa = 1.45;
  double giayKinKhung = 0.75;
  double sangToiThieu = 70;
  double loaToiDa = 0.015;
  // máy xê dịch giữa hai khung liên tiếp, tính bằng điểm ảnh của ảnh 160 px (chênh lệch chia cho độ tương phản
  // cảnh): tay cầm máy run nhẹ 0,7–1,4; va máy, lật trang trên 3. Trước đây đo chênh lệch thô (ngưỡng 5): sách
  // đặt trên nền đen tương phản mạnh, tay run nhẹ đã vượt ngưỡng, đồng hồ giữ yên cứ chạy lại từ đầu.
  double chuyenDongToiDa = 2.5;
  // tay đang vuốt, lật trang chỉ chiếm một phần khung hình: xét thêm độ dời trong từng ô (lưới 4×4) của ảnh 160 px.
  // Video chụp thật: tay di chuyển trên trang 7–35, sách nằm yên dưới 4; tay cầm máy run (mô phỏng) dưới 4–6
  double chuyenDongOToiDa = 5.0;
  double xeDichToiDa = 0.03; // khung trang lệch so với khung trung bình lúc đang giữ (tỉ lệ đường chéo)
  double doNetToiThieu = 6.0;
  double thoiGianGiu = 0.5;
  // một vài khung hình hỏng (tìm mép trượt, rung, mờ thoáng qua) trong lúc đang giữ không làm đồng hồ chạy lại
  double thoiGianChiu = 0.4;
  // Trang mới phải khác trang vừa chụp từng này (khacNhau). Hai cặp trang sách in cùng khổ chữ chỉ khác nhau 0,22–0,33
  // (video chụp thật của người dùng), nên khi đã thấy động tác lật trang (tay che trang, trang ra khỏi khung, máy hay
  // trang dịch chuyển mạnh, cộng lại [thoiGianLat] giây) thì chỉ cần khác [khacTrangSauLat]. Chưa thấy lật trang thì
  // vẫn đòi [khacTrang]: va máy rồi về đúng trang cũ (khác dưới 0,16) không bị chụp lại.
  double khacTrang = 0.24;
  double khacTrangSauLat = 0.18;
  double thoiGianLat = 1.0; // lật trang thật trong video 1,2–4 giây; tay chạm vuốt trang 0,7 giây
  double tayToiDa = 0.005; // phần trang bị tay che (màu da, thò vào từ mép trang)
  double cheTrang = 0.45; // khác trang vừa chụp hơn mức này: tay đang che hay đang lật trang
}

class TrangThaiTuChup {
  TrangThaiTuChup(
    this.ma, {
    this.khung,
    this.kinKhung = false,
    this.tienDo = 0,
    this.soTrang = 0,
    this.rong = 0,
    this.cao = 0,
  });

  String ma;
  List<Diem>? khung; // theo tọa độ ảnh phân tích (rong × cao)
  bool kinKhung;
  double tienDo;
  int soTrang;
  int rong, cao;

  String get loiNhac => ma == 'da_chup' ? 'Đã chụp trang $soTrang' : (loiNhacTuChup[ma] ?? '');

  Map<String, Object?> toMap() => {
    'ma': ma,
    'khung': khung == null
        ? null
        : [
            for (final (x, y) in khung!) ...[x, y],
          ],
    'kinKhung': kinKhung,
    'tienDo': tienDo,
    'soTrang': soTrang,
    'rong': rong,
    'cao': cao,
  };

  static TrangThaiTuChup fromMap(Map m) {
    final k = m['khung'] as List?;
    return TrangThaiTuChup(
      m['ma'] as String,
      khung: k == null
          ? null
          : [for (var i = 0; i < 8; i += 2) ((k[i] as num).toDouble(), (k[i + 1] as num).toDouble())],
      kinKhung: m['kinKhung'] as bool,
      tienDo: (m['tienDo'] as num).toDouble(),
      soTrang: m['soTrang'] as int,
      rong: m['rong'] as int,
      cao: m['cao'] as int,
    );
  }
}

/// Phần trang (thu vào 8% mỗi phía) bị tay che: điểm màu da (sắc 6–25 theo thang 0–180 của OpenCV, bỏ đỏ của mực
/// dấu; bão hòa cao hơn giấy 30) thuộc mảng chạm dải mép trang, vì tay luôn thò vào từ ngoài; con dấu, hình minh họa
/// nằm trong trang không tính. Video chụp thật: khung có tay 1–28%, khung sạch 0%.
double tiLeTay(cv.Mat nho, List<Diem> khung) {
  final h = nho.rows, w = nho.cols;
  final cx = khung.map((p) => p.$1).reduce((a, b) => a + b) / 4,
      cy = khung.map((p) => p.$2).reduce((a, b) => a + b) / 4;
  final trong = [for (final (x, y) in khung) (cx + (x - cx) * 0.84, cy + (y - cy) * 0.84)];
  final ngoaiD = u8Chep(cv.fillPoly(matNaRong(h, w), daGiac(khung), cv.Scalar.all(1)));
  final trongD = u8Chep(cv.fillPoly(matNaRong(h, w), daGiac(trong), cv.Scalar.all(1)));
  final hsv = u8Chep(cv.cvtColor(nho, cv.COLOR_BGR2HSV));
  final demS = List<int>.filled(256, 0);
  var nTrong = 0;
  for (var i = 0; i < trongD.length; i++) {
    if (trongD[i] == 0) continue;
    demS[hsv[i * 3 + 1]]++;
    nTrong++;
  }
  if (nTrong < 100) return 0;
  var tich = 0, sGiay = 0;
  for (var v = 0; v < 256; v++) {
    tich += demS[v];
    if (tich >= nTrong / 2) {
      sGiay = v;
      break;
    }
  }
  final nguongS = math.max(45, sGiay + 30);
  final da = matNaRong(h, w);
  final dd = da.data;
  for (var i = 0; i < dd.length; i++) {
    if (ngoaiD[i] == 0) continue;
    final hh = hsv[i * 3], ss = hsv[i * 3 + 1], vv = hsv[i * 3 + 2];
    if (hh >= 6 && hh <= 25 && ss > nguongS && vv >= 80) dd[i] = 255;
  }
  final mo = cv.morphologyEx(da, cv.MORPH_OPEN, cv.Mat.ones(3, 3, cv.MatType.CV_8UC1));
  final nhanM = cv.Mat.empty(), tkM = cv.Mat.empty(), tamM = cv.Mat.empty();
  final n = cv.connectedComponentsWithStats(mo, nhanM, tkM, tamM, 8, cv.MatType.CV_32S, cv.CCL_DEFAULT);
  if (n < 2) return 0;
  final nhan = i32Chep(nhanM);
  final chamMep = List<bool>.filled(n, false), dtTrong = List<int>.filled(n, 0);
  for (var i = 0; i < nhan.length; i++) {
    final l = nhan[i];
    if (l == 0) continue;
    if (trongD[i] == 0) {
      chamMep[l] = true;
    } else {
      dtTrong[l]++;
    }
  }
  var tay = 0;
  for (var l = 1; l < n; l++) {
    if (chamMep[l]) tay += dtTrong[l];
  }
  return tay / nTrong;
}

/// Phần khung hình là giấy có chữ: sáng, ít màu, có nét mực.
double _tiLeGiay(cv.Mat nho, cv.Mat xam) {
  final hsv = cv.cvtColor(nho, cv.COLOR_BGR2HSV);
  final sang = cv.threshold(cv.gaussianBlur(xam, (5, 5), 0), 0, 1, cv.THRESH_BINARY + cv.THRESH_OTSU).$2;
  final g = matNaRong(xam.rows, xam.cols);
  final gd = g.data, s = sang.data, h = hsv.data;
  for (var i = 0; i < gd.length; i++) {
    gd[i] = (s[i] > 0 && h[i * 3 + 1] < 70) ? 1 : 0;
  }
  final dong = cv.morphologyEx(g, cv.MORPH_CLOSE, cv.Mat.ones(9, 9, cv.MatType.CV_8UC1));
  final muc = cv.adaptiveThreshold(xam, 1, cv.ADAPTIVE_THRESH_MEAN_C, cv.THRESH_BINARY_INV, 15, 12);
  var giay = 0, nMuc = 0;
  final dd = dong.data, md = muc.data;
  for (var i = 0; i < dd.length; i++) {
    giay += dd[i];
    nMuc += md[i];
  }
  final tlMuc = nMuc / md.length;
  return (tlMuc > 0.005 && tlMuc < 0.4) ? giay / dd.length : 0.0;
}

const _ckRong = 48, _ckCao = 64;

/// Bản đồ mật độ mực của trang (48×64), không phụ thuộc độ sáng; dùng so hai lần chụp.
Float32List chuKyTrang(cv.Mat xam, List<Diem> khung) {
  const rong = _ckRong * 2, cao = _ckCao * 2;
  final m = cv.getPerspectiveTransform2f(
    cv.VecPoint2f.fromList([for (final (x, y) in khung) cv.Point2f(x, y)]),
    cv.VecPoint2f.fromList([
      cv.Point2f(0, 0),
      cv.Point2f(rong - 1, 0),
      cv.Point2f(rong - 1, cao - 1),
      cv.Point2f(0, cao - 1),
    ]),
  );
  final to = cv.warpPerspective(xam, m, (rong, cao)).convertTo(cv.MatType.CV_32FC1);
  final nen = cv.gaussianBlur(to, (0, 0), 8);
  final t = f32(to), n = f32(nen);
  for (var i = 0; i < t.length; i++) {
    t[i] = (1.0 - t[i] / (n[i] + 1.0)).clamp(0.0, 1.0);
  }
  // làm mờ trước khi thu nhỏ: xê dịch nửa điểm ảnh không đổi kết quả
  final mo = cv.gaussianBlur(to, (0, 0), 2);
  final nho = cv.resize(mo, (_ckRong, _ckCao), interpolation: cv.INTER_AREA);
  final kq = Float32List.fromList(f32(nho));
  for (var i = 0; i < kq.length; i++) {
    kq[i] *= 255;
  }
  return kq;
}

/// Độ khác hai trang so với lượng mực trung bình: cùng trang dưới 0,16; trang khác trên 0,33.
double khacNhau(Float32List? a, Float32List? b, {int dich = 2}) {
  if (a == null || b == null) return 9.0;
  var tbA = 0.0, tbB = 0.0;
  for (var i = 0; i < a.length; i++) {
    tbA += a[i];
    tbB += b[i];
  }
  tbA /= a.length;
  tbB /= b.length;
  var nhoNhat = double.infinity;
  for (var dy = -dich; dy <= dich; dy++) {
    for (var dx = -dich; dx <= dich; dx++) {
      var s = 0.0, n = 0;
      for (var y = dich; y < _ckCao - dich; y++) {
        for (var x = dich; x < _ckRong - dich; x++) {
          s += (a[y * _ckRong + x] - b[(y + dy) * _ckRong + x + dx]).abs();
          n++;
        }
      }
      nhoNhat = math.min(nhoNhat, s / n);
    }
  }
  return nhoNhat / math.max((tbA + tbB) / 2, 1.0);
}

class BoTuChup {
  BoTuChup([CauHinhTuChup? ch]) : ch = ch ?? CauHinhTuChup();

  final CauHinhTuChup ch;
  int soTrang = 0;
  Uint8List? _viTruoc;
  Float32List? _chuKyCuoi;
  double? _t0, _tTot;
  List<Diem>? _khung0, _hienTot;
  bool _kinTot = false;
  double? _tKhung; // thời điểm khung hình trước
  double _tLat = 0; // thời gian thấy động tác lật trang kể từ lần chụp cuối (các chuỗi đủ dài)
  double _chuoiLat = 0; // chuỗi khung xáo trộn liền nhau đang diễn ra
  bool _xaoTron = false; // khung hiện tại có dấu hiệu lật trang
  double khacCuoi = 0; // độ khác trang vừa chụp của khung gần nhất (để chẩn đoán)
  double get tLat => _tLat + _chuoiLat;

  void datLai({bool quenTrangCuoi = true}) {
    _t0 = null;
    _tTot = null;
    _khung0 = null;
    _viTruoc = null;
    _tKhung = null;
    if (quenTrangCuoi) {
      _chuKyCuoi = null;
      _tLat = 0;
    }
    _chuoiLat = 0;
  }

  /// Đã thấy đủ động tác lật trang kể từ lần chụp cuối. Một khung lỗi lẻ (tìm mép trượt) không tính: chỉ cộng chuỗi
  /// khung xáo trộn liền nhau dài từ 0,25 giây (lật trang thật kéo dài 1–4 giây).
  bool get daLat => _tLat + (_chuoiLat >= 0.25 ? _chuoiLat : 0) >= ch.thoiGianLat;

  void _ghiLat(double buoc) {
    if (_xaoTron) {
      _chuoiLat += buoc;
    } else {
      if (_chuoiLat >= 0.25) _tLat += _chuoiLat;
      _chuoiLat = 0;
    }
    _xaoTron = false;
  }

  /// Nhận một khung hình BGR (cạnh dài ≤ 640) tại thời điểm `t` giây.
  TrangThaiTuChup nhanKhung(cv.Mat nho, double t) {
    final hn = nho.rows, wn = nho.cols;
    final xam = cv.cvtColor(nho, cv.COLOR_BGR2GRAY);
    TrangThaiTuChup tt(String ma, {List<Diem>? khung, bool kin = false}) =>
        TrangThaiTuChup(ma, khung: khung, kinKhung: kin, soTrang: soTrang, rong: wn, cao: hn);
    void huy() {
      _t0 = null;
      _tTot = null;
      _khung0 = null;
    }

    final buoc = _tKhung == null ? 0.0 : (t - _tKhung!).clamp(0.0, 0.3);
    _tKhung = t;

    // Khung hỏng khi đang giữ: còn trong thời gian chịu thì coi như vẫn giữ (giữ khung, tiến độ), không chụp ở khung này
    TrangThaiTuChup loiTam(String ma, {List<Diem>? khung, bool kin = false}) {
      // trang ra khỏi khung, bị che, máy hay trang dịch chuyển mạnh: dấu hiệu đang lật trang
      if (const {'khong_thay', 'xa', 'cat_mep', 'nghieng', 'rung', 'tay'}.contains(ma)) _xaoTron = true;
      _ghiLat(buoc);
      final t0 = _t0, tTot = _tTot;
      // rung là chuyển động thật (máy, tay trên trang): đếm lại ngay, không chịu
      if (ma != 'rung' && ma != 'tay' && t0 != null && tTot != null && t - tTot <= ch.thoiGianChiu) {
        return tt('dang_giu', khung: _hienTot, kin: _kinTot)..tienDo = math.min(0.99, (t - t0) / ch.thoiGianGiu);
      }
      huy();
      return tt(ma, khung: khung, kin: kin);
    }

    // chuyển động giữa hai khung liên tiếp (ảnh 160 px đã làm mờ)
    final viCao = math.max(1, (160 * hn / wn).round());
    final vi = cv.gaussianBlur(cv.resize(xam, (160, viCao), interpolation: cv.INTER_AREA), (5, 5), 0).data;
    var chuyenDong = 0.0, chuyenDongO = 0.0;
    final truoc = _viTruoc;
    if (truoc != null && truoc.length == vi.length) {
      var s = 0, g = 0, nG = 0;
      final sO = List<int>.filled(16, 0), gO = List<int>.filled(16, 0), nO = List<int>.filled(16, 0);
      final int oCao = math.max<int>(1, viCao ~/ 4);
      for (var i = 0; i < vi.length; i++) {
        final x = i % 160;
        final int o = math.min<int>(3, (i ~/ 160) ~/ oCao) * 4 + math.min<int>(3, x ~/ 40);
        final d = (vi[i] - truoc[i]).abs();
        s += d;
        sO[o] += d;
        nO[o]++;
        if (x != 159) {
          final e = (vi[i + 1] - vi[i]).abs();
          g += e;
          gO[o] += e;
          nG++;
        }
        if (i + 160 < vi.length) {
          final e = (vi[i + 160] - vi[i]).abs();
          g += e;
          gO[o] += e;
          nG++;
        }
      }
      // chênh lệch ≈ độ dời × độ dốc sáng: chia cho độ dốc trung bình ra độ dời (điểm ảnh), không phụ thuộc tương phản
      chuyenDong = (s / vi.length) / math.max(g / math.max(nG, 1), 0.5);
      for (var o = 0; o < 16; o++) {
        if (nO[o] == 0) continue;
        // ô gần như phẳng (nền đen, lề trắng): sàn độ dốc 2 để nhiễu không thành chuyển động
        chuyenDongO = math.max(chuyenDongO, (sO[o] / nO[o]) / math.max(gO[o] / (2 * nO[o]), 2.0));
      }
    }
    _viTruoc = Uint8List.fromList(vi);

    // bộ tìm mép kiểu CamScanner, bản nhanh (ảnh 400 px, không tinh chỉnh): đủ cho khung xem trước, ~4 lần nhanh hơn
    var khung = timTuGiac(nho, tinh: false, canh: 400)?.$1;
    if (khung != null) {
      final le = ch.leMep * math.max(wn, hn);
      final cham = [
        khung.map((e) => e.$1).reduce(math.min) < le,
        khung.map((e) => e.$2).reduce(math.min) < le,
        khung.map((e) => e.$1).reduce(math.max) > wn - 1 - le,
        khung.map((e) => e.$2).reduce(math.max) > hn - 1 - le,
      ].where((c) => c).length;
      if (cham >= 3) khung = null; // giấy phủ kín, đó không phải mép giấy thật
    }
    var kin = false;
    if (khung == null) {
      final giay = _tiLeGiay(nho, xam);
      if (giay < ch.giayKinKhung) return loiTam(giay > 0.02 ? 'xa' : 'khong_thay');
      kin = true;
      khung = [(0, 0), (wn - 1.0, 0), (wn - 1.0, hn - 1.0), (0, hn - 1.0)];
    }
    final hien = kin ? null : khung;

    if (!kin) {
      final dt = dienTich(khung) / (wn * hn);
      final d = [
        for (var i = 0; i < 4; i++)
          math.sqrt(
                math.pow(khung[i].$1 - khung[(i + 1) % 4].$1, 2) + math.pow(khung[i].$2 - khung[(i + 1) % 4].$2, 2),
              ) +
              1e-6,
      ];
      final lech = [d[0] / d[2], d[2] / d[0], d[1] / d[3], d[3] / d[1]].reduce(math.max);
      String? loi;
      if (dt < ch.dienTichToiThieu) {
        loi = 'xa';
      } else if (_biCat(khung, wn, hn, ch.leMep)) {
        loi = 'cat_mep';
      } else if (lech > ch.lechCanhToiDa) {
        loi = 'nghieng';
      }
      if (loi != null) return loiTam(loi, khung: hien);
    }

    // độ sáng, lóa, độ nét trong vùng trang
    final matNa = cv.erode(
      cv.fillPoly(matNaRong(hn, wn), daGiac(khung), cv.Scalar.all(1)),
      cv.Mat.ones(7, 7, cv.MatType.CV_8UC1),
    );
    final md = matNa.data, xd = xam.data;
    final lap = cv.laplacian(xam, cv.MatType.CV_16S, ksize: 3).convertTo(cv.MatType.CV_32FC1);
    final ld = f32(lap);
    final dem = List<int>.filled(256, 0);
    var n = 0;
    var tongLap = 0.0;
    for (var i = 0; i < md.length; i++) {
      if (md[i] == 0) continue;
      dem[xd[i]]++;
      tongLap += ld[i].abs();
      n++;
    }
    if (n < 100) return loiTam('khong_thay');
    var tich = 0, trungVi = 0;
    for (var v = 0; v < 256; v++) {
      tich += dem[v];
      if (tich >= n / 2) {
        trungVi = v;
        break;
      }
    }
    final nguongLoa = math.max(248, trungVi + 15);
    var nLoa = 0;
    for (var v = nguongLoa; v < 256; v++) {
      nLoa += dem[v];
    }
    final doNet = tongLap / n;

    String? loi;
    if (trungVi < ch.sangToiThieu) {
      loi = 'toi';
    } else if (nLoa / n > ch.loaToiDa) {
      loi = 'loa';
    } else if (!kin && tiLeTay(nho, khung) > ch.tayToiDa) {
      // phủ kín khung: không có mép trang để biết tay thò vào
      loi = 'tay';
    } else if (chuyenDong > ch.chuyenDongToiDa || chuyenDongO > ch.chuyenDongOToiDa) {
      loi = 'rung';
    } else if (doNet < ch.doNetToiThieu) {
      loi = 'mo';
    }
    if (loi != null) return loiTam(loi, khung: hien, kin: kin);

    final chuKy = chuKyTrang(xam, khung);
    final khac = khacNhau(chuKy, _chuKyCuoi);
    khacCuoi = khac;
    if (khac > ch.cheTrang) _xaoTron = true;
    if (khac < (daLat ? ch.khacTrangSauLat : ch.khacTrang)) {
      if (daLat) return loiTam('cho_trang_moi', khung: hien, kin: kin);
      _ghiLat(buoc);
      huy();
      return tt('cho_trang_moi', khung: hien, kin: kin);
    }

    final cheo = math.sqrt(wn * wn + hn * hn.toDouble());
    var xeDich = 0.0;
    if (_khung0 != null) {
      for (var i = 0; i < 4; i++) {
        xeDich = math.max(xeDich, math.max((khung[i].$1 - _khung0![i].$1).abs(), (khung[i].$2 - _khung0![i].$2).abs()));
      }
    }
    if (_t0 == null || xeDich / cheo > ch.xeDichToiDa) {
      _t0 = t;
      _khung0 = khung;
    } else {
      // khung trung bình trượt theo tay cầm máy trôi chậm; khung tìm được rung vài điểm ảnh giữa các khung hình
      _khung0 = [
        for (var i = 0; i < 4; i++)
          (0.8 * _khung0![i].$1 + 0.2 * khung[i].$1, 0.8 * _khung0![i].$2 + 0.2 * khung[i].$2),
      ];
    }
    _ghiLat(buoc);
    _tTot = t;
    _hienTot = hien;
    _kinTot = kin;
    final kq = tt('dang_giu', khung: hien, kin: kin)..tienDo = math.min(1.0, (t - _t0!) / ch.thoiGianGiu);
    if (kq.tienDo < 1.0) return kq;

    // Đủ thời gian giữ: báo chụp. Ứng dụng gọi takePicture() lấy ảnh độ phân giải gốc.
    _chuKyCuoi = chuKy;
    _tLat = 0;
    _chuoiLat = 0;
    huy();
    soTrang++;
    return kq
      ..ma = 'da_chup'
      ..soTrang = soTrang;
  }
}

/// Trang bị khung hình cắt mất một phần: có một cạnh tứ giác nằm dọc mép khung hình (hai góc cùng sát một mép), hoặc
/// một góc bị kẹp đúng vào mép khung hình.
/// Góc trang chỉ chạm hay gần mép khung hình mà trang vẫn trọn trong khung thì không tính (trước đây báo "lùi máy"
/// cả khi trang đã nằm trọn, cách mép dưới 1%).
bool _biCat(List<Diem> khung, int w, int h, double le) {
  final l = math.max(2.0, le * math.max(w, h));
  final sat = [
    khung.where((p) => p.$1 <= l).length,
    khung.where((p) => p.$2 <= l).length,
    khung.where((p) => p.$1 >= w - 1 - l).length,
    khung.where((p) => p.$2 >= h - 1 - l).length,
  ];
  if (sat.any((n) => n >= 2)) return true;
  // góc nằm đúng trên mép khung hình: bộ tìm mép kẹp góc thật (ở ngoài khung) vào mép, tức trang bị cắt mất một góc
  return khung.any((p) => p.$1 <= 0.5 || p.$2 <= 0.5 || p.$1 >= w - 1.5 || p.$2 >= h - 1.5);
}

/// Trung bình |Laplace| trong khung giữa 60% của ảnh xám sau khi đưa cạnh dài về [canh] điểm ảnh.
double _doNetGiua(cv.Mat xam, int canh) {
  final s = canh / math.max(xam.rows, xam.cols);
  final nho = cv.resize(xam, ((xam.cols * s).round(), (xam.rows * s).round()), interpolation: cv.INTER_AREA);
  final h = nho.rows, w = nho.cols;
  final vung = nho.region(cv.Rect((w * 0.2).round(), (h * 0.2).round(), (w * 0.6).round(), (h * 0.6).round())).clone();
  final lap = f32Chep(cv.laplacian(vung, cv.MatType.CV_32F, ksize: 3));
  var t = 0.0;
  for (final v in lap) {
    t += v.abs();
  }
  return lap.isEmpty ? 0 : t / lap.length;
}

/// Tỉ lệ chi tiết của ảnh chụp: độ nét vùng giữa ở 1280 px chia cho ở 640 px. Ảnh nét còn nhiều chi tiết nhỏ ở
/// tỉ lệ lớn (0,65–0,95 trên ảnh mẫu); ảnh lấy nét hụt (mờ ≥ 3 px ở ảnh 3000 px) tụt về 0,45–0,6. Không phụ thuộc
/// lượng chữ trên trang như độ nét trung bình. Ảnh nhỏ hơn 1280 px thì không đo được (trả 1).
double tiLeNet(cv.Mat xam) {
  if (math.max(xam.rows, xam.cols) < 1280) return 1.0;
  final n640 = _doNetGiua(xam, 640);
  return n640 < 1e-3 ? 1.0 : _doNetGiua(xam, 1280) / n640;
}

/// Ngưỡng tỉ lệ chi tiết dưới đó coi ảnh chụp là mờ (lấy nét hụt): lấy nét lại và chụp lại một lần.
const nguongTiLeNet = 0.55;

/// Tỉ lệ chi tiết của một ảnh JPEG (ảnh chụp thật); gọi trong isolate.
double tiLeNetAnhChup(Uint8List jpeg) => tiLeNet(cv.imdecode(jpeg, cv.IMREAD_GRAYSCALE));

/// Dựng ảnh BGR thu nhỏ từ khung BGRA của camera (iOS: một lớp, 4 byte mỗi điểm), xoay theo hướng cảm biến.
cv.Mat bgrTuBgra({
  required Uint8List bgra,
  required int rong,
  required int cao,
  required int buoc,
  required int xoay,
  int canh = 640,
}) {
  final b = math.max(1, (math.max(rong, cao) / canh).ceil());
  final w = rong ~/ b, h = cao ~/ b;
  final kq = cv.Mat.zeros(h, w, cv.MatType.CV_8UC3);
  final o = kq.data;
  for (var r = 0; r < h; r++) {
    final dong = r * b * buoc;
    for (var c = 0; c < w; c++) {
      final s = dong + c * b * 4, i = (r * w + c) * 3;
      o[i] = bgra[s];
      o[i + 1] = bgra[s + 1];
      o[i + 2] = bgra[s + 2];
    }
  }
  return xoay90(kq, xoay);
}

/// Dựng ảnh BGR thu nhỏ từ khung YUV420 của camera (Android), xoay theo hướng cảm biến.
cv.Mat bgrTuYuv({
  required Uint8List y,
  required Uint8List u,
  required Uint8List v,
  required int rong,
  required int cao,
  required int buocY,
  required int buocUV,
  required int buocDiemUV,
  required int xoay,
  int canh = 640,
}) {
  final buoc = math.max(1, (math.max(rong, cao) / canh).ceil());
  final w = rong ~/ buoc, h = cao ~/ buoc;
  final kq = cv.Mat.zeros(h, w, cv.MatType.CV_8UC3);
  final o = kq.data;
  for (var r = 0; r < h; r++) {
    final sy = r * buoc;
    for (var c = 0; c < w; c++) {
      final sx = c * buoc;
      final yy = y[sy * buocY + sx].toDouble();
      final iuv = (sy >> 1) * buocUV + (sx >> 1) * buocDiemUV;
      final uu = u[iuv] - 128.0, vv = v[iuv] - 128.0;
      final i = (r * w + c) * 3;
      o[i] = (yy + 1.772 * uu).round().clamp(0, 255);
      o[i + 1] = (yy - 0.344136 * uu - 0.714136 * vv).round().clamp(0, 255);
      o[i + 2] = (yy + 1.402 * vv).round().clamp(0, 255);
    }
  }
  return xoay90(kq, xoay);
}
