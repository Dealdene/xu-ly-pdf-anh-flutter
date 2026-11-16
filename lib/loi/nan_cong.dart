// Nắn trang cong (sách mở, giấy cong vênh) theo dòng chữ. Chuyển từ ung-dung/loi_xu_ly/nan_cong.py.
//
// Trang đã cắt, nắn phối cảnh theo 4 góc vẫn còn cong nếu giấy không phẳng: dòng chữ võng lên gần gáy sách.
// 1. Nhị phân hóa chữ, nối các chữ cùng dòng bằng phép đóng ngang, giữ các khối dài và mảnh (dòng chữ).
// 2. Mỗi dòng: đường giữa (trung bình tung độ nét mực theo từng cột), khớp đa thức bậc 3 có loại điểm lạc.
// 3. Độ lệch D = tung độ đường cong − đường thẳng chung (độ dốc trung vị của mọi dòng, ở độ cao trung bình của dòng).
//    Khớp mặt trơn D(x, y) (bậc 4 theo x, bậc 2 theo y) cho cả trang.
// 4. Ánh xạ ngược: điểm (x, y) của ảnh ra lấy từ (x, y + D(x, y)) của ảnh vào; cùng cỡ ảnh, mép thiếu lấy theo mép.
// Trang phẳng (lệch < 0,3% chiều cao), quá ít dòng, hoặc mặt khớp không tin cậy thì trả nguyên ảnh.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'anh.dart';
import 'nan_phang.dart';

const int _canhXuLy = 1400;

/// Giải hệ phương trình tuyến tính vuông (khử Gauss, chọn phần tử trụ); null nếu suy biến.
List<double>? _giai(List<List<double>> a, List<double> b) {
  final n = b.length;
  final m = [
    for (var i = 0; i < n; i++) [...a[i], b[i]],
  ];
  for (var c = 0; c < n; c++) {
    var tru = c;
    for (var r = c + 1; r < n; r++) {
      if (m[r][c].abs() > m[tru][c].abs()) tru = r;
    }
    if (m[tru][c].abs() < 1e-12) return null;
    final t = m[c];
    m[c] = m[tru];
    m[tru] = t;
    for (var r = 0; r < n; r++) {
      if (r == c) continue;
      final f = m[r][c] / m[c][c];
      if (f == 0) continue;
      for (var k = c; k <= n; k++) {
        m[r][k] -= f * m[c][k];
      }
    }
  }
  return [for (var i = 0; i < n; i++) m[i][n] / m[i][i]];
}

/// Bình phương tối thiểu: hệ số x sao cho A·x ≈ y (qua phương trình chuẩn).
List<double>? _btnt(List<List<double>> hang, List<double> y) {
  final k = hang.first.length;
  final ata = List.generate(k, (_) => List<double>.filled(k, 0));
  final aty = List<double>.filled(k, 0);
  for (var i = 0; i < hang.length; i++) {
    final r = hang[i];
    for (var a = 0; a < k; a++) {
      aty[a] += r[a] * y[i];
      for (var b = a; b < k; b++) {
        ata[a][b] += r[a] * r[b];
      }
    }
  }
  for (var a = 0; a < k; a++) {
    for (var b = 0; b < a; b++) {
      ata[a][b] = ata[b][a];
    }
  }
  return _giai(ata, aty);
}

double _da(List<double> hs, double x) {
  var v = 0.0;
  for (var i = hs.length - 1; i >= 0; i--) {
    v = v * x + hs[i];
  }
  return v;
}

/// Khớp y = f(x/w) bậc 3 (bậc 2 nếu dòng ngắn), loại điểm lạc; hệ số tăng dần theo bậc.
List<double>? _khopDong(List<(double, double)> d, int w) {
  final x = [for (final p in d) p.$1 / w], y = [for (final p in d) p.$2];
  final bac = (x.reduce(math.max) - x.reduce(math.min)) > 0.4 ? 3 : 2;
  var giu = List<bool>.filled(x.length, true);
  List<double>? hs;
  for (var vong = 0; vong < 3; vong++) {
    final chi = [
      for (var i = 0; i < x.length; i++)
        if (giu[i]) i,
    ];
    if (chi.length < bac + 4) return null;
    hs = _btnt(
      [
        for (final i in chi) [for (var j = 0; j <= bac; j++) math.pow(x[i], j).toDouble()],
      ],
      [for (final i in chi) y[i]],
    );
    if (hs == null) return null;
    final sai = [for (var i = 0; i < x.length; i++) (_da(hs, x[i]) - y[i]).abs()];
    final sg = [for (final i in chi) sai[i]]..sort();
    final nguong = math.max(1.5, 2.5 * sg[sg.length ~/ 2]);
    giu = [for (final s in sai) s < nguong];
  }
  return hs;
}

/// Các dòng chữ: mỗi dòng là danh sách (x, y giữa) gộp theo ô 4 cột.
List<List<(double, double)>> _dongChu(cv.Mat xam) {
  final h = xam.rows, w = xam.cols;
  final muc = cv.adaptiveThreshold(xam, 255, cv.ADAPTIVE_THRESH_MEAN_C, cv.THRESH_BINARY_INV, 31, 15);
  final nhan = cv.Mat.empty(), tk = cv.Mat.empty(), tam = cv.Mat.empty();
  final n = cv.connectedComponentsWithStats(muc, nhan, tk, tam, 8, cv.MatType.CV_32S, cv.CCL_DEFAULT);
  if (n < 20) return [];
  final cao = [for (var i = 1; i < n; i++) tk.at<int>(i, cv.CC_STAT_HEIGHT)];
  final hop = cao.where((c) => c > 3 && c < 0.05 * h).toList()..sort();
  final caoChu = hop.isEmpty ? 10.0 : hop[hop.length ~/ 2].toDouble();
  final giu = List<bool>.filled(n, false);
  for (var i = 1; i < n; i++) {
    final ch = tk.at<int>(i, cv.CC_STAT_HEIGHT),
        cw = tk.at<int>(i, cv.CC_STAT_WIDTH),
        dt = tk.at<int>(i, cv.CC_STAT_AREA);
    giu[i] = ch >= 2 && ch <= 3 * caoChu && cw <= 6 * caoChu && dt >= 4;
  }
  final nd = i32Chep(nhan);
  final cd = Uint8List(h * w);
  for (var i = 0; i < h * w; i++) {
    if (giu[nd[i]]) cd[i] = 255;
  }
  final chu = cv.Mat.fromList(h, w, cv.MatType.CV_8UC1, cd);
  // nối chữ trong dòng: đóng ngang cỡ ~1,6 chiều cao chữ, rồi mở ngang nhẹ để bỏ cầu nối mảnh giữa hai dòng
  final kx = math.max(5, (1.6 * caoChu).toInt());
  var dong = cv.morphologyEx(
    chu,
    cv.MORPH_CLOSE,
    cv.getStructuringElement(cv.MORPH_RECT, (kx, 1)),
    borderType: cv.BORDER_REPLICATE,
  );
  dong = cv.morphologyEx(
    dong,
    cv.MORPH_OPEN,
    cv.getStructuringElement(cv.MORPH_RECT, (math.max(3, kx ~/ 2), 1)),
    borderType: cv.BORDER_REPLICATE,
  );
  final nhan2 = cv.Mat.empty(), tk2 = cv.Mat.empty(), tam2 = cv.Mat.empty();
  final n2 = cv.connectedComponentsWithStats(dong, nhan2, tk2, tam2, 8, cv.MatType.CV_32S, cv.CCL_DEFAULT);
  final nd2 = i32Chep(nhan2);
  final kq = <List<(double, double)>>[];
  for (var i = 1; i < n2; i++) {
    final x0 = tk2.at<int>(i, cv.CC_STAT_LEFT), y0 = tk2.at<int>(i, cv.CC_STAT_TOP);
    final cw = tk2.at<int>(i, cv.CC_STAT_WIDTH), ch = tk2.at<int>(i, cv.CC_STAT_HEIGHT);
    if (cw < 0.15 * w || ch > 3.5 * caoChu || cw < 8 * ch) continue;
    final xs = <double>[], ys = <double>[];
    for (var x = x0; x < x0 + cw; x++) {
      var dem = 0, tong = 0;
      for (var y = y0; y < y0 + ch; y++) {
        if (cd[y * w + x] > 0 && nd2[y * w + x] == i) {
          dem++;
          tong += y;
        }
      }
      if (dem >= 2) {
        xs.add(x.toDouble());
        ys.add(tong / dem);
      }
    }
    if (xs.length < 0.3 * cw) continue;
    final o = <int, (double, double, int)>{};
    for (var k = 0; k < xs.length; k++) {
      final key = xs[k] ~/ 4;
      final c = o[key] ?? (0.0, 0.0, 0);
      o[key] = (c.$1 + xs[k], c.$2 + ys[k], c.$3 + 1);
    }
    final khoa = o.keys.toList()..sort();
    kq.add([for (final k in khoa) (o[k]!.$1 / o[k]!.$3, o[k]!.$2 / o[k]!.$3)]);
  }
  return kq;
}

/// Lưới độ lệch dọc D (64 hàng × 48 cột, theo điểm ảnh của ảnh vào) và độ lệch lớn nhất; null nếu trang coi như phẳng.
(List<List<double>>, double)? tinhDoLech(cv.Mat anh) {
  final (nho, s) = thuNho(anh, _canhXuLy);
  final xam = nho.channels == 3 ? cv.cvtColor(nho, cv.COLOR_BGR2GRAY) : nho;
  final hn = xam.rows, wn = xam.cols;
  final dong = _dongChu(xam);
  if (dong.length < 3) return null;
  final mau = <(List<double>, List<double>)>[];
  for (final d in dong) {
    final hs = _khopDong(d, wn);
    if (hs == null) continue;
    final x0 = d.map((p) => p.$1).reduce(math.min), x1 = d.map((p) => p.$1).reduce(math.max);
    final xs = [for (var i = 0; i < 24; i++) x0 + (x1 - x0) * i / 23];
    mau.add((xs, [for (final x in xs) _da(hs, x / wn)]));
  }
  if (mau.length < 3) return null;
  // độ dốc chung của dòng (trung vị): chỉ nắn phần cong, phần nghiêng để bước sửa nghiêng xoay
  final docs = <double>[];
  for (final (xs, ys) in mau) {
    final mx = xs.reduce((a, b) => a + b) / xs.length, my = ys.reduce((a, b) => a + b) / ys.length;
    var sxy = 0.0, sxx = 0.0;
    for (var i = 0; i < xs.length; i++) {
      sxy += (xs[i] - mx) * (ys[i] - my);
      sxx += (xs[i] - mx) * (xs[i] - mx);
    }
    docs.add(sxx > 0 ? sxy / sxx : 0);
  }
  docs.sort();
  final doc = docs[docs.length ~/ 2];
  final X = <double>[], Y = <double>[], D = <double>[];
  for (final (xs, ys) in mau) {
    var goc = 0.0;
    for (var i = 0; i < xs.length; i++) {
      goc += ys[i] - doc * xs[i];
    }
    goc /= xs.length;
    for (var i = 0; i < xs.length; i++) {
      final thang = goc + doc * xs[i];
      X.add(xs[i]);
      Y.add(thang);
      D.add(ys[i] - thang);
    }
  }
  final by = mau.length >= 6 ? 2 : (mau.length >= 4 ? 1 : 0);
  final cot = [
    for (var j = 0; j < 5; j++)
      for (var k = 0; k <= by; k++) (j, k),
  ];
  List<double> hang(double u, double v) => [for (final (j, k) in cot) math.pow(u, j) * math.pow(v, k).toDouble()];
  final A = [for (var i = 0; i < X.length; i++) hang(X[i] / wn * 2 - 1, Y[i] / hn * 2 - 1)];
  final hs = _btnt(A, D);
  if (hs == null) return null;
  var lechMau = 0.0, ssD = 0.0, ssDu = 0.0;
  for (var i = 0; i < D.length; i++) {
    var f = 0.0;
    for (var c = 0; c < hs.length; c++) {
      f += hs[c] * A[i][c];
    }
    lechMau = math.max(lechMau, D[i].abs());
    ssD += D[i] * D[i];
    ssDu += (f - D[i]) * (f - D[i]);
  }
  if (lechMau < 0.003 * hn || math.sqrt(ssDu) > 0.45 * math.sqrt(ssD)) return null;
  // lưới thô; ngoài vùng có dòng chữ giữ độ lệch ở mép vùng (không ngoại suy đa thức)
  final uMin = X.reduce(math.min) / wn * 2 - 1, uMax = X.reduce(math.max) / wn * 2 - 1;
  final vMin = Y.reduce(math.min) / hn * 2 - 1, vMax = Y.reduce(math.max) / hn * 2 - 1;
  final luoi = [
    for (var r = 0; r < 64; r++)
      [
        for (var c = 0; c < 48; c++)
          () {
            final u = ((c / 47 * (wn - 1)) / wn * 2 - 1).clamp(uMin, uMax);
            final v = ((r / 63 * (hn - 1)) / hn * 2 - 1).clamp(vMin, vMax);
            final h = hang(u, v);
            var f = 0.0;
            for (var k = 0; k < hs.length; k++) {
              f += hs[k] * h[k];
            }
            return f.clamp(-1.5 * lechMau, 1.5 * lechMau) / s;
          }(),
      ],
  ];
  return (luoi, lechMau / s);
}

/// Cột gáy sách nếu ảnh là hai trang mở (khổ ngang, giữa ảnh có một dải gần như không có chữ); null nếu không.
int? timGay(cv.Mat anh) {
  final h = anh.rows, w = anh.cols;
  if (w < 0.95 * h) return null;
  final (nho, s) = thuNho(anh, 1000);
  final xam = nho.channels == 3 ? cv.cvtColor(nho, cv.COLOR_BGR2GRAY) : nho;
  final m = u8Chep(cv.adaptiveThreshold(xam, 1, cv.ADAPTIVE_THRESH_MEAN_C, cv.THRESH_BINARY_INV, 25, 15));
  final hn = xam.rows, wn = xam.cols;
  final cot = List<double>.filled(wn, 0);
  for (var y = 0; y < hn; y++) {
    for (var x = 0; x < wn; x++) {
      cot[x] += m[y * wn + x];
    }
  }
  final mo = List<double>.filled(wn, 0);
  for (var x = 0; x < wn; x++) {
    var t = 0.0, d = 0;
    for (var k = x - 7; k <= x + 7; k++) {
      if (k >= 0 && k < wn) {
        t += cot[k];
        d++;
      }
    }
    mo[x] = t / d;
  }
  final tb = mo.reduce((a, b) => a + b) / wn;
  final lo = (0.35 * wn).toInt(), hi = (0.65 * wn).toInt();
  var x = lo;
  for (var k = lo; k < hi; k++) {
    if (mo[k] < mo[x]) x = k;
  }
  // ảnh trang sách người dùng chụp: mực ở gáy 0,05–0,15 lần trung bình; trang đơn: > 1
  if (mo[x] > 0.3 * math.max(tb, 1e-6)) return null;
  return (x / s).round();
}

/// Nắn trang cong theo dòng chữ; trang phẳng hoặc không đủ dòng chữ thì trả nguyên ảnh. Ảnh hai trang sách mở (hai
/// mặt cong ngược nhau, một mặt khớp chung không được) thì tách ở gáy, nắn từng trang rồi ghép lại.
cv.Mat nanTrangCong(cv.Mat anh) {
  final gay = timGay(anh);
  if (gay != null && gay > 10 && gay < anh.cols - 10) {
    // cắt giữa khe trắng ở gáy (đường có thể xiên), không cắt qua chữ đầu dòng
    final duong = kheGay(anh);
    final (cTrai, cPhai) = duong != null
        ? catTheoDuong(anh, duong.$1, duong.$2)
        : (anh.region(cv.Rect(0, 0, gay, anh.rows)).clone(), anh.region(cv.Rect(gay, 0, anh.cols - gay, anh.rows)).clone());
    // mỗi trang nắn và xoay thẳng riêng theo dòng chữ của nó (hai trang sách mở nghiêng mỗi trang một kiểu)
    return _ghepNgang(_xoayThang(_nanMot(cTrai)), _xoayThang(_nanMot(cPhai)));
  }
  return _nanMot(anh);
}

cv.Mat _nanMot(cv.Mat anh) {
  final kq = tinhDoLech(anh);
  if (kq == null) return nanLe(anh);
  final (luoi, _) = kq;
  final h = anh.rows, w = anh.cols;
  final nhoD = cv.Mat.fromList(64, 48, cv.MatType.CV_32FC1, [for (final hang in luoi) ...hang]);
  final D = f32Chep(cv.resize(nhoD, (w, h), interpolation: cv.INTER_CUBIC));
  final mx = cv.Mat.zeros(h, w, cv.MatType.CV_32FC1), my = cv.Mat.zeros(h, w, cv.MatType.CV_32FC1);
  final ax = f32(mx), ay = f32(my);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      ax[i] = x.toDouble();
      ay[i] = y + D[i];
    }
  }
  return nanLe(cv.remap(anh, mx, my, cv.INTER_CUBIC, borderMode: cv.BORDER_REPLICATE));
}

/// Trung vị (như numpy: chẵn phần tử thì lấy trung bình hai phần tử giữa).
double _tv(List<double> a) {
  final b = [...a]..sort();
  final n = b.length;
  return n.isOdd ? b[n ~/ 2] : (b[n ~/ 2 - 1] + b[n ~/ 2]) / 2;
}

/// Màu nền (trung vị từng kênh trên ảnh thu nhỏ) để tô phần khung nới thêm.
cv.Scalar _mauNen(cv.Mat anh) {
  final (nho, _) = thuNho(anh, 200);
  final d = u8Chep(nho), c = nho.channels;
  final kenh = [
    for (var k = 0; k < c; k++) _tv([for (var i = k; i < d.length; i += c) d[i].toDouble()]),
  ];
  return c == 3 ? cv.Scalar(kenh[0], kenh[1], kenh[2]) : cv.Scalar.all(kenh[0]);
}

/// Xoay một trang cho dòng chữ nằm ngang theo độ dốc trung vị của chính nó; nới khung, tô màu nền (không đẩy chữ
/// sát mép ra ngoài ảnh). Giống _xoay_thang của nan_cong.py.
cv.Mat _xoayThang(cv.Mat anh) {
  final (nho, _) = thuNho(anh, _canhXuLy);
  final xam = nho.channels == 3 ? cv.cvtColor(nho, cv.COLOR_BGR2GRAY) : nho;
  final docs = <double>[];
  for (final d in _dongChu(xam)) {
    if (d.length < 4) continue;
    final mx = d.map((p) => p.$1).reduce((a, b) => a + b) / d.length;
    final my = d.map((p) => p.$2).reduce((a, b) => a + b) / d.length;
    var sxy = 0.0, sxx = 0.0;
    for (final (x, y) in d) {
      sxy += (x - mx) * (y - my);
      sxx += (x - mx) * (x - mx);
    }
    if (sxx > 0) docs.add(sxy / sxx);
  }
  if (docs.length < 5) return anh;
  final goc = math.atan(_tv(docs)) * 180 / math.pi;
  if (goc.abs() < 0.3 || goc.abs() > 6) return anh;
  return xoayAnh(anh, goc, mauNen: _mauNen(anh));
}

/// Ghép hai trang cạnh nhau; trang thấp hơn được đệm màu nền trên dưới cho bằng chiều cao.
cv.Mat _ghepNgang(cv.Mat trai, cv.Mat phai) {
  final h = math.max(trai.rows, phai.rows);
  cv.Mat dem(cv.Mat t) {
    final d = h - t.rows;
    return d == 0 ? t : cv.copyMakeBorder(t, d ~/ 2, d - d ~/ 2, 0, 0, cv.BORDER_CONSTANT, value: _mauNen(t));
  }

  return cv.hconcat(dem(trai), dem(phai));
}

// ---------- nắn vuông khối chữ (lề trái, lề phải) ----------

/// Khớp đường lề x = f(y/h) (bậc 2, bậc 1 nếu ít dòng; hệ số tăng dần theo bậc) qua đầu dòng (phia = 1: lề trái,
/// loại dòng thụt vào) hoặc cuối dòng (phia = -1: lề phải, loại dòng ngắn); null nếu không đủ dòng.
List<double>? _khopLe(List<double> y, List<double> x, int phia, double caoChu, int h) {
  var giu = List<bool>.filled(y.length, true);
  List<double>? hs;
  for (var vong = 0; vong < 4; vong++) {
    final chi = [
      for (var i = 0; i < y.length; i++)
        if (giu[i]) i,
    ];
    if (chi.length < 5) return null;
    final bac = chi.length >= 9 ? 2 : 1;
    hs = _btnt(
      [
        for (final i in chi) [for (var j = 0; j <= bac; j++) math.pow(y[i] / h, j).toDouble()],
      ],
      [for (final i in chi) x[i]],
    );
    if (hs == null) return null;
    // > 0: thụt vào trong khối (dòng đầu đoạn, dòng cuối đoạn, tiêu đề)
    final r = [for (var i = 0; i < y.length; i++) (x[i] - _da(hs, y[i] / h)) * phia];
    final ng = math.max(0.6 * caoChu, 2.5 * _tv([for (final i in chi) r[i].abs()]));
    giu = [for (final v in r) v < ng && v > -2.5 * caoChu];
  }
  final ys = [
    for (var i = 0; i < y.length; i++)
      if (giu[i]) y[i],
  ];
  if (ys.length < 5 || ys.reduce(math.max) - ys.reduce(math.min) < 0.35 * h) return null;
  return hs;
}

class _LeKhoi {
  _LeKhoi(this.s, this.hn, this.wn, this.trai, this.phai, this.k, this.y0, this.y1, this.xl0, this.rong0, this.lech);
  final double s;
  final int hn, wn;
  final List<double> trai, phai;
  final double k, y0, y1, xl0, rong0, lech; // lech: độ lệch lề lớn nhất (điểm ảnh của ảnh thu nhỏ)
}

/// Hai lề của khối chữ (trên ảnh thu nhỏ); null nếu không đo được. Giống _le_khoi của nan_cong.py.
_LeKhoi? _leKhoi(cv.Mat anh) {
  final (nho, s) = thuNho(anh, _canhXuLy);
  final xam = nho.channels == 3 ? cv.cvtColor(nho, cv.COLOR_BGR2GRAY) : nho;
  final hn = xam.rows, wn = xam.cols;
  final dong = _dongChu(xam);
  if (dong.length < 6) return null;
  final dauY = <double>[], dauX = <double>[], cuoiY = <double>[], cuoiX = <double>[], docs = <double>[];
  for (final d in dong) {
    final hs = _khopDong(d, wn);
    if (hs == null) continue;
    final x0 = d.map((p) => p.$1).reduce(math.min), x1 = d.map((p) => p.$1).reduce(math.max);
    final ya = _da(hs, x0 / wn), yb = _da(hs, x1 / wn);
    dauY.add(ya);
    dauX.add(x0);
    cuoiY.add(yb);
    cuoiX.add(x1);
    docs.add((yb - ya) / math.max(x1 - x0, 1.0));
  }
  if (dauY.length < 6) return null;
  // chiều cao chữ ước theo khoảng cách dòng (dòng chữ cách nhau ~1,6–2 lần chiều cao chữ)
  final yy = [...dauY]..sort();
  final caoChu = _tv([for (var i = 1; i < yy.length; i++) yy[i] - yy[i - 1]]) / 1.8;
  final trai = _khopLe(dauY, dauX, 1, caoChu, hn), phai = _khopLe(cuoiY, cuoiX, -1, caoChu, hn);
  if (trai == null || phai == null) return null;
  final y0 = math.max(math.min(dauY.reduce(math.min), cuoiY.reduce(math.min)), 0.0);
  final y1 = math.min(math.max(dauY.reduce(math.max), cuoiY.reduce(math.max)), hn - 1.0);
  final ys = [for (var i = 0; i < 64; i++) y0 + (y1 - y0) * i / 63];
  final xl = [for (final y in ys) _da(trai, y / hn)], xr = [for (final y in ys) _da(phai, y / hn)];
  final rong = [for (var i = 0; i < 64; i++) xr[i] - xl[i]];
  final rMin = rong.reduce(math.min), rMax = rong.reduce(math.max);
  if (rMin < 0.3 * wn || rMin < 0.8 * rMax) return null; // khối chữ hẹp bất thường, hai lề lệch nhau quá nhiều
  final k = -_tv(docs); // lề đích vuông góc với dòng chữ
  final ym = 0.5 * (y0 + y1);
  final xl0 = _tv(xl), rong0 = _tv(rong);
  var lech = 0.0;
  for (var i = 0; i < 64; i++) {
    final dich = xl0 + k * (ys[i] - ym);
    lech = math.max(lech, math.max((xl[i] - dich).abs(), (xr[i] - dich - rong0).abs()));
  }
  return _LeKhoi(s, hn, wn, trai, phai, k, y0, y1, xl0, rong0, lech);
}

/// Độ lệch lớn nhất của lề khối chữ so với hai đường thẳng vuông góc dòng chữ, % bề ngang ảnh (kiểm thử).
double? doLechLe(cv.Mat anh) {
  final l = _leKhoi(anh);
  return l == null ? null : 100 * l.lech / l.wn;
}

/// Nắn vuông khối chữ: lề trái, lề phải (đầu và cuối các dòng) xiên hay cong do trang cong, chụp lệch thì kéo ngang
/// từng hàng điểm ảnh cho hai lề thành đường thẳng vuông góc với dòng chữ, bề ngang dòng bằng nhau. Nới khung hai
/// bên bằng độ dời lớn nhất (tô màu nền) để chữ sát mép không bị đẩy ra ngoài. Lề đã thẳng, quá ít dòng, khối chữ
/// lệch bất thường thì trả nguyên ảnh; chỗ lệch thành bậc trên vài dòng liền không nắn (giống đoạn thụt lề).
cv.Mat nanLe(cv.Mat anh) {
  final l = _leKhoi(anh);
  if (l == null) return anh;
  if (l.lech < math.max(1.5, 0.004 * l.wn) || l.lech > 0.08 * l.wn) return anh;
  final h = anh.rows, w = anh.cols, s = l.s;
  final ym = 0.5 * (l.y0 + l.y1);
  final nl = (l.lech / s).ceil() + 4, wr = w + 2 * nl;
  final mx = cv.Mat.zeros(h, wr, cv.MatType.CV_32FC1), my = cv.Mat.zeros(h, wr, cv.MatType.CV_32FC1);
  final ax = f32(mx), ay = f32(my);
  for (var y = 0; y < h; y++) {
    final yh = (y * s).clamp(l.y0, l.y1);
    final xlh = _da(l.trai, yh / l.hn);
    final tl = (_da(l.phai, yh / l.hn) - xlh) / l.rong0;
    final dich = l.xl0 + l.k * (yh - ym);
    for (var x = 0; x < wr; x++) {
      final i = y * wr + x;
      ax[i] = (xlh + ((x - nl) * s - dich) * tl) / s;
      ay[i] = y.toDouble();
    }
  }
  return cv.remap(anh, mx, my, cv.INTER_CUBIC, borderMode: cv.BORDER_CONSTANT, borderValue: _mauNen(anh));
}

/// Độ võng dòng chữ (dùng cho kiểm thử): trung vị và lớn nhất, theo % chiều cao trang, của khoảng lệch lớn nhất giữa
/// đường cong khớp với từng dòng và đường thẳng khớp với chính dòng đó; kèm số dòng đo được.
(double, double, int) doVongDong(cv.Mat anh) {
  final xam = anh.channels == 3 ? cv.cvtColor(anh, cv.COLOR_BGR2GRAY) : anh;
  final h = xam.rows, w = xam.cols;
  final vong = <double>[];
  for (final d in _dongChu(xam)) {
    final hs = _khopDong(d, w);
    if (hs == null) continue;
    final x0 = d.map((p) => p.$1).reduce(math.min), x1 = d.map((p) => p.$1).reduce(math.max);
    final xs = [for (var i = 0; i < 50; i++) x0 + (x1 - x0) * i / 49];
    final ys = [for (final x in xs) _da(hs, x / w)];
    final mx = xs.reduce((a, b) => a + b) / 50, my = ys.reduce((a, b) => a + b) / 50;
    var sxy = 0.0, sxx = 0.0;
    for (var i = 0; i < 50; i++) {
      sxy += (xs[i] - mx) * (ys[i] - my);
      sxx += (xs[i] - mx) * (xs[i] - mx);
    }
    final k = sxx > 0 ? sxy / sxx : 0.0;
    var lon = 0.0;
    for (var i = 0; i < 50; i++) {
      lon = math.max(lon, (ys[i] - (my + k * (xs[i] - mx))).abs());
    }
    vong.add(lon / h * 100);
  }
  if (vong.isEmpty) return (0, 0, 0);
  vong.sort();
  return (vong[vong.length ~/ 2], vong.last, vong.length);
}
