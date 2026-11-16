// Tính năng 3: tìm mép giấy, sửa phối cảnh, sửa nghiêng, tách trang đôi, xóa viền.
// Chuyển từ ung-dung/loi_xu_ly/nan_phang.py (bản Python đã kiểm thử).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'anh.dart';
import 'tim_mep.dart';

final double tiLeA4 = math.sqrt(2);

/// Sắp 4 điểm theo thứ tự: trên trái, trên phải, dưới phải, dưới trái.
List<Diem> sapXepGoc(List<Diem> p) {
  final cx = p.map((e) => e.$1).reduce((a, b) => a + b) / p.length;
  final cy = p.map((e) => e.$2).reduce((a, b) => a + b) / p.length;
  final s = [...p]..sort((a, b) => math.atan2(a.$2 - cy, a.$1 - cx).compareTo(math.atan2(b.$2 - cy, b.$1 - cx)));
  var dau = 0;
  for (var i = 1; i < 4; i++) {
    if (s[i].$1 + s[i].$2 < s[dau].$1 + s[dau].$2) dau = i;
  }
  return [for (var i = 0; i < 4; i++) s[(dau + i) % 4]];
}

List<List<Diem>> _tuGiac(cv.Mat matNa, double dt) {
  final (duong, _) = cv.findContours(matNa, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
  final ds = [for (var i = 0; i < duong.length; i++) duong[i]];
  final dtDuong = [for (final c in ds) cv.contourArea(c)];
  final thuTu = List<int>.generate(ds.length, (i) => i)..sort((a, b) => dtDuong[b].compareTo(dtDuong[a]));
  final kq = <List<Diem>>[];
  for (final i in thuTu.take(5)) {
    if (dtDuong[i] < 0.15 * dt) break;
    final bao = cv.VecPoint.fromList(baoLoi([for (var k = 0; k < ds[i].length; k++) ds[i][k]]));
    final chuVi = cv.arcLength(bao, true);
    for (final eps in const [0.02, 0.03, 0.05, 0.08]) {
      final xx = cv.approxPolyDP(bao, eps * chuVi, true);
      if (xx.length == 4) {
        kq.add([for (var k = 0; k < 4; k++) (xx[k].x.toDouble(), xx[k].y.toDouble())]);
        break;
      }
    }
  }
  return kq;
}

/// Tìm 4 góc tờ giấy trong ảnh chụp (bộ tìm mép kiểu CamScanner, tim_mep.dart). Trả null nếu giấy chiếm gần hết ảnh,
/// khung chỉ là một phần tài liệu (chụp kín hai trang sách), hoặc không tìm được.
List<Diem>? timMepGiay(cv.Mat anh) {
  final kq = timTuGiac(anh);
  if (kq == null) return null;
  final goc = kq.$1;
  final w = anh.cols - 1.0, h = anh.rows - 1.0;
  final khungAnh = [(0.0, 0.0), (w, 0.0), (w, h), (0.0, h)];
  var lech = 0.0;
  for (var i = 0; i < 4; i++) {
    lech = math.max(lech, math.sqrt(math.pow(goc[i].$1 - khungAnh[i].$1, 2) + math.pow(goc[i].$2 - khungAnh[i].$2, 2)));
  }
  if (lech < 0.015 * math.sqrt(w * w + h * h)) return null;
  final (nho, s) = thuNho(anh, 800);
  final xam = cv.cvtColor(nho, cv.COLOR_BGR2GRAY);
  final giongGiay = _giongGiay(nho, cv.gaussianBlur(xam, (5, 5), 0));
  if (_ngoaiKhungConChu([for (final (x, y) in goc) (x * s, y * s)], giongGiay, xam)) return null;
  return sapXepGoc(goc);
}

/// Bộ tìm mép cũ (đến 2026-11): đường bao lớn nhất của ảnh cạnh hoặc vùng sáng ít màu. Giữ để so sánh.
List<Diem>? timMepGiayCu(cv.Mat anh) {
  final (nho, s) = thuNho(anh, 800);
  final dt = (nho.rows * nho.cols).toDouble();
  final xam = cv.cvtColor(nho, cv.COLOR_BGR2GRAY);
  final mo = cv.gaussianBlur(xam, (5, 5), 0);

  final ungVien = <List<Diem>>[];
  // Cách 1: theo cạnh. Đường bao nằm ngoài mép thật một khoảng bằng độ giãn, nên kéo góc vào.
  final canh = cv.dilate(cv.canny(mo, 40, 120), cv.Mat.ones(3, 3, cv.MatType.CV_8UC1), iterations: 2);
  for (final q in _tuGiac(canh, dt)) {
    final cx = q.map((e) => e.$1).reduce((a, b) => a + b) / 4;
    final cy = q.map((e) => e.$2).reduce((a, b) => a + b) / 4;
    ungVien.add([
      for (final (x, y) in q)
        () {
          final dx = cx - x, dy = cy - y;
          final l = math.max(math.sqrt(dx * dx + dy * dy), 1e-6);
          return (x + dx / l * 2.5, y + dy / l * 2.5);
        }(),
    ]);
  }

  // Cách 2: vùng sáng, ít màu (giấy trên nền bàn tối hoặc sặc sỡ).
  final giongGiay = _giongGiay(nho, mo);
  var matNa = cv.morphologyEx(giongGiay, cv.MORPH_CLOSE, cv.getStructuringElement(cv.MORPH_ELLIPSE, (15, 15)));
  matNa = cv.morphologyEx(matNa, cv.MORPH_OPEN, cv.getStructuringElement(cv.MORPH_ELLIPSE, (9, 9)));
  ungVien.addAll(_tuGiac(matNa, dt));

  final hopLe = ungVien.where((q) => dienTich(q) < 0.95 * dt).toList();
  if (hopLe.isEmpty) return null;
  hopLe.sort((a, b) => dienTich(b).compareTo(dienTich(a)));
  final tot = hopLe.first;
  if (_ngoaiKhungConChu(tot, giongGiay, xam)) return null;
  return sapXepGoc([for (final (x, y) in tot) (x / s, y / s)]);
}

/// Mặt nạ 0/255: sáng (Otsu) và ít màu (độ bão hòa < 70).
cv.Mat _giongGiay(cv.Mat nho, cv.Mat mo) {
  final hsv = cv.cvtColor(nho, cv.COLOR_BGR2HSV);
  final sang = cv.threshold(mo, 0, 255, cv.THRESH_BINARY + cv.THRESH_OTSU).$2;
  final h = hsv.data, s = sang.data;
  final kq = matNaRong(nho.rows, nho.cols);
  final k = kq.data;
  for (var i = 0; i < k.length; i++) {
    k[i] = (s[i] > 0 && h[i * 3 + 1] < 70) ? 255 : 0;
  }
  return kq;
}

/// Ngoài khung cũng là giấy có chữ (ví dụ chụp kín hai trang sách) thì khung chỉ là một phần tài liệu; cắt theo nó sẽ
/// mất nội dung. Chỉ đếm mực trên vùng giấy ngoài khung (đã lấp chữ, lùi khỏi mép vùng) và cách khung một dải: mép bìa
/// sổ, mép tờ giấy lót bên dưới, bóng sát mép không bị tính là chữ.
bool _ngoaiKhungConChu(List<Diem> khung, cv.Mat giongGiay, cv.Mat xam) {
  final h = xam.rows, w = xam.cols;
  final nhan15 = cv.Mat.ones(15, 15, cv.MatType.CV_8UC1);
  final trongM = cv.fillPoly(matNaRong(h, w), daGiac(sapXepGoc(khung)), cv.Scalar.all(1));
  final ngoai = u8Chep(cv.dilate(trongM, nhan15, borderType: cv.BORDER_REPLICATE));
  final hep = u8Chep(cv.erode(trongM, nhan15, borderType: cv.BORDER_REPLICATE));
  final giay = u8Chep(
    cv.erode(
      cv.morphologyEx(
        giongGiay,
        cv.MORPH_CLOSE,
        cv.getStructuringElement(cv.MORPH_ELLIPSE, (15, 15)),
        borderType: cv.BORDER_REPLICATE,
      ),
      cv.Mat.ones(9, 9, cv.MatType.CV_8UC1),
      borderType: cv.BORDER_REPLICATE,
    ),
  );
  final muc = u8Chep(cv.adaptiveThreshold(xam, 1, cv.ADAPTIVE_THRESH_MEAN_C, cv.THRESH_BINARY_INV, 15, 12));
  var nNgoai = 0, nVung = 0, mucVung = 0, nTrong = 0, mucTrong = 0;
  for (var i = 0; i < muc.length; i++) {
    if (ngoai[i] == 0) {
      nNgoai++;
      if (giay[i] > 0) {
        nVung++;
        mucVung += muc[i];
      }
    }
    if (hep[i] > 0) {
      nTrong++;
      mucTrong += muc[i];
    }
  }
  if (nNgoai < 0.03 * muc.length || nVung < 0.5 * nNgoai) return false;
  final tlTrong = nTrong > 0 ? mucTrong / nTrong : 0.0;
  return mucVung / nVung > 0.3 * math.max(tlTrong, 1e-4);
}

bool laToanAnh(List<Diem> khung, int rong, int cao) {
  final goc = [(0.0, 0.0), (rong - 1.0, 0.0), (rong - 1.0, cao - 1.0), (0.0, cao - 1.0)];
  final s = sapXepGoc(khung);
  for (var i = 0; i < 4; i++) {
    if ((s[i].$1 - goc[i].$1).abs() > 1.5 || (s[i].$2 - goc[i].$2).abs() > 1.5) return false;
  }
  return true;
}

List<double> _cheo(List<double> a, List<double> b) => [
  a[1] * b[2] - a[2] * b[1],
  a[2] * b[0] - a[0] * b[2],
  a[0] * b[1] - a[1] * b[0],
];
double _vo(List<double> a, List<double> b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

/// Tỉ lệ cao/rộng thật của tờ giấy, suy từ 4 góc (Zhang & He 2007). Null nếu không giải được.
double? tiLePhoiCanh(List<Diem> goc, int rongAnh, int caoAnh) {
  final u0 = rongAnh / 2, v0 = caoAnh / 2;
  final p = [
    for (final (x, y) in goc) <double>[x, y, 1.0],
  ];
  final m1 = p[0], m2 = p[1], m4 = p[2], m3 = p[3];
  final k2 = _vo(_cheo(m1, m4), m3) / _vo(_cheo(m2, m4), m3);
  final k3 = _vo(_cheo(m1, m4), m2) / _vo(_cheo(m3, m4), m2);
  final n2 = [for (var i = 0; i < 3; i++) k2 * m2[i] - m1[i]];
  final n3 = [for (var i = 0; i < 3; i++) k3 * m3[i] - m1[i]];
  if (n2[2].abs() < 1e-9 || n3[2].abs() < 1e-9) return null;
  final f2 =
      -((n2[0] * n3[0] - (n2[0] * n3[2] + n2[2] * n3[0]) * u0 + n2[2] * n3[2] * u0 * u0) +
          (n2[1] * n3[1] - (n2[1] * n3[2] + n2[2] * n3[1]) * v0 + n2[2] * n3[2] * v0 * v0)) /
      (n2[2] * n3[2]);
  if (!f2.isFinite || f2 <= 0) return null;
  final f = math.sqrt(f2);
  double doDai2(List<double> n) {
    final a = (n[0] - u0 * n[2]) / f, b = (n[1] - v0 * n[2]) / f;
    return a * a + b * b + n[2] * n[2];
  }

  final rong2 = doDai2(n2), cao2 = doDai2(n3);
  if (rong2 <= 0 || cao2 <= 0) return null;
  final r = math.sqrt(cao2 / rong2);
  return (r > 0.25 && r < 4 && f > 0.3 * math.max(rongAnh, caoAnh)) ? r : null;
}

double _kc(Diem a, Diem b) => math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));

/// Biến đổi phối cảnh đưa tứ giác `khung` về hình chữ nhật.
/// Nới khung khi nắn phẳng (phần mỗi cạnh): mép trang cong phình ra ngoài đường nối hai góc.
const double noiKhung = 0.025;

/// Biến đổi phối cảnh đưa tứ giác [khung] về hình chữ nhật. [noi] > 0: lấy thêm một dải quanh tứ giác (theo phần bề
/// ngang, bề cao trang) để chữ ở chỗ mép trang cong phình ra ngoài đường nối hai góc không bị cắt lẹm; nền bàn, bìa
/// sách trong dải được tô màu giấy, phần thừa do bước cắt sát chữ bỏ đi.
cv.Mat lamPhang(cv.Mat anh, List<Diem> khung, {bool khopA4 = true, double noi = 0}) {
  if (laToanAnh(khung, anh.cols, anh.rows)) return anh;
  final g = sapXepGoc(khung);
  final tl = g[0], tr = g[1], br = g[2], bl = g[3];
  var rong = math.max(_kc(tr, tl), _kc(br, bl));
  var cao = math.max(_kc(bl, tl), _kc(br, tr));
  final r = tiLePhoiCanh(g, anh.cols, anh.rows);
  if (r != null) {
    final dt = rong * cao;
    rong = math.sqrt(dt / r);
    cao = math.sqrt(dt * r);
  }
  if (khopA4) {
    final rr = cao / rong;
    for (final dich in [tiLeA4, 1 / tiLeA4]) {
      if ((rr / dich - 1).abs() < 0.06) cao = rong * dich;
    }
  }
  final w = math.max(rong.round(), 10), h = math.max(cao.round(), 10);
  final nx = (noi * w).round(), ny = (noi * h).round();
  final m = cv.getPerspectiveTransform2f(
    cv.VecPoint2f.fromList([for (final (x, y) in g) cv.Point2f(x, y)]),
    cv.VecPoint2f.fromList([
      cv.Point2f(nx.toDouble(), ny.toDouble()),
      cv.Point2f(nx + w - 1.0, ny.toDouble()),
      cv.Point2f(nx + w - 1.0, ny + h - 1.0),
      cv.Point2f(nx.toDouble(), ny + h - 1.0),
    ]),
  );
  final ra = cv.warpPerspective(anh, m, (w + 2 * nx, h + 2 * ny), flags: cv.INTER_CUBIC, borderMode: cv.BORDER_REPLICATE);
  return (nx > 0 || ny > 0) && ra.channels == 3 ? _xoaNenNoi(ra, nx, ny) : ra;
}

/// Dải nới quanh trang (ngoài tứ giác mép giấy) có nền bàn, bìa sách, ngón tay: tô màu giấy những mảng lớn, tối
/// hoặc có màu, chạm mép ảnh. Nét chữ (mảnh) ở chỗ mép trang cong phình ra ngoài thì giữ. Giống _xoa_nen_noi (Python).
cv.Mat _xoaNenNoi(cv.Mat anh, int nx, int ny) {
  final h = anh.rows, w = anh.cols, n = h * w;
  final hsv = u8Chep(cv.cvtColor(anh, cv.COLOR_BGR2HSV));
  // độ sáng giấy: trung vị kênh V trong phần trang
  final hist = List<int>.filled(256, 0);
  var dem = 0;
  for (var y = ny; y < h - ny; y += 2) {
    for (var x = nx; x < w - nx; x += 2) {
      hist[hsv[(y * w + x) * 3 + 2]]++;
      dem++;
    }
  }
  var tich = 0, giayV = 255;
  for (var v = 0; v < 256; v++) {
    tich += hist[v];
    if (tich * 2 >= dem) {
      giayV = v;
      break;
    }
  }
  // chỉ xét dải nới (và một chút vào trong, chỗ mép giấy bị bóng)
  final ax = nx + math.max(2, nx ~/ 3), ay = ny + math.max(2, ny ~/ 3);
  final khac = Uint8List(n);
  for (var y = 0; y < h; y++) {
    final trongY = y >= ay && y < h - ay;
    for (var x = 0; x < w; x++) {
      if (trongY && x >= ax && x < w - ax) continue;
      final i = y * w + x;
      if (hsv[i * 3 + 2] < giayV - 45 || hsv[i * 3 + 1] > 70) khac[i] = 1;
    }
  }
  final k = math.max(5, (0.012 * math.min(h, w)).toInt()) | 1;
  final lon = cv.morphologyEx(cv.Mat.fromList(h, w, cv.MatType.CV_8UC1, khac), cv.MORPH_OPEN,
      cv.getStructuringElement(cv.MORPH_ELLIPSE, (k, k)), borderType: cv.BORDER_REPLICATE);
  final nhanM = cv.Mat.empty(), tkM = cv.Mat.empty(), tamM = cv.Mat.empty();
  final sn = cv.connectedComponentsWithStats(lon, nhanM, tkM, tamM, 8, cv.MatType.CV_32S, cv.CCL_DEFAULT);
  final nhan = i32Chep(nhanM), tk = i32Chep(tkM);
  final chamBien = List<bool>.filled(sn, false);
  var co = false;
  for (var i = 1; i < sn; i++) {
    final x = tk[i * 5], y = tk[i * 5 + 1], cw = tk[i * 5 + 2], ch = tk[i * 5 + 3];
    if (x == 0 || y == 0 || x + cw >= w || y + ch >= h) {
      chamBien[i] = true;
      co = true;
    }
  }
  if (!co) return anh;
  final xoa = Uint8List(n);
  for (var i = 0; i < n; i++) {
    if (chamBien[nhan[i]]) xoa[i] = 1;
  }
  final xoaM = u8Chep(cv.dilate(cv.Mat.fromList(h, w, cv.MatType.CV_8UC1, xoa), cv.Mat.ones(5, 5, cv.MatType.CV_8UC1)));
  // màu giấy: trung vị từng kênh phần trang (lấy thưa)
  final d = u8Chep(anh);
  final mau = <int>[];
  for (var c = 0; c < 3; c++) {
    final hc = List<int>.filled(256, 0);
    var dc = 0;
    for (var y = ny; y < h - ny; y += 3) {
      for (var x = nx; x < w - nx; x += 3) {
        hc[d[(y * w + x) * 3 + c]]++;
        dc++;
      }
    }
    var t = 0, v = 255;
    for (var u = 0; u < 256; u++) {
      t += hc[u];
      if (t * 2 >= dc) {
        v = u;
        break;
      }
    }
    mau.add(v);
  }
  final ra = anh.clone();
  final o = ra.data;
  for (var i = 0; i < n; i++) {
    if (xoaM[i] > 0) {
      o[i * 3] = mau[0];
      o[i * 3 + 1] = mau[1];
      o[i * 3 + 2] = mau[2];
    }
  }
  return ra;
}

/// Xoay ngược chiều kim đồng hồ `gocDo` độ, nới khung để không mất nội dung.
cv.Mat xoayAnh(cv.Mat anh, double gocDo, {cv.Scalar? mauNen}) {
  if (gocDo.abs() < 1e-6) return anh;
  final h = anh.rows, w = anh.cols;
  final m = cv.getRotationMatrix2D(cv.Point2f(w / 2, h / 2), gocDo, 1.0);
  final cos = m.at<double>(0, 0).abs(), sin = m.at<double>(0, 1).abs();
  final rong = (h * sin + w * cos + 0.5).toInt(), cao = (h * cos + w * sin + 0.5).toInt();
  m.set<double>(0, 2, m.at<double>(0, 2) + rong / 2 - w / 2);
  m.set<double>(1, 2, m.at<double>(1, 2) + cao / 2 - h / 2);
  return cv.warpAffine(
    anh,
    m,
    (rong, cao),
    flags: cv.INTER_CUBIC,
    borderMode: cv.BORDER_CONSTANT,
    borderValue: mauNen ?? cv.mean(anh),
  );
}

cv.Mat xoay90(cv.Mat anh, int gocCungKim) {
  switch (gocCungKim % 360) {
    case 90:
      return cv.rotate(anh, cv.ROTATE_90_CLOCKWISE);
    case 180:
      return cv.rotate(anh, cv.ROTATE_180);
    case 270:
      return cv.rotate(anh, cv.ROTATE_90_COUNTERCLOCKWISE);
    default:
      return anh;
  }
}

/// Góc (độ, ngược chiều kim đồng hồ) cần xoay để dòng chữ nằm ngang, theo phép chiếu ngang.
double doNghieng(cv.Mat anh, {double gioiHan = 6.0}) {
  var xam = anh.channels == 3 ? cv.cvtColor(anh, cv.COLOR_BGR2GRAY) : anh;
  xam = thuNho(xam, 1000).$1;
  final nhiPhan = cv.adaptiveThreshold(xam, 255, cv.ADAPTIVE_THRESH_MEAN_C, cv.THRESH_BINARY_INV, 25, 15);
  final h = nhiPhan.rows, w = nhiPhan.cols;
  var tong = 0;
  for (final v in nhiPhan.data) {
    if (v > 0) tong++;
  }
  if (tong < 0.003 * h * w) return 0.0;
  final tam = cv.Point2f(w / 2, h / 2);

  double diem(double a) {
    final xoay = cv.warpAffine(nhiPhan, cv.getRotationMatrix2D(tam, a, 1.0), (w, h), flags: cv.INTER_NEAREST);
    final d = xoay.data;
    var truoc = 0.0, s = 0.0;
    for (var y = 0; y < h; y++) {
      var hang = 0;
      for (var x = y * w, het = x + w; x < het; x++) {
        hang += d[x];
      }
      if (y > 0) s += (hang - truoc) * (hang - truoc);
      truoc = hang.toDouble();
    }
    return s;
  }

  double tim(double tu, double den, double buoc) {
    var tot = tu, diemTot = -1.0;
    for (var a = tu; a <= den + 1e-6; a += buoc) {
      final d = diem(a);
      if (d > diemTot) {
        diemTot = d;
        tot = a;
      }
    }
    return tot;
  }

  var tot = tim(-gioiHan, gioiHan, 0.5);
  tot = tim(tot - 0.5, tot + 0.5, 0.1);
  return tot.abs() < 0.1 ? 0.0 : (tot * 100).round() / 100;
}

/// Tô trắng dải nền bàn sót ở mép trang sau khi cắt (dùng cho ảnh đã làm sạch).
cv.Mat xoaVienToi(cv.Mat anh, {double beRong = 0.02}) {
  final h = anh.rows, w = anh.cols;
  final a = anh.data;
  final toi = matNaRong(h, w);
  final t = toi.data;
  for (var p = 0; p < h * w; p++) {
    final i = p * 3;
    t[p] = (math.min(a[i], math.min(a[i + 1], a[i + 2])) < 200) ? 1 : 0;
  }
  final dh = math.max(3, (h * beRong).toInt()), dw = math.max(3, (w * beRong).toInt());
  final xoa = matNaRong(h, w);
  final xd = xoa.data;
  var coXoa = false;
  // Xét riêng từng dải mép, vì viền bốn cạnh thường nối liền qua các góc.
  for (final (x0, y0, rw, rh, doc) in [
    (0, 0, w, dh, false),
    (0, h - dh, w, dh, false),
    (0, 0, dw, h, true),
    (w - dw, 0, dw, h, true),
  ]) {
    final dai = toi.region(cv.Rect(x0, y0, rw, rh)).clone();
    final k = math.max(3, (0.03 * (doc ? h : w)).toInt());
    final noi = cv.morphologyEx(dai, cv.MORPH_CLOSE, cv.Mat.ones(doc ? k : 1, doc ? 1 : k, cv.MatType.CV_8UC1));
    final nhan = cv.Mat.empty(), tk = cv.Mat.empty(), tam = cv.Mat.empty();
    final n = cv.connectedComponentsWithStats(noi, nhan, tk, tam, 8, cv.MatType.CV_32S, cv.CCL_DEFAULT);
    final giu = List<bool>.filled(n, false);
    // mép ngoài của dải (sát mép ảnh): trên, dưới, trái, phải
    final ngoai = y0 == 0 && !doc ? 0 : (!doc ? 1 : (x0 == 0 ? 2 : 3));
    for (var j = 1; j < n; j++) {
      final dd = tk.at<int>(j, doc ? cv.CC_STAT_HEIGHT : cv.CC_STAT_WIDTH);
      final l = tk.at<int>(j, cv.CC_STAT_LEFT), tp = tk.at<int>(j, cv.CC_STAT_TOP);
      final cw = tk.at<int>(j, cv.CC_STAT_WIDTH), ch = tk.at<int>(j, cv.CC_STAT_HEIGHT);
      // vệt nền dài dọc mép, hoặc mảnh nền chạm sát mép ảnh (mép trang cong để lại vệt đứt đoạn)
      final chamMep = switch (ngoai) {
        0 => tp == 0,
        1 => tp + ch == rh,
        2 => l == 0,
        _ => l + cw == rw,
      };
      giu[j] = dd >= 0.1 * (doc ? h : w) || chamMep;
    }
    if (!giu.contains(true)) continue;
    final dd = dai.data;
    for (var y = 0; y < rh; y++) {
      for (var x = 0; x < rw; x++) {
        if (dd[y * rw + x] > 0 && giu[nhan.at<int>(y, x)]) {
          xd[(y + y0) * w + x + x0] = 1;
          coXoa = true;
        }
      }
    }
  }
  if (!coXoa) return anh;
  final mo = cv.dilate(xoa, cv.Mat.ones(3, 3, cv.MatType.CV_8UC1));
  final kq = anh.clone();
  final o = kq.data, m = mo.data;
  for (var p = 0; p < h * w; p++) {
    if (m[p] > 0) {
      o[p * 3] = 255;
      o[p * 3 + 1] = 255;
      o[p * 3 + 2] = 255;
    }
  }
  return kq;
}

/// Khớp đường thẳng x = k·y + c (bình phương nhỏ nhất); trả (k, c).
(double, double) _khopThang(List<double> y, List<double> x) {
  final n = y.length;
  final my = y.reduce((a, b) => a + b) / n, mx = x.reduce((a, b) => a + b) / n;
  var sxy = 0.0, syy = 0.0;
  for (var i = 0; i < n; i++) {
    sxy += (y[i] - my) * (x[i] - mx);
    syy += (y[i] - my) * (y[i] - my);
  }
  final k = syy > 0 ? sxy / syy : 0.0;
  return (k, mx - k * my);
}

double _trungVi(List<double> a) {
  final b = [...a]..sort();
  return b.length.isOdd ? b[b.length ~/ 2] : (b[b.length ~/ 2 - 1] + b[b.length ~/ 2]) / 2;
}

/// Đường cắt giữa hai trang sách mở: (x ở mép trên, x ở mép dưới) theo tọa độ ảnh, đi giữa khe trắng giữa hai khối chữ
/// (không theo bóng gáy: bóng thường lệch sang một trang, cắt theo bóng thì phạm vào chữ đầu dòng). Khe xiên khi cặp
/// trang nghiêng: đo khe theo từng dải ngang rồi khớp một đường thẳng. null nếu không thấy khe rõ. Giống _khe_gay (Python).
(double, double)? kheGay(cv.Mat anh) {
  final w = anh.cols;
  final s = math.min(1.0, 1000 / w);
  final nho = s < 1 ? cv.resize(anh, ((anh.cols * s).round(), (anh.rows * s).round()), interpolation: cv.INTER_AREA) : anh;
  final xam = nho.channels == 3 ? cv.cvtColor(nho, cv.COLOR_BGR2GRAY) : nho;
  final hn = xam.rows, wn = xam.cols;
  final muc = cv.adaptiveThreshold(xam, 1, cv.ADAPTIVE_THRESH_MEAN_C, cv.THRESH_BINARY_INV, 25, 15);
  final nhanM = cv.Mat.empty(), tkM = cv.Mat.empty(), tamM = cv.Mat.empty();
  final n = cv.connectedComponentsWithStats(muc, nhanM, tkM, tamM, 8, cv.MatType.CV_32S, cv.CCL_DEFAULT);
  if (n < 40) return null;
  final nhan = i32Chep(nhanM), tk = i32Chep(tkM);
  final cao = <double>[];
  for (var i = 1; i < n; i++) {
    final cw = tk[i * 5 + 2], ch = tk[i * 5 + 3];
    if (ch >= 3 && ch < 0.05 * hn && cw < 0.1 * wn) cao.add(ch.toDouble());
  }
  if (cao.length < 30) return null;
  final caoChu = _trungVi(cao);
  // nét chữ: cỡ chữ, không chạm mép ảnh; nếp gáy, mép giấy (dài, mảnh) và đốm nhỏ không tính
  final chu = Uint8List(n);
  for (var i = 1; i < n; i++) {
    final x = tk[i * 5], cw = tk[i * 5 + 2], ch = tk[i * 5 + 3], dt = tk[i * 5 + 4];
    if (ch >= 3 && ch < 0.05 * hn && cw < 0.1 * wn && ch <= 3 * caoChu && cw <= 6 * caoChu && dt >= 3 && x > 1 &&
        x + cw < wn - 1) {
      chu[i] = 1;
    }
  }
  // số điểm mực chữ theo từng cột, theo từng dải ngang
  const soDai = 12;
  final cotDai = List.generate(soDai, (_) => List<int>.filled(wn, 0));
  for (var y = 0; y < hn; y++) {
    final dai = math.min(soDai - 1, y * soDai ~/ hn);
    final c = cotDai[dai];
    for (var x = 0; x < wn; x++) {
      if (chu[nhan[y * wn + x]] == 1) c[x]++;
    }
  }
  final lo = (0.3 * wn).toInt(), hi = (0.7 * wn).toInt();
  List<(int, int)> khe(List<int> cot, int toiThieu) {
    final ra = <(int, int)>[];
    int? bd;
    for (var k = lo; k < hi; k++) {
      final t = cot[k] == 0;
      if (t && bd == null) bd = k;
      if ((!t || k == hi - 1) && bd != null) {
        final kt = t ? k + 1 : k;
        if (kt - bd >= toiThieu) ra.add((bd, kt));
        bd = null;
      }
    }
    return ra;
  }

  int tong(List<int> c, int a, int b) {
    var t = 0;
    for (var k = a; k < b; k++) {
      t += c[k];
    }
    return t;
  }

  // khe chung cả trang: đoạn trắng rộng nhất ở giữa (lề trong hai trang cộng lại, rộng hơn mọi khoảng cách chữ);
  // cho phép vài điểm mực lẻ (dấu, bụi) trong khe
  final nguong = math.max(1, (0.002 * hn).toInt());
  final cot = List<int>.filled(wn, 0);
  for (var x = 0; x < wn; x++) {
    var t = 0;
    for (final c in cotDai) {
      t += c[x];
    }
    cot[x] = t <= nguong ? 0 : t;
  }
  final chung = khe(cot, math.max(3, (1.5 * caoChu).toInt()));
  if (chung.isEmpty) return null;
  var (g0, g1) = chung.first;
  for (final d in chung) {
    if (d.$2 - d.$1 > g1 - g0) (g0, g1) = d;
  }
  // hai bên khe đều phải có chữ (cặp trang thật)
  final tongMuc = tong(cot, 0, wn);
  if (tong(cot, 0, g0) < 0.2 * tongMuc || tong(cot, g1, wn) < 0.2 * tongMuc) return null;
  // theo dải ngang: tâm khe ở từng dải (dải có chữ cả hai bên, khe không quá rộng do dòng ngắn)
  final gr = g1 - g0;
  final tam = <double>[], yy = <double>[], rong = <double>[];
  for (var b = 0; b < soDai; b++) {
    final y0 = b * hn ~/ soDai, y1 = (b + 1) * hn ~/ soDai;
    final c = cotDai[b];
    final cac = khe(c, 2);
    if (cac.isEmpty) continue;
    int chong((int, int) d) => math.min(d.$2, g1 + 2 * gr) - math.max(d.$1, g0 - 2 * gr);
    var d = cac.first;
    for (final e in cac) {
      if (chong(e) > chong(d)) d = e;
    }
    if (d.$2 <= g0 - gr || d.$1 >= g1 + gr) continue;
    if (tong(c, 0, d.$1) < 3 || tong(c, d.$2, wn) < 3) continue;
    tam.add((d.$1 + d.$2) / 2);
    yy.add((y0 + y1) / 2);
    rong.add((d.$2 - d.$1).toDouble());
  }
  var xTren = (g0 + g1) / 2, xDuoi = xTren;
  if (tam.length >= 4) {
    // bỏ dải có khe quá rộng (dòng cuối đoạn ngắn, dải trống một bên)
    final tvRong = _trungVi(rong);
    var t = <double>[], y = <double>[];
    for (var i = 0; i < tam.length; i++) {
      if (rong[i] <= 1.6 * tvRong) {
        t.add(tam[i]);
        y.add(yy[i]);
      }
    }
    if (t.length >= 4) {
      var (k, c0) = _khopThang(y, t);
      for (var lan = 0; lan < 2; lan++) {
        final du = [for (var i = 0; i < t.length; i++) (t[i] - (k * y[i] + c0)).abs()];
        final nguongDu = math.max(2.0, 2.5 * _trungVi(du));
        final t2 = <double>[], y2 = <double>[];
        for (var i = 0; i < t.length; i++) {
          if (du[i] <= nguongDu) {
            t2.add(t[i]);
            y2.add(y[i]);
          }
        }
        if (t2.length < 4) break;
        (k, c0) = _khopThang(y2, t2);
        t = t2;
        y = y2;
      }
      k = k.clamp(-0.1, 0.1); // gáy nghiêng tối đa ~6°
      xTren = c0;
      xDuoi = k * hn + c0;
    }
  }
  return (xTren / s, xDuoi / s);
}

/// Cắt ảnh làm hai theo đường thẳng ([xTren] ở mép trên, [xDuoi] ở mép dưới). Phần của nửa này nằm bên kia đường cắt
/// (đường xiên) được lấp bằng chính điểm ảnh trên đường cắt (nền khe gáy kéo dài), không lẫn chữ trang bên.
(cv.Mat, cv.Mat) catTheoDuong(cv.Mat anh, double xTren, double xDuoi) {
  final h = anh.rows, w = anh.cols;
  final duong = [for (var y = 0; y < h; y++) xTren + (xDuoi - xTren) * y / math.max(h - 1, 1)];
  final a = duong.reduce(math.max).ceil().clamp(1, w - 1);
  final b = duong.reduce(math.min).floor().clamp(1, w - 1);
  cv.Mat cat(int x0, int rong, bool trai) {
    final mx = cv.Mat.zeros(h, rong, cv.MatType.CV_32FC1), my = cv.Mat.zeros(h, rong, cv.MatType.CV_32FC1);
    final ax = f32(mx), ay = f32(my);
    for (var y = 0; y < h; y++) {
      final d = duong[y];
      for (var x = 0; x < rong; x++) {
        final i = y * rong + x;
        final xx = (x0 + x).toDouble();
        ax[i] = trai ? math.min(xx, d) : math.max(xx, d);
        ay[i] = y.toDouble();
      }
    }
    return cv.remap(anh, mx, my, cv.INTER_LINEAR, borderMode: cv.BORDER_REPLICATE);
  }

  return (cat(0, a, true), cat(b, w - b, false));
}

/// Tách ảnh hai trang sách mở thành hai trang, cắt giữa khe trắng ở gáy (đường thẳng, có thể xiên). Khổ gần vuông
/// (không tìm được mép, cặp trang hẹp) vẫn tách nếu thấy rõ khe gáy giữa hai khối chữ. Giống tach_trang_doi (Python).
List<cv.Mat> tachTrangDoi(cv.Mat anh) {
  final h = anh.rows, w = anh.cols;
  if (w < h) return [anh];
  final duong = kheGay(anh);
  if (duong != null) {
    final (trai, phai) = catTheoDuong(anh, duong.$1, duong.$2);
    return [trai, phai];
  }
  if (w < 1.15 * h) return [anh];
  // không thấy khe chữ rõ (trang ít chữ, ảnh): theo bóng gáy hoặc cột ít mực nhất
  final s = 800 / w;
  final xam = cv.cvtColor(
    cv.resize(anh, (800, math.max(1, (h * s).round())), interpolation: cv.INTER_AREA),
    cv.COLOR_BGR2GRAY,
  );
  final hn = xam.rows, wn = xam.cols, d = xam.data;
  final cot = List<double>.filled(wn, 0), mucCot = List<double>.filled(wn, 0);
  for (var y = 0; y < hn; y++) {
    for (var x = 0; x < wn; x++) {
      final v = d[y * wn + x];
      cot[x] += v;
      if (v < 128) mucCot[x] += 1;
    }
  }
  final moCot = moGauss1D([for (final c in cot) c / hn], 5);
  final lo = (0.35 * wn).toInt(), hi = (0.65 * wn).toInt();
  var i = lo;
  for (var k = lo; k < hi; k++) {
    if (moCot[k] < moCot[i]) i = k;
  }
  final sx = [...moCot]..sort();
  var x = i;
  if (moCot[i] >= sx[sx.length ~/ 2] - 12) {
    final moMuc = moGauss1D([for (final c in mucCot) c / hn], 5);
    x = lo;
    for (var k = lo; k < hi; k++) {
      if (moMuc[k] < moMuc[x]) x = k;
    }
  }
  final cat = (x / s).round().clamp(1, w - 1);
  return [anh.region(cv.Rect(0, 0, cat, h)).clone(), anh.region(cv.Rect(cat, 0, w - cat, h)).clone()];
}
