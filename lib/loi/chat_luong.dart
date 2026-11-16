// Đo chất lượng trang để báo trang nên chụp lại: chữ nhòe (rung tay, đang lật trang, lấy nét hụt) và tay che trang.
// Chuyển từ ung-dung/loi_xu_ly/chat_luong.py (bản Python đã kiểm thử trên hồ sơ 214 trang của người dùng: chỉ hai
// trang chụp lúc đang lật trang bị báo nhòe).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'anh.dart';
import 'tu_chup.dart';

const loiXam = 60; // điểm tối nhất của ô chữ trên mức này: lõi nét xám (nhòe)
const nguongOXam = 0.45; // phần ô chữ có lõi xám
const nguongLoiTv = 55; // lõi trung vị
const nguongTay = 0.05; // phần vùng giữa trang có tay (ngón cái giữ mép sách 0–3,4%; tay đặt lên trang 5–30%)

/// (phần ô chữ có lõi xám, lõi trung vị) của trang đã làm sạch (Giữ màu / Xám); null nếu không đủ chữ. Chữ in nét
/// thì lõi nét gần đen; chữ nhòe loang mực, lõi chỉ còn xám. Ô vuông chừng 6 dòng chữ.
(double, double)? doNhoe(cv.Mat anh) {
  final (nho, _) = thuNho(anh, 1600);
  final xam = nho.channels == 3 ? cv.cvtColor(nho, cv.COLOR_BGR2GRAY) : nho;
  final hn = xam.rows, wn = xam.cols;
  final muc = cv.adaptiveThreshold(xam, 1, cv.ADAPTIVE_THRESH_MEAN_C, cv.THRESH_BINARY_INV, 31, 15);
  final nhanM = cv.Mat.empty(), tkM = cv.Mat.empty(), tamM = cv.Mat.empty();
  final n = cv.connectedComponentsWithStats(muc, nhanM, tkM, tamM, 8, cv.MatType.CV_32S, cv.CCL_DEFAULT);
  final tk = i32Chep(tkM);
  final cao = <int>[];
  for (var i = 1; i < n; i++) {
    final ch = tk[i * 5 + 3];
    if (ch > 4 && ch < 0.05 * hn) cao.add(ch);
  }
  if (cao.length < 40) return null;
  cao.sort();
  final caoChu = cao.length.isOdd ? cao[cao.length ~/ 2].toDouble() : (cao[cao.length ~/ 2 - 1] + cao[cao.length ~/ 2]) / 2;
  final o = math.max((6 * caoChu).toInt(), 32);
  final d = u8Chep(xam);
  final loi = <double>[];
  final hist = List<int>.filled(256, 0);
  // phân vị theo kiểu numpy (nội suy tuyến tính) trên biểu đồ tần số
  double phanVi(int tong, double q) {
    final vt = q / 100 * (tong - 1);
    final duoi = vt.floor(), tren = vt.ceil();
    int giaTri(int k) {
      var t = 0;
      for (var v = 0; v < 256; v++) {
        t += hist[v];
        if (t > k) return v;
      }
      return 255;
    }

    final a = giaTri(duoi), b = giaTri(tren);
    return a + (b - a) * (vt - duoi);
  }

  for (var y = 0; y < hn - o ~/ 2; y += o) {
    for (var x = 0; x < wn - o ~/ 2; x += o) {
      final y1 = math.min(hn, y + o), x1 = math.min(wn, x + o);
      hist.fillRange(0, 256, 0);
      for (var yy = y; yy < y1; yy++) {
        final r = yy * wn;
        for (var xx = x; xx < x1; xx++) {
          hist[d[r + xx]]++;
        }
      }
      final tong = (y1 - y) * (x1 - x);
      final p1 = phanVi(tong, 1), p3 = phanVi(tong, 3), p90 = phanVi(tong, 90);
      if (p90 - p3 < 40) continue;
      // ô có chữ: đủ điểm mực
      final nguong = p3 + 0.4 * (p90 - p3);
      var mucO = 0;
      for (var v = 0; v < 256 && v < nguong; v++) {
        mucO += hist[v];
      }
      if (mucO < 0.02 * tong) continue;
      loi.add(p1);
    }
  }
  if (loi.length < 6) return null;
  loi.sort();
  final xamO = loi.where((v) => v > loiXam).length / loi.length;
  final tv = loi.length.isOdd ? loi[loi.length ~/ 2] : (loi[loi.length ~/ 2 - 1] + loi[loi.length ~/ 2]) / 2;
  return (xamO, tv);
}

bool laNhoe(cv.Mat anh) {
  final d = doNhoe(anh);
  return d != null && (d.$1 > nguongOXam || d.$2 > nguongLoiTv);
}

/// Phần vùng giữa trang bị tay, ngón tay che (ảnh màu, trước khi làm sạch).
double doTay(cv.Mat anh) {
  if (anh.channels != 3) return 0;
  final (nho, _) = thuNho(anh, 640);
  final w = nho.cols - 1.0, h = nho.rows - 1.0;
  return tiLeTay(nho, [(0, 0), (w, 0), (w, h), (0, h)]);
}

// ---------------------------------------------------------------------------------------------------------------
// Nhòe trên ảnh gốc (chưa làm sạch; đo được ở mọi chế độ, dùng cả ở màn camera ngay sau khi chụp): độ rộng mép nét
// chữ theo từng hướng (0°, 45°, 90°, 135°). Mỗi ô 96 px (trang thu về 1600 px): độ rộng = tương phản / độ dốc lớn
// nhất (phân vị 99) theo hướng đó, lấy hướng rộng nhất (rung tay chỉ nhòe theo một hướng). Ảnh chụp nét 2,4–2,9 px;
// rung 10 px (chừng nửa cỡ chữ) 5,1–8,8 px. Báo khi độ rộng trung vị quá 4,8 px. Giống chat_luong.do_mo_mep.

const oMep = 96; // ô đo độ rộng mép (px, trang 1600 px)
const nguongMep = 4.8; // độ rộng mép nét chữ trung vị (px) quá mức này: trang nhòe
const canhTrung = 1000; // cỡ trang khi so trùng
const nguongTrung = 40; // số điểm khớp từ mức này: hai trang là một (chụp trùng)

/// Phân vị [q] (0..100) từ biểu đồ tần số [hist] có [tong] phần tử, nội suy kiểu numpy; [buoc]: độ rộng một mức.
double _phanViHist(List<int> hist, int tong, double q, double buoc) {
  final vt = q / 100 * (tong - 1);
  final duoi = vt.floor(), tren = vt.ceil();
  int giaTri(int k) {
    var t = 0;
    for (var v = 0; v < hist.length; v++) {
      t += hist[v];
      if (t > k) return v;
    }
    return hist.length - 1;
  }

  final a = giaTri(duoi), b = giaTri(tren);
  return (a + (b - a) * (vt - duoi)) * buoc;
}

/// (phần ô chữ có mép nhòe, độ rộng mép trung vị px) của trang chưa làm sạch; null nếu không đủ chữ.
(double, double)? doMoMep(cv.Mat anh) {
  final (nho, _) = thuNho(anh, 1600);
  final xam = nho.channels == 3 ? cv.cvtColor(nho, cv.COLOR_BGR2GRAY) : nho;
  final hn = xam.rows, wn = xam.cols;
  final gx = f32Chep(cv.sobel(xam, cv.MatType.CV_32F, 1, 0, ksize: 3));
  final gy = f32Chep(cv.sobel(xam, cv.MatType.CV_32F, 0, 1, ksize: 3));
  final d = u8Chep(xam);
  // độ dốc theo 4 hướng, lượng tử 0,25 (1024 mức): |g|/8*4
  final n = hn * wn;
  final huong = List.generate(4, (_) => Uint16List(n));
  final c = math.sqrt(0.5);
  for (var i = 0; i < n; i++) {
    final x = gx[i], y = gy[i];
    huong[0][i] = math.min((x.abs() * 0.5).floor(), 1023);
    huong[1][i] = math.min(((c * (x + y)).abs() * 0.5).floor(), 1023);
    huong[2][i] = math.min((y.abs() * 0.5).floor(), 1023);
    huong[3][i] = math.min(((c * (x - y)).abs() * 0.5).floor(), 1023);
  }
  const o = oMep;
  final rong = <double>[];
  final hist = List<int>.filled(256, 0), hd = List<int>.filled(1024, 0);
  for (var y = 0; y < hn - o ~/ 2; y += o) {
    for (var x = 0; x < wn - o ~/ 2; x += o) {
      final y1 = math.min(hn, y + o), x1 = math.min(wn, x + o);
      final tong = (y1 - y) * (x1 - x);
      hist.fillRange(0, 256, 0);
      for (var yy = y; yy < y1; yy++) {
        final r = yy * wn;
        for (var xx = x; xx < x1; xx++) {
          hist[d[r + xx]]++;
        }
      }
      final p3 = _phanViHist(hist, tong, 3, 1), p90 = _phanViHist(hist, tong, 90, 1);
      if (p90 - p3 < 40) continue;
      final nguong = (p3 + 0.4 * (p90 - p3)).ceil();
      var muc = 0;
      for (var v = 0; v < nguong && v < 256; v++) {
        muc += hist[v];
      }
      if (muc < 0.02 * tong) continue;
      var r = 0.0;
      for (final h in huong) {
        hd.fillRange(0, 1024, 0);
        for (var yy = y; yy < y1; yy++) {
          final rr = yy * wn;
          for (var xx = x; xx < x1; xx++) {
            hd[h[rr + xx]]++;
          }
        }
        r = math.max(r, (p90 - p3) / math.max(_phanViHist(hd, tong, 99, 0.25), 0.25));
      }
      rong.add(r);
    }
  }
  if (rong.length < 6) return null;
  rong.sort();
  final tv = rong.length.isOdd ? rong[rong.length ~/ 2] : (rong[rong.length ~/ 2 - 1] + rong[rong.length ~/ 2]) / 2;
  return (rong.where((v) => v > nguongMep).length / rong.length, tv);
}

bool laNhoeGoc(cv.Mat anh) {
  final d = doMoMep(anh);
  return d != null && d.$2 > nguongMep;
}

// ---------------------------------------------------------------------------------------------------------------
// Trùng trang: so đặc trưng ORB (1000 px, 2000 điểm) của hai trang kết quả, đếm cặp khớp theo một phép đồng dạng
// (dời, co giãn 0,7–1,4 lần, xoay tới 15°), thử mọi cặp trong 50 cặp khớp tốt nhất (tất định; không dùng findHomography
// vì bản dựng OpenCV không có calib3d). Trên 214 trang của người dùng: 10 cặp chụp trùng 110–573 điểm khớp; cặp có
// trang bị tay che nửa trang 36; các trang khác nhau tối đa 26. Ngưỡng 40 (báo nhầm thì có thể xóa mất trang thật).
// Giống chat_luong.diem_khop.

typedef DacTrung = (cv.VecKeyPoint, cv.Mat);

/// Điểm đặc trưng ORB của một trang kết quả, để so trùng.
DacTrung dacTrung(cv.Mat anh) {
  final (nho, _) = thuNho(anh, canhTrung);
  final xam = nho.channels == 3 ? cv.cvtColor(nho, cv.COLOR_BGR2GRAY) : nho;
  return cv.ORB.create(nFeatures: 2000).detectAndCompute(xam, cv.Mat.empty());
}

/// Số điểm khớp theo một phép đồng dạng giữa hai trang.
int diemKhop(DacTrung a, DacTrung b) {
  final (ka, da) = a;
  final (kb, db) = b;
  if (da.isEmpty || db.isEmpty || ka.length < 20 || kb.length < 20) return 0;
  final cap = cv.BFMatcher.create(type: cv.NORM_HAMMING).knnMatch(da, db, 2);
  final tot = <(double, int, int)>[]; // (khoảng cách, chỉ số trang A, chỉ số trang B)
  for (final m in cap) {
    if (m.length == 2 && m[0].distance < 0.75 * m[1].distance) tot.add((m[0].distance, m[0].queryIdx, m[0].trainIdx));
  }
  if (tot.length < 8) return tot.length;
  tot.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  final n = tot.length;
  final px = Float64List(n), py = Float64List(n), qx = Float64List(n), qy = Float64List(n);
  for (var i = 0; i < n; i++) {
    final p = ka[tot[i].$2], q = kb[tot[i].$3];
    px[i] = p.x;
    py[i] = p.y;
    qx[i] = q.x;
    qy[i] = q.y;
  }
  var totNhat = 0;
  final k = math.min(50, n);
  for (var i = 0; i < k; i++) {
    for (var j = i + 1; j < k; j++) {
      final dx = px[j] - px[i], dy = py[j] - py[i];
      final d2 = dx * dx + dy * dy;
      if (d2 < 2500) continue;
      // z = (q_j − q_i) / (p_j − p_i): co giãn và xoay (số phức)
      final ex = qx[j] - qx[i], ey = qy[j] - qy[i];
      final zr = (ex * dx + ey * dy) / d2, zi = (ey * dx - ex * dy) / d2;
      final co = math.sqrt(zr * zr + zi * zi);
      if (co <= 0.7 || co >= 1.4 || math.atan2(zi, zr).abs() > 0.26) continue;
      final tr = qx[i] - (zr * px[i] - zi * py[i]), ti = qy[i] - (zr * py[i] + zi * px[i]);
      var c = 0;
      for (var m = 0; m < n; m++) {
        final ux = zr * px[m] - zi * py[m] + tr - qx[m], uy = zr * py[m] + zi * px[m] + ti - qy[m];
        if (ux * ux + uy * uy < 64) c++;
      }
      if (c > totNhat) totNhat = c;
    }
  }
  return totNhat;
}

/// Trang mới (các tệp kết quả [moi]) giống hệt trang nào trong [lanCan] (mỗi trang một danh sách tệp kết quả):
/// trả chỉ số các trang trùng. Chạy trong isolate.
List<int> trangTrung(List<String> moi, List<List<String>> lanCan) {
  DacTrung doc(String p) => dacTrung(gioiHan(cv.imread(p), 2400));
  final a = [for (final p in moi) doc(p)];
  final kq = <int>[];
  for (var i = 0; i < lanCan.length; i++) {
    final b = [for (final p in lanCan[i]) doc(p)];
    if (a.any((x) => b.any((y) => diemKhop(x, y) >= nguongTrung))) kq.add(i);
  }
  return kq;
}
