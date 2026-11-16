// Tính năng 2: làm sáng nền, tăng tương phản, giữ màu mực, khử nhiễu.
// Chuyển từ ung-dung/loi_xu_ly/lam_sach.py (bản Python đã kiểm thử). Bản điện thoại thêm (2026-10-29):
// lọc trung vị, đường cong tương phản dốc gấp đôi, xóa đốm nhiễu theo cỡ chữ (xoaDom).
// Đo trên ảnh chụp kém mau4: đốm nhiễu 743 → khoảng 120, nhận dạng đúng 71% → khoảng 90%.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'anh.dart';

const cheDoLamSach = {
  'giu_mau': 'Giữ màu',
  'xam': 'Xám',
  'den_trang': 'Đen trắng',
  'khong': 'Không làm sạch',
};

/// Ảnh nền (8 bit, cùng kích thước) đã xóa nét chữ, gồm cả bóng đổ.
cv.Mat uocLuongNen(cv.Mat anh) {
  final h = anh.rows, w = anh.cols;
  final (nho, _) = thuNho(anh, 1000);
  final nhan = cv.getStructuringElement(cv.MORPH_ELLIPSE, (25, 25));
  var nen = cv.morphologyEx(nho, cv.MORPH_CLOSE, nhan);
  nen = cv.medianBlur(nen, 21);
  // Vùng ảnh màu lớn không xóa được bằng phép đóng: chặn dưới để không bị chia trắng bệch.
  final d = nen.data;
  final san = [for (var c = 0; c < 3; c++) phanVi(d, 95, kenh: 3, lech: c) * 0.45];
  for (var i = 0; i < d.length; i++) {
    final s = san[i % 3];
    if (d[i] < s) d[i] = s.round();
  }
  nen = cv.gaussianBlur(nen, (0, 0), 3);
  return cv.resize(nen, (w, h), interpolation: cv.INTER_CUBIC);
}

double _chuyenMem(double x, double a, double b) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Làm sạch ảnh trang (BGR 8 bit). `doTrang`, `doDam`, `khuNhieu` trong 0..1.
cv.Mat lamSach(cv.Mat anh, {String cheDo = 'giu_mau', double doTrang = 0.5, double doDam = 0.5, double khuNhieu = 0.5}) {
  if (cheDo == 'khong') return anh;
  if (khuNhieu > 0) anh = cv.medianBlur(anh, 3); // nhiễu hạt cảm biến, khối nén JPEG
  final nen = uocLuongNen(anh);
  final a = anh.data, n = nen.data;
  final soDiem = anh.rows * anh.cols;

  // Lượt 1: phân vị 0,5% của độ sáng đã chuẩn hóa (điểm đen).
  const muc = 4096;
  final dem = List<int>.filled(muc, 0);
  for (var p = 0, i = 0; p < soDiem; p += 4, i = p * 3) {
    final b = math.min(a[i] / math.max(n[i], 1), 1.0);
    final g = math.min(a[i + 1] / math.max(n[i + 1], 1), 1.0);
    final r = math.min(a[i + 2] / math.max(n[i + 2], 1), 1.0);
    dem[((0.114 * b + 0.587 * g + 0.299 * r) * (muc - 1)).round()]++;
  }
  var tich = 0, kSoDiem = 0;
  for (final c in dem) {
    kSoDiem += c;
  }
  var diemDen = 0.35;
  for (var v = 0; v < muc; v++) {
    tich += dem[v];
    if (tich >= 0.005 * kSoDiem) {
      diemDen = math.min(v / (muc - 1), 0.35);
      break;
    }
  }
  final diemTrang = 0.97 - 0.15 * doTrang;
  final gamma = 1.0 + 2 * doDam; // chữ chụp điện thoại thường nhạt: đường cong dốc hơn bản PC
  // Bảng tra cho đường cong tương phản và đường cong nhánh màu.
  final bangXam = Float32List(muc), bangMau = Float32List(muc);
  for (var v = 0; v < muc; v++) {
    final y = v / (muc - 1);
    bangXam[v] = math.pow(((y - diemDen) / (diemTrang - diemDen)).clamp(0.0, 1.0), gamma).toDouble();
    bangMau[v] = math.pow(y, 1.0 + doDam).toDouble();
  }

  if (cheDo == 'xam' || cheDo == 'den_trang') {
    final xam = matNaRong(anh.rows, anh.cols);
    final x = xam.data;
    for (var p = 0; p < soDiem; p++) {
      final i = p * 3;
      final b = math.min(a[i] / math.max(n[i], 1), 1.0);
      final g = math.min(a[i + 1] / math.max(n[i + 1], 1), 1.0);
      final r = math.min(a[i + 2] / math.max(n[i + 2], 1), 1.0);
      x[p] = (bangXam[((0.114 * b + 0.587 * g + 0.299 * r) * (muc - 1)).round()] * 255 + 0.5).toInt();
    }
    var ra = xam;
    if (cheDo == 'den_trang') {
      ra = cv.threshold(xam, 0, 255, cv.THRESH_BINARY + cv.THRESH_OTSU).$2;
    }
    return xoaDom(cv.cvtColor(ra, cv.COLOR_GRAY2BGR), khuNhieu);
  }

  // Giữ màu: trộn nhánh xám và nhánh màu theo độ đậm màu tuyệt đối.
  final kq = cv.Mat.zeros(anh.rows, anh.cols, cv.MatType.CV_8UC3);
  final o = kq.data;
  for (var p = 0; p < soDiem; p++) {
    final i = p * 3;
    final b = math.min(a[i] / math.max(n[i], 1), 1.0);
    final g = math.min(a[i + 1] / math.max(n[i + 1], 1), 1.0);
    final r = math.min(a[i + 2] / math.max(n[i + 2], 1), 1.0);
    final y = 0.114 * b + 0.587 * g + 0.299 * r;
    final k = (y * (muc - 1)).round();
    final xam = bangXam[k];
    final doMau = math.max(b, math.max(g, r)) - math.min(b, math.min(g, r));
    final ts = _chuyenMem(doMau, 0.10, 0.22);
    if (ts <= 0) {
      final v = (xam * 255 + 0.5).toInt();
      o[i] = v;
      o[i + 1] = v;
      o[i + 2] = v;
      continue;
    }
    final yMau = bangMau[k];
    final he = yMau / math.max(y, 1e-3);
    final mb = yMau + (b * he - yMau) * 1.25;
    final mg = yMau + (g * he - yMau) * 1.25;
    final mr = yMau + (r * he - yMau) * 1.25;
    o[i] = ((xam * (1 - ts) + mb * ts).clamp(0.0, 1.0) * 255 + 0.5).toInt();
    o[i + 1] = ((xam * (1 - ts) + mg * ts).clamp(0.0, 1.0) * 255 + 0.5).toInt();
    o[i + 2] = ((xam * (1 - ts) + mr * ts).clamp(0.0, 1.0) * 255 + 0.5).toInt();
  }
  return xoaDom(kq, khuNhieu);
}

cv.Mat _gian(cv.Mat mat, double r) {
  final k = math.max(2, r.round());
  return cv.dilate(mat, cv.getStructuringElement(cv.MORPH_ELLIPSE, (2 * k + 1, 2 * k + 1)));
}

/// Xóa đốm tối nhỏ đứng riêng (bụi, nhiễu) trên ảnh đã làm sạch, sửa tại chỗ.
/// Khoảng "gần chữ" tính theo cỡ chữ đo được để giữ dấu thanh tiếng Việt và dấu câu:
/// đốm vừa (cỡ dấu mũ, dấu phẩy) giữ nếu cách chữ dưới 1,2 cỡ chữ;
/// đốm nhỏ (cỡ dấu sắc, dấu nặng, dấu chấm) giữ nếu cách chữ hoặc dấu đã giữ dưới 0,45 cỡ chữ.
cv.Mat xoaDom(cv.Mat ra, double khuNhieu) {
  if (khuNhieu <= 0) return ra;
  final toi = cv.threshold(cv.cvtColor(ra, cv.COLOR_BGR2GRAY), 169, 255, cv.THRESH_BINARY_INV).$2;
  final nhan = cv.Mat.empty(), tk = cv.Mat.empty(), tam = cv.Mat.empty();
  final n = cv.connectedComponentsWithStats(toi, nhan, tk, tam, 8, cv.MatType.CV_32S, cv.CCL_DEFAULT);
  if (n < 3) return ra;
  final dt = [for (var i = 0; i < n; i++) tk.at<int>(i, cv.CC_STAT_AREA)];
  // cỡ chữ: trung vị chiều cao các thành phần vừa phải (bỏ đốm)
  final cao = [
    for (var i = 1; i < n; i++)
      if (dt[i] >= 20 && tk.at<int>(i, cv.CC_STAT_HEIGHT) >= 6) tk.at<int>(i, cv.CC_STAT_HEIGHT)
  ]..sort();
  final h = cao.isEmpty ? 20.0 : cao[cao.length ~/ 2].toDouble();
  final dtNho = math.max(3.0, math.pow(0.12 * h, 2) * math.pi * (0.5 + khuNhieu));
  final dtVua = dtNho * 4;
  final loai = Uint8List(n); // 0 nền, 1 nhỏ, 2 vừa, 3 chữ
  for (var i = 1; i < n; i++) {
    loai[i] = dt[i] <= dtNho ? 1 : (dt[i] <= dtVua ? 2 : 3);
  }
  final b = nhan.data;
  final l = b.buffer.asInt32List(b.offsetInBytes, b.lengthInBytes ~/ 4);
  final nho = matNaRong(ra.rows, ra.cols), vua = matNaRong(ra.rows, ra.cols), lon = matNaRong(ra.rows, ra.cols);
  final dn = nho.data, dv = vua.data, dl = lon.data;
  for (var p = 0; p < l.length; p++) {
    switch (loai[l[p]]) {
      case 1:
        dn[p] = 255;
      case 2:
        dv[p] = 255;
      case 3:
        dl[p] = 255;
    }
  }
  final giuVua = cv.bitwiseAND(vua, _gian(lon, 1.2 * h));
  final ganGiu = _gian(cv.bitwiseOR(lon, giuVua), 0.45 * h);
  final xoa = cv.bitwiseOR(cv.bitwiseAND(vua, cv.bitwiseNOT(giuVua)), cv.bitwiseAND(nho, cv.bitwiseNOT(ganGiu)));
  ra.setTo(cv.Scalar.all(255), mask: xoa);
  return ra;
}
