// Tìm mép giấy kiểu CamScanner: gom ứng viên tứ giác từ nhiều nguồn, chấm điểm theo độ bám cạnh, tinh chỉnh từng cạnh.
// Chuyển từ ung-dung/loi_xu_ly/tim_mep.py (đã đo trên bộ ảnh tổng hợp kiem_thu/anh_mau_mep: 17/17, hai bộ ngẫu nhiên 53/53;
// bộ tìm mép cũ chỉ đạt khoảng một nửa: trượt khi giấy nằm trên bàn trắng, nền lộn xộn, giấy chồng giấy).
//
// 1. Thu nhỏ (cạnh dài 640), xóa chữ bằng phép đóng hình thái, đổi sang Lab để thấy cả mép chỉ khác màu.
// 2. Ứng viên tứ giác: đường bao ảnh cạnh Canny (3 mức), vùng Otsu sáng/tối, phân cụm màu k-means, ghép 4 đường Hough.
// 3. Chấm điểm: rải điểm dọc từng cạnh, đo đạo hàm vuông góc với cạnh; cạnh thật có đạo hàm mạnh, cùng dấu trên gần
//    hết chiều dài (ngưỡng theo độ nhiễu hai bên mép). Cộng phần diện tích và phần "giống giấy" (sáng, ít màu) bên trong.
// 4. Tờ giấy nằm trên vật khác (tờ giấy trắng lót dưới, bìa sổ): chọn tứ giác trong nếu vành ngoài không có chữ.
// 5. Tinh chỉnh ở ảnh lớn hơn (1280): dò cực đại đạo hàm dọc pháp tuyến, khớp đường thẳng, giao lại ra 4 góc.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'anh.dart';

const int _canhNho = 640;
const int _canhTinh = 1280;
const double _nguongMin = 8, _nguongMax = 24;

/// Ảnh đã chuẩn bị ở một cỡ: ảnh nhỏ, Lab đã xóa chữ, đạo hàm của kênh dốc nhất.
class _Anh {
  _Anh(this.s, this.nho, this.lab, this.gx, this.gy, this.w, this.h, this.nguong);
  final double s;
  final cv.Mat nho, lab;
  final Float32List gx, gy;
  final int w, h;
  final double nguong;
}

_Anh _chuanBi(cv.Mat anh, int canh) {
  final (nho, s) = thuNho(anh, canh);
  final k = math.max(5, (9 * math.max(nho.rows, nho.cols) / _canhNho).round()) | 1;
  final sach = cv.medianBlur(
    cv.morphologyEx(
      nho,
      cv.MORPH_CLOSE,
      cv.getStructuringElement(cv.MORPH_ELLIPSE, (k, k)),
      borderType: cv.BORDER_REPLICATE,
    ),
    5,
  );
  final lab = cv.cvtColor(sach, cv.COLOR_BGR2Lab);
  final kenh = cv.split(lab);
  final h = lab.rows, w = lab.cols, n = h * w;
  final gx = Float32List(n), gy = Float32List(n), lon = Float32List(n);
  for (var c = 0; c < 3; c++) {
    final mo = cv.gaussianBlur(kenh[c].convertTo(cv.MatType.CV_32FC1), (0, 0), 1.0);
    final he = (c == 0 ? 1.0 : 2.0) / 4; // a, b nhân 2 vì dải giá trị hẹp hơn L
    final sx = f32Chep(cv.sobel(mo, cv.MatType.CV_32F, 1, 0, ksize: 3));
    final sy = f32Chep(cv.sobel(mo, cv.MatType.CV_32F, 0, 1, ksize: 3));
    for (var i = 0; i < n; i++) {
      final x = sx[i] * he, y = sy[i] * he;
      final m = x * x + y * y;
      if (c == 0 || m > lon[i]) {
        lon[i] = m;
        gx[i] = x;
        gy[i] = y;
      }
    }
  }
  // ngưỡng mép theo độ nhiễu nền: 2,5 lần phân vị 90 của độ dốc toàn ảnh (đã xóa chữ) cộng 4
  final mau = <double>[];
  for (var y = 0; y < h; y += 2) {
    for (var x = 0; x < w; x += 2) {
      mau.add(math.sqrt(lon[y * w + x]));
    }
  }
  mau.sort();
  final p90 = mau.isEmpty ? 0.0 : mau[(0.9 * (mau.length - 1)).round()];
  return _Anh(s, nho, lab, gx, gy, w, h, (2.5 * p90 + 4).clamp(_nguongMin, _nguongMax));
}

// ---------- hình học ----------

typedef _Q = List<Diem>;

double _kc(Diem a, Diem b) => math.sqrt((a.$1 - b.$1) * (a.$1 - b.$1) + (a.$2 - b.$2) * (a.$2 - b.$2));

/// Sắp 4 điểm: trên trái, trên phải, dưới phải, dưới trái (thuận chiều kim đồng hồ trên ảnh).
_Q _sapXep(_Q q) {
  final cx = q.map((e) => e.$1).reduce((a, b) => a + b) / 4;
  final cy = q.map((e) => e.$2).reduce((a, b) => a + b) / 4;
  final s = [...q]..sort((a, b) => math.atan2(a.$2 - cy, a.$1 - cx).compareTo(math.atan2(b.$2 - cy, b.$1 - cx)));
  var dau = 0;
  for (var i = 1; i < 4; i++) {
    if (s[i].$1 + s[i].$2 < s[dau].$1 + s[dau].$2) dau = i;
  }
  return [for (var i = 0; i < 4; i++) s[(dau + i) % 4]];
}

bool _loi(_Q q) {
  var duong = 0, am = 0;
  for (var i = 0; i < 4; i++) {
    final a = q[i], b = q[(i + 1) % 4], c = q[(i + 2) % 4];
    final z = (b.$1 - a.$1) * (c.$2 - b.$2) - (b.$2 - a.$2) * (c.$1 - b.$1);
    if (z > 0) duong++;
    if (z < 0) am++;
  }
  return duong == 4 || am == 4;
}

bool _hopLe(_Q q, int h, int w) {
  if (!_loi(q) || dienTich(q) < 0.08 * h * w) return false;
  final ngan = math.min(h, w);
  for (var i = 0; i < 4; i++) {
    final a = q[(i + 3) % 4], b = q[i], c = q[(i + 1) % 4];
    if (_kc(c, b) < 0.12 * ngan) return false;
    final ux = a.$1 - b.$1, uy = a.$2 - b.$2, vx = c.$1 - b.$1, vy = c.$2 - b.$2;
    final cos = (ux * vx + uy * vy) / math.max(math.sqrt(ux * ux + uy * uy) * math.sqrt(vx * vx + vy * vy), 1e-6);
    if (cos <= -0.77 || cos >= 0.77) return false; // góc trong 40°..140°
  }
  return true;
}

/// Đường thẳng (điểm, hướng đơn vị).
typedef _Duong = (Diem, Diem);

Diem? _giao(_Duong d1, _Duong d2) {
  final (p, u) = d1;
  final (q, v) = d2;
  final det = u.$1 * v.$2 - u.$2 * v.$1;
  if (det.abs() < 1e-6) return null;
  final t = ((q.$1 - p.$1) * v.$2 - (q.$2 - p.$2) * v.$1) / det;
  return (p.$1 + t * u.$1, p.$2 + t * u.$2);
}

// ---------- ứng viên ----------

/// Tứ giác xấp xỉ một bao lồi: giảm dần độ mịn tới khi còn 4 đỉnh; thừa đỉnh thì chọn 4 đỉnh bao diện tích lớn nhất.
_Q? _bonDinh(List<cv.Point> bao) {
  final vec = cv.VecPoint.fromList(bao);
  final chuVi = cv.arcLength(vec, true);
  List<Diem>? xx;
  for (final eps in const [0.01, 0.02, 0.03, 0.045, 0.06, 0.08]) {
    final a = cv.approxPolyDP(vec, eps * chuVi, true);
    xx = [for (var i = 0; i < a.length; i++) (a[i].x.toDouble(), a[i].y.toDouble())];
    if (xx.length == 4) return xx;
    if (xx.length < 4) return null;
    if (xx.length <= 8) break;
  }
  if (xx == null || xx.length > 12) return null;
  _Q? tot;
  var dtTot = 0.0;
  final n = xx.length;
  for (var a = 0; a < n; a++) {
    for (var b = a + 1; b < n; b++) {
      for (var c = b + 1; c < n; c++) {
        for (var d = c + 1; d < n; d++) {
          final q = [xx[a], xx[b], xx[c], xx[d]];
          final dt = dienTich(q);
          if (dt > dtTot) {
            tot = q;
            dtTot = dt;
          }
        }
      }
    }
  }
  return tot;
}

List<_Q> _tuMatNa(cv.Mat matNa, double dt, int toiDa, int loai) {
  final (duong, _) = cv.findContours(matNa, loai, cv.CHAIN_APPROX_SIMPLE);
  final ds = [for (var i = 0; i < duong.length; i++) duong[i]];
  final dtd = [for (final c in ds) cv.contourArea(c)];
  final thuTu = List<int>.generate(ds.length, (i) => i)..sort((a, b) => dtd[b].compareTo(dtd[a]));
  final kq = <_Q>[];
  for (final i in thuTu.take(toiDa)) {
    final bao = baoLoi([for (var k = 0; k < ds[i].length; k++) ds[i][k]]);
    if (bao.length < 3 || dienTich([for (final p in bao) (p.x.toDouble(), p.y.toDouble())]) < 0.08 * dt) break;
    final q = _bonDinh(bao);
    if (q != null) kq.add(q);
  }
  return kq;
}

/// Ghép 4 đường thẳng Hough thành tứ giác: hai cặp gần song song, hai cặp lệch hướng nhau nhiều.
List<_Q> _tuDuongThang(cv.Mat canh, int h, int w) {
  final ngan = math.min(h, w);
  final m = cv.HoughLinesP(canh, 1, math.pi / 180, 50, minLineLength: 0.12 * ngan, maxLineGap: 0.03 * ngan);
  if (m.isEmpty || m.rows == 0) return [];
  final d = i32Chep(m);
  final doan = [
    for (var i = 0; i + 3 < d.length; i += 4)
      (d[i].toDouble(), d[i + 1].toDouble(), d[i + 2].toDouble(), d[i + 3].toDouble()),
  ]..sort((a, b) => _kc((b.$1, b.$2), (b.$3, b.$4)).compareTo(_kc((a.$1, a.$2), (a.$3, a.$4))));
  final duong = <_Duong>[];
  final cos4 = math.cos(4 * math.pi / 180);
  for (final (x1, y1, x2, y2) in doan) {
    final l = math.max(_kc((x1, y1), (x2, y2)), 1e-6);
    final u = ((x2 - x1) / l, (y2 - y1) / l);
    final p = ((x1 + x2) / 2, (y1 + y2) / 2);
    var trung = false;
    for (final (p2, u2) in duong) {
      final cs = (u.$1 * u2.$1 + u.$2 * u2.$2).abs();
      final kc = ((p.$1 - p2.$1) * -u.$2 + (p.$2 - p2.$2) * u.$1).abs();
      if (cs > cos4 && kc < 0.015 * ngan) {
        trung = true;
        break;
      }
    }
    if (!trung) duong.add((p, u));
    if (duong.length >= 16) break;
  }
  final cap = <(_Duong, _Duong)>[];
  final cos30 = math.cos(30 * math.pi / 180), cos50 = math.cos(50 * math.pi / 180);
  for (var i = 0; i < duong.length; i++) {
    for (var j = i + 1; j < duong.length; j++) {
      final (pa, ua) = duong[i];
      final (pb, ub) = duong[j];
      if ((ua.$1 * ub.$1 + ua.$2 * ub.$2).abs() < cos30) continue;
      if (((pb.$1 - pa.$1) * -ua.$2 + (pb.$2 - pa.$2) * ua.$1).abs() < 0.2 * ngan) continue;
      cap.add((duong[i], duong[j]));
    }
  }
  final kq = <_Q>[];
  for (var i = 0; i < cap.length; i++) {
    for (var j = i + 1; j < cap.length; j++) {
      final (a, b) = cap[i];
      final (c, e) = cap[j];
      if ((a.$2.$1 * c.$2.$1 + a.$2.$2 * c.$2.$2).abs() > cos50) continue;
      final g = [_giao(a, c), _giao(c, b), _giao(b, e), _giao(e, a)];
      if (g.any((x) => x == null)) continue;
      final q = [for (final x in g) x!];
      if (q.any((p) => p.$1 < -0.15 * w || p.$1 > 1.15 * w || p.$2 < -0.15 * h || p.$2 > 1.15 * h)) continue;
      kq.add(q);
    }
  }
  return kq;
}

List<_Q> _ungVien(_Anh a) {
  final h = a.h, w = a.w;
  final dt = (h * w).toDouble();
  final kenh = cv.split(a.lab);
  final u8 = [
    kenh[0],
    kenh[1].convertTo(cv.MatType.CV_8UC1, alpha: 2, beta: -128),
    kenh[2].convertTo(cv.MatType.CV_8UC1, alpha: 2, beta: -128),
  ];
  final kq = <_Q>[];
  // 1. đường bao của ảnh cạnh (ba mức ngưỡng), gộp ba kênh Lab
  for (final (thap, cao) in const [(10.0, 30.0), (20.0, 60.0), (40.0, 120.0)]) {
    var canh = cv.canny(u8[0], thap, cao);
    for (final c in u8.skip(1)) {
      canh = cv.bitwiseOR(canh, cv.canny(c, thap, cao));
    }
    final gian = cv.dilate(canh, cv.Mat.ones(3, 3, cv.MatType.CV_8UC1), iterations: 2, borderType: cv.BORDER_REPLICATE);
    kq.addAll(_tuMatNa(gian, dt, 6, cv.RETR_LIST));
    if (thap == 20) {
      final gian2 = cv.dilate(canh, cv.Mat.ones(2, 2, cv.MatType.CV_8UC1), borderType: cv.BORDER_REPLICATE);
      kq.addAll(_tuDuongThang(gian2, h, w));
    }
  }
  // 2. vùng sáng / tối theo Otsu
  final sang = cv.threshold(cv.gaussianBlur(kenh[0], (5, 5), 0), 0, 255, cv.THRESH_BINARY + cv.THRESH_OTSU).$2;
  final nhan = cv.getStructuringElement(cv.MORPH_ELLIPSE, (9, 9));
  cv.Mat sachMatNa(cv.Mat m) => cv.morphologyEx(
    cv.morphologyEx(m, cv.MORPH_OPEN, nhan, borderType: cv.BORDER_REPLICATE),
    cv.MORPH_CLOSE,
    nhan,
    borderType: cv.BORDER_REPLICATE,
  );
  for (final m in [sang, cv.bitwiseNOT(sang)]) {
    kq.addAll(_tuMatNa(sachMatNa(m), dt, 3, cv.RETR_EXTERNAL));
  }
  // 3. phân cụm màu k-means (2 và 3 cụm) trên ảnh rất nhỏ
  final s = 160 / math.max(h, w);
  final be = cv.resize(a.lab, (
    math.max(1, (w * s).round()),
    math.max(1, (h * s).round()),
  ), interpolation: cv.INTER_AREA);
  final bd = u8Chep(be);
  final nb = be.rows * be.cols;
  final duLieu = <double>[
    for (var i = 0; i < nb; i++) ...[bd[i * 3].toDouble(), bd[i * 3 + 1] * 2.0 - 128, bd[i * 3 + 2] * 2.0 - 128],
  ];
  final mat = cv.Mat.fromList(nb, 3, cv.MatType.CV_32FC1, duLieu);
  for (final k in const [2, 3]) {
    final (_, nhanCum, _) = cv.kmeans(
      mat,
      k,
      cv.Mat.empty(),
      (cv.TERM_EPS + cv.TERM_MAX_ITER, 20, 1.0),
      2,
      cv.KMEANS_PP_CENTERS,
    );
    final l = i32Chep(nhanCum);
    for (var c = 0; c < k; c++) {
      final m = cv.Mat.zeros(be.rows, be.cols, cv.MatType.CV_8UC1);
      final md = m.data;
      for (var i = 0; i < nb; i++) {
        if (l[i] == c) md[i] = 255;
      }
      kq.addAll(_tuMatNa(sachMatNa(cv.resize(m, (w, h), interpolation: cv.INTER_NEAREST)), dt, 2, cv.RETR_EXTERNAL));
    }
  }
  return kq;
}

// ---------- chấm điểm ----------

/// Độ bám cạnh a→b: (tỉ lệ điểm có mép rõ, dấu chủ đạo của đạo hàm, ngưỡng đã dùng); null nếu cạnh gần hết ngoài ảnh.
(double, int, double)? _bamCanh(Diem a, Diem b, _Anh g, {int soDiem = 48, int tamDo = 2}) {
  final w = g.w, h = g.h;
  final l = math.max(_kc(a, b), 1e-6);
  final ux = (b.$1 - a.$1) / l, uy = (b.$2 - a.$2) / l;
  final nx = uy, ny = -ux; // pháp tuyến hướng ra ngoài (tứ giác thuận chiều kim đồng hồ)
  final duong = <double>[], am = <double>[], nhieu = <double>[];
  for (var i = 0; i < soDiem; i++) {
    final t = 0.06 + 0.88 * i / (soDiem - 1);
    final px = a.$1 + (b.$1 - a.$1) * t, py = a.$2 + (b.$2 - a.$2) * t;
    final x0 = px.round(), y0 = py.round();
    if (x0 < 2 || x0 >= w - 2 || y0 < 2 || y0 >= h - 2) continue;
    var lon = -1e9, nho = 1e9;
    for (var d = -tamDo; d <= tamDo; d++) {
      final x = (px + nx * d).round(), y = (py + ny * d).round();
      var v = 0.0;
      if (x >= 2 && x < w - 2 && y >= 2 && y < h - 2) v = g.gx[y * w + x] * nx + g.gy[y * w + x] * ny;
      if (v > lon) lon = v;
      if (v < nho) nho = v;
    }
    duong.add(lon);
    am.add(-nho);
    for (final d in const [-9, -7, -5, 5, 7, 9]) {
      final x = (px + nx * d).round().clamp(0, w - 1), y = (py + ny * d).round().clamp(0, h - 1);
      final gx = g.gx[y * w + x], gy = g.gy[y * w + x];
      nhieu.add(math.sqrt(gx * gx + gy * gy));
    }
  }
  if (duong.length < 0.3 * soDiem) return null;
  // ngưỡng riêng của cạnh theo độ nhiễu hai bên mép: giấy trắng trên giấy trắng mép chỉ chênh ~12 nhưng hai bên phẳng
  nhieu.sort();
  final nguong = (2.5 * nhieu[(0.75 * (nhieu.length - 1)).round()] + 3).clamp(4.0, g.nguong);
  final nd = duong.where((v) => v > nguong).length, na = am.where((v) => v > nguong).length;
  final dau = nd >= na ? 1 : -1;
  return ((dau > 0 ? nd : na) / duong.length, dau, nguong);
}

/// Mặt nạ "giống giấy" (sáng hơn ngưỡng Otsu của L, ít màu) ở 1/4 cỡ ảnh nhỏ, để tính nhanh tỉ lệ giấy trong tứ giác.
(Uint8List, int, int) _giongGiay(_Anh a) {
  final be = cv.resize(a.lab, ((a.w / 4).round(), (a.h / 4).round()), interpolation: cv.INTER_AREA);
  final L = cv.split(be)[0];
  final (nguong, _) = cv.threshold(L, 0, 255, cv.THRESH_BINARY + cv.THRESH_OTSU);
  final d = u8Chep(be), n = be.rows * be.cols;
  final kq = Uint8List(n);
  final ngL = math.min(nguong, 200);
  for (var i = 0; i < n; i++) {
    final sac = ((d[i * 3 + 1] - 128).abs() + (d[i * 3 + 2] - 128).abs()) * 2;
    kq[i] = (d[i * 3] > ngL && sac < 60) ? 1 : 0;
  }
  return (kq, be.cols, be.rows);
}

double _tiLeGiay(_Q q, (Uint8List, int, int) giay, double tl) {
  final (g, w, h) = giay;
  final m = cv.fillPoly(matNaRong(h, w), daGiac([for (final (x, y) in q) (x * tl, y * tl)]), cv.Scalar.all(1));
  final md = u8Chep(m);
  var n = 0, c = 0;
  for (var i = 0; i < md.length; i++) {
    if (md[i] > 0) {
      n++;
      c += g[i];
    }
  }
  return n > 0 ? c / n : 0.0;
}

double _cham(_Q q, _Anh a, (Uint8List, int, int)? giay) {
  if (!_hopLe(q, a.h, a.w)) return -1;
  final f = <double>[];
  final dau = <int>{};
  var biet = 0;
  for (var i = 0; i < 4; i++) {
    final r = _bamCanh(q[i], q[(i + 1) % 4], a);
    if (r == null) {
      f.add(0.55);
    } else {
      f.add(r.$1);
      dau.add(r.$2);
      biet++;
    }
  }
  if (biet < 2) return -1; // quá nửa chu vi nằm ngoài ảnh: không đủ chứng cứ
  final tb = f.reduce((x, y) => x + y) / 4, nhoNhat = f.reduce(math.min);
  if (nhoNhat < 0.3 || tb < 0.5) return -1;
  final dongDau = dau.length <= 1 ? 1.0 : 0.8; // giấy sáng hơn nền thì cả 4 cạnh cùng dấu
  var diem = (0.6 * tb + 0.4 * nhoNhat) * dongDau + 0.45 * dienTich(q) / (a.h * a.w);
  if (giay != null) diem += 0.2 * _tiLeGiay(q, giay, giay.$2 / a.w);
  return diem;
}

/// Cả 4 cạnh đều bám mép rõ (≥ 70% chiều dài) và cùng dấu: tờ giấy thật, không phải khối chữ hay mảnh ghép.
bool _canhRo(_Q q, _Anh a) {
  final dau = <int>{};
  for (var i = 0; i < 4; i++) {
    final r = _bamCanh(q[i], q[(i + 1) % 4], a);
    if (r == null) continue;
    if (r.$1 < 0.7) return false;
    dau.add(r.$2);
  }
  return dau.length <= 1;
}

/// Mật độ mực trong vành giữa tứ giác ngoài và trong, và bên trong tứ giác trong (bỏ dải 7 điểm ảnh sát mép).
(double, double) _matDoMuc(Uint8List muc, int w, int h, _Q ngoai, _Q trong) {
  final nhan = cv.Mat.ones(15, 15, cv.MatType.CV_8UC1);
  final mn = u8Chep(
    cv.erode(cv.fillPoly(matNaRong(h, w), daGiac(ngoai), cv.Scalar.all(1)), nhan, borderType: cv.BORDER_REPLICATE),
  );
  final mtRong = u8Chep(
    cv.dilate(cv.fillPoly(matNaRong(h, w), daGiac(trong), cv.Scalar.all(1)), nhan, borderType: cv.BORDER_REPLICATE),
  );
  final mtHep = u8Chep(
    cv.erode(cv.fillPoly(matNaRong(h, w), daGiac(trong), cv.Scalar.all(1)), nhan, borderType: cv.BORDER_REPLICATE),
  );
  var nv = 0, cv_ = 0, nt = 0, ct = 0;
  for (var i = 0; i < muc.length; i++) {
    if (mn[i] > 0 && mtRong[i] == 0) {
      nv++;
      cv_ += muc[i];
    }
    if (mtHep[i] > 0) {
      nt++;
      ct += muc[i];
    }
  }
  return (nv > 0 ? cv_ / nv : 0.0, nt > 0 ? ct / nt : 0.0);
}

/// Tứ giác tốt nhất có thể là vật bao quanh tờ giấy (tờ giấy trắng lót dưới, bìa sổ). Có tứ giác nằm trong, 4 cạnh rõ,
/// mà vành giữa hai tứ giác gần như không có mực còn bên trong có chữ thì tờ giấy là tứ giác trong.
(_Q, double) _chonTrong(_Q tot, double diemTot, List<(_Q, double)> ds, _Anh a) {
  final xam = cv.cvtColor(a.nho, cv.COLOR_BGR2GRAY);
  final muc = u8Chep(cv.adaptiveThreshold(xam, 1, cv.ADAPTIVE_THRESH_MEAN_C, cv.THRESH_BINARY_INV, 15, 12));
  final sx = [...ds]..sort((x, y) => dienTich(y.$1).compareTo(dienTich(x.$1)));
  while (true) {
    final dtTot = dienTich(tot);
    (_Q, double)? chon;
    final vt = cv.VecPoint.fromList([for (final (x, y) in tot) cv.Point(x.round(), y.round())]);
    for (final (q, d) in sx) {
      if (d < 0.75 * (diemTot - 0.45 * dtTot / (a.w * a.h) - 0.2) || dienTich(q) > 0.92 * dtTot) continue;
      if (q.any((p) => cv.pointPolygonTest(vt, cv.Point2f(p.$1, p.$2), true) < -3)) continue;
      if (!_canhRo(q, a)) continue;
      final (vanh, trong) = _matDoMuc(muc, a.w, a.h, tot, q);
      if (trong > 0.02 && vanh < 0.25 * trong) {
        chon = (q, d);
        break;
      }
    }
    if (chon == null) return (tot, diemTot);
    (tot, diemTot) = chon;
  }
}

// ---------- tinh chỉnh ----------

/// Khớp đường thẳng có trọng số Huber (vài vòng bình phương tối thiểu có trọng số).
_Duong? _khopDuong(List<Diem> p) {
  if (p.length < 2) return null;
  var wt = List<double>.filled(p.length, 1.0);
  _Duong? kq;
  for (var vong = 0; vong < 5; vong++) {
    var sw = 0.0, mx = 0.0, my = 0.0;
    for (var i = 0; i < p.length; i++) {
      sw += wt[i];
      mx += wt[i] * p[i].$1;
      my += wt[i] * p[i].$2;
    }
    mx /= sw;
    my /= sw;
    var sxx = 0.0, sxy = 0.0, syy = 0.0;
    for (var i = 0; i < p.length; i++) {
      final dx = p[i].$1 - mx, dy = p[i].$2 - my;
      sxx += wt[i] * dx * dx;
      sxy += wt[i] * dx * dy;
      syy += wt[i] * dy * dy;
    }
    final goc = 0.5 * math.atan2(2 * sxy, sxx - syy);
    final u = (math.cos(goc), math.sin(goc));
    kq = ((mx, my), u);
    wt = [
      for (final (x, y) in p)
        () {
          final r = ((x - mx) * -u.$2 + (y - my) * u.$1).abs();
          return r <= 1.0 ? 1.0 : 1.0 / r;
        }(),
    ];
  }
  return kq;
}

_Q _tinhChinh(_Q q, _Anh g) {
  final w = g.w, h = g.h;
  final r = math.max(4, (0.012 * math.max(h, w)).toInt());
  final duong = <_Duong>[];
  for (var i = 0; i < 4; i++) {
    final a = q[i], b = q[(i + 1) % 4];
    final l = math.max(_kc(a, b), 1e-6);
    final u = ((b.$1 - a.$1) / l, (b.$2 - a.$2) / l);
    final nx = u.$2, ny = -u.$1;
    final bam = _bamCanh(a, b, g, soDiem: 16, tamDo: 3);
    if (bam == null) {
      duong.add((a, u));
      continue;
    }
    final (_, dau, nguongCanh) = bam;
    final diem = <Diem>[];
    for (var k = 0; k < 60; k++) {
      final t = 0.05 + 0.9 * k / 59;
      final px = a.$1 + (b.$1 - a.$1) * t, py = a.$2 + (b.$2 - a.$2) * t;
      int? tot;
      var gtot = nguongCanh;
      for (var d = -r; d <= r; d++) {
        final x = (px + nx * d).round(), y = (py + ny * d).round();
        if (x < 1 || x >= w - 1 || y < 1 || y >= h - 1) continue;
        final v = dau * (g.gx[y * w + x] * nx + g.gy[y * w + x] * ny);
        if (v > gtot) {
          tot = d;
          gtot = v;
        }
      }
      if (tot != null) diem.add((px + nx * tot, py + ny * tot));
    }
    final dg = diem.length >= 12 ? _khopDuong(diem) : null;
    duong.add(dg ?? (a, u));
  }
  final moi = [for (var i = 0; i < 4; i++) _giao(duong[(i + 3) % 4], duong[i]) ?? q[i]];
  var lech = 0.0;
  for (var i = 0; i < 4; i++) {
    lech = math.max(lech, _kc(moi[i], q[i]));
  }
  if (lech > 0.03 * math.sqrt(h * h + w * w) || !_hopLe(moi, h, w)) return q;
  return moi;
}

// ---------- nửa cặp trang (sách mở chụp sát) ----------

/// Phần trang bên kia gáy thấy được (so với bề rộng trang) để coi là chụp cả cặp trang.
const double trangKeToiThieu = 0.5;

/// Quãng đường từ p theo hướng đơn vị d tới biên ảnh w×h.
double _toiBien(Diem p, Diem d, int h, int w) {
  var t = double.infinity;
  for (final (pk, dk, gioi) in [(p.$1, d.$1, w - 1.0), (p.$2, d.$2, h - 1.0)]) {
    if (dk > 1e-6) t = math.min(t, (gioi - pk) / dk);
    if (dk < -1e-6) t = math.min(t, -pk / dk);
  }
  return math.max(t, 0);
}

/// Sách mở chụp sát, trang bên kia gáy lọt một phần ra ngoài khung (góp ý 14/11/2026: "app chỉ nhận 1/2 trang khi
/// chụp sách"): tứ giác tìm được chỉ là trang còn nguyên, bên kia một cạnh của nó (gáy) là giấy có chữ chạy tới biên
/// ảnh. Trả (cạnh i: q[i]→q[i+1], phần trang bên kia thấy được) nếu thấy được từ [trangKeToiThieu] trở lên; null nếu
/// không (chụp từng trang thì trang bên cạnh thường chỉ lộ một mẩu, không nối). Giống _canh_noi của tim_mep.py.
(int, double)? _canhNoi(_Q q, _Anh a, (Uint8List, int, int) giay) {
  final h = a.h, w = a.w;
  final bien = [
    q.map((p) => p.$1).reduce(math.min),
    q.map((p) => p.$2).reduce(math.min),
    w - 1 - q.map((p) => p.$1).reduce(math.max),
    h - 1 - q.map((p) => p.$2).reduce(math.max),
  ].reduce(math.min);
  if (bien < 3) return null; // chính trang này đã chạm biên
  final xam = cv.cvtColor(a.nho, cv.COLOR_BGR2GRAY);
  final muc = u8Chep(cv.adaptiveThreshold(xam, 1, cv.ADAPTIVE_THRESH_MEAN_C, cv.THRESH_BINARY_INV, 15, 12));
  final lui = u8Chep(cv.erode(cv.fillPoly(matNaRong(h, w), daGiac(q), cv.Scalar.all(1)), cv.Mat.ones(15, 15, cv.MatType.CV_8UC1),
      borderType: cv.BORDER_REPLICATE));
  var nt = 0, ct = 0;
  for (var i = 0; i < muc.length; i++) {
    if (lui[i] > 0) {
      nt++;
      ct += muc[i];
    }
  }
  if (nt == 0) return null;
  final mucTrong = ct / nt;
  if (mucTrong < 0.02) return null;
  final (g, gw, gh) = giay;
  final tl = gw / w;
  (int, double)? tot;
  for (var i = 0; i < 4; i++) {
    final pa = q[i], pb = q[(i + 1) % 4], pc = q[(i + 2) % 4], pd = q[(i + 3) % 4];
    // hai cạnh kề kéo dài qua a, b; bề rộng trang theo từng cạnh kề
    final la = _kc(pa, pd), lb = _kc(pb, pc);
    if (la < 10 || lb < 10) continue;
    final da = ((pa.$1 - pd.$1) / la, (pa.$2 - pd.$2) / la), db = ((pb.$1 - pc.$1) / lb, (pb.$2 - pc.$2) / lb);
    final ta = _toiBien(pa, da, h, w) / la, tb = _toiBien(pb, db, h, w) / lb;
    final thay = math.min(ta, tb);
    // thấy quá ít (chụp từng trang), hoặc trang bên kia đủ trong khung (không phải bị cắt); trang gần máy trông rộng
    // hơn (phối cảnh) nên cho một bên tới 1,3 lần, bên kia phải bị cắt (≤ 1,02)
    if (thay < trangKeToiThieu || thay > 1.02 || math.max(ta, tb) > 1.3) continue;
    // dải bên kia gáy: bỏ 8% sát gáy (bóng gáy), lấy tới 60% bề rộng trang hoặc tới biên
    final u0 = 0.08, u1 = math.min(0.6, thay - 0.02);
    final dai = <Diem>[
      (pa.$1 + da.$1 * la * u0, pa.$2 + da.$2 * la * u0),
      (pb.$1 + db.$1 * lb * u0, pb.$2 + db.$2 * lb * u0),
      (pb.$1 + db.$1 * lb * u1, pb.$2 + db.$2 * lb * u1),
      (pa.$1 + da.$1 * la * u1, pa.$2 + da.$2 * la * u1),
    ];
    final m = u8Chep(cv.fillPoly(matNaRong(h, w), daGiac(dai), cv.Scalar.all(1)));
    var n = 0, c = 0;
    for (var k = 0; k < m.length; k++) {
      if (m[k] > 0) {
        n++;
        c += muc[k];
      }
    }
    if (n < 200) continue;
    final mg = u8Chep(cv.fillPoly(matNaRong(gh, gw), daGiac([for (final (x, y) in dai) (x * tl, y * tl)]), cv.Scalar.all(1)));
    var ng = 0, cg = 0;
    for (var k = 0; k < mg.length; k++) {
      if (mg[k] > 0) {
        ng++;
        cg += g[k];
      }
    }
    final tiGiay = ng > 0 ? cg / ng : 0.0;
    if (tiGiay > 0.6 && c / n > 0.35 * mucTrong && (tot == null || thay > tot.$2)) tot = (i, thay);
  }
  return tot;
}

/// Kéo cạnh q[i]→q[i+1] ra tới biên ảnh w×h dọc theo hai cạnh kề (giữ thứ tự góc).
List<Diem> _noiCanh(List<Diem> q, int i, int h, int w) {
  final kq = [...q];
  for (final (gc, k) in [(i, (i + 3) % 4), ((i + 1) % 4, (i + 2) % 4)]) {
    final l = math.max(_kc(q[gc], q[k]), 1e-6);
    final d = ((q[gc].$1 - q[k].$1) / l, (q[gc].$2 - q[k].$2) / l);
    final t = _toiBien(q[gc], d, h, w);
    kq[gc] = (q[gc].$1 + d.$1 * t, q[gc].$2 + d.$2 * t);
  }
  return kq;
}

/// 4 góc tờ giấy (trên trái, trên phải, dưới phải, dưới trái; tọa độ ảnh vào) và điểm tin cậy; null nếu không thấy.
/// [canh]: cạnh dài ảnh dò (640; khung xem trước lúc chụp dùng 400 cho nhanh), [tinh]: tinh chỉnh cạnh ở ảnh 1280 px.
(List<Diem>, double)? timTuGiac(cv.Mat anh, {bool tinh = true, int canh = _canhNho}) {
  final a = _chuanBi(anh, canh);
  final giay = _giongGiay(a);
  _Q? tot;
  var diemTot = 0.0;
  final daXet = <_Q>[], ds = <(_Q, double)>[];
  for (final q0 in _ungVien(a)) {
    final q = _sapXep(q0);
    var trung = false;
    for (final x in daXet) {
      var m = 0.0;
      for (var i = 0; i < 4; i++) {
        m = math.max(m, math.max((q[i].$1 - x[i].$1).abs(), (q[i].$2 - x[i].$2).abs()));
      }
      if (m < 3) {
        trung = true;
        break;
      }
    }
    if (trung) continue;
    daXet.add(q);
    final d = _cham(q, a, giay);
    if (d > 0) ds.add((q, d));
    if (d > diemTot) {
      tot = q;
      diemTot = d;
    }
  }
  if (tot == null) return null;
  (tot, diemTot) = _chonTrong(tot, diemTot, ds, a);
  final noi = _canhNoi(tot, a, giay);
  List<Diem> kq;
  if (tinh) {
    final b = _chuanBi(anh, _canhTinh);
    final tl = b.s / a.s;
    kq = [
      for (final (x, y) in _tinhChinh([for (final (x, y) in tot) (x * tl, y * tl)], b)) (x / b.s, y / b.s),
    ];
  } else {
    kq = [for (final (x, y) in tot) (x / a.s, y / a.s)];
  }
  // nửa cặp trang: lấy cả phần trang bên kia gáy tới biên ảnh
  if (noi != null) kq = _noiCanh(kq, noi.$1, anh.rows, anh.cols);
  final wg = anh.cols - 1.0, hg = anh.rows - 1.0;
  return ([for (final (x, y) in kq) (x.clamp(0.0, wg), y.clamp(0.0, hg))], diemTot);
}

/// Chẩn đoán (chỉ dùng khi kiểm thử): các số trung gian để so với bản Python.
String chanDoanTimMep(cv.Mat anh, List<Diem> dapAn) {
  final a = _chuanBi(anh, _canhNho);
  final q = _sapXep([for (final (x, y) in dapAn) ((x * a.s).clamp(0.0, a.w - 1.0), (y * a.s).clamp(0.0, a.h - 1.0))]);
  final giay = _giongGiay(a);
  final uv = _ungVien(a);
  var gan = 1e9;
  for (final x0 in uv) {
    final x = _sapXep(x0);
    var m = 0.0;
    for (var i = 0; i < 4; i++) {
      m = math.max(m, math.max((x[i].$1 - q[i].$1).abs(), (x[i].$2 - q[i].$2).abs()));
    }
    gan = math.min(gan, m);
  }
  final canh = [for (var i = 0; i < 4; i++) _bamCanh(q[i], q[(i + 1) % 4], a)];
  final kq = timTuGiac(anh);
  return 'w=${a.w} h=${a.h} s=${a.s.toStringAsFixed(4)} nguong=${a.nguong.toStringAsFixed(2)} '
      'gx[mid]=${a.gx[(a.h ~/ 2) * a.w + a.w ~/ 2].toStringAsFixed(2)} ungvien=${uv.length} gan=${gan.toStringAsFixed(1)} '
      'hople=${_hopLe(q, a.h, a.w)} diemDung=${_cham(q, a, giay).toStringAsFixed(3)} giay=${_tiLeGiay(q, giay, giay.$2 / a.w).toStringAsFixed(2)} '
      'canh=$canh tim=${kq == null ? null : [for (final p in kq.$1) '(${p.$1.round()},${p.$2.round()})']} diem=${kq?.$2.toStringAsFixed(3)}';
}
