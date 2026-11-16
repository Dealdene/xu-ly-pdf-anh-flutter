// Cắt sát vùng chữ và xóa vết bẩn ngoài vùng chữ (nền bàn, bìa sách, ngón tay giữ sách, góc đen, nêm đen ở gáy sách).
// Chuyển từ ung-dung/loi_xu_ly/cat_chu.py (thử trên 8 ảnh sách người dùng chụp bằng bản 0.7.1 và ảnh công văn mẫu).
//
// 1. Nét mực (ngưỡng thích nghi) và vùng tối (xám < 110); chiều cao chữ = trung vị chiều cao các nét vừa cỡ.
// 2. Vết: khối lớn lấp kín khung bao, rất tối (xám < 40), màu da (ngón tay), vệt sáng dài, hoặc nét lớn chạm mép ảnh.
//    Nét chữ: không chạm mép, không phải vết, không sát vết, không quá nhỏ, không quá nhạt.
// 3. Nối chữ thành khối; giữ các khối nhiều chữ, gộp dần khối nhỏ ở gần (số trang, chú thích); nới vùng cho trọn mọi
//    nét chạm vào vùng (dấu chấm, dấu thanh) để không bao giờ cắt lẹm vào chữ.
// 4. Ảnh ra = vùng chữ + lề trắng (1,5 chiều cao chữ, ít nhất 1,5% cạnh dài); vết lấn vào vùng được tô trắng kín.
// 0.7.3 (ảnh sách chụp thật lần hai): vết còn gồm bóng mờ nét dày (vệt bóng cong ở mép, bóng ngón tay), mẩu đen dày sát
// mép; tiêu đề, chú thích cách xa thân bài (tới 12% chiều cao) vẫn giữ; dải gáy giữa hai trang được xóa sạch; ngón tay
// màu da tô trắng (giữ nét chữ bị ngón tay đè).
// Trang không đủ chữ (ảnh, trang trắng) thì trả nguyên ảnh.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'anh.dart';

const int _canhXuLy = 1600;

class _Vung {
  _Vung(this.x0, this.y0, this.x1, this.y1, this.caoChu, this.xoa);
  final int x0, y0, x1, y1;
  final double caoChu;
  final cv.Mat? xoa; // mặt nạ 0/1 vết cần tô trắng (theo ảnh nhỏ)
}

_Vung? _vungNoiDung(cv.Mat nho) {
  final xam = cv.cvtColor(nho, cv.COLOR_BGR2GRAY);
  final hsv = cv.cvtColor(nho, cv.COLOR_BGR2HSV);
  final h = xam.rows, w = xam.cols, np = h * w;
  final muc = cv.adaptiveThreshold(xam, 255, cv.ADAPTIVE_THRESH_MEAN_C, cv.THRESH_BINARY_INV, 31, 15);
  final toi = cv.threshold(xam, 109, 255, cv.THRESH_BINARY_INV).$2; // xám < 110
  final tong = cv.bitwiseOR(muc, toi);
  final nhanM = cv.Mat.empty(), tkM = cv.Mat.empty(), tamM = cv.Mat.empty();
  final n = cv.connectedComponentsWithStats(tong, nhanM, tkM, tamM, 8, cv.MatType.CV_32S, cv.CCL_DEFAULT);
  if (n < 30) return null;
  final nhan = i32Chep(nhanM), tk = i32Chep(tkM);
  final xd = u8Chep(xam), hd = u8Chep(hsv);
  int g(int i, int c) => tk[i * 5 + c];
  // chiều cao chữ
  final vua = <int>[
    for (var i = 1; i < n; i++)
      if (g(i, 3) > 4 && g(i, 3) < 0.05 * h) g(i, 3)
  ]..sort();
  if (vua.length < 20) return null;
  final caoChu = vua[vua.length ~/ 2].toDouble(), cc2 = caoChu * caoChu;
  // bán kính nét (khoảng cách xa nhất từ trong nét ra mép nét): chữ in, kể cả chữ đậm của tiêu đề, dưới 0,35 chiều
  // cao chữ; bóng ngón tay, vệt bóng cong ở mép, mẩu đen ở góc thì dày hơn nhiều
  final kc = f32Chep(cv.distanceTransform(tong, cv.DIST_L2, cv.DIST_MASK_3, cv.DIST_LABEL_CCOMP).$1);
  final banKinh = Float64List(n);
  // trung bình xám, bão hòa, sắc độ từng nét
  final demPx = Float64List(n), tongXam = Float64List(n), tongBh = Float64List(n), tongSac = Float64List(n);
  for (var p = 0; p < np; p++) {
    final l = nhan[p];
    if (l == 0) continue;
    demPx[l]++;
    if (kc[p] > banKinh[l]) banKinh[l] = kc[p];
    tongXam[l] += xd[p];
    tongSac[l] += hd[p * 3];
    tongBh[l] += hd[p * 3 + 1];
  }
  final vet = List<bool>.filled(n, false), nhoL = List<bool>.filled(n, false), chamMep = List<bool>.filled(n, false);
  final xamTb = Float64List(n), bhTb = Float64List(n), lapDayL = Float64List(n);
  final mo = List<bool>.filled(n, false);
  for (var i = 1; i < n; i++) {
    final x = g(i, 0), y = g(i, 1), cw = g(i, 2), ch = g(i, 3), dt = g(i, 4).toDouble();
    final d = math.max(demPx[i], 1.0);
    final xm = tongXam[i] / d, bh = tongBh[i] / d, sac = tongSac[i] / d;
    xamTb[i] = xm;
    bhTb[i] = bh;
    chamMep[i] = x <= 1 || y <= 1 || x + cw >= w - 1 || y + ch >= h - 1;
    final lapDay = dt / math.max(cw * ch, 1);
    lapDayL[i] = lapDay;
    // bóng mờ dày (ngón tay, vệt bóng cong ở mép trang): nét dày mà nhạt
    mo[i] = banKinh[i] > 0.35 * caoChu && xm > 100 && dt > 1.5 * cc2;
    final satMep = math.min(math.min(x, y), math.min(w - x - cw, h - y - ch)) < 4 * caoChu;
    // vết (số đo trên ảnh sách người dùng chụp: nét chữ xám 85–110, bão hòa ~0; nêm đen, góc đen xám 16–22;
    // ngón tay màu da bão hòa 50–95, sắc 8–35; dấu đỏ, chữ ký xanh bão hòa ~155 nên không bị tính)
    final dac = (dt > 9 * cc2 && lapDay > 0.45) ||
        cw > 0.5 * w ||
        ch > 0.5 * h ||
        (dt > 4 * cc2 && xm < 40) ||
        (dt > 3 * cc2 && bh > 30 && bh < 125 && sac > 8 && sac < 35 && xm > 110) ||
        ((ch > 6 * caoChu || cw > 30 * caoChu) && xm > 150) ||
        mo[i] ||
        // mẩu đen dày sát mép ảnh (góc đen, nêm đen ở đầu gáy)
        (banKinh[i] > 0.5 * caoChu && xm < 70 && satMep);
    // đốm nhỏ (bụi, chấm lẻ) và nét rất nhạt (viền ngón tay, bóng) không tính là chữ
    nhoL[i] = dt < math.max(4.0, 0.15 * cc2) || xm > 190;
    vet[i] = dac || (chamMep[i] && !nhoL[i] && (dt > 9 * cc2 || ch > 3 * caoChu || cw > 8 * caoChu));
  }
  // mảnh vụn sát vết (cách dưới một chiều cao chữ) cũng là vết
  final matVet = Uint8List(np);
  for (var p = 0; p < np; p++) {
    if (vet[nhan[p]]) matVet[p] = 1;
  }
  final k2 = (2 * caoChu).toInt() | 1;
  final ganVet =
      u8Chep(cv.dilate(cv.Mat.fromList(h, w, cv.MatType.CV_8UC1, matVet), cv.getStructuringElement(cv.MORPH_RECT, (k2, k2))));
  final chamVet = List<bool>.filled(n, false);
  for (var p = 0; p < np; p++) {
    if (ganVet[p] > 0) chamVet[nhan[p]] = true;
  }
  final chu = [for (var i = 0; i < n; i++) i > 0 && !chamMep[i] && !vet[i] && !nhoL[i] && !chamVet[i]];
  if (chu.where((c) => c).length < 20) return null;
  final matChu = Uint8List(np);
  for (var p = 0; p < np; p++) {
    if (chu[nhan[p]]) matChu[p] = 1;
  }
  final kx = math.max(3, (2.5 * caoChu).toInt()), ky = math.max(3, (1.5 * caoChu).toInt());
  final khoiM = cv.dilate(cv.Mat.fromList(h, w, cv.MatType.CV_8UC1, matChu), cv.getStructuringElement(cv.MORPH_RECT, (kx, ky)));
  final nhanK = cv.Mat.empty(), tkK = cv.Mat.empty(), tamK = cv.Mat.empty();
  final nk = cv.connectedComponentsWithStats(khoiM, nhanK, tkK, tamK, 8, cv.MatType.CV_32S, cv.CCL_DEFAULT);
  if (nk < 2) return null;
  final nhk = i32Chep(nhanK), tkk = i32Chep(tkK);
  final dem = List<int>.filled(nk, 0);
  for (var p = 0; p < np; p++) {
    if (matChu[p] > 0) dem[nhk[p]]++;
  }
  final hop = [
    for (var i = 1; i < nk; i++)
      (tkk[i * 5], tkk[i * 5 + 1], tkk[i * 5] + tkk[i * 5 + 2], tkk[i * 5 + 1] + tkk[i * 5 + 3], dem[i])
  ];
  final lonNhat = hop.map((b) => b.$5).reduce(math.max);
  final giu = hop.where((b) => b.$5 >= 0.15 * lonNhat).toList();
  final con = hop.where((b) => b.$5 < 0.15 * lonNhat && b.$5 >= 2).toList();
  var x0 = giu.map((b) => b.$1).reduce(math.min), y0 = giu.map((b) => b.$2).reduce(math.min);
  var x1 = giu.map((b) => b.$3).reduce(math.max), y1 = giu.map((b) => b.$4).reduce(math.max);
  final gan = math.max(0.06 * math.min(w, h), 4 * caoChu);
  // tiêu đề, chú thích cuối trang: khối có từ ba nét, nằm trong bề ngang vùng chữ, cách xa hơn (tới 12% chiều cao)
  final ganDoc = math.max(0.12 * h, 10 * caoChu);
  var thayDoi = true;
  while (thayDoi) {
    thayDoi = false;
    for (final b in [...con]) {
      final dx = math.max(math.max(x0 - b.$3, b.$1 - x1), 0), dy = math.max(math.max(y0 - b.$4, b.$2 - y1), 0);
      if (math.max(dx, dy) <= gan ||
          (b.$5 >= 3 && dx == 0 && b.$1 >= x0 - 2 * caoChu && b.$3 <= x1 + 2 * caoChu && dy <= ganDoc)) {
        x0 = math.min(x0, b.$1);
        y0 = math.min(y0, b.$2);
        x1 = math.max(x1, b.$3);
        y1 = math.max(y1, b.$4);
        con.remove(b);
        thayDoi = true;
      }
    }
  }
  // khối giãn rộng hơn nét thật nửa nhân giãn mỗi bên: thu lại
  x0 += kx ~/ 2;
  x1 -= kx ~/ 2;
  y0 += ky ~/ 2;
  y1 -= ky ~/ 2;
  if (x1 <= x0 || y1 <= y0) return null;
  // nới vùng cho trọn mọi nét chạm vào hoặc sát vùng (dấu chấm, dấu thanh): không bao giờ cắt lẹm vào chữ
  for (var vong = 0; vong < 3; vong++) {
    var nx0 = x0, ny0 = y0, nx1 = x1, ny1 = y1;
    for (var i = 1; i < n; i++) {
      if (vet[i] || xamTb[i] > 190 || chamMep[i]) continue;
      final x = g(i, 0), y = g(i, 1), cw = g(i, 2), ch = g(i, 3);
      if (x < x1 + caoChu && x + cw > x0 - caoChu && y < y1 + caoChu && y + ch > y0 - caoChu) {
        nx0 = math.min(nx0, x);
        ny0 = math.min(ny0, y);
        nx1 = math.max(nx1, x + cw);
        ny1 = math.max(ny1, y + ch);
      }
    }
    if (nx0 == x0 && ny0 == y0 && nx1 == x1 && ny1 == y1) break;
    (x0, y0, x1, y1) = (nx0, ny0, nx1, ny1);
  }
  // vết chạm mép ảnh hoặc lấn vào từ ngoài vùng nội dung: xóa, tô kín cả phần trong viền; khối tối nằm trọn trong
  // vùng nội dung mà không chạm mép (ảnh minh họa) thì giữ
  final xoaL = List<bool>.filled(n, false);
  var coXoa = false;
  for (var i = 1; i < n; i++) {
    if (!vet[i]) continue;
    final x = g(i, 0), y = g(i, 1), cw = g(i, 2), ch = g(i, 3);
    if (chamMep[i] || !(x >= x0 && y >= y0 && x + cw <= x1 && y + ch <= y1)) {
      xoaL[i] = true;
      coXoa = true;
    }
  }
  // bóng mờ nhỏ trong vùng chữ (vệt ngón tay, bóng xám): xóa; mảng lớn, kín (ảnh minh họa) thì giữ
  for (var i = 1; i < n; i++) {
    if (mo[i] && g(i, 4) < 25 * cc2 && lapDayL[i] < 0.6) {
      xoaL[i] = true;
      coXoa = true;
    }
  }
  // gáy sách giữa hai trang (ảnh sách mở): dải dọc ở giữa không có chữ, hai bên đều có chữ. Bóng gáy, vệt đứt quãng,
  // mẩu đen ở đầu gáy nằm trọn trong dải thì xóa; nét màu (dấu, chữ ký) và nét vắt qua dải (bảng) thì giữ
  final dai = _daiGay(chu, n, g, x0, x1, caoChu);
  if (dai != null) {
    final (g0, g1) = dai;
    for (var i = 1; i < n; i++) {
      if (!chu[i] && g(i, 0) >= g0 - caoChu && g(i, 0) + g(i, 2) <= g1 + caoChu && bhTb[i] < 60) {
        xoaL[i] = true;
        coXoa = true;
      }
    }
  }
  cv.Mat? xoa;
  if (coXoa) {
    final xd2 = Uint8List(np);
    for (var p = 0; p < np; p++) {
      if (xoaL[nhan[p]]) xd2[p] = 1;
    }
    xoa = cv.Mat.fromList(h, w, cv.MatType.CV_8UC1, xd2);
    final (duong, _) = cv.findContours(xoa, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
    // tô kín lòng vết (ngón tay rỗng ruột…); vết hình khung bao quanh gần cả ảnh (dải nền bàn quanh trang khi nắn
    // phẳng có nới khung) thì lòng là cả trang: chỉ xóa chính vết
    final giu = cv.VecVecPoint.fromList([
      for (final c in duong)
        if (!(cv.boundingRect(c).width > 0.9 * w && cv.boundingRect(c).height > 0.9 * h)) c.toList(),
    ]);
    cv.drawContours(xoa, giu, -1, cv.Scalar.all(1), thickness: cv.FILLED);
  }
  return _Vung(x0, y0, x1, y1, caoChu, xoa);
}

/// (cột đầu, cột cuối) của dải không chữ ở giữa vùng chữ, rộng từ 4 chiều cao chữ; null nếu không có.
(int, int)? _daiGay(List<bool> chu, int n, int Function(int, int) g, int x0, int x1, double caoChu) {
  final rong = x1 - x0;
  if (rong < 20 * caoChu) return null;
  final coChu = Int32List(rong + 1);
  for (var i = 1; i < n; i++) {
    if (!chu[i]) continue;
    final a = math.max(0, g(i, 0) - x0), b = math.min(rong, g(i, 0) + g(i, 2) - x0);
    for (var c = a; c < b; c++) {
      coChu[c]++;
    }
  }
  final lo = (0.3 * rong).toInt(), hi = (0.7 * rong).toInt();
  var tot0 = 0, tot1 = 0;
  int? dau;
  for (var c = lo; c <= hi; c++) {
    final trong = c < hi && coChu[c] == 0;
    if (trong && dau == null) {
      dau = c;
    } else if (!trong && dau != null) {
      if (c - dau > tot1 - tot0) {
        tot0 = dau;
        tot1 = c;
      }
      dau = null;
    }
  }
  if (tot1 - tot0 < 4 * caoChu) return null;
  var tong = 0, trai = 0, phai = 0;
  for (var c = 0; c <= rong; c++) {
    tong += coChu[c];
    if (c < tot0) trai += coChu[c];
    if (c >= tot1) phai += coChu[c];
  }
  // hai bên đều phải có nhiều chữ (hai trang sách), không phải lề rộng của một trang
  if (trai < 0.2 * tong || phai < 0.2 * tong) return null;
  return (x0 + tot0, x0 + tot1);
}

/// Diện tích bao lồi của một tập điểm (chuỗi đơn điệu Andrew).
double _dienTichBaoLoi(List<(int, int)> d) {
  if (d.length < 3) return 0;
  d.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
  int cheo((int, int) o, (int, int) a, (int, int) b) => (a.$1 - o.$1) * (b.$2 - o.$2) - (a.$2 - o.$2) * (b.$1 - o.$1);
  final bao = <(int, int)>[];
  for (final p in d) {
    while (bao.length >= 2 && cheo(bao[bao.length - 2], bao.last, p) <= 0) {
      bao.removeLast();
    }
    bao.add(p);
  }
  final duoi = bao.length + 1;
  for (final p in d.reversed.skip(1)) {
    while (bao.length >= duoi && cheo(bao[bao.length - 2], bao.last, p) <= 0) {
      bao.removeLast();
    }
    bao.add(p);
  }
  bao.removeLast();
  var s = 0.0;
  for (var i = 0; i < bao.length; i++) {
    final a = bao[i], b = bao[(i + 1) % bao.length];
    s += a.$1 * b.$2 - b.$1 * a.$2;
  }
  return s.abs() / 2;
}

/// Ngón tay giữ sách (sau khi làm sạch thành mảng cam, hồng nhạt): tô trắng; nét chữ bị ngón tay đè thì giữ, chuyển
/// về màu xám. Chỉ nhận mảng màu da đặc, đủ lớn, không quá lớn: vòng dấu đỏ (sắc đỏ, rỗng ruột), dòng tô sáng (mảnh),
/// giấy ngả vàng (cả trang) không bị tính. Trả chính [anh] nếu không có ngón tay.
cv.Mat xoaDaTay(cv.Mat anh) {
  if (anh.channels != 3) return anh;
  final h = anh.rows, w = anh.cols;
  final (nho, _) = thuNho(anh, 800);
  final hn = nho.rows, wn = nho.cols, np = hn * wn;
  final hsv = u8Chep(cv.cvtColor(nho, cv.COLOR_BGR2HSV));
  // số đo trên ảnh người dùng: ngón tay sau làm sạch sắc 6–29, bão hòa 40–140, sáng 170–250; dấu đỏ sắc 0–4, 170–180
  final daD = Uint8List(np);
  for (var p = 0; p < np; p++) {
    final hh = hsv[p * 3], ss = hsv[p * 3 + 1], vv = hsv[p * 3 + 2];
    if (hh >= 5 && hh <= 30 && ss >= 35 && ss <= 200 && vv >= 120) daD[p] = 1;
  }
  var da = cv.Mat.fromList(hn, wn, cv.MatType.CV_8UC1, daD);
  da = cv.morphologyEx(da, cv.MORPH_OPEN, cv.Mat.ones(3, 3, cv.MatType.CV_8UC1), borderType: cv.BORDER_REPLICATE);
  da = cv.morphologyEx(da, cv.MORPH_CLOSE, cv.Mat.ones(9, 9, cv.MatType.CV_8UC1), borderType: cv.BORDER_REPLICATE);
  final nhanM = cv.Mat.empty(), tkM = cv.Mat.empty(), tamM = cv.Mat.empty();
  final n = cv.connectedComponentsWithStats(da, nhanM, tkM, tamM, 8, cv.MatType.CV_32S, cv.CCL_DEFAULT);
  final nhan = i32Chep(nhanM), tk = i32Chep(tkM);
  final ungVien = <int>{};
  for (var i = 1; i < n; i++) {
    final cw = tk[i * 5 + 2], ch = tk[i * 5 + 3], dt = tk[i * 5 + 4];
    if (dt < 0.0015 * np || dt > 0.25 * np || math.min(cw, ch) < 0.025 * math.min(hn, wn)) continue;
    ungVien.add(i);
  }
  if (ungVien.isEmpty) return anh;
  // mảng đặc (ngón tay lồi), không phải vòng dấu rỗng ruột: diện tích so với bao lồi (điểm biên của từng mảng)
  final bien = {for (final i in ungVien) i: <(int, int)>[]};
  for (var y = 0; y < hn; y++) {
    for (var x = 0; x < wn; x++) {
      final l = nhan[y * wn + x];
      if (!ungVien.contains(l)) continue;
      if (x == 0 ||
          y == 0 ||
          x == wn - 1 ||
          y == hn - 1 ||
          nhan[y * wn + x - 1] != l ||
          nhan[y * wn + x + 1] != l ||
          nhan[(y - 1) * wn + x] != l ||
          nhan[(y + 1) * wn + x] != l) {
        bien[l]!.add((x, y));
      }
    }
  }
  final giu = <int>{
    for (final i in ungVien)
      if (tk[i * 5 + 4] >= 0.6 * _dienTichBaoLoi(bien[i]!)) i
  };
  if (giu.isEmpty) return anh;
  // nới theo phần màu da nhạt hơn nối liền (mép ngón tay, phần bị làm sáng gần hết)
  final nhatD = Uint8List(np);
  for (var p = 0; p < np; p++) {
    final hh = hsv[p * 3], ss = hsv[p * 3 + 1], vv = hsv[p * 3 + 2];
    if ((hh >= 3 && hh <= 32 && ss >= 18 && vv >= 40) || giu.contains(nhan[p])) nhatD[p] = 1;
  }
  final nhat = cv.morphologyEx(
      cv.Mat.fromList(hn, wn, cv.MatType.CV_8UC1, nhatD), cv.MORPH_CLOSE, cv.Mat.ones(7, 7, cv.MatType.CV_8UC1),
      borderType: cv.BORDER_REPLICATE);
  final nhan2M = cv.Mat.empty();
  cv.connectedComponents(nhat, nhan2M, 8, cv.MatType.CV_32S, cv.CCL_DEFAULT);
  final nhan2 = i32Chep(nhan2M);
  final giu2 = <int>{};
  for (var p = 0; p < np; p++) {
    if (giu.contains(nhan[p]) && nhan2[p] > 0) giu2.add(nhan2[p]);
  }
  var dienTich2 = 0;
  for (var p = 0; p < np; p++) {
    if (giu2.contains(nhan2[p])) dienTich2++;
  }
  // phần nới tràn quá rộng (giấy ngả vàng chưa trắng hết) thì chỉ lấy lõi
  final dungNoi = dienTich2 <= 0.3 * np;
  final matD = Uint8List(np);
  for (var p = 0; p < np; p++) {
    if (dungNoi ? giu2.contains(nhan2[p]) : giu.contains(nhan[p])) matD[p] = 1;
  }
  final mat = u8Chep(cv.resize(
      cv.dilate(cv.Mat.fromList(hn, wn, cv.MatType.CV_8UC1, matD), cv.Mat.ones(9, 9, cv.MatType.CV_8UC1)), (w, h),
      interpolation: cv.INTER_NEAREST));
  final xamM = cv.cvtColor(anh, cv.COLOR_BGR2GRAY);
  final xam = u8Chep(xamM);
  // nền quanh từng điểm (lọc lấy sáng nhất): nét chữ là điểm tối hơn nền hẳn
  final k = math.max(5, (0.012 * math.max(h, w)).round() | 1);
  final nen = u8Chep(cv.dilate(xamM, cv.getStructuringElement(cv.MORPH_ELLIPSE, (k, k))));
  final netD = Uint8List(h * w);
  for (var p = 0; p < h * w; p++) {
    if (mat[p] > 0 && xam[p] < nen[p] - 60) netD[p] = 1;
  }
  // chỉ giữ nét cỡ chữ; viền ngón tay (dải dài theo mép ngón) thì xóa
  final nhan3M = cv.Mat.empty(), tk3M = cv.Mat.empty(), tam3M = cv.Mat.empty();
  final n3 = cv.connectedComponentsWithStats(
      cv.Mat.fromList(h, w, cv.MatType.CV_8UC1, netD), nhan3M, tk3M, tam3M, 8, cv.MatType.CV_32S, cv.CCL_DEFAULT);
  final nhan3 = i32Chep(nhan3M), tk3 = i32Chep(tk3M);
  final gioi = 0.03 * math.max(h, w);
  final nhoL = List<bool>.filled(n3, false);
  for (var i = 1; i < n3; i++) {
    nhoL[i] = tk3[i * 5 + 2] <= gioi && tk3[i * 5 + 3] <= gioi;
  }
  final ra = anh.clone();
  final rd = ra.data;
  for (var p = 0; p < h * w; p++) {
    if (mat[p] == 0) continue;
    final v = nhoL[nhan3[p]] ? xam[p] : 255;
    rd[p * 3] = v;
    rd[p * 3 + 1] = v;
    rd[p * 3 + 2] = v;
  }
  return ra;
}

/// Cắt sát vùng chữ, chừa lề trắng; xóa vết lấn vào vùng chữ. Không đủ chữ thì trả nguyên ảnh.
/// Tên các kiểu lề trang (hiện ở Cài đặt, Xử lý lại).
const tenLe = {'sat': 'Sát chữ', 'vua': 'Vừa', 'trang': 'Giữ cả trang'};

/// Lề "vừa": giữ lề thật của trang tới 6% cạnh dài (góp ý 15/11/2026: "lề không cần cắt sát quá").
const double leVua = 0.06;

/// Cắt theo vùng chữ, chừa lề trắng; xóa vết tối lấn vào vùng chữ. Không đủ chữ thì trả nguyên ảnh.
/// [le]: 'sat' chừa lề hẹp (1,5 chiều cao chữ); 'vua' giữ lề thật của trang (khoảng cách chữ tới mép ảnh), tối đa 6%
/// cạnh dài, ít nhất như 'sat'; 'trang' giữ trọn lề tới mép ảnh. Lề luôn là nền trắng mới (vết ngoài vùng chữ mất).
/// [giuKho]: ảnh là một trang giấy đã cắt theo mép (có khung): trang ít chữ (cuối chương, trang tên) vẫn giữ khổ trang,
/// không bị cắt còn một mẩu. Giống cat_sat_chu (Python).
cv.Mat catSatChu(cv.Mat anh, {double leChu = 1.5, double leToiThieu = 0.015, String le = 'vua', bool giuKho = false}) {
  final h = anh.rows, w = anh.cols;
  final (nho, s) = thuNho(anh, _canhXuLy);
  final v = _vungNoiDung(nho);
  if (v == null) return anh;
  final x0 = math.max(0, (v.x0 / s).floor() - 1), y0 = math.max(0, (v.y0 / s).floor() - 1);
  final x1 = math.min(w, (v.x1 / s).ceil() + 1), y1 = math.min(h, (v.y1 / s).ceil() + 1);
  if ((x1 - x0) * (y1 - y0) > 0.97 * w * h) return anh;
  // vùng chữ tìm trên ảnh gốc (ngón tay còn nguyên là một khối vết lớn); tô trắng ngón tay trên ảnh ra
  final vung = xoaDaTay(anh.region(cv.Rect(x0, y0, x1 - x0, y1 - y0)).clone());
  final xoa = v.xoa;
  if (xoa != null) {
    final to = cv.resize(cv.dilate(xoa, cv.Mat.ones(3, 3, cv.MatType.CV_8UC1)), (w, h), interpolation: cv.INTER_NEAREST);
    final md = u8Chep(to.region(cv.Rect(x0, y0, x1 - x0, y1 - y0)).clone());
    final vd = vung.data, kenh = vung.channels;
    for (var p = 0; p < md.length; p++) {
      if (md[p] == 0) continue;
      for (var c = 0; c < kenh; c++) {
        vd[p * kenh + c] = 255;
      }
    }
  }
  final toiThieu = math.max(leChu * v.caoChu / s, leToiThieu * math.max(h, w)).round();
  var tren = toiThieu, duoi = toiThieu, trai = toiThieu, phai = toiThieu;
  if (le != 'sat') {
    final toiDa = le == 'trang' ? math.max(h, w) : math.max(toiThieu, (leVua * math.max(h, w)).toInt());
    int leThat(int d) => math.min(math.max(d, toiThieu), toiDa);
    // khoảng cách chữ tới mép ảnh (mép giấy sau khi nắn)
    tren = leThat(y0);
    duoi = leThat(h - y1);
    trai = leThat(x0);
    phai = leThat(w - x1);
    if (giuKho) {
      // trang ít chữ: giữ khổ trang (bỏ dải nới khung 2,5% ở mép)
      final boY = (0.03 * h).toInt(), boX = (0.03 * w).toInt();
      if (y1 - y0 < 0.6 * h) {
        tren = math.max(tren, y0 - boY);
        duoi = math.max(duoi, h - boY - y1);
      }
      if (x1 - x0 < 0.5 * w) {
        trai = math.max(trai, x0 - boX);
        phai = math.max(phai, w - boX - x1);
      }
    }
  }
  return cv.copyMakeBorder(vung, tren, duoi, trai, phai, cv.BORDER_CONSTANT, value: cv.Scalar.all(255));
}
