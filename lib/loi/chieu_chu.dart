// Nhận ra trang có dòng chữ chạy dọc (ảnh chụp khi cầm máy ngang, trang sách mở chụp xoay) để xoay về ngang trước
// các bước cần dòng chữ nằm ngang (tìm gáy, nắn cong, sửa nghiêng, cắt sát chữ). Chuyển từ
// ung-dung/loi_xu_ly/chieu_chu.py.
//
// Chỉ phân biệt dòng ngang / dòng dọc, không phân biệt xuôi / ngược: bước đoán chiều bằng Tesseract sau khi xử lý lo
// việc lật 180°. Cách làm: lấy các nét cỡ chữ, nối chữ theo chiều ngang rồi theo chiều dọc; chiều nào nối ra nhiều dải
// dài, mảnh (dòng chữ) hơn hẳn thì đó là chiều dòng chữ.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'anh.dart';

const int _canhXuLy = 1000;

double _doDaiDong(cv.Mat chu, double caoChu, bool ngang) {
  final k = math.max(3, (1.6 * caoChu).toInt());
  final dong = cv.morphologyEx(chu, cv.MORPH_CLOSE, cv.getStructuringElement(cv.MORPH_RECT, ngang ? (k, 1) : (1, k)),
      borderType: cv.BORDER_REPLICATE);
  final nhanM = cv.Mat.empty(), tkM = cv.Mat.empty(), tamM = cv.Mat.empty();
  final n = cv.connectedComponentsWithStats(dong, nhanM, tkM, tamM, 8, cv.MatType.CV_32S, cv.CCL_DEFAULT);
  final tk = i32Chep(tkM);
  var tong = 0.0;
  for (var i = 1; i < n; i++) {
    final w = tk[i * 5 + 2].toDouble(), h = tk[i * 5 + 3].toDouble();
    final dai = ngang ? w : h, day = ngang ? h : w;
    if (dai > 6 * day && dai > 8 * caoChu && day < 3 * caoChu) tong += dai;
  }
  return tong;
}

/// true nếu dòng chữ của trang chạy dọc (cần xoay 90°).
bool chuDoc(cv.Mat anh) {
  final (nho, _) = thuNho(anh, _canhXuLy);
  final xam = nho.channels == 3 ? cv.cvtColor(nho, cv.COLOR_BGR2GRAY) : nho;
  final muc = cv.adaptiveThreshold(xam, 255, cv.ADAPTIVE_THRESH_MEAN_C, cv.THRESH_BINARY_INV, 25, 15);
  final nhanM = cv.Mat.empty(), tkM = cv.Mat.empty(), tamM = cv.Mat.empty();
  final n = cv.connectedComponentsWithStats(muc, nhanM, tkM, tamM, 8, cv.MatType.CV_32S, cv.CCL_DEFAULT);
  if (n < 40) return false;
  final tk = i32Chep(tkM), nhan = i32Chep(nhanM);
  final gioi = 0.05 * math.max(xam.rows, xam.cols);
  final vua = List<bool>.filled(n, false);
  final canh = <int>[];
  for (var i = 1; i < n; i++) {
    final w = tk[i * 5 + 2], h = tk[i * 5 + 3], dt = tk[i * 5 + 4];
    if (w >= 2 && h >= 2 && w < gioi && h < gioi && dt >= 4) {
      vua[i] = true;
      canh.add(math.max(w, h));
    }
  }
  if (canh.length < 40) return false;
  canh.sort();
  final caoChu = canh[canh.length ~/ 2].toDouble();
  final giu = Uint8List(n);
  for (var i = 1; i < n; i++) {
    if (vua[i] && math.max(tk[i * 5 + 2], tk[i * 5 + 3]) <= 3 * caoChu) giu[i] = 255;
  }
  final d = Uint8List(nhan.length);
  for (var p = 0; p < nhan.length; p++) {
    d[p] = giu[nhan[p]];
  }
  final chu = cv.Mat.fromList(xam.rows, xam.cols, cv.MatType.CV_8UC1, d);
  final ngang = _doDaiDong(chu, caoChu, true), doc = _doDaiDong(chu, caoChu, false);
  return doc > 1.5 * ngang && doc > 30 * caoChu;
}
