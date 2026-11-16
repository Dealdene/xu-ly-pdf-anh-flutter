// Sửa chữ theo khối (tính năng 5, hướng A, bản điện thoại). Các dòng liền nhau của một đoạn gộp thành một khối chữ;
// sửa là thay cả khối: xóa nét mực cũ, tô màu nền, dời phần trang bên dưới nếu số dòng đổi, phủ chữ mới
// (chữ mới vẽ bằng dart:ui ở ve_chu.dart). Phần này thuần Dart + OpenCV, chạy được trong isolate.
// Tham khảo ung-dung/loi_xu_ly/sua_noi_dung.py: lấy nét mực bằng thành phần liên thông, nhận dấu thanh nằm ngoài
// khung từ, không cho sửa vùng có mực màu.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'nhan_dang.dart';

const tenCanLe = {'trai': 'căn trái', 'giua': 'căn giữa', 'deu': 'đều hai bên', 'phai': 'căn phải'};

/// Lời báo khi khối có con dấu, chữ ký (mực màu).
const baoMucMau = 'Chỗ này có con dấu, chữ ký, không cho sửa để tránh làm sai lệch giấy tờ';

class LoiSuaChu implements Exception {
  const LoiSuaChu(this.loi);
  final String loi;

  @override
  String toString() => loi;
}

/// Một khối chữ: một đoạn (các dòng liền nhau cùng ocr_par) hoặc một dòng đứng riêng (tiêu đề).
class KhoiChu {
  KhoiChu(this.dong,
      {required this.can, required this.thutDau, required this.khoangDong, required this.xTrai, required this.xPhai});

  final List<DongChu> dong;
  final String can; // trai | giua | deu | phai
  final double thutDau; // dòng đầu thụt vào so với các dòng sau (điểm ảnh, có thể âm)
  final double khoangDong; // khoảng cách hai đường chân chữ liền nhau
  final double xTrai, xPhai; // bề ngang được dàn chữ mới (dòng đầu bắt đầu ở xTrai + thutDau)

  double get x0 => dong.map((d) => d.x0).reduce(math.min);
  double get y0 => dong.map((d) => d.y0).reduce(math.min);
  double get x1 => dong.map((d) => d.x1).reduce(math.max);
  double get y1 => dong.map((d) => d.y1).reduce(math.max);
  double get coChu => _trungVi([for (final d in dong) d.coChu]);

  /// Chữ của khối: các dòng nối bằng dấu cách; dòng bị ngắt cứng (từ đầu dòng sau vẫn vừa chỗ trống cuối dòng
  /// này, như hai dòng quốc hiệu hay mỗi câu một dòng) thì nối bằng xuống dòng để dàn lại vẫn giữ.
  String get chu {
    final b = StringBuffer(dong.first.vanBan);
    for (var i = 1; i < dong.length; i++) {
      final truoc = dong[i - 1], sau = dong[i];
      final cho = xPhai - xTrai - (i == 1 && (can == 'trai' || can == 'deu') ? thutDau : 0) - (truoc.x1 - truoc.x0);
      final tuDau = sau.tu.first;
      b
        ..write(cho > tuDau.x1 - tuDau.x0 + 0.3 * coChu ? '\n' : ' ')
        ..write(sau.vanBan);
    }
    return b.toString();
  }
}

double _trungVi(List<double> v) {
  if (v.isEmpty) return 0;
  final s = [...v]..sort();
  return s.length.isOdd ? s[s.length ~/ 2] : (s[s.length ~/ 2 - 1] + s[s.length ~/ 2]) / 2;
}

/// Gộp các dòng của trang thành khối chữ; đoán căn lề, thụt đầu dòng, khoảng cách dòng của từng khối.
List<KhoiChu> timKhoi(TrangChu trang) {
  final nhom = <List<DongChu>>[];
  for (final d in trang.dong) {
    final truoc = nhom.isEmpty ? null : nhom.last.last;
    final moi = truoc == null ||
        d.doanMoi ||
        d.y0 - truoc.y1 > 1.5 * math.max(d.coChu, truoc.coChu) || // cách xa
        d.x0 > truoc.x1 ||
        d.x1 < truoc.x0; // không chồng nhau theo chiều ngang (cột khác)
    if (moi) {
      nhom.add([d]);
    } else {
      nhom.last.add(d);
    }
  }
  if (nhom.isEmpty) return [];
  final rong = trang.rong > 0 ? trang.rong.toDouble() : trang.dong.map((d) => d.x1).reduce(math.max);
  // lề chữ của trang: lấy theo các dòng dài (thân bài)
  final dai = [for (final d in trang.dong) if (d.x1 - d.x0 >= 0.45 * rong) d];
  final cotTrai = dai.isEmpty ? rong * 0.1 : dai.map((d) => d.x0).reduce(math.min);
  final cotPhai = dai.isEmpty ? rong * 0.9 : dai.map((d) => d.x1).reduce(math.max);
  // khoảng dòng chung của trang, dùng cho khối một dòng khi chữ mới dài ra
  final khoang = [
    for (final g in nhom)
      for (var i = 1; i < g.length; i++) g[i].chanChuTai(g[i].x0) - g[i - 1].chanChuTai(g[i - 1].x0),
  ];
  final khoangTrang = khoang.isEmpty ? null : _trungVi(khoang);
  return [for (final g in nhom) _khoi(g, rong, cotTrai, cotPhai, khoangTrang)];
}

KhoiChu _khoi(List<DongChu> g, double rongTrang, double cotTrai, double cotPhai, double? khoangTrang) {
  final co = _trungVi([for (final d in g) d.coChu]);
  final sai = math.max(0.4 * co, 4.0);
  final x0 = g.map((d) => d.x0).reduce(math.min), x1 = g.map((d) => d.x1).reduce(math.max);
  final tam = (x0 + x1) / 2;
  final n = g.length;
  bool chamPhai(DongChu d) => x1 - d.x1 <= sai;
  String can;
  var thut = 0.0;
  var xTrai = x0, xPhai = x1;
  if (n >= 2) {
    final sau = g.skip(1);
    final traiSau = sau.map((d) => d.x0).reduce(math.min);
    thut = g.first.x0 - traiSau;
    if (thut.abs() <= sai) thut = 0;
    bool chamTrai(DongChu d) => d.x0 - traiSau <= sai;
    final canTam = g.every((d) => ((d.x0 + d.x1) / 2 - tam).abs() <= sai);
    final tranRong = g.every(chamPhai) && sau.every(chamTrai);
    final deu = g.take(n - 1).every(chamPhai) && sau.every(chamTrai);
    if (tranRong) {
      can = 'deu';
    } else if (canTam) {
      can = 'giua';
    } else if (deu) {
      can = 'deu';
    } else if (g.every(chamPhai)) {
      can = 'phai';
    } else {
      can = 'trai';
    }
    xTrai = traiSau;
  } else {
    final cotTam = (cotTrai + cotPhai) / 2;
    final ganTam = math.min((tam - rongTrang / 2).abs(), (tam - cotTam).abs()) <= math.max(0.02 * rongTrang, sai);
    if (ganTam && x1 - x0 < 0.9 * (cotPhai - cotTrai)) {
      can = 'giua';
    } else if (x0 - cotTrai > 0.25 * (cotPhai - cotTrai) && cotPhai - x1 <= 2 * sai) {
      can = 'phai';
    } else {
      can = 'trai';
    }
  }
  switch (can) {
    case 'giua':
      final nua = math.max((x1 - x0) / 2, math.min(tam - cotTrai, cotPhai - tam));
      xTrai = tam - nua;
      xPhai = tam + nua;
    case 'phai':
      xTrai = math.min(xTrai, cotTrai);
    case 'trai':
      xPhai = math.max(x1, cotPhai);
  }
  final khoangDong = n >= 2
      ? _trungVi([for (var i = 1; i < n; i++) g[i].chanChuTai(g[i].x0) - g[i - 1].chanChuTai(g[i - 1].x0)])
      : (khoangTrang != null && khoangTrang >= g.first.y1 - g.first.y0 && khoangTrang <= 3 * co ? khoangTrang : 1.2 * co);
  return KhoiChu(g, can: can, thutDau: can == 'trai' || can == 'deu' ? thut : 0, khoangDong: khoangDong, xTrai: xTrai, xPhai: xPhai);
}

// ---------------------------------------------------------------- đo ảnh

/// Ảnh trang đã giải mã: dữ liệu BGR (sửa trực tiếp được) và ảnh xám.
class _Anh {
  _Anh(this.mat, this.xam) : w = mat.cols, h = mat.rows, bgr = mat.data;
  final cv.Mat mat;
  final Uint8List bgr, xam;
  final int w, h;
}

_Anh _doc(Uint8List maHoa) {
  // không thu nhỏ: tọa độ khối chữ tính theo đúng cỡ ảnh đã nhận dạng
  final m = cv.imdecode(maHoa, cv.IMREAD_COLOR);
  if (m.isEmpty) throw const FormatException('Không đọc được ảnh');
  return _Anh(m, Uint8List.fromList(cv.cvtColor(m, cv.COLOR_BGR2GRAY).data));
}

int _otsu(List<int> hist) {
  final n = hist.fold(0, (s, v) => s + v);
  if (n == 0) return 128;
  var tong = 0.0;
  for (var i = 0; i < 256; i++) {
    tong += i * hist[i];
  }
  var sB = 0.0, wB = 0, tot = 0.0, nguong = 128;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = n - wB;
    if (wF == 0) break;
    sB += t * hist[t];
    final mB = sB / wB, mF = (tong - sB) / wF;
    final v = wB * wF * (mB - mF) * (mB - mF);
    if (v > tot) {
      tot = v;
      nguong = t;
    }
  }
  return nguong;
}

/// Nét mực của một dòng: ngưỡng Otsu trong khung dòng, giữ các thành phần liên thông nằm chủ yếu trong khung
/// (lấy trọn nét nhô ra ngoài), cộng dấu thanh nhỏ nằm sát ngay trên, dưới khung. Ghi 1 vào [mat] (cỡ trang);
/// trả khung bao nét mực [x0, y0, x1, y1) hoặc null nếu không có mực.
List<int>? _netDong(_Anh a, DongChu d, Uint8List mat, {int le = 2}) {
  final w = a.w, h = a.h, xam = a.xam;
  final x0 = d.x0.floor().clamp(0, w - 1), y0 = d.y0.floor().clamp(0, h - 1);
  final x1 = d.x1.ceil().clamp(x0 + 1, w), y1 = d.y1.ceil().clamp(y0 + 1, h);
  final cao = y1 - y0;
  final vx0 = math.max(0, x0 - cao), vy0 = math.max(0, y0 - cao), vx1 = math.min(w, x1 + cao), vy1 = math.min(h, y1 + cao);
  final hist = List<int>.filled(256, 0);
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      hist[xam[y * w + x]]++;
    }
  }
  final t = _otsu(hist).clamp(60, 200);
  final vw = vx1 - vx0, vh = vy1 - vy0;
  // thành phần liên thông 8 hướng (loang theo hàng đợi): 0 = nền, −1 = mực chưa gán, ≥ 1 = số thành phần
  final nhan = Int32List(vw * vh);
  for (var y = 0; y < vh; y++) {
    for (var x = 0; x < vw; x++) {
      if (xam[(y + vy0) * w + x + vx0] < t) nhan[y * vw + x] = -1;
    }
  }
  final giu = <bool>[false];
  final hang = Int32List(vw * vh);
  final bx0 = x0 - le, by0 = y0 - le, bx1 = x1 + le, by1 = y1 + le;
  for (var p = 0; p < nhan.length; p++) {
    if (nhan[p] != -1) continue;
    final so = giu.length;
    var dau = 0, cuoi = 0;
    hang[cuoi++] = p;
    nhan[p] = so;
    var cx0 = vw, cy0 = vh, cx1 = 0, cy1 = 0;
    while (dau < cuoi) {
      final q = hang[dau++];
      final qx = q % vw, qy = q ~/ vw;
      if (qx < cx0) cx0 = qx;
      if (qx > cx1) cx1 = qx;
      if (qy < cy0) cy0 = qy;
      if (qy > cy1) cy1 = qy;
      for (var dy = -1; dy <= 1; dy++) {
        final ny = qy + dy;
        if (ny < 0 || ny >= vh) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final nx = qx + dx;
          if (nx < 0 || nx >= vw) continue;
          final r = ny * vw + nx;
          if (nhan[r] == -1) {
            nhan[r] = so;
            hang[cuoi++] = r;
          }
        }
      }
    }
    // khung thành phần theo tọa độ trang, cạnh phải, dưới không gồm
    final kx0 = cx0 + vx0, ky0 = cy0 + vy0, kx1 = cx1 + vx0 + 1, ky1 = cy1 + vy0 + 1;
    final cw = kx1 - kx0, ch = ky1 - ky0;
    final gx = math.max(0, math.min(kx1, bx1) - math.max(kx0, bx0));
    final gy = math.max(0, math.min(ky1, by1) - math.max(ky0, by0));
    var lay = gx * gy >= 0.4 * cw * ch;
    // dấu thanh, dấu nặng Tesseract có khi để ngoài khung: nhận nét nhỏ nằm trọn trong bề ngang dòng,
    // sát ngay trên hoặc dưới khung (trong 1/4 chiều cao chữ), để không lấy nhầm nét của dòng bên cạnh
    if (!lay &&
        kx0 >= bx0 - 2 &&
        kx1 <= bx1 + 2 &&
        ch < 0.5 * cao &&
        cw < 0.8 * cao &&
        ((by0 - 0.25 * cao <= ky1 && ky1 <= by0 + 2) || (by1 - 2 <= ky0 && ky0 <= by1 + 0.25 * cao))) {
      lay = true;
    }
    giu.add(lay);
  }
  var mx0 = w, my0 = h, mx1 = -1, my1 = -1;
  for (var y = 0; y < vh; y++) {
    for (var x = 0; x < vw; x++) {
      final so = nhan[y * vw + x];
      if (so > 0 && giu[so]) {
        final px = x + vx0, py = y + vy0;
        mat[py * w + px] = 1;
        if (px < mx0) mx0 = px;
        if (px > mx1) mx1 = px;
        if (py < my0) my0 = py;
        if (py > my1) my1 = py;
      }
    }
  }
  return mx1 < 0 ? null : [mx0, my0, mx1 + 1, my1 + 1];
}

/// Nới mặt nạ [r] điểm ảnh (hình vuông) trong vùng [x0, y0, x1, y1); trả mặt nạ mới cỡ trang.
Uint8List _noRong(Uint8List mat, int w, int h, int r, List<int> vung) {
  final x0 = math.max(0, vung[0] - r), y0 = math.max(0, vung[1] - r);
  final x1 = math.min(w, vung[2] + r), y1 = math.min(h, vung[3] + r);
  final ngang = Uint8List(w * h), ra = Uint8List(w * h);
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      if (mat[y * w + x] == 0) continue;
      for (var k = math.max(x0, x - r); k <= math.min(x1 - 1, x + r); k++) {
        ngang[y * w + k] = 1;
      }
    }
  }
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      if (ngang[y * w + x] == 0) continue;
      for (var k = math.max(y0, y - r); k <= math.min(y1 - 1, y + r); k++) {
        ra[k * w + x] = 1;
      }
    }
  }
  return ra;
}

List<int> _gop(List<int> a, List<int> b) =>
    [math.min(a[0], b[0]), math.min(a[1], b[1]), math.max(a[2], b[2]), math.max(a[3], b[3])];

List<int> _khungSo(KhoiChu k, int w, int h, double le) => [
      (k.x0 - le).floor().clamp(0, w),
      (k.y0 - le).floor().clamp(0, h),
      (k.x1 + le).ceil().clamp(0, w),
      (k.y1 + le).ceil().clamp(0, h),
    ];

/// Trung vị từng kênh BGR của các điểm [chon] trong vùng.
List<int> _trungViMau(Uint8List bgr, int w, List<int> vung, bool Function(int p) chon) {
  final dem = [List<int>.filled(256, 0), List<int>.filled(256, 0), List<int>.filled(256, 0)];
  var n = 0;
  for (var y = vung[1]; y < vung[3]; y++) {
    for (var x = vung[0]; x < vung[2]; x++) {
      final p = y * w + x;
      if (!chon(p)) continue;
      for (var c = 0; c < 3; c++) {
        dem[c][bgr[p * 3 + c]]++;
      }
      n++;
    }
  }
  if (n == 0) return [255, 255, 255];
  return [
    for (var c = 0; c < 3; c++)
      () {
        var tich = 0;
        for (var v = 0; v < 256; v++) {
          tich += dem[c][v];
          if (tich * 2 >= n) return v;
        }
        return 255;
      }(),
  ];
}

/// Vùng có mực màu (đỏ con dấu, xanh chữ ký, bút phê) chiếm đáng kể trong số điểm mực hay không.
bool _coMucMau(_Anh a, List<int> vung, {double nguong = 0.12}) => coMucMau(a.bgr, a.w, vung, nguong: nguong);

/// Như trên, trên dữ liệu BGR rộng [w] (vùng [x0, y0, x1, y1) nằm trong ảnh). Dùng chung với Sửa ký tự (sua_ky_tu.dart).
bool coMucMau(Uint8List d, int w, List<int> vung, {double nguong = 0.12}) {
  var toiHoacMau = 0, mau = 0;
  for (var y = vung[1]; y < vung[3]; y++) {
    for (var x = vung[0]; x < vung[2]; x++) {
      final p = (y * w + x) * 3;
      final b = d[p], g = d[p + 1], r = d[p + 2];
      final v = math.max(b, math.max(g, r)), nho = math.min(b, math.min(g, r));
      final s = v == 0 ? 0 : 255 * (v - nho) ~/ v;
      final laMau = s > 70 && v < 235;
      if (laMau) mau++;
      if (laMau || v < 200) toiHoacMau++;
    }
  }
  return mau > nguong * math.max(1, toiHoacMau);
}

/// Khối nào có mực màu (không cho sửa), theo thứ tự [khoi].
List<bool> kiemMucMau(Uint8List anhMaHoa, List<KhoiChu> khoi) {
  final a = _doc(anhMaHoa);
  return [for (final k in khoi) _coMucMau(a, _khungSo(k, a.w, a.h, 0.3 * k.coChu))];
}

/// Số đo nét mực của một khối, để đoán phông và xóa chữ cũ.
class DoKhoi {
  DoKhoi({
    required this.mucMau,
    required this.nen,
    required this.mau,
    required this.khungMuc,
    required this.iDo,
    required this.phu,
    required this.khungPhu,
  });

  final bool mucMau;
  final List<int> nen, mau; // BGR: màu nền quanh khối, màu chữ (lõi nét đậm nhất)
  final List<List<int>?> khungMuc; // khung nét mực từng dòng [x0, y0, x1, y1)
  final int iDo; // dòng dùng để đoán phông (dòng dài nhất)
  final Uint8List phu; // độ phủ mực 0–255 quanh dòng iDo
  final List<int> khungPhu; // vùng của [phu] trên trang [x0, y0, x1, y1)
}

/// Nét mực tất cả các dòng của khối (mặt nạ cỡ trang) và khung từng dòng.
(Uint8List, List<List<int>?>) _matKhoi(_Anh a, KhoiChu k) {
  final mat = Uint8List(a.w * a.h);
  final khung = [for (final d in k.dong) _netDong(a, d, mat)];
  return (mat, khung);
}

List<int>? _khungChung(List<List<int>?> ds) {
  List<int>? kq;
  for (final k in ds) {
    if (k != null) kq = kq == null ? k : _gop(kq, k);
  }
  return kq;
}

List<int> _noKhung(List<int> k, int le, int w, int h) =>
    [math.max(0, k[0] - le), math.max(0, k[1] - le), math.min(w, k[2] + le), math.min(h, k[3] + le)];

DoKhoi doKhoi(Uint8List anhMaHoa, KhoiChu k) {
  final a = _doc(anhMaHoa);
  final w = a.w, h = a.h;
  final mucMau = _coMucMau(a, _khungSo(k, w, h, 0.3 * k.coChu));
  final (mat, khung) = _matKhoi(a, k);
  final chung = _khungChung(khung) ?? _khungSo(k, w, h, 0);
  // màu nền: trung vị các điểm không phải mực quanh khối
  final no = _noRong(mat, w, h, 2, chung);
  final nen = _trungViMau(a.bgr, w, _noKhung(chung, 6, w, h), (p) => no[p] == 0);
  final nenXam = (0.114 * nen[0] + 0.587 * nen[1] + 0.299 * nen[2]);
  // dòng đo: dòng có nét mực rộng nhất
  var iDo = 0;
  for (var i = 1; i < khung.length; i++) {
    final ki = khung[i], kd = khung[iDo];
    if (ki != null && (kd == null || ki[2] - ki[0] > kd[2] - kd[0])) iDo = i;
  }
  final kd = khung[iDo] ?? _khungSo(k, w, h, 0);
  // màu chữ: trung vị các điểm lõi nét (40% đậm nhất) của cả khối
  final hist = List<int>.filled(256, 0);
  var soMuc = 0;
  for (var y = chung[1]; y < chung[3]; y++) {
    for (var x = chung[0]; x < chung[2]; x++) {
      if (mat[y * w + x] == 1) {
        hist[a.xam[y * w + x]]++;
        soMuc++;
      }
    }
  }
  int phanVi(double q) {
    var tich = 0;
    for (var v = 0; v < 256; v++) {
      tich += hist[v];
      if (tich >= q * soMuc) return v;
    }
    return 255;
  }

  final loi = phanVi(0.4), dam = phanVi(0.1);
  final mau = soMuc == 0 ? [20, 20, 20] : _trungViMau(a.bgr, w, chung, (p) => mat[p] == 1 && a.xam[p] <= loi);
  // độ phủ thật của mực (0..1) quanh dòng đo: theo độ tối so với nền, chỉ trong nét đã nới 1 điểm ảnh
  final kp = _noKhung(kd, 4, w, h);
  final no1 = _noRong(mat, w, h, 1, kd);
  final pw = kp[2] - kp[0], ph = kp[3] - kp[1];
  final phu = Uint8List(pw * ph);
  final mau0 = math.max(nenXam - dam, 1.0);
  for (var y = 0; y < ph; y++) {
    for (var x = 0; x < pw; x++) {
      final p = (y + kp[1]) * w + x + kp[0];
      if (no1[p] == 0) continue;
      phu[y * pw + x] = (((nenXam - a.xam[p]) / mau0).clamp(0.0, 1.0) * 255).round();
    }
  }
  return DoKhoi(mucMau: mucMau, nen: nen, mau: mau, khungMuc: khung, iDo: iDo, phu: phu, khungPhu: kp);
}

/// Kết quả áp sửa: ảnh trang mới (PNG, không mất dữ liệu nên chỗ không sửa giữ nguyên điểm ảnh) và
/// có phần trang bị đẩy ra ngoài mép dưới hay không.
class AnhDaSua {
  AnhDaSua(this.anh, this.tran);
  final Uint8List anh;
  final bool tran;
}

/// Xóa chữ cũ của khối (tô màu nền lên nét mực đã nới 2 điểm ảnh), dời phần trang từ hàng [yCat] trở xuống
/// [dy] hàng, rồi phủ chữ mới: màu [mau] (BGR) theo độ phủ [phu] (0–255) đặt ở vùng [khungPhu] trên trang.
AnhDaSua apSua(Uint8List anhMaHoa, KhoiChu k,
    {required Uint8List phu, required List<int> khungPhu, required List<int> mau, required int dy, required int yCat}) {
  final a = _doc(anhMaHoa);
  final w = a.w, h = a.h, d = a.bgr;
  final (mat, khung) = _matKhoi(a, k);
  final chung = _khungChung(khung);
  var nen = [255, 255, 255];
  if (chung != null) {
    final no = _noRong(mat, w, h, 2, chung);
    nen = _trungViMau(d, w, _noKhung(chung, 6, w, h), (p) => no[p] == 0);
    final xoa = _noKhung(chung, 2, w, h);
    for (var y = xoa[1]; y < xoa[3]; y++) {
      for (var x = xoa[0]; x < xoa[2]; x++) {
        final p = y * w + x;
        if (no[p] == 0) continue;
        d[p * 3] = nen[0];
        d[p * 3 + 1] = nen[1];
        d[p * 3 + 2] = nen[2];
      }
    }
  }
  var tran = false;
  final hang = w * 3;
  final cat = yCat.clamp(0, h);
  if (dy > 0) {
    // phần cuối trang bị đẩy ra ngoài: có mực không
    final nenXam = 0.114 * nen[0] + 0.587 * nen[1] + 0.299 * nen[2];
    var soMuc = 0;
    for (var y = math.max(cat, h - dy); y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (a.xam[y * w + x] < nenXam - 60) soMuc++;
      }
    }
    tran = soMuc > 30;
    for (var y = h - 1; y >= cat + dy; y--) {
      d.setRange(y * hang, (y + 1) * hang, d, (y - dy) * hang);
    }
    _toNen(d, w, cat, math.min(h, cat + dy), nen);
  } else if (dy < 0) {
    final len = -dy;
    for (var y = math.max(0, cat - len); y < h - len; y++) {
      d.setRange(y * hang, (y + 1) * hang, d, (y + len) * hang);
    }
    _toNen(d, w, h - len, h, nen);
  }
  // phủ chữ mới
  final pw = khungPhu[2] - khungPhu[0];
  for (var y = math.max(0, khungPhu[1]); y < math.min(h, khungPhu[3]); y++) {
    for (var x = math.max(0, khungPhu[0]); x < math.min(w, khungPhu[2]); x++) {
      final al = phu[(y - khungPhu[1]) * pw + x - khungPhu[0]];
      if (al == 0) continue;
      final p = (y * w + x) * 3;
      for (var c = 0; c < 3; c++) {
        d[p + c] = (d[p + c] * (255 - al) + mau[c] * al + 127) ~/ 255;
      }
    }
  }
  final (ok, png) = cv.imencode('.png', a.mat, params: cv.VecI32.fromList([cv.IMWRITE_PNG_COMPRESSION, 3]));
  if (!ok) throw StateError('Không mã hóa được ảnh');
  return AnhDaSua(png, tran);
}

void _toNen(Uint8List d, int w, int y0, int y1, List<int> nen) {
  for (var p = y0 * w; p < y1 * w; p++) {
    d[p * 3] = nen[0];
    d[p * 3 + 1] = nen[1];
    d[p * 3 + 2] = nen[2];
  }
}
