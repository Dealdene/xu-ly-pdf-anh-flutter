// Tiện ích chung cho ảnh: giải mã, mã hóa, thu nhỏ, truy cập dữ liệu Mat.
import 'dart:ffi' as ffi;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Cạnh dài tối đa của ảnh xử lý trên điện thoại: A4 ở 3000 px ≈ 256 dpi,
/// đủ cho in và nhận dạng chữ mà không tốn quá nhiều bộ nhớ.
const int canhToiDa = 3000;

/// Một điểm (x, y) theo tọa độ điểm ảnh.
typedef Diem = (double, double);

cv.Mat giaiMa(Uint8List duLieu, {int canh = canhToiDa}) {
  final m = cv.imdecode(duLieu, cv.IMREAD_COLOR);
  if (m.isEmpty) {
    throw const FormatException('Không đọc được ảnh');
  }
  return gioiHan(m, canh);
}

cv.Mat gioiHan(cv.Mat m, int canh) {
  final dai = math.max(m.rows, m.cols);
  if (dai <= canh) return m;
  final s = canh / dai;
  return cv.resize(m, ((m.cols * s).round(), (m.rows * s).round()), interpolation: cv.INTER_AREA);
}

/// Thu nhỏ để cạnh dài không quá `canh`; trả kèm tỉ lệ đã dùng.
(cv.Mat, double) thuNho(cv.Mat m, int canh) {
  final s = math.min(1.0, canh / math.max(m.rows, m.cols));
  if (s >= 1.0) return (m, 1.0);
  return (cv.resize(m, ((m.cols * s).round(), (m.rows * s).round()), interpolation: cv.INTER_AREA), s);
}

Uint8List maHoa(cv.Mat m, {int chatLuong = 92}) {
  final (ok, buf) = cv.imencode('.jpg', m, params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, chatLuong]));
  if (!ok) throw StateError('Không mã hóa được ảnh');
  return buf;
}

/// Ảnh 8 bit một kênh, cùng kích thước, toàn số 0.
cv.Mat matNaRong(int rows, int cols) => cv.Mat.zeros(rows, cols, cv.MatType.CV_8UC1);

/// Dữ liệu float của Mat CV_32F (liên tục trong bộ nhớ).
Float32List f32(cv.Mat m) => m.dataPtr.cast<ffi.Float>().asTypedList(m.total * m.channels);

/// Dữ liệu int32 của Mat CV_32S (nhãn thành phần liên thông, nhãn k-means, đoạn thẳng Hough).
Int32List i32(cv.Mat m) => m.dataPtr.cast<ffi.Int32>().asTypedList(m.total * m.channels);

// Bản chép dữ liệu của Mat ra bộ nhớ Dart. `Mat.data`, `f32`, `i32` chỉ là cửa sổ nhìn vào bộ nhớ của Mat: Mat tạm thời
// (kết quả một phép tính không gán vào biến còn dùng) có thể bị thu hồi khi đang đọc, làm ứng dụng chết (SIGSEGV).
Uint8List u8Chep(cv.Mat m) => Uint8List.fromList(m.data);
Float32List f32Chep(cv.Mat m) => Float32List.fromList(f32(m));
Int32List i32Chep(cv.Mat m) => Int32List.fromList(i32(m));

/// Bao lồi (thuật toán dây chuyền đơn điệu).
List<cv.Point> baoLoi(List<cv.Point> p) {
  if (p.length < 3) return p;
  final s = [...p]..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  int cheo(cv.Point o, cv.Point a, cv.Point b) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  final duoi = <cv.Point>[], tren = <cv.Point>[];
  for (final q in s) {
    while (duoi.length >= 2 && cheo(duoi[duoi.length - 2], duoi.last, q) <= 0) {
      duoi.removeLast();
    }
    duoi.add(q);
  }
  for (final q in s.reversed) {
    while (tren.length >= 2 && cheo(tren[tren.length - 2], tren.last, q) <= 0) {
      tren.removeLast();
    }
    tren.add(q);
  }
  return [...duoi.sublist(0, duoi.length - 1), ...tren.sublist(0, tren.length - 1)];
}

/// Diện tích đa giác (công thức dây giày).
double dienTich(List<Diem> p) {
  var s = 0.0;
  for (var i = 0; i < p.length; i++) {
    final (x1, y1) = p[i];
    final (x2, y2) = p[(i + 1) % p.length];
    s += x1 * y2 - x2 * y1;
  }
  return s.abs() / 2;
}

cv.VecVecPoint daGiac(List<Diem> p) => cv.VecVecPoint.fromList([
      [for (final (x, y) in p) cv.Point(x.round(), y.round())]
    ]);

/// Phân vị `q` (0–100) của các giá trị 0–255 có trong `duLieu`, bước `buoc` giữa hai mẫu.
double phanVi(Uint8List duLieu, double q, {int kenh = 1, int lech = 0, int buoc = 1}) {
  final dem = List<int>.filled(256, 0);
  var n = 0;
  for (var i = lech; i < duLieu.length; i += kenh * buoc) {
    dem[duLieu[i]]++;
    n++;
  }
  final can = q / 100 * n;
  var tich = 0;
  for (var v = 0; v < 256; v++) {
    tich += dem[v];
    if (tich >= can) return v.toDouble();
  }
  return 255;
}

/// Làm mờ Gauss một dãy số (dùng cho đường chiếu theo cột).
List<double> moGauss1D(List<double> x, double sigma) {
  final r = (sigma * 3).ceil();
  final nhan = [for (var i = -r; i <= r; i++) math.exp(-i * i / (2 * sigma * sigma))];
  final tong = nhan.reduce((a, b) => a + b);
  return List<double>.generate(x.length, (i) {
    var s = 0.0;
    for (var k = -r; k <= r; k++) {
      final j = (i + k).clamp(0, x.length - 1);
      s += x[j] * nhan[k + r];
    }
    return s / tong;
  });
}
