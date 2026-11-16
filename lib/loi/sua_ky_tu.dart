// Sửa ký tự giữ nguyên bản gốc (tính năng 5, bản điện thoại): thêm, bớt ký tự trên ảnh scan, ảnh chụp mà không vẽ lại chữ.
// Chuyển từ ung-dung/loi_xu_ly/sua_ky_tu.py (bản PC đã kiểm chứng trên tệp thật của người dùng).
//
// Mỗi dòng chữ được chia thành các mảnh nằm liền nhau: mỗi ký tự, mỗi khoảng trắng là một dải điểm ảnh gốc
// (khung ký tự lấy từ Tesseract, hOCR có hocr_char_boxes). Sửa dòng = xếp lại các mảnh:
// - ký tự không đụng tới giữ nguyên từng điểm ảnh (chỉ dời ngang khi có chèn, xóa phía trước);
// - xóa ký tự = bỏ mảnh;
// - chèn ký tự = chép nguyên hình ký tự đó từ chỗ khác trên cùng trang (cùng cỡ, cùng nét, cùng độ nhòe); trang không
//   có thì chép từ trang khác của hồ sơ (đánh dấu chưa chắc); cả hồ sơ không có mới vẽ bằng phông (ve_chu.dart);
// - dòng có dãy dấu chấm dẫn (mục lục) thì dãy chấm co giãn để phần sau (số trang) đứng nguyên chỗ.
// Nhận dạng chữ chỉ dùng để biết ranh giới ký tự và tìm ký tự mẫu; máy đọc sai cũng không làm đổi chỗ không sửa.
// Ảnh chụp, bản scan lệch làm dòng nghiêng: đường chân chữ là đường xiên đo riêng từng dòng; khi dời, chép chỉ đụng tới
// nét mực của chính dòng (nét dòng trên, dòng dưới lọt vào cùng dải giữ nguyên), mảnh dời đi theo độ dốc của dòng.
// Phần đọc hOCR, đo ảnh, dựng dòng thuần Dart + OpenCV (chạy được trong isolate); riêng ký tự vẽ bằng phông cần
// dart:ui nên do màn hình cung cấp qua BoVeKyTu.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'nhan_dang.dart';
import 'sua_chu.dart' show coMucMau;

/// Phiên bản thuật toán đọc dòng: đổi thì đệm cũ (kt_*.json) tự hết hiệu lực.
const banDocKyTu = 4;

// ---------------------------------------------------------------- ảnh

/// Ảnh BGR 8 bit giữ trong bộ nhớ Dart (gửi qua isolate được, sửa trực tiếp từng điểm ảnh).
class AnhBgr {
  AnhBgr(this.w, this.h, this.bgr);
  final int w, h;
  final Uint8List bgr;

  /// Giải mã đúng cỡ (không thu nhỏ: tọa độ ký tự tính theo đúng ảnh đã nhận dạng).
  factory AnhBgr.giaiMa(Uint8List maHoa) {
    final m = cv.imdecode(maHoa, cv.IMREAD_COLOR);
    if (m.isEmpty) throw const FormatException('Không đọc được ảnh');
    final a = AnhBgr(m.cols, m.rows, Uint8List.fromList(m.data));
    m.dispose();
    return a;
  }

  factory AnhBgr.docTep(String duongDan) => AnhBgr.giaiMa(File(duongDan).readAsBytesSync());

  /// Độ xám như cv2.COLOR_BGR2GRAY (số nguyên 14 bit).
  int xam(int x, int y) {
    final p = (y * w + x) * 3;
    return (bgr[p] * 1868 + bgr[p + 1] * 9617 + bgr[p + 2] * 4899 + 8192) >> 14;
  }

  /// Ảnh xám vùng [x0, x1) × [y0, y1); vùng phải nằm trong ảnh.
  Uint8List xamVung(int x0, int y0, int x1, int y1) {
    final rw = x1 - x0;
    final ra = Uint8List(math.max(0, rw) * math.max(0, y1 - y0));
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        ra[(y - y0) * rw + x - x0] = xam(x, y);
      }
    }
    return ra;
  }

  AnhBgr cat(int x0, int y0, int x1, int y1) {
    final rw = x1 - x0, rh = y1 - y0;
    final ra = Uint8List(rw * rh * 3);
    for (var y = 0; y < rh; y++) {
      ra.setRange(y * rw * 3, (y + 1) * rw * 3, bgr, ((y + y0) * w + x0) * 3);
    }
    return AnhBgr(rw, rh, ra);
  }

  AnhBgr banSao() => AnhBgr(w, h, Uint8List.fromList(bgr));

  cv.Mat _mat() {
    final m = cv.Mat.zeros(h, w, cv.MatType.CV_8UC3);
    m.data.setAll(0, bgr);
    return m;
  }

  /// PNG (không mất dữ liệu: chỗ không sửa giữ nguyên từng điểm ảnh).
  Uint8List png({int nen = 3}) {
    final m = _mat();
    final (ok, buf) = cv.imencode('.png', m, params: cv.VecI32.fromList([cv.IMWRITE_PNG_COMPRESSION, nen]));
    m.dispose();
    if (!ok) throw StateError('Không mã hóa được ảnh');
    return buf;
  }

  /// Phóng, thu (nội suy bậc ba).
  AnhBgr doiCo(int w2, int h2) {
    final m = _mat();
    final r = cv.resize(m, (w2, h2), interpolation: cv.INTER_CUBIC);
    final a = AnhBgr(r.cols, r.rows, Uint8List.fromList(r.data));
    m.dispose();
    r.dispose();
    return a;
  }
}

/// Ảnh đưa vào Tesseract: ảnh chụp, PDF nén thường chỉ 100–150 dpi, chữ cao chưa tới 10 điểm ảnh, Tesseract đọc rất sai.
/// Phóng tới cạnh ngắn ≈ 2480 px (cỡ A4 300 dpi, tối đa ×3) CHỈ để nhận dạng, ghi ảnh xám PNG vào [ra]; tọa độ đọc được
/// chia lại cho hệ số phóng trả về. Trả 1 (không ghi tệp) nếu không cần phóng.
double ghiAnhNhanDangKyTu(String vao, String ra) {
  final m = cv.imread(vao, flags: cv.IMREAD_GRAYSCALE);
  if (m.isEmpty) throw const FormatException('Không đọc được ảnh');
  final phong = math.min(3.0, math.max(1.0, 2480 / math.max(1, math.min(m.rows, m.cols))));
  if (phong <= 1.05) {
    m.dispose();
    return 1.0;
  }
  final p = cv.resize(m, ((m.cols * phong).round(), (m.rows * phong).round()), interpolation: cv.INTER_CUBIC);
  final ok = cv.imwrite(ra, p, params: cv.VecI32.fromList([cv.IMWRITE_PNG_COMPRESSION, 1]));
  m.dispose();
  p.dispose();
  if (!ok) throw StateError('Không ghi được ảnh tạm');
  return phong;
}

// ---------------------------------------------------------------- tiện ích số

double _trungVi(List<num> v) {
  if (v.isEmpty) return 0;
  final s = [for (final x in v) x.toDouble()]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// Giá trị đứng thứ [k] (đếm từ 0) theo bảng đếm 256 mức.
int _thuK(List<int> dem, int k) {
  var tich = 0;
  for (var v = 0; v < 256; v++) {
    tich += dem[v];
    if (tich > k) return v;
  }
  return 255;
}

/// Phân vị [q] (0–100, nội suy tuyến tính như np.percentile) của các giá trị 0–255.
double _phanVi8(Uint8List v, double q) {
  if (v.isEmpty) return 0;
  final dem = List<int>.filled(256, 0);
  for (final x in v) {
    dem[x]++;
  }
  final r = q / 100 * (v.length - 1);
  final lo = r.floor();
  final a = _thuK(dem, lo), b = _thuK(dem, math.min(lo + 1, v.length - 1));
  return a + (r - lo) * (b - a);
}

/// Ngưỡng Otsu như cv2.threshold(…, THRESH_OTSU): điểm ≤ ngưỡng là mực.
int _otsu(Uint8List xam) {
  final hist = List<int>.filled(256, 0);
  for (final v in xam) {
    hist[v]++;
  }
  final n = xam.length;
  if (n == 0) return 128;
  var tong = 0.0;
  for (var i = 0; i < 256; i++) {
    tong += i * hist[i];
  }
  var sB = 0.0, wB = 0, tot = -1.0, nguong = 0;
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

/// Mực theo ngưỡng Otsu (THRESH_BINARY_INV): 1 ở điểm tối.
Uint8List _mucOtsu(Uint8List xam) {
  final t = _otsu(xam);
  return Uint8List.fromList([for (final v in xam) v <= t ? 1 : 0]);
}

/// Thành phần liên thông 8 hướng của ảnh nhị phân [bin] (1 = mực): nhãn từng điểm (0 = nền) và [x, y, rộng, cao,
/// diện tích] từng thành phần (phần tử 0 là nền, như cv2.connectedComponentsWithStats).
(Int32List, List<List<int>>) _thanhPhan(Uint8List bin, int w, int h) {
  final nhan = Int32List(w * h);
  final tk = <List<int>>[
    [0, 0, w, h, 0]
  ];
  final hang = Int32List(w * h);
  for (var p = 0; p < bin.length; p++) {
    if (bin[p] == 0 || nhan[p] != 0) continue;
    final so = tk.length;
    var dau = 0, cuoi = 0;
    hang[cuoi++] = p;
    nhan[p] = so;
    var cx0 = w, cy0 = h, cx1 = 0, cy1 = 0;
    while (dau < cuoi) {
      final q = hang[dau++];
      final qx = q % w, qy = q ~/ w;
      if (qx < cx0) cx0 = qx;
      if (qx > cx1) cx1 = qx;
      if (qy < cy0) cy0 = qy;
      if (qy > cy1) cy1 = qy;
      for (var dy = -1; dy <= 1; dy++) {
        final ny = qy + dy;
        if (ny < 0 || ny >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final nx = qx + dx;
          if (nx < 0 || nx >= w) continue;
          final r = ny * w + nx;
          if (bin[r] != 0 && nhan[r] == 0) {
            nhan[r] = so;
            hang[cuoi++] = r;
          }
        }
      }
    }
    tk.add([cx0, cy0, cx1 - cx0 + 1, cy1 - cy0 + 1, cuoi]);
  }
  return (nhan, tk);
}

final _chuSo = RegExp(r'^[\p{L}\p{N}]+$', unicode: true);

/// Như str.isalnum() của Python: chữ (kể cả có dấu) hoặc số.
bool laChuSo(String s) => _chuSo.hasMatch(s);

// ---------------------------------------------------------------- dòng, ký tự

class KyTu {
  KyTu(this.chu, this.x0, this.y0, this.x1, this.y1, this.tinCay, {this.dam = 0, this.chia = false});

  final String chu;
  final int x0, y0, x1, y1; // khung ký tự (x1, y1 không tính)
  final double tinCay; // 0–100; 0: nét mực chưa biết tên (nối dài dòng)
  double dam; // bề dày nét riêng ký tự (điểm ảnh), đo khi nhận dạng (đệm cùng khung để chọn mẫu ở trang chưa nạp ảnh)
  final bool chia; // khung ước lượng: chữ dính nét chữ bên cạnh, chia đôi nét (kém tin khi làm mẫu chép)
  Float32List? hinh; // hình thu nhỏ 16×16 (so dáng chữ), tính khi cần

  int get cao => y1 - y0;
  int get rong => x1 - x0;

  KyTu doi(int dx, [int dy = 0]) => KyTu(chu, x0 + dx, y0 + dy, x1 + dx, y1 + dy, tinCay, dam: dam, chia: chia);

  List<Object> toJson() => [chu, x0, y0, x1, y1, tinCay, (dam * 100).round() / 100, if (chia) 1];

  factory KyTu.fromJson(List j) => KyTu(j[0] as String, j[1] as int, j[2] as int, j[3] as int, j[4] as int, (j[5] as num).toDouble(),
      dam: j.length > 6 ? (j[6] as num).toDouble() : 0, chia: j.length > 7);
}

class DongAnh {
  DongAnh(this.x0, this.y0, this.x1, this.y1, this.chan, this.tu,
      {this.dai0 = 0, this.dai1 = 0, this.dam = 0, this.mucMau = false, this.nghieng = 0, this.xChan = 0, this.tren = 0, this.duoi = 0});

  int x0, y0, x1, y1; // khung dòng của Tesseract
  double chan; // đường chân chữ (y) tại cột [xChan]
  List<List<KyTu>> tu;
  int dai0, dai1; // dải dọc chứa trọn dòng (cả phần xiên); chỉ nét của dòng mới bị dời, chép
  double dam; // độ đậm nét (bề dày nét / cỡ chữ)
  bool mucMau; // dòng có mực màu (con dấu, chữ ký, bút phê): không cho sửa
  double nghieng; // độ dốc đường chân chữ (dy/dx): ảnh chụp, bản scan lệch
  double xChan; // [chan] đo tại cột này
  double tren, duoi; // dòng chiếm từ chanTai(x) - tren tới chanTai(x) + duoi (cả dấu, nét xuống)

  /// Đường chân chữ tại cột [x] (dòng nghiêng).
  double chanTai(num x) => chan + nghieng * (x - xChan);

  /// Mép trên, mép dưới của dòng tại cột [x] (dải xiên; dòng chưa đo độ nghiêng thì là dải dọc).
  (double, double) daiTai(num x) {
    if (tren == 0) return (dai0.toDouble(), dai1.toDouble());
    final c = chanTai(x);
    return (c - tren, c + duoi);
  }

  List<KyTu> get kyTu => [for (final w in tu) ...w];

  String get chu => tu.map((w) => w.map((c) => c.chu).join()).join(' ');

  /// Chiều cao chữ thường không dấu, không nét lên xuống (a, c, e, m, n, o…): so cỡ chữ hai dòng ổn định hơn [co],
  /// vốn dao động theo tỉ lệ chữ hoa, chữ có dấu trong dòng. null nếu dòng có ít hơn 3 chữ như vậy.
  double? get coX {
    final cao = [for (final c in kyTu) if ('acemnorsuvwxz'.contains(c.chu) && c.chu.length == 1 && c.tinCay >= 70) c.cao];
    return cao.length >= 3 ? _trungVi(cao) : null;
  }

  /// Cỡ chữ của dòng: trung vị chiều cao khung các ký tự cỡ chữ thường (bỏ dấu chấm, dấu phẩy).
  double get co {
    final tat = kyTu;
    if (tat.isEmpty) return (y1 - y0).toDouble();
    var chac = [for (final c in tat) if (c.tinCay >= 60) c]; // bỏ "chữ" máy đọc nhầm từ chấm, vết bẩn
    if (chac.isEmpty) chac = tat;
    final cao = [for (final c in chac) c.cao.toDouble()]..sort();
    // dòng mục lục có hàng chục "ký tự" máy đọc từ dấu chấm: lấy theo nhóm ký tự lớn nhất
    final cuoi = cao.sublist(math.max(0, cao.length - 3));
    final dinh = cuoi.reduce((a, b) => a + b) / cuoi.length;
    return _trungVi([for (final v in cao) if (v >= 0.6 * dinh) v]);
  }

  Map<String, Object> toJson() => {
        'k': [x0, y0, x1, y1],
        'c': chan,
        'd': [dai0, dai1],
        'm': dam,
        if (mucMau) 'mau': true,
        'n': nghieng,
        'xc': xChan,
        'tr': tren,
        'du': duoi,
        't': [
          for (final w in tu) [for (final c in w) c.toJson()]
        ],
      };

  factory DongAnh.fromJson(Map j) {
    final k = [for (final v in j['k'] as List) v as int];
    final d = j['d'] as List;
    return DongAnh(k[0], k[1], k[2], k[3], (j['c'] as num).toDouble(), [
      for (final w in j['t'] as List) [for (final c in w as List) KyTu.fromJson(c as List)]
    ],
        dai0: d[0] as int,
        dai1: d[1] as int,
        dam: (j['m'] as num).toDouble(),
        mucMau: j['mau'] as bool? ?? false,
        nghieng: (j['n'] as num? ?? 0).toDouble(),
        xChan: (j['xc'] as num? ?? 0).toDouble(),
        tren: (j['tr'] as num? ?? 0).toDouble(),
        duoi: (j['du'] as num? ?? 0).toDouble());
  }
}

/// Các dòng (kèm khung từng ký tự) của một ảnh trang.
class TrangKyTu {
  TrangKyTu(this.rong, this.cao, this.dong, this.khe);

  final int rong, cao;
  final List<DongAnh> dong;
  final double khe; // khe trung vị giữa hai ký tự liền nhau trong một từ

  /// Mép phải chữ của trang (báo dòng sửa dài quá lề).
  int get lePhai => dong.isEmpty ? rong : dong.map((d) => d.x1).reduce(math.max);

  /// Dòng ở điểm (x, y) của ảnh: dải xiên theo dòng (ảnh chụp nghiêng) chứa y, bề ngang nới 15 điểm ảnh; nhiều dòng
  /// thì lấy dòng có lõi chữ gần nhất.
  DongAnh? dongTai(double x, double y) {
    DongAnh? tot;
    var kc = double.infinity;
    for (final d in dong) {
      final (t, b) = d.daiTai(x);
      if (t <= y && y <= b && d.x0 - 15 <= x && x <= d.x1 + 15) {
        final k = (d.chanTai(x) - 0.35 * d.co - y).abs();
        if (k < kc) {
          kc = k;
          tot = d;
        }
      }
    }
    return tot;
  }

  Map<String, Object> toJson() => {'v': banDocKyTu, 'w': rong, 'h': cao, 'khe': khe, 'dong': [for (final d in dong) d.toJson()]};

  /// null nếu đệm của phiên bản thuật toán cũ.
  static TrangKyTu? fromJson(Map j) => j['v'] != banDocKyTu
      ? null
      : TrangKyTu(j['w'] as int, j['h'] as int, [for (final d in j['dong'] as List) DongAnh.fromJson(d as Map)], (j['khe'] as num).toDouble());
}

// ---------------------------------------------------------------- đọc dòng, ký tự

final _the = RegExp(r'''<span class=['"](ocr_line|ocr_header|ocr_textfloat|ocr_caption|ocrx_word|ocrx_cinfo)['"][^>]*?title=(['"])(.*?)\2[^>]*>''',
    dotAll: true);

String _boMa(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
    .replaceAll('&amp;', '&');

/// Nhận dạng xong (hOCR có khung ký tự, ảnh đã phóng [phong] lần): đọc dòng, gộp dòng cùng hàng, nối dài dòng theo
/// nét mực, thay dãy chấm dẫn, tính lại đường chân chữ, đo độ đậm nét, đánh dấu dòng có mực màu.
TrangKyTu docTrangKyTu(String hocr, AnhBgr anh, double phong) {
  var dong = gopDongCungHang(anh, docHocrKyTu(hocr, anh.h, phong > 1.05 ? phong : 1.0));
  dong = thayChamDan(anh, noiDaiDong(anh, dong));
  for (final d in dong) {
    _tinhChan(d, anh.h);
    nanKhung(anh, d);
    _tinhChan(d, anh.h);
    doDam(anh, d);
    d.mucMau = coMucMau(anh.bgr, anh.w, [d.x0, d.dai0, math.min(d.x1, anh.w), d.dai1]);
    for (final c in d.kyTu) {
      if (laChuSo(c.chu)) damKyTu(anh, d, c);
    }
  }
  return TrangKyTu(anh.w, anh.h, dong, kheTrongTu(dong));
}

/// Ký tự có nét, dấu xuống dưới đường chân: không dùng để đo đường chân.
final _duoiChan = {for (final r in 'gjpqyQ,;()[]{}|/ạặậẹệịọộợụựỵẠẶẬẸỆỊỌỘỢỤỰỴ'.runes) String.fromCharCode(r)};

/// Đường chân chữ: đường xiên qua đáy khung các ký tự thật, cỡ chữ thường (bỏ dấu chấm, ký tự chưa biết tên, ký tự có
/// nét xuống, chữ máy đọc không chắc), sau khi đã gộp dòng và thay dãy chấm. Độ dốc theo Theil–Sen (trung vị độ dốc
/// từng cặp ký tự cách xa nhau) nên vài khung máy đọc lệch không kéo lệch cả đường. Rồi tính dải xiên của dòng.
void _tinhChan(DongAnh d, [int? caoTrang]) {
  final co = d.co;
  final chon = [
    for (final c in d.kyTu)
      if (c.chu != '.' && c.chu != '?' && !_duoiChan.contains(c.chu) && c.tinCay >= 60 && c.cao >= 0.6 * co) c
  ];
  d.xChan = (d.x0 + d.x1) / 2;
  if (chon.isEmpty) return;
  final xs = [for (final c in chon) (c.x0 + c.x1) / 2], ys = [for (final c in chon) c.y1.toDouble()];
  final doc = <double>[];
  for (var i = 0; i < xs.length; i++) {
    for (var j = i + 1; j < xs.length; j++) {
      final dx = xs[j] - xs[i];
      if (dx.abs() >= co) doc.add((ys[j] - ys[i]) / dx);
    }
  }
  d.nghieng = doc.length >= 3 ? _trungVi(doc).clamp(-0.2, 0.2) : 0.0;
  d.chan = _trungVi([for (var i = 0; i < xs.length; i++) ys[i] - d.nghieng * (xs[i] - d.xChan)]);
  // dải xiên: phủ trọn khung các ký tự (dấu thanh, nét xuống) quanh đường chân
  var tren = -double.infinity, duoi = -double.infinity;
  for (final c in d.kyTu) {
    final ct = d.chanTai((c.x0 + c.x1) / 2);
    tren = math.max(tren, ct - c.y0);
    duoi = math.max(duoi, c.y1 - ct);
  }
  d.tren = (tren + 2).clamp(0.8 * co, 1.8 * co).toDouble();
  d.duoi = (duoi + 2).clamp(0.25 * co, 0.8 * co).toDouble();
  if (caoTrang != null) {
    final a = d.chanTai(d.x0), b = d.chanTai(d.x1);
    d.dai0 = math.max(0, math.min(d.dai0, (math.min(a, b) - d.tren).floor()));
    d.dai1 = math.min(caoTrang, math.max(d.dai1, (math.max(a, b) + d.duoi).ceil()));
  }
}

/// Nắn khung ký tự theo nét mực thật. Khung ký tự của Tesseract (LSTM) chỉ đúng thứ tự, hay lệch ngang nửa ký tự
/// (khung "ư" trùm sang "t", khung "ộ" lấn sang "m"): chia mảnh, chép mẫu theo khung lệch là cắt đôi chữ, chép nhầm
/// nét chữ bên cạnh ("lỗi phông" khi gõ chữ mới). Từng từ: các nét chính (thành phần liên thông cao từ nửa chiều cao
/// chữ thường, chạm đường chân) xếp theo thứ tự rồi ghép với các chữ, số của từ theo thứ tự (quy hoạch động, so mép
/// trái, phải: một chữ có thể gồm vài nét đứt, vài chữ dính chung một nét thì chia nét theo bề rộng khung cũ); nét nhỏ
/// trên thân chữ, dưới đường chân (dấu thanh, chấm i, móc ơ ư, dấu nặng) theo chữ đứng dưới, trên nó; nét nhỏ ngang
/// thân chữ theo dấu câu gần nhất. Như nan_khung() bản PC.
void nanKhung(AnhBgr anh, DongAnh d) {
  final y0 = d.dai0, y1 = d.dai1;
  final x0 = math.max(0, d.x0 - 2), x1 = math.min(anh.w, d.x1 + 2);
  if (y1 <= y0 || x1 <= x0 || d.tren == 0) return;
  final w = x1 - x0, h = y1 - y0;
  final (_, tk) = _thanhPhan(_mucOtsu(anh.xamVung(x0, y0, x1, y1)), w, h);
  final xh = xCao(d), co = d.co;
  final chinh = <List<int>>[], nho = <List<int>>[];
  for (var i = 1; i < tk.length; i++) {
    final [tx, ty, tw, th, dt] = tk[i];
    final gx = tx + x0, gy = ty + y0;
    final ct = d.chanTai(gx + tw / 2);
    if (dt < 2 || th > 2.6 * co || !(ct - d.tren <= gy + th / 2 && gy + th / 2 <= ct + d.duoi)) continue;
    // nét chính: đủ cao và chạm đường chân (móc ơ, ư, dấu thanh tách rời thì không)
    final laChinh = th >= 0.5 * xh && gy + th >= ct - 0.25 * xh;
    (laChinh ? chinh : nho).add([gx, gy, gx + tw, gy + th]);
  }
  if (chinh.isEmpty) return;
  final tu = [for (final w in d.tu) if (w.any((c) => laChuSo(c.chu) && c.tinCay > 0)) w];
  if (tu.isEmpty) return;
  final nhip = [for (final w in tu) (w.map((c) => c.x0).reduce(math.min), w.map((c) => c.x1).reduce(math.max))];
  final cuaTu = [for (final _ in tu) <List<int>>[]];
  chinh.sort((a, b) {
    for (var i = 0; i < 4; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return 0;
  });
  for (final g in chinh) {
    final cx = (g[0] + g[2]) / 2;
    var tot = -1;
    var kcTot = double.infinity;
    for (var k = 0; k < nhip.length; k++) {
      final (a, b) = nhip[k];
      if (a - 0.3 * co <= cx && cx <= b + 0.3 * co && (cx - (a + b) / 2).abs() < kcTot) {
        kcTot = (cx - (a + b) / 2).abs();
        tot = k;
      }
    }
    if (tot >= 0) cuaTu[tot].add(g);
  }
  // phạt mỗi chữ (nét) ghép thêm: khung máy đọc lệch cả chữ, chỉ ghép khi số nét, số chữ không khớp
  final phat = 1.0 * co;
  final moi = <KyTu, List<int>>{};
  final chia = <KyTu>{};
  for (var ti = 0; ti < tu.length; ti++) {
    final gs = cuaTu[ti];
    final chu = [for (final c in tu[ti]) if (laChuSo(c.chu) && c.tinCay > 0) c];
    if (gs.isEmpty) continue;
    final nc = chu.length, ng = gs.length;
    double lech(int j0, int j1, int i0, int i1) {
      var a0 = 1 << 30, a1 = -1, b0 = 1 << 30, b1 = -1;
      for (var j = j0; j < j1; j++) {
        a0 = math.min(a0, gs[j][0]);
        a1 = math.max(a1, gs[j][2]);
      }
      for (var i = i0; i < i1; i++) {
        b0 = math.min(b0, chu[i].x0);
        b1 = math.max(b1, chu[i].x1);
      }
      return ((a0 - b0).abs() + (a1 - b1).abs()).toDouble();
    }

    final dp = [for (var i = 0; i <= nc; i++) List<double>.filled(ng + 1, double.infinity)];
    final tuDau = [for (var i = 0; i <= nc; i++) List<(int, int)?>.filled(ng + 1, null)];
    dp[0][0] = 0;
    for (var i = 0; i <= nc; i++) {
      for (var j = 0; j <= ng; j++) {
        if (dp[i][j] == double.infinity || (i == nc && j == ng)) continue;
        if (i < nc) {
          for (var k = 1; k <= math.min(3, ng - j); k++) {
            final cp = dp[i][j] + lech(j, j + k, i, i + 1) + phat * (k - 1);
            if (cp < dp[i + 1][j + k]) {
              dp[i + 1][j + k] = cp;
              tuDau[i + 1][j + k] = (i, j);
            }
          }
        }
        if (j < ng) {
          for (var k = 2; k <= math.min(4, nc - i); k++) {
            final cp = dp[i][j] + lech(j, j + 1, i, i + k) + phat * (k - 1);
            if (cp < dp[i + k][j + 1]) {
              dp[i + k][j + 1] = cp;
              tuDau[i + k][j + 1] = (i, j);
            }
          }
        }
      }
    }
    if (dp[nc][ng] == double.infinity) continue;
    var i = nc, j = ng;
    while (i != 0 || j != 0) {
      final (pi, pj) = tuDau[i][j]!;
      final nhom = gs.sublist(pj, j);
      final hop = [
        nhom.map((g) => g[0]).reduce(math.min),
        nhom.map((g) => g[1]).reduce(math.min),
        nhom.map((g) => g[2]).reduce(math.max),
        nhom.map((g) => g[3]).reduce(math.max),
      ];
      if (i - pi == 1) {
        moi[chu[pi]] = hop;
      } else {
        // nhiều chữ dính một nét: chia theo bề rộng khung cũ; khung ước lượng nên kém tin khi làm mẫu
        final rong = [for (final c in chu.sublist(pi, i)) math.max(1, c.x1 - c.x0)];
        final tong = rong.reduce((a, b) => a + b);
        var x = hop[0].toDouble();
        for (var k = 0; k < rong.length; k++) {
          final x2 = x + (hop[2] - hop[0]) * rong[k] / tong;
          moi[chu[pi + k]] = [x.round(), hop[1], x2.round(), hop[3]];
          chia.add(chu[pi + k]);
          x = x2;
        }
      }
      i = pi;
      j = pj;
    }
  }
  if (moi.isEmpty) return;
  final tat = d.kyTu;
  final chuSo = [for (final c in tat) if (moi.containsKey(c)) c];
  final dauCau = [for (final c in tat) if (!laChuSo(c.chu) && c.chu.trim().isNotEmpty) c];
  final nhoDau = <KyTu, List<List<int>>>{};
  for (final g in nho) {
    final cx = (g[0] + g[2]) / 2, cy = (g[1] + g[3]) / 2;
    final ct = d.chanTai(cx);
    if (cy < ct - 0.6 * xh || cy > ct + 0.1 * xh) {
      // dấu thanh, chấm i, móc, dấu nặng: theo chữ đứng dưới, trên
      KyTu? tot;
      var hang = 2;
      var kc = double.infinity;
      for (final c in chuSo) {
        final m = moi[c]!;
        final trong = m[0] - 1 <= cx && cx <= m[2] + 1 ? 0 : 1;
        final k = (cx - (m[0] + m[2]) / 2).abs();
        if (trong < hang || (trong == hang && k < kc)) {
          hang = trong;
          kc = k;
          tot = c;
        }
      }
      if (tot != null && (hang == 0 || kc <= 0.6 * co)) {
        final m = moi[tot]!;
        moi[tot] = [math.min(m[0], g[0]), math.min(m[1], g[1]), math.max(m[2], g[2]), math.max(m[3], g[3])];
      }
    } else if (dauCau.isNotEmpty) {
      // nét nhỏ ngang thân chữ: dấu câu
      final c = dauCau.reduce((a, b) => (cx - (a.x0 + a.x1) / 2).abs() <= (cx - (b.x0 + b.x1) / 2).abs() ? a : b);
      if ((cx - (c.x0 + c.x1) / 2).abs() <= 0.8 * co) nhoDau.putIfAbsent(c, () => []).add(g);
    }
  }
  for (final c in dauCau) {
    final gs = nhoDau[c];
    if (gs == null) continue;
    moi[c] = [
      gs.map((g) => g[0]).reduce(math.min),
      gs.map((g) => g[1]).reduce(math.min),
      gs.map((g) => g[2]).reduce(math.max),
      gs.map((g) => g[3]).reduce(math.max),
    ];
  }
  for (final w in d.tu) {
    for (var k = 0; k < w.length; k++) {
      final m = moi[w[k]];
      if (m != null) w[k] = KyTu(w[k].chu, m[0], m[1], m[2], m[3], w[k].tinCay, chia: chia.contains(w[k]));
    }
  }
}

/// Đọc hOCR có khung ký tự; [phong]: ảnh đưa vào Tesseract đã phóng bao nhiêu lần (tọa độ chia lại).
List<DongAnh> docHocrKyTu(String hocr, int caoTrang, [double phong = 1.0]) {
  int q(num v) => (v / phong).round();
  final dong = <DongAnh>[];
  for (final m in _the.allMatches(hocr)) {
    final loai = m[1]!, tieuDe = m[3]!;
    if (loai == 'ocrx_cinfo') {
      final k = RegExp(r'x_bboxes (-?\d+) (-?\d+) (-?\d+) (-?\d+)').firstMatch(tieuDe);
      final cuoi = hocr.indexOf('<', m.end);
      final chu = _boMa(hocr.substring(m.end, cuoi < 0 ? hocr.length : cuoi)).trim();
      final tc = RegExp(r'x_conf ([\d.]+)').firstMatch(tieuDe);
      if (k != null && chu.isNotEmpty && dong.isNotEmpty && dong.last.tu.isNotEmpty) {
        final x0 = q(int.parse(k[1]!)), y0 = q(int.parse(k[2]!));
        dong.last.tu.last.add(KyTu(chu, x0, y0, math.max(x0 + 1, q(int.parse(k[3]!) + 1)), math.max(y0 + 1, q(int.parse(k[4]!) + 1)),
            tc != null ? double.parse(tc[1]!) : 0.0));
      }
    } else if (loai == 'ocrx_word') {
      if (dong.isNotEmpty) dong.last.tu.add([]);
    } else {
      final k = RegExp(r'bbox (\d+) (\d+) (\d+) (\d+)').firstMatch(tieuDe);
      if (k == null) continue;
      final x0 = int.parse(k[1]!), y0 = int.parse(k[2]!), x1 = int.parse(k[3]!), y1 = int.parse(k[4]!);
      final b = RegExp(r'baseline (-?[\d.]+) (-?[\d.]+)').firstMatch(tieuDe);
      final chan = (y1 + (b != null ? double.parse(b[2]!) + double.parse(b[1]!) * (x1 - x0) / 2 : 0.0)) / phong;
      dong.add(DongAnh(q(x0), q(y0), q(x1), q(y1), chan, []));
    }
  }
  final kq = <DongAnh>[];
  for (final d in dong) {
    d.tu = [for (final w in d.tu) if (w.isNotEmpty) w];
    if (d.tu.isEmpty) continue;
    // đường chân chữ: trung vị đáy khung các ký tự cỡ thường (số liệu baseline của Tesseract hay lệch)
    final co = d.co;
    final day = [for (final c in d.kyTu) if (c.cao >= 0.6 * co) c.y1];
    if (day.isNotEmpty) d.chan = _trungVi(day);
    kq.add(d);
  }
  // dải dọc mỗi dòng: nới khỏi khung một chút nhưng không quá nửa khoảng cách tới dòng trên, dưới
  for (final d in kq) {
    final cao = d.y1 - d.y0;
    var tren = math.max(0, d.y0 - cao ~/ 4), duoi = math.min(caoTrang, d.y1 + cao ~/ 4);
    for (final e in kq) {
      if (identical(e, d) || e.x1 <= d.x0 || e.x0 >= d.x1) continue;
      if (e.y1 <= d.y0) {
        tren = math.max(tren, (e.y1 + d.y0) ~/ 2);
      } else if (e.y0 >= d.y1) {
        duoi = math.min(duoi, (d.y1 + e.y0) ~/ 2);
      }
    }
    d
      ..dai0 = tren
      ..dai1 = duoi;
  }
  return kq;
}

/// Tỉ lệ cỡ chữ dòng đích / dòng nguồn; chênh dưới 12% coi như cùng cỡ (cùng tài liệu thường cùng cỡ chữ).
double tiLeCo(DongAnh dich, DongAnh nguon) {
  final a = dich.coX, b = nguon.coX;
  final r = a != null && b != null ? a / b : dich.co / math.max(nguon.co, 1);
  return (r - 1).abs() <= 0.12 ? 1.0 : r;
}

/// Gộp các dòng Tesseract tách rời nằm trên cùng một hàng chữ (mục lục: số trang, dãy chấm hay thành dòng riêng).
/// Chỉ gộp khi khoảng hở hẹp (< 30% bề rộng trang) hoặc được nối bằng dãy chấm dẫn: hai cột văn bản không bị gộp.
List<DongAnh> gopDongCungHang(AnhBgr anh, List<DongAnh> cacDong) {
  final rongTrang = anh.w;
  int theoCho(DongAnh a, DongAnh b) => a.y0 != b.y0 ? a.y0.compareTo(b.y0) : a.x0.compareTo(b.x0);
  final kq = <DongAnh>[];
  for (final d in [...cacDong]..sort(theoCho)) {
    var daGop = false;
    for (var gi = 0; gi < kq.length; gi++) {
      final g = kq[gi];
      final cao = math.min(g.y1 - g.y0, d.y1 - d.y0);
      final trung = math.min(g.y1, d.y1) - math.max(g.y0, d.y0);
      if (trung < 0.5 * cao || (g.chan - d.chan).abs() > 0.35 * math.max(g.co, d.co)) continue;
      final (trai, phai) = g.x0 <= d.x0 ? (g, d) : (d, g);
      final ho = phai.x0 - trai.x1;
      if (ho < -2) continue;
      final moi = DongAnh(math.min(g.x0, d.x0), math.min(g.y0, d.y0), math.max(g.x1, d.x1), math.max(g.y1, d.y1),
          (g.chan + d.chan) / 2, [...trai.tu, ...phai.tu],
          dai0: math.min(g.dai0, d.dai0), dai1: math.max(g.dai1, d.dai1));
      if (ho > 0.3 * rongTrang) {
        final cham = timChamDan(anh, moi);
        final phu = cham.isEmpty || cham.every((c) => c.$2 == c.$1) ? 0 : cham.last.$2 - cham.first.$1;
        if (phu < 0.6 * ho) continue;
      }
      kq[gi] = moi;
      daGop = true;
      break;
    }
    if (!daGop) kq.add(d);
  }
  return kq..sort(theoCho);
}

/// Nối dài dòng sang phải theo nét mực: Tesseract hay bỏ sót phần chữ đứng lẻ ở mép phải (số trang mục lục,
/// dãy chấm dẫn). Nét mực nằm đúng hàng chữ sau phần đã đọc được thêm vào dòng thành ký tự chưa biết tên ("?"; "."
/// nếu là chấm nhỏ trên đường chân chữ): xóa, dời được như chữ khác, chỉ không dùng làm mẫu chép.
/// Dừng ở khoảng trống lớn (sang cột khác) và bỏ nét quá cao (con dấu, đường kẻ).
List<DongAnh> noiDaiDong(AnhBgr anh, List<DongAnh> cacDong) {
  final rongTrang = anh.w;
  for (final d in cacDong) {
    final y0 = d.dai0, y1 = d.dai1, x0 = d.x1;
    if (x0 >= rongTrang - 2 || y1 <= y0 || d.x1 <= d.x0) continue;
    final t = _otsu(anh.xamVung(d.x0, y0, d.x1, y1));
    final vw = rongTrang - x0, vh = y1 - y0;
    final vung = anh.xamVung(x0, y0, rongTrang, y1);
    final toi = Uint8List.fromList([for (final v in vung) v < t ? 1 : 0]);
    final (_, tk) = _thanhPhan(toi, vw, vh);
    final co = d.co, loi0 = d.y0, loi1 = d.y1;
    final net = <List<int>>[];
    for (var i = 1; i < tk.length; i++) {
      final [cx, cy, cw, ch, dt] = tk[i];
      final gy0 = y0 + cy, gy1 = y0 + cy + ch;
      if (dt < 2 || ch > 1.6 * co || cw > 3 * co) continue;
      if (math.min(gy1, loi1) - math.max(gy0, loi0) < 0.5 * ch) continue; // không nằm trên hàng chữ của dòng
      net.add([x0 + cx, gy0, x0 + cx + cw, gy1]);
    }
    net.sort((a, b) {
      for (var i = 0; i < 4; i++) {
        if (a[i] != b[i]) return a[i].compareTo(b[i]);
      }
      return 0;
    });
    // gộp nét chồng nhau theo chiều ngang (dấu thanh, nét đứt) thành một ký tự
    final ky = <List<int>>[];
    for (final a in net) {
      if (ky.isNotEmpty && a[0] <= ky.last[2]) {
        final b = ky.last;
        b[1] = math.min(b[1], a[1]);
        b[2] = math.max(b[2], a[2]);
        b[3] = math.max(b[3], a[3]);
      } else {
        ky.add([...a]);
      }
    }
    final khoang = math.max(3.0, 0.3 * co);
    final tu = <List<KyTu>>[];
    var cuoi = x0;
    for (final a in ky) {
      if (a[0] - cuoi > 0.2 * rongTrang) break; // khoảng trống lớn: sang cột khác
      final nho = a[3] - a[1] <= 0.45 * co && a[2] - a[0] <= 0.45 * co && (a[3] - d.chan).abs() <= 0.3 * co;
      final c = KyTu(nho ? '.' : '?', a[0], a[1], a[2], a[3], 0.0);
      if (tu.isEmpty || a[0] - cuoi > khoang) {
        tu.add([c]);
      } else {
        tu.last.add(c);
      }
      cuoi = a[2];
    }
    if (tu.isNotEmpty) {
      d.tu = [...d.tu, ...tu];
      d.x1 = math.max(d.x1, cuoi);
    }
  }
  return cacDong;
}

/// Tesseract đọc dãy chấm dẫn thành hàng chục "chữ" (n, i, u…) với độ tin cậy cao: bỏ các chữ đó, thay bằng các
/// dấu chấm tìm theo hình dạng, để cỡ chữ của dòng đo đúng và không lấy nhầm mẫu chép.
List<DongAnh> thayChamDan(AnhBgr anh, List<DongAnh> cacDong) {
  for (final d in cacDong) {
    final cham = timChamDan(anh, d);
    if (cham.isEmpty) continue;
    final buoc = (cham.last.$1 - cham.first.$1) / (cham.length - 1);
    final r0 = cham.first.$1 - buoc / 2, r1 = cham.last.$2 + buoc / 2;
    final yTren = (d.chan - 0.3 * d.co).round();
    final tu = [
      for (final w in d.tu) [for (final c in w) if (!(r0 <= (c.x0 + c.x1) / 2 && (c.x0 + c.x1) / 2 <= r1)) c]
    ].where((w) => w.isNotEmpty).toList();
    final truoc = [for (final w in tu) if (w.last.x1 <= r0 + buoc / 2) w];
    final sau = [for (final w in tu) if (!truoc.any((v) => identical(v, w))) w];
    final chan = d.chan.round();
    final day = [for (final (a, b) in cham) KyTu('.', a, math.max(yTren, chan - (b - a) - 1), b, chan + 1, 100.0)];
    d.tu = [...truoc, day, ...sau];
  }
  return cacDong;
}

/// Khe trung vị giữa hai ký tự liền nhau trong một từ (điểm ảnh). Bỏ khe cạnh dấu chấm, nét chưa biết tên: trang mục
/// lục có hàng trăm khe giữa các chấm dẫn (rộng hơn khe chữ nhiều), tính vào thì ký tự chèn bị giãn thưa (khác bản PC).
double kheTrongTu(List<DongAnh> cacDong) {
  bool cham(KyTu c) => c.chu == '.' || c.chu == '?';
  final khe = [
    for (final d in cacDong)
      for (final w in d.tu)
        for (var i = 1; i < w.length; i++)
          if (!cham(w[i]) && !cham(w[i - 1])) w[i].x0 - w[i - 1].x1
  ];
  return khe.isEmpty ? 1.0 : _trungVi(khe);
}

/// Dãy dấu chấm dẫn (mục lục) theo hình dạng: ≥ 5 chấm nhỏ cách đều, nằm trên đường chân chữ.
/// Không dựa vào chữ máy đọc (ảnh mờ thường đọc dãy chấm thành chữ loạn). Trả [(x0, x1)] từng chấm.
List<(int, int)> timChamDan(AnhBgr anh, DongAnh d) {
  final y0 = d.dai0, y1 = d.dai1, x0 = d.x0, x1 = math.min(d.x1, anh.w);
  if (y1 <= y0 || x1 <= x0) return [];
  final (_, tk) = _thanhPhan(_mucOtsu(anh.xamVung(x0, y0, x1, y1)), x1 - x0, y1 - y0);
  final co = d.co;
  // chấm nhỏ ở nửa dưới dòng; không so với một đường chân cố định vì bản scan nghiêng làm dãy chấm dốc dần
  final cham = <(int, int, int)>[
    for (var i = 1; i < tk.length; i++)
      if (tk[i][2] <= 0.45 * co &&
          tk[i][3] <= 0.45 * co &&
          tk[i][4] >= 2 &&
          d.chan - 0.6 * co <= y0 + tk[i][1] + tk[i][3] &&
          y0 + tk[i][1] + tk[i][3] <= d.chan + 0.4 * co)
        (tk[i][0], tk[i][0] + tk[i][2], y0 + tk[i][1] + tk[i][3])
  ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : (a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$3.compareTo(b.$3)));
  var tot = <(int, int, int)>[];
  var day = cham.take(1).toList();
  for (final c in cham.skip(1)) {
    final buoc = c.$1 - day.last.$1;
    final cungHang = (c.$3 - day.last.$3).abs() <= math.max(2, 0.15 * co); // chấm liền nhau gần cùng độ cao
    final bool hopLe;
    if (day.length >= 2) {
      // bản scan có chấm lệch nhịp, chấm mờ mất: chấp nhận bước 0,5–1,8 lần bước trung bình
      final tb = (day.last.$1 - day.first.$1) / (day.length - 1);
      hopLe = cungHang && 0.5 * tb <= buoc && buoc <= 1.8 * tb;
    } else {
      hopLe = cungHang && 0.15 * co <= buoc && buoc <= 1.2 * co;
    }
    if (hopLe) {
      day.add(c);
    } else {
      if (day.length > tot.length) tot = day;
      day = [c];
    }
  }
  if (day.length > tot.length) tot = day;
  return tot.length >= 5 ? [for (final (a, b, _) in tot) (x0 + a, x0 + b)] : [];
}

/// Độ đậm nét của dòng: bề dày nét trung vị (biến đổi khoảng cách trên nét mực) chia cỡ chữ. Đo một lần, lưu vào dòng.
double doDam(AnhBgr anh, DongAnh d) {
  if (d.dam != 0) return d.dam;
  final y0 = d.dai0, y1 = d.dai1, x0 = d.x0, x1 = math.min(d.x1, anh.w);
  if (y1 <= y0 || x1 <= x0) return 0;
  final w = x1 - x0, h = y1 - y0;
  final kc = _khoangCach(_mucOtsu(anh.xamVung(x0, y0, x1, y1)), w, h);
  // đường giữa nét: điểm có khoảng cách lớn nhất trong ô 3×3 quanh nó
  final dinh = <double>[];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = kc[y * w + x];
      if (v <= 0 || v > 1e8) continue;
      var lon = true;
      for (var dy = -1; dy <= 1 && lon; dy++) {
        final ny = y + dy;
        if (ny < 0 || ny >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          if (nx < 0 || nx >= w) continue;
          if (kc[ny * w + nx] > v) {
            lon = false;
            break;
          }
        }
      }
      if (lon) dinh.add(v);
    }
  }
  d.dam = dinh.isEmpty ? 0.0 : 2 * _trungVi(dinh) / math.max(d.co, 1);
  return d.dam;
}

/// Khoảng cách từ mỗi điểm mực tới nền gần nhất (cv2.distanceTransform DIST_L2 mặt nạ 3: bước 0,955 và 1,3693;
/// ngoài vùng coi như rất xa, như OpenCV).
Float32List _khoangCach(Uint8List bin, int w, int h) {
  const a = 0.955, b = 1.3693, xa = 1e9;
  final d = Float32List(w * h);
  for (var i = 0; i < d.length; i++) {
    d[i] = bin[i] != 0 ? xa : 0;
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = y * w + x;
      var v = d[p];
      if (v == 0) continue;
      if (x > 0) v = math.min(v, d[p - 1] + a);
      if (y > 0) {
        v = math.min(v, d[p - w] + a);
        if (x > 0) v = math.min(v, d[p - w - 1] + b);
        if (x < w - 1) v = math.min(v, d[p - w + 1] + b);
      }
      d[p] = v;
    }
  }
  for (var y = h - 1; y >= 0; y--) {
    for (var x = w - 1; x >= 0; x--) {
      final p = y * w + x;
      var v = d[p];
      if (v == 0) continue;
      if (x < w - 1) v = math.min(v, d[p + 1] + a);
      if (y < h - 1) {
        v = math.min(v, d[p + w] + a);
        if (x < w - 1) v = math.min(v, d[p + w + 1] + b);
        if (x > 0) v = math.min(v, d[p + w - 1] + b);
      }
      d[p] = v;
    }
  }
  return d;
}

// ---------------------------------------------------------------- nét mực thuộc dòng nào

/// Phân nét mực trong vùng cột [x0, x1) × dải dòng [d]: (của dòng d, của chỗ khác), mỗi mảng 0/1 cỡ rộng × cao vùng
/// (cột đã kẹp trong ảnh). Dòng nghiêng, dòng sát nhau làm nét dòng trên, dòng dưới lọt vào dải: những nét đó phải
/// đứng yên khi dời, xóa ký tự. Mỗi thành phần liên thông thuộc dòng có khung ký tự phủ nhiều điểm mực của nó nhất
/// (khung ký tự của máy đọc gồm cả dấu thanh, dấu nặng nên dấu không bị gán nhầm sang dòng bên cạnh). Thành phần không
/// chạm khung nào thì thuộc dòng có dải xiên chứa tâm nó, gần lõi chữ nhất; nét dính liền hai dòng thì tách từng điểm
/// theo khung ký tự. Đường kẻ dài, nét quá cao (khung bảng, con dấu) không thuộc dòng nào: giữ nguyên.
(Uint8List, Uint8List) netCuaDong(AnhBgr anh, List<DongAnh> cacDong, DongAnh d, int x0, int x1) {
  final y0 = d.dai0, y1 = d.dai1;
  x0 = math.max(0, x0);
  x1 = math.min(anh.w, x1);
  final h = y1 - y0, w = x1 - x0;
  if (h <= 0 || w <= 0) return (Uint8List(0), Uint8List(0));
  // ngưỡng mực đo trên cả dòng (vùng hẹp chỉ toàn nền thì Otsu chia nhầm vân giấy)
  final lx0 = math.max(0, math.min(x0, d.x0)), lx1 = math.min(anh.w, math.max(x1, d.x1));
  final t = _otsu(anh.xamVung(lx0, y0, lx1, y1));
  final xam = anh.xamVung(x0, y0, x1, y1);
  final toi = Uint8List(w * h);
  for (var i = 0; i < toi.length; i++) {
    toi[i] = xam[i] <= t ? 1 : 0;
  }
  final (nhan, tk) = _thanhPhan(toi, w, h);
  final gan = [for (final e in cacDong) if (e.x1 > x0 && e.x0 < x1 && e.dai1 > y0 && e.dai0 < y1) e];
  if (!gan.any((e) => identical(e, d))) gan.add(d);
  // khung ký tự từng dòng: mỗi điểm ghi chỉ số dòng (−1: không khung nào, −2: khung hai dòng chồng nhau)
  final khung = Int32List(w * h)..fillRange(0, w * h, -1);
  for (var k = 0; k < gan.length; k++) {
    for (final c in gan[k].kyTu) {
      final a0 = math.max(0, c.x0 - x0 - 1), b0 = math.max(0, c.y0 - y0 - 1);
      final a1 = math.min(w, c.x1 - x0 + 1), b1 = math.min(h, c.y1 - y0 + 1);
      for (var y = b0; y < b1; y++) {
        for (var x = a0; x < a1; x++) {
          final o = khung[y * w + x];
          if (o == -1) {
            khung[y * w + x] = k;
          } else if (o >= 0 && o != k) {
            khung[y * w + x] = -2;
          }
        }
      }
    }
  }
  final n = tk.length, so = gan.length;
  // đếm điểm mực từng thành phần nằm trong khung từng dòng
  final dem = Int32List(n * so);
  for (var p = 0; p < nhan.length; p++) {
    if (nhan[p] > 0 && khung[p] >= 0) dem[nhan[p] * so + khung[p]]++;
  }
  final chu = Int32List(n)..fillRange(0, n, -1); // dòng sở hữu từng thành phần (−1: không dòng nào)
  final tach = List<bool>.filled(n, false); // thành phần dính hai dòng: tách từng điểm
  final co = d.co;
  for (var i = 1; i < n; i++) {
    final [cx, cy, cw, ch, _] = tk[i];
    if ((cw > 8 * co && ch < 0.35 * co) || ch > 2.6 * co) continue; // đường kẻ, khung, con dấu
    var tong = 0, k = 0;
    for (var j = 0; j < so; j++) {
      tong += dem[i * so + j];
      if (dem[i * so + j] > dem[i * so + k]) k = j;
    }
    if (tong > 0) {
      chu[i] = k;
      if (ch > 1.3 * co && tong - dem[i * so + k] >= 0.15 * tong) tach[i] = true;
      continue;
    }
    // không chạm khung ký tự nào: theo dải xiên
    final tx = x0 + cx + cw / 2, ty = y0 + cy + ch / 2;
    var tot = -1;
    double? kcTot;
    for (var j = 0; j < so; j++) {
      final e = gan[j];
      final u = e.chanTai(tx) - ty;
      if (-(e.duoi != 0 ? e.duoi : 0.3 * e.co) <= u && u <= (e.tren != 0 ? e.tren : 1.3 * e.co)) {
        final kc = (u - 0.35 * e.co).abs() / math.max(e.co, 1);
        if (kcTot == null || kc < kcTot) {
          tot = j;
          kcTot = kc;
        }
      }
    }
    chu[i] = tot;
  }
  final ki = gan.indexWhere((e) => identical(e, d));
  final coGan = [for (final e in gan) e.co];
  final cua = Uint8List(w * h), khac = Uint8List(w * h);
  for (var p = 0; p < nhan.length; p++) {
    final i = nhan[p];
    if (i == 0) continue;
    var ai = chu[i];
    if (tach[i]) {
      // điểm của thành phần dính hai dòng: theo khung ký tự; ngoài khung thì theo đường chân gần nhất
      if (khung[p] >= 0) {
        ai = khung[p];
      } else {
        final px = x0 + p % w, py = y0 + p ~/ w;
        var gn = double.infinity;
        for (var j = 0; j < so; j++) {
          final kc = (gan[j].chanTai(px) - 0.35 * coGan[j] - py).abs() / math.max(coGan[j], 1);
          if (kc < gn) {
            gn = kc;
            ai = j;
          }
        }
      }
    }
    if (ai == ki) {
      cua[p] = 1;
    } else {
      khac[p] = 1;
    }
  }
  return (cua, khac);
}

/// Nới mặt nạ 0/1 một điểm ảnh (ô 3×3).
Uint8List _no3(Uint8List mat, int w, int h) {
  final no = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (mat[y * w + x] == 0) continue;
      for (var yy = math.max(0, y - 1); yy <= math.min(h - 1, y + 1); yy++) {
        for (var xx = math.max(0, x - 1); xx <= math.min(w - 1, x + 1); xx++) {
          no[yy * w + xx] = 1;
        }
      }
    }
  }
  return no;
}

// ---------------------------------------------------------------- mảnh của dòng

/// Ký tự vẽ sẵn bằng phông (khi cả hồ sơ không có ký tự đó): độ phủ, gốc bút trong hình, màu mực.
class HinhVe {
  HinhVe(this.phu, this.w, this.h, this.gocX, this.chan, this.mau, this.rongChu);
  final Uint8List phu; // 0–255
  final int w, h;
  final double gocX, chan; // gốc bút (x, đường chân) trong hình
  final List<int> mau; // BGR
  final double rongChu; // bề rộng bước chữ của phông
}

/// Định dạng người dùng đặt khi đổi phông đoạn bôi chọn: phông (chỉ số trong PhongChu.tatCa của ve_chu.dart), cỡ chữ
/// (fontSize, điểm ảnh), màu mực (BGR), viền thêm cho nét đậm như chữ thật.
class DinhDangVe {
  const DinhDangVe(this.phong, this.co, this.mau, {this.vien = 0});
  final int phong;
  final double co;
  final List<int> mau;
  final double vien;

  DinhDangVe doiCo(double co2) => DinhDangVe(phong, co2, mau, vien: co > 0 ? vien * co2 / co : vien);
}

/// Một mảnh của dòng sau khi sửa. loai: goc (dải gốc của chính dòng), chep (ký tự chép từ chỗ khác, có thể ở trang
/// khác; giữ sẵn điểm ảnh mẫu), ve (vẽ bằng phông khi cả hồ sơ không có ký tự đó, hoặc đoạn người dùng đổi phông).
class Manh {
  Manh(this.loai, this.chu,
      {this.x0 = 0,
      this.x1 = 0,
      this.cao = 0,
      this.mau,
      this.matMau,
      this.chuaChac = false,
      this.chanMau = 0,
      this.tiLe = 1.0,
      this.rongVe = 0,
      this.coVe = 0,
      this.hinh,
      this.mauMuc,
      this.diem = 0,
      this.coDoi = 1.0,
      this.kieuVe,
      this.banGoc,
      this.nenMuc});

  final String loai, chu;
  int x0, x1; // goc: dải cột trên ảnh
  final int cao; // goc: chiều cao khung ký tự (để vẽ ký tự thiếu cho cân cỡ)
  final AnhBgr? mau; // chep: điểm ảnh mẫu (cả dải dọc dòng nguồn)
  final Uint8List? matMau; // chep: 1 ở các nét thuộc ký tự mẫu (cỡ như [mau])
  final bool chuaChac; // mẫu lấy từ trang khác hoặc vẽ bằng phông: nên xem lại, có thể chọn mẫu khác
  final double chanMau; // chep: đường chân chữ trong ảnh mẫu
  final double tiLe; // chep: phóng, thu cho khớp cỡ dòng đích
  final double rongVe; // ve: bề rộng
  final double coVe; // ve: cỡ chữ (điểm ảnh)
  final HinhVe? hinh; // ve: chữ vẽ sẵn (null: chưa vẽ được, để trống chỗ)
  List<double>? mauMuc; // chep: tô bằng màu mực (BGR) ở chỗ chèn, đậm nhạt đều với chữ quanh
  double diem; // chep: điểm chọn mẫu (nhỏ là hợp); mẫu ghép dấu cộng thêm
  // đổi cỡ, đổi phông đoạn bôi chọn
  final double coDoi; // tỉ lệ cỡ người dùng đặt so với cỡ gốc (phóng, thu chính nét chữ gốc)
  final DinhDangVe? kieuVe; // ve: phông, cỡ, màu người dùng chọn
  final Manh? banGoc; // mảnh trước khi đổi cỡ, đổi phông (để trả lại nét gốc)
  final (double, double)? nenMuc; // chep từ nét gốc của dòng: độ sáng nền, lõi mực đo trên cả dòng

  /// Định dạng đã khác bản gốc (đổi cỡ, đổi phông): mảnh được vẽ ra ngoài dải dòng nếu cần.
  bool get doiDinhDang => kieuVe != null || (coDoi - 1).abs() > 1e-3;

  int get rong {
    if (loai == 've') return rongVe.round();
    if (loai == 'goc') return math.max(0, x1 - x0);
    return math.max(1, (mau!.w * tiLe).round());
  }

  Manh banSao({double? tiLe, double? rongVe, double? coVe, HinhVe? hinh, double? coDoi, Manh? banGoc}) => Manh(loai, chu,
      x0: x0,
      x1: x1,
      cao: cao,
      mau: mau,
      matMau: matMau,
      chuaChac: chuaChac,
      chanMau: chanMau,
      tiLe: tiLe ?? this.tiLe,
      rongVe: rongVe ?? this.rongVe,
      coVe: coVe ?? this.coVe,
      hinh: hinh ?? this.hinh,
      mauMuc: mauMuc,
      diem: diem,
      coDoi: coDoi ?? this.coDoi,
      kieuVe: kieuVe,
      banGoc: banGoc ?? this.banGoc,
      nenMuc: nenMuc);
}

/// Chia dòng thành các mảnh gốc liền nhau: ký tự (cắt ở giữa khe hai ký tự) và khoảng trắng giữa các từ.
/// Có [anh] thì dãy chấm dẫn được thay bằng các mảnh chấm tìm theo hình dạng.
List<Manh> manhDong(DongAnh d, [AnhBgr? anh]) {
  var kq = <Manh>[];
  for (var wi = 0; wi < d.tu.length; wi++) {
    final w = d.tu[wi];
    for (var ci = 0; ci < w.length; ci++) {
      final c = w[ci];
      final trai = ci == 0 ? c.x0 : (w[ci - 1].x1 + c.x0) ~/ 2;
      final phai = ci == w.length - 1 ? c.x1 : (c.x1 + w[ci + 1].x0) ~/ 2;
      kq.add(Manh('goc', c.chu, x0: trai, x1: math.max(trai + 1, phai), cao: c.cao));
    }
    if (wi < d.tu.length - 1) {
      final a = kq.last.x1, b = d.tu[wi + 1].first.x0;
      kq.add(Manh('goc', ' ', x0: a, x1: math.max(a + 1, b)));
    }
  }
  // khung ký tự đè nhau (chữ nghiêng, ghép nét, máy đọc loạn): cắt ở giữa chỗ chồng, giữ các mảnh liền nhau, không chồng.
  // Mảnh rộng 0 (ký tự máy đọc thừa, khung lọt hẳn trong ký tự bên cạnh) phải bỏ: ép rộng 1 điểm ảnh làm lệch cả dòng.
  // Khác bản PC: so với mảnh còn giữ gần nhất chứ không chỉ mảnh liền trước, vì bỏ một mảnh có thể để lộ chỗ chồng
  // với mảnh trước nữa (từ máy đọc chồng lên từ sau): không xử lý thì vài cột điểm ảnh bị dán hai lần thành vệt lạ.
  final gon = <Manh>[];
  for (final b in kq) {
    while (gon.isNotEmpty && b.x0 < gon.last.x1) {
      final a = gon.last;
      b.x0 = a.x1 = math.max(a.x0, (a.x1 + b.x0) ~/ 2);
      if (a.x1 > a.x0) break;
      gon.removeLast();
    }
    if (b.x1 > b.x0) gon.add(b);
  }
  kq = gon;
  final cham = anh != null ? timChamDan(anh, d) : const <(int, int)>[];
  if (cham.isNotEmpty) {
    final buoc = (cham.last.$1 - cham.first.$1) / (cham.length - 1);
    final cat = [
      (cham.first.$1 - buoc / 2).round(),
      for (var i = 1; i < cham.length; i++) (cham[i - 1].$2 + cham[i].$1) ~/ 2,
      (cham.last.$2 + buoc / 2).round(),
    ];
    final r0 = cat.first, r1 = cat.last;
    final truoc = [for (final m in kq) if (m.x0 < r0) m];
    final sau = [for (final m in kq) if (m.x1 > r1) m];
    if (truoc.isNotEmpty) truoc.last.x1 = math.min(truoc.last.x1, r0);
    if (sau.isNotEmpty) sau.first.x0 = math.max(sau.first.x0, r1);
    // khoảng hở giữa mảnh cuối trước dãy chấm và dãy chấm (nếu có) gộp vào mảnh trước
    if (truoc.isNotEmpty && truoc.last.x1 < r0) truoc.last.x1 = r0;
    if (sau.isNotEmpty && sau.first.x0 > r1) sau.insert(0, Manh('goc', ' ', x0: r1, x1: sau.first.x0));
    kq = [
      ...truoc,
      for (var i = 1; i < cat.length; i++) Manh('goc', '.', x0: cat[i - 1], x1: cat[i]),
      ...sau,
    ];
  }
  return kq;
}

/// Mảnh chép từ ký tự [c] của dòng [d] trên ảnh [anh] (kèm nửa khe hai bên). Chỉ giữ các nét có phần lớn nằm trong
/// khung ký tự: nét của ký tự đứng cạnh lọt vào dải cắt không bị chép theo; và chỉ nét của chính dòng ([cacDong]: các
/// dòng của trang đó): dòng nghiêng, dòng sát nhau có nét dòng trên, dòng dưới trong cùng cột.
Manh manhChep(AnhBgr anh, DongAnh d, KyTu c, double khe, {double tiLe = 1.0, bool chuaChac = false, List<DongAnh>? cacDong}) {
  var x0 = (c.x0 - khe / 2).round(), x1 = (c.x1 + khe / 2).round();
  x0 = math.max(0, x0);
  x1 = math.min(anh.w, math.max(x0 + 1, x1));
  final y0 = d.dai0, y1 = d.dai1;
  final mau = anh.cat(x0, y0, x1, y1);
  final w = mau.w, h = mau.h;
  final (nhan, tk) = _thanhPhan(_mucOtsu(mau.xamVung(0, 0, w, h)), w, h);
  final cx0 = c.x0 - x0, cx1 = c.x1 - x0;
  final giu = List<bool>.filled(tk.length, false);
  // ảnh nhòe làm chữ dính nhau thành một thành phần: trong khung ký tự thì giữ hết điểm mực của các thành phần chạm
  // khung (nét của dòng trên, dòng dưới lọt vào cùng cột thì không chạm khung, bỏ)
  final cham = List<bool>.filled(tk.length, false);
  final cy0 = c.y0 - y0 - 2, cy1 = c.y1 - y0 + 2;
  // chữ không dấu (trừ i, j có chấm; g, j, p, q, y có nét xuống): nét nhỏ nằm hẳn trên đỉnh thân chữ, hẳn dưới đường
  // chân là dấu của chữ bên cạnh lọt vào khung (ảnh mờ làm khung máy đọc rộng ra), không chép theo
  final xh = xCao(d), chan = d.chanTai((c.x0 + c.x1) / 2) - y0;
  final khongDau = c.chu.length == 1 && tachDau(c.chu) == null && laChuSo(c.chu);
  for (var i = 1; i < tk.length; i++) {
    final [tx, ty, tw, th, _] = tk[i];
    final trong = math.max(0, math.min(tx + tw, cx1) - math.max(tx, cx0));
    // khung ký tự của máy đọc gồm cả dấu của chính nó: nét nằm hẳn trên, dưới khung là dấu của chữ bên cạnh
    giu[i] = trong >= 0.5 * tw && ty < cy1 && ty + th > cy0;
    if (giu[i] && khongDau && th < 0.5 * xh) {
      if (!'ij'.contains(c.chu) && ty + th <= chan - (c.chu.toUpperCase() == c.chu && c.chu.toLowerCase() != c.chu ? 1.5 : 0.95) * xh) {
        giu[i] = false;
      } else if (!'gjpqy'.contains(c.chu) && ty >= chan + 0.15 * xh) {
        giu[i] = false;
      }
    }
    cham[i] = ty < cy1 && ty + th > cy0 && tx < cx1 && tx + tw > cx0;
  }
  final (cua, _) = netCuaDong(anh, cacDong ?? [d], d, x0, x1);
  final mat = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final n = nhan[y * w + x];
      if ((giu[n] || (cham[n] && x >= math.max(0, cx0) && x < math.max(0, cx1))) && cua[y * w + x] == 1) mat[y * w + x] = 1;
    }
  }
  // nới 1 điểm ảnh (ô 3×3) để lấy cả viền nhòe quanh nét
  return Manh('chep', c.chu,
      mau: mau,
      matMau: _no3(mat, w, h),
      chanMau: d.chanTai((c.x0 + c.x1) / 2) - y0,
      tiLe: (tiLe - 1).abs() > 0.06 ? tiLe : 1.0,
      chuaChac: chuaChac);
}

/// Các dòng của một trang dùng để tìm ký tự mẫu; ảnh có sẵn (trang đang sửa) hoặc nạp khi cần (trang khác).
class TrangNguon {
  TrangNguon(this.dong, {this.anh, this.tai});
  final List<DongAnh> dong;
  AnhBgr? anh;
  final Future<AnhBgr> Function()? tai;

  Future<AnhBgr> layAnh() async => anh ??= await tai!();
}

/// Ký tự mẫu đã chọn: trang thứ mấy trong nguồn (0: trang đang sửa), dòng, ký tự, tỉ lệ cỡ, điểm (nhỏ là hợp).
typedef ChonMau = ({int trang, DongAnh dong, KyTu kyTu, double tiLe, double diem});

/// Chiều cao chữ thường không dấu của dòng (đỉnh thân a, o, n… tới đường chân).
double xCao(DongAnh d) => d.coX ?? 0.62 * d.co;

/// Bề dày nét trung bình của ảnh nhị phân (1 = mực): 2 × diện tích / chu vi (chu vi đếm cạnh điểm mực giáp nền theo 4
/// hướng). Mịn hơn đo bằng biến đổi khoảng cách (chỉ ra bội của 1 điểm ảnh), nên phân biệt được chữ đậm với chữ thường
/// cả khi nét chỉ dày 3–4 điểm ảnh (ảnh chụp).
double beDayNet(Uint8List toi, int w, int h) {
  var dt = 0, canh = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = toi[y * w + x] != 0;
      if (v) dt++;
      if ((x + 1 < w && toi[y * w + x + 1] != 0) != v) canh++;
      if ((y + 1 < h && toi[(y + 1) * w + x] != 0) != v) canh++;
      if (v && x == 0) canh++;
      if (v && y == 0) canh++;
    }
  }
  return dt == 0 ? 0 : 2 * dt / math.max(canh, 1);
}

/// Độ đậm nét của riêng một ký tự: bề dày nét (điểm ảnh). Một dòng có thể lẫn chữ đậm, chữ thường (nhãn hàng, tiêu đề
/// in đậm giữa dòng) nên không dùng độ đậm trung bình cả dòng để chọn mẫu. Đo một lần, đệm cùng khung ký tự.
double damKyTu(AnhBgr anh, DongAnh d, KyTu c) {
  if (c.dam != 0) return c.dam;
  final x0 = math.max(0, c.x0 - 1), y0 = math.max(0, c.y0 - 1), x1 = math.min(anh.w, c.x1 + 1), y1 = math.min(anh.h, c.y1 + 1);
  if (x1 <= x0 || y1 <= y0) return 0;
  c.dam = beDayNet(_mucOtsu(anh.xamVung(x0, y0, x1, y1)), x1 - x0, y1 - y0);
  return c.dam;
}

/// Bề dày nét trung vị các chữ, số của dòng (điểm ảnh); ký tự chưa đo (ảnh trang chưa nạp) thì bỏ qua.
double damDong(DongAnh d, [AnhBgr? anh]) {
  final v = [
    for (final c in d.kyTu)
      if (laChuSo(c.chu) && c.tinCay >= 50) anh != null ? damKyTu(anh, d, c) : c.dam
  ].where((x) => x > 0).toList();
  return v.isEmpty ? 0 : _trungVi(v);
}

/// Bề dày nét trung vị các chữ, số của dòng quanh cột [x] (trong khoảng [r], mặc định 2,5 cỡ chữ): đo một ký tự lẻ dao
/// động theo dáng chữ, lấy vài chữ quanh nó thì ổn định mà vẫn phân biệt được từ in đậm giữa dòng chữ thường.
double damQuanh(DongAnh d, double x, {AnhBgr? anh, double? r}) {
  final ban = r ?? 2.5 * d.co;
  final v = [
    for (final c in d.kyTu)
      if (laChuSo(c.chu) && c.tinCay >= 50 && ((c.x0 + c.x1) / 2 - x).abs() <= ban) anh != null ? damKyTu(anh, d, c) : c.dam
  ].where((x) => x > 0).toList();
  return v.length >= 2 ? _trungVi(v) : damDong(d, anh);
}

/// Hình thu nhỏ 16×16 (độ phủ mực trung bình từng ô) của ký tự, để so dáng các mẫu cùng tên.
Float32List _hinhKyTu(AnhBgr anh, KyTu c) {
  final da = c.hinh;
  if (da != null) return da;
  final x0 = math.max(0, c.x0), y0 = math.max(0, c.y0), x1 = math.min(anh.w, c.x1), y1 = math.min(anh.h, c.y1);
  final kq = Float32List(256);
  if (x1 > x0 && y1 > y0) {
    final w = x1 - x0, h = y1 - y0;
    final toi = _mucOtsu(anh.xamVung(x0, y0, x1, y1));
    for (var i = 0; i < 16; i++) {
      final ya = i * h ~/ 16, yb = math.max(ya + 1, (i + 1) * h ~/ 16);
      for (var j = 0; j < 16; j++) {
        final xa = j * w ~/ 16, xb = math.max(xa + 1, (j + 1) * w ~/ 16);
        var t = 0;
        for (var y = ya; y < math.min(yb, h); y++) {
          for (var x = xa; x < math.min(xb, w); x++) {
            t += toi[y * w + x];
          }
        }
        kq[i * 16 + j] = t / ((yb - ya) * (xb - xa));
      }
    }
  }
  c.hinh = kq;
  return kq;
}

/// Chỉ số các ứng viên có dáng khác hẳn các ứng viên cùng tên (≥ 3 ứng viên có ảnh): thường là chỗ máy đọc nhầm (ảnh
/// chụp mờ, chữ đậm đọc thành chữ khác) mà vẫn báo tin cậy cao. Chép nhầm hình là "lỗi phông" dễ thấy nhất.
Set<int> _laHinh(List<(int, DongAnh, KyTu)> ungVien, List<TrangNguon> nguon) {
  final la = <int>{};
  final nhom = <String, List<int>>{};
  for (var i = 0; i < ungVien.length; i++) {
    if (nguon[ungVien[i].$1].anh != null) nhom.putIfAbsent(ungVien[i].$3.chu, () => []).add(i);
  }
  for (final ds in nhom.values) {
    if (ds.length < 3) continue;
    final h = [for (final i in ds) _hinhKyTu(nguon[ungVien[i].$1].anh!, ungVien[i].$3)];
    final tv = <double>[];
    for (var a = 0; a < ds.length; a++) {
      final kc = <double>[];
      for (var b = 0; b < ds.length; b++) {
        if (a == b) continue;
        var t = 0.0;
        for (var k = 0; k < 256; k++) {
          t += (h[a][k] - h[b][k]).abs();
        }
        kc.add(t / 256);
      }
      tv.add(_trungVi(kc));
    }
    final chuan = _trungVi(tv);
    for (var a = 0; a < ds.length; a++) {
      if (tv[a] > math.max(0.22, 1.6 * chuan)) la.add(ds[a]);
    }
  }
  return la;
}

/// Các ký tự mẫu hợp lệ trong [nguon] (ký tự [chon] nhận), xếp theo điểm tăng dần (nhỏ là hợp). Loại mẫu có chiều cao,
/// bề rộng (so với cỡ dòng của nó) khác hẳn các mẫu cùng tên, mẫu dáng lạ; rồi ưu tiên cỡ chữ, độ đậm nét gần chữ quanh
/// chỗ chèn ([damDich], điểm ảnh), cùng trang, cùng dòng, máy đọc chắc, khung đo thật (không phải chia đôi nét). Có
/// mẫu đậm nhạt vừa (chênh dưới 18%) thì bỏ hẳn mẫu chênh nhiều: chữ chèn lệch đậm nhạt rất dễ thấy. [xetDam] = false:
/// không xét độ đậm (dấu thanh nhỏ, dáng gần như nhau ở chữ đậm, chữ thường). Như _ung_vien() bản PC.
List<ChonMau> _ungVien(List<TrangNguon> nguon, DongAnh dich, bool Function(String) chon, double damDich,
    {double Function(String)? them, bool xetDam = true}) {
  final ungVien = <(int, DongAnh, KyTu)>[
    for (var t = 0; t < nguon.length; t++)
      for (final d in nguon[t].dong)
        for (final w in d.tu)
          for (final c in w)
            if (chon(c.chu) &&
                c.tinCay >= 70 &&
                // chữ, số không thể là một nét nhỏ: loại chỗ máy đọc nhầm dấu chấm, vết bẩn thành chữ
                (!laChuSo(c.chu) || (c.cao >= 0.55 * d.co && c.rong >= 0.2 * d.co)))
              (t, d, c)
  ];
  if (ungVien.isEmpty) return [];
  final la = _laHinh(ungVien, nguon);
  final nhom = <String, (double, double, int)>{};
  for (final chu in {for (final u in ungVien) u.$3.chu}) {
    final cao = [for (final (_, d, c) in ungVien) if (c.chu == chu) c.cao / math.max(d.co, 1)];
    final rong = [for (final (_, d, c) in ungVien) if (c.chu == chu) c.rong / math.max(d.co, 1)];
    nhom[chu] = (_trungVi(cao), _trungVi(rong), cao.length);
  }
  final kq = <(ChonMau, double)>[];
  for (var i = 0; i < ungVien.length; i++) {
    if (la.contains(i)) continue;
    final (t, d, c) = ungVien[i];
    final (trungCao, trungRong, so) = nhom[c.chu]!;
    final lechHinh = (c.cao / math.max(d.co, 1) - trungCao).abs() / math.max(trungCao, 1e-6) +
        (c.rong / math.max(d.co, 1) - trungRong).abs() / math.max(trungRong, 1e-6);
    if (so >= 3 && lechHinh > 0.5) continue;
    final tiLe = tiLeCo(dich, d);
    final damMau = damQuanh(d, (c.x0 + c.x1) / 2, anh: nguon[t].anh);
    final lechDam = xetDam && damMau > 0 && damDich > 0 ? math.log(damMau * tiLe / damDich).abs() : 0.0;
    final diem = math.log(tiLe).abs() * 3 +
        lechHinh +
        4 * lechDam +
        (identical(d, dich) ? 0 : 0.15) +
        (t > 0 ? 0.6 : 0) +
        (100 - c.tinCay) / 100 +
        (c.chia ? 0.5 : 0) +
        (them?.call(c.chu) ?? 0);
    kq.add(((trang: t, dong: d, kyTu: c, tiLe: tiLe, diem: diem), lechDam));
  }
  final vua = [for (final k in kq) if (k.$2 <= math.log(1.18)) k];
  final ds = vua.isNotEmpty ? vua : kq;
  ds.sort((a, b) => a.$1.diem.compareTo(b.$1.diem));
  return [for (final k in ds) k.$1];
}

/// Tìm ký tự [chu] trong các trang [nguon] (trang đang sửa đứng đầu) để chép. [damDich]: bề dày nét các chữ quanh chỗ
/// chèn (mặc định: cả dòng đích). Mẫu lấy từ trang khác đánh dấu chưa chắc (khi chép).
ChonMau? chonKyTuMau(List<TrangNguon> nguon, DongAnh dich, String chu, {double? damDich}) {
  final kq = _ungVien(nguon, dich, (x) => x == chu, damDich ?? damDong(dich, nguon.first.anh));
  return kq.isEmpty ? null : kq.first;
}

// ---- dấu tiếng Việt: chữ có dấu không có sẵn thì ghép thân chữ với dấu chép từ chữ khác cùng trang

/// Chữ có dấu tiếng Việt → (thân, các dấu trên, dấu dưới) dạng tổ hợp, như tach_dau() bản PC (bảng sinh bằng
/// unicodedata của Python: Dart không có sẵn chuẩn hóa Unicode).
const _bangDau = <String, (String, String, String)>{
  'À': ('A', '\u0300', ''),
  'Á': ('A', '\u0301', ''),
  'Â': ('A', '\u0302', ''),
  'Ã': ('A', '\u0303', ''),
  'È': ('E', '\u0300', ''),
  'É': ('E', '\u0301', ''),
  'Ê': ('E', '\u0302', ''),
  'Ì': ('I', '\u0300', ''),
  'Í': ('I', '\u0301', ''),
  'Î': ('I', '\u0302', ''),
  'Ò': ('O', '\u0300', ''),
  'Ó': ('O', '\u0301', ''),
  'Ô': ('O', '\u0302', ''),
  'Õ': ('O', '\u0303', ''),
  'Ù': ('U', '\u0300', ''),
  'Ú': ('U', '\u0301', ''),
  'Û': ('U', '\u0302', ''),
  'Ý': ('Y', '\u0301', ''),
  'à': ('a', '\u0300', ''),
  'á': ('a', '\u0301', ''),
  'â': ('a', '\u0302', ''),
  'ã': ('a', '\u0303', ''),
  'è': ('e', '\u0300', ''),
  'é': ('e', '\u0301', ''),
  'ê': ('e', '\u0302', ''),
  'ì': ('i', '\u0300', ''),
  'í': ('i', '\u0301', ''),
  'î': ('i', '\u0302', ''),
  'ò': ('o', '\u0300', ''),
  'ó': ('o', '\u0301', ''),
  'ô': ('o', '\u0302', ''),
  'õ': ('o', '\u0303', ''),
  'ù': ('u', '\u0300', ''),
  'ú': ('u', '\u0301', ''),
  'û': ('u', '\u0302', ''),
  'ý': ('y', '\u0301', ''),
  'Ă': ('A', '\u0306', ''),
  'ă': ('a', '\u0306', ''),
  'Ĕ': ('E', '\u0306', ''),
  'ĕ': ('e', '\u0306', ''),
  'Ĩ': ('I', '\u0303', ''),
  'ĩ': ('i', '\u0303', ''),
  'Ĭ': ('I', '\u0306', ''),
  'ĭ': ('i', '\u0306', ''),
  'Ŏ': ('O', '\u0306', ''),
  'ŏ': ('o', '\u0306', ''),
  'Ũ': ('U', '\u0303', ''),
  'ũ': ('u', '\u0303', ''),
  'Ŭ': ('U', '\u0306', ''),
  'ŭ': ('u', '\u0306', ''),
  'Ŷ': ('Y', '\u0302', ''),
  'ŷ': ('y', '\u0302', ''),
  'Ṍ': ('O', '\u0303\u0301', ''),
  'ṍ': ('o', '\u0303\u0301', ''),
  'Ṹ': ('U', '\u0303\u0301', ''),
  'ṹ': ('u', '\u0303\u0301', ''),
  'Ạ': ('A', '', '\u0323'),
  'ạ': ('a', '', '\u0323'),
  'Ả': ('A', '\u0309', ''),
  'ả': ('a', '\u0309', ''),
  'Ấ': ('A', '\u0302\u0301', ''),
  'ấ': ('a', '\u0302\u0301', ''),
  'Ầ': ('A', '\u0302\u0300', ''),
  'ầ': ('a', '\u0302\u0300', ''),
  'Ẩ': ('A', '\u0302\u0309', ''),
  'ẩ': ('a', '\u0302\u0309', ''),
  'Ẫ': ('A', '\u0302\u0303', ''),
  'ẫ': ('a', '\u0302\u0303', ''),
  'Ậ': ('A', '\u0302', '\u0323'),
  'ậ': ('a', '\u0302', '\u0323'),
  'Ắ': ('A', '\u0306\u0301', ''),
  'ắ': ('a', '\u0306\u0301', ''),
  'Ằ': ('A', '\u0306\u0300', ''),
  'ằ': ('a', '\u0306\u0300', ''),
  'Ẳ': ('A', '\u0306\u0309', ''),
  'ẳ': ('a', '\u0306\u0309', ''),
  'Ẵ': ('A', '\u0306\u0303', ''),
  'ẵ': ('a', '\u0306\u0303', ''),
  'Ặ': ('A', '\u0306', '\u0323'),
  'ặ': ('a', '\u0306', '\u0323'),
  'Ẹ': ('E', '', '\u0323'),
  'ẹ': ('e', '', '\u0323'),
  'Ẻ': ('E', '\u0309', ''),
  'ẻ': ('e', '\u0309', ''),
  'Ẽ': ('E', '\u0303', ''),
  'ẽ': ('e', '\u0303', ''),
  'Ế': ('E', '\u0302\u0301', ''),
  'ế': ('e', '\u0302\u0301', ''),
  'Ề': ('E', '\u0302\u0300', ''),
  'ề': ('e', '\u0302\u0300', ''),
  'Ể': ('E', '\u0302\u0309', ''),
  'ể': ('e', '\u0302\u0309', ''),
  'Ễ': ('E', '\u0302\u0303', ''),
  'ễ': ('e', '\u0302\u0303', ''),
  'Ệ': ('E', '\u0302', '\u0323'),
  'ệ': ('e', '\u0302', '\u0323'),
  'Ỉ': ('I', '\u0309', ''),
  'ỉ': ('i', '\u0309', ''),
  'Ị': ('I', '', '\u0323'),
  'ị': ('i', '', '\u0323'),
  'Ọ': ('O', '', '\u0323'),
  'ọ': ('o', '', '\u0323'),
  'Ỏ': ('O', '\u0309', ''),
  'ỏ': ('o', '\u0309', ''),
  'Ố': ('O', '\u0302\u0301', ''),
  'ố': ('o', '\u0302\u0301', ''),
  'Ồ': ('O', '\u0302\u0300', ''),
  'ồ': ('o', '\u0302\u0300', ''),
  'Ổ': ('O', '\u0302\u0309', ''),
  'ổ': ('o', '\u0302\u0309', ''),
  'Ỗ': ('O', '\u0302\u0303', ''),
  'ỗ': ('o', '\u0302\u0303', ''),
  'Ộ': ('O', '\u0302', '\u0323'),
  'ộ': ('o', '\u0302', '\u0323'),
  'Ớ': ('Ơ', '\u0301', ''),
  'ớ': ('ơ', '\u0301', ''),
  'Ờ': ('Ơ', '\u0300', ''),
  'ờ': ('ơ', '\u0300', ''),
  'Ở': ('Ơ', '\u0309', ''),
  'ở': ('ơ', '\u0309', ''),
  'Ỡ': ('Ơ', '\u0303', ''),
  'ỡ': ('ơ', '\u0303', ''),
  'Ợ': ('Ơ', '', '\u0323'),
  'ợ': ('ơ', '', '\u0323'),
  'Ụ': ('U', '', '\u0323'),
  'ụ': ('u', '', '\u0323'),
  'Ủ': ('U', '\u0309', ''),
  'ủ': ('u', '\u0309', ''),
  'Ứ': ('Ư', '\u0301', ''),
  'ứ': ('ư', '\u0301', ''),
  'Ừ': ('Ư', '\u0300', ''),
  'ừ': ('ư', '\u0300', ''),
  'Ử': ('Ư', '\u0309', ''),
  'ử': ('ư', '\u0309', ''),
  'Ữ': ('Ư', '\u0303', ''),
  'ữ': ('ư', '\u0303', ''),
  'Ự': ('Ư', '', '\u0323'),
  'ự': ('ư', '', '\u0323'),
  'Ỳ': ('Y', '\u0300', ''),
  'ỳ': ('y', '\u0300', ''),
  'Ỵ': ('Y', '', '\u0323'),
  'ỵ': ('y', '', '\u0323'),
  'Ỷ': ('Y', '\u0309', ''),
  'ỷ': ('y', '\u0309', ''),
  'Ỹ': ('Y', '\u0303', ''),
  'ỹ': ('y', '\u0303', ''),
};

/// Dạng tổ hợp (chữ + dấu rời theo thứ tự chuẩn NFD) → chữ dựng sẵn (NFC), để ghép chữ gõ bằng dấu rời.
const _bangGhep = <String, String>{
  'A\u0300': 'À',
  'A\u0301': 'Á',
  'A\u0302': 'Â',
  'A\u0303': 'Ã',
  'E\u0300': 'È',
  'E\u0301': 'É',
  'E\u0302': 'Ê',
  'I\u0300': 'Ì',
  'I\u0301': 'Í',
  'I\u0302': 'Î',
  'O\u0300': 'Ò',
  'O\u0301': 'Ó',
  'O\u0302': 'Ô',
  'O\u0303': 'Õ',
  'U\u0300': 'Ù',
  'U\u0301': 'Ú',
  'U\u0302': 'Û',
  'Y\u0301': 'Ý',
  'a\u0300': 'à',
  'a\u0301': 'á',
  'a\u0302': 'â',
  'a\u0303': 'ã',
  'e\u0300': 'è',
  'e\u0301': 'é',
  'e\u0302': 'ê',
  'i\u0300': 'ì',
  'i\u0301': 'í',
  'i\u0302': 'î',
  'o\u0300': 'ò',
  'o\u0301': 'ó',
  'o\u0302': 'ô',
  'o\u0303': 'õ',
  'u\u0300': 'ù',
  'u\u0301': 'ú',
  'u\u0302': 'û',
  'y\u0301': 'ý',
  'A\u0306': 'Ă',
  'a\u0306': 'ă',
  'E\u0306': 'Ĕ',
  'e\u0306': 'ĕ',
  'I\u0303': 'Ĩ',
  'i\u0303': 'ĩ',
  'I\u0306': 'Ĭ',
  'i\u0306': 'ĭ',
  'O\u0306': 'Ŏ',
  'o\u0306': 'ŏ',
  'U\u0303': 'Ũ',
  'u\u0303': 'ũ',
  'U\u0306': 'Ŭ',
  'u\u0306': 'ŭ',
  'Y\u0302': 'Ŷ',
  'y\u0302': 'ŷ',
  'O\u0303\u0301': 'Ṍ',
  'o\u0303\u0301': 'ṍ',
  'U\u0303\u0301': 'Ṹ',
  'u\u0303\u0301': 'ṹ',
  'A\u0323': 'Ạ',
  'a\u0323': 'ạ',
  'A\u0309': 'Ả',
  'a\u0309': 'ả',
  'A\u0302\u0301': 'Ấ',
  'a\u0302\u0301': 'ấ',
  'A\u0302\u0300': 'Ầ',
  'a\u0302\u0300': 'ầ',
  'A\u0302\u0309': 'Ẩ',
  'a\u0302\u0309': 'ẩ',
  'A\u0302\u0303': 'Ẫ',
  'a\u0302\u0303': 'ẫ',
  'A\u0323\u0302': 'Ậ',
  'a\u0323\u0302': 'ậ',
  'A\u0306\u0301': 'Ắ',
  'a\u0306\u0301': 'ắ',
  'A\u0306\u0300': 'Ằ',
  'a\u0306\u0300': 'ằ',
  'A\u0306\u0309': 'Ẳ',
  'a\u0306\u0309': 'ẳ',
  'A\u0306\u0303': 'Ẵ',
  'a\u0306\u0303': 'ẵ',
  'A\u0323\u0306': 'Ặ',
  'a\u0323\u0306': 'ặ',
  'E\u0323': 'Ẹ',
  'e\u0323': 'ẹ',
  'E\u0309': 'Ẻ',
  'e\u0309': 'ẻ',
  'E\u0303': 'Ẽ',
  'e\u0303': 'ẽ',
  'E\u0302\u0301': 'Ế',
  'e\u0302\u0301': 'ế',
  'E\u0302\u0300': 'Ề',
  'e\u0302\u0300': 'ề',
  'E\u0302\u0309': 'Ể',
  'e\u0302\u0309': 'ể',
  'E\u0302\u0303': 'Ễ',
  'e\u0302\u0303': 'ễ',
  'E\u0323\u0302': 'Ệ',
  'e\u0323\u0302': 'ệ',
  'I\u0309': 'Ỉ',
  'i\u0309': 'ỉ',
  'I\u0323': 'Ị',
  'i\u0323': 'ị',
  'O\u0323': 'Ọ',
  'o\u0323': 'ọ',
  'O\u0309': 'Ỏ',
  'o\u0309': 'ỏ',
  'O\u0302\u0301': 'Ố',
  'o\u0302\u0301': 'ố',
  'O\u0302\u0300': 'Ồ',
  'o\u0302\u0300': 'ồ',
  'O\u0302\u0309': 'Ổ',
  'o\u0302\u0309': 'ổ',
  'O\u0302\u0303': 'Ỗ',
  'o\u0302\u0303': 'ỗ',
  'O\u0323\u0302': 'Ộ',
  'o\u0323\u0302': 'ộ',
  'O\u031b\u0301': 'Ớ',
  'o\u031b\u0301': 'ớ',
  'O\u031b\u0300': 'Ờ',
  'o\u031b\u0300': 'ờ',
  'O\u031b\u0309': 'Ở',
  'o\u031b\u0309': 'ở',
  'O\u031b\u0303': 'Ỡ',
  'o\u031b\u0303': 'ỡ',
  'O\u031b\u0323': 'Ợ',
  'o\u031b\u0323': 'ợ',
  'U\u0323': 'Ụ',
  'u\u0323': 'ụ',
  'U\u0309': 'Ủ',
  'u\u0309': 'ủ',
  'U\u031b\u0301': 'Ứ',
  'u\u031b\u0301': 'ứ',
  'U\u031b\u0300': 'Ừ',
  'u\u031b\u0300': 'ừ',
  'U\u031b\u0309': 'Ử',
  'u\u031b\u0309': 'ử',
  'U\u031b\u0303': 'Ữ',
  'u\u031b\u0303': 'ữ',
  'U\u031b\u0323': 'Ự',
  'u\u031b\u0323': 'ự',
  'Y\u0300': 'Ỳ',
  'y\u0300': 'ỳ',
  'Y\u0323': 'Ỵ',
  'y\u0323': 'ỵ',
  'Y\u0309': 'Ỷ',
  'y\u0309': 'ỷ',
  'Y\u0303': 'Ỹ',
  'y\u0303': 'ỹ',
  'o\u031b': 'ơ',
  'u\u031b': 'ư',
  'O\u031b': 'Ơ',
  'U\u031b': 'Ư',
};

const _thanMoc = {'ơ': 'o\u031b', 'ư': 'u\u031b', 'Ơ': 'O\u031b', 'Ư': 'U\u031b'};

/// Chữ có dấu tiếng Việt → (thân, các dấu trên, dấu dưới) dạng tổ hợp: "ố" → ("o", "\u0302\u0301", ""), "ợ" → ("ơ",
/// "", "\u0323"). Thân giữ móc (ơ, ư). null nếu không phải chữ có dấu.
(String, String, String)? tachDau(String ch) => _bangDau[ch];

/// Ghép dấu rời [dau] (bàn phím gõ dấu rời, Unicode tổ hợp) vào chữ [truoc]: "o" + "\u0302" → "ô", "ô" + "\u0323" →
/// "ộ". null nếu không thành chữ tiếng Việt.
String? ghepDauRoi(String truoc, String dau) {
  var than = truoc, tren = '', duoi = '';
  final t = _bangDau[truoc];
  if (t != null) (than, tren, duoi) = t;
  if (dau == '\u0323') {
    duoi = dau;
  } else if (dau == '\u031b') {
    than = {'o': 'ơ', 'u': 'ư', 'O': 'Ơ', 'U': 'Ư'}[than] ?? than;
  } else {
    tren += dau;
  }
  if (tren.isEmpty && duoi.isEmpty) return than == truoc ? null : than;
  return _bangGhep['${_thanMoc[than] ?? than}$duoi$tren'];
}

/// Mặt nạ (thân, dấu trên, dấu dưới) của mẫu chép [m] (đã phóng theo tỉ lệ, tiLe = 1), chia theo thành phần liên
/// thông: nằm hẳn trên đỉnh thân chữ là dấu trên, nằm hẳn dưới đường chân là dấu dưới. Mặt nạ mẫu đã nới 1 điểm ảnh
/// làm dấu sát thân dính vào thân: tách trên lõi (co lại 3×3), rồi nới nhãn ra như cũ.
(Uint8List, Uint8List, Uint8List) _tachPhan(Manh m, bool hoa, double xh) {
  final w = m.mau!.w, h = m.mau!.h, mat = m.matMau!;
  final loi = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var du = mat[y * w + x] != 0;
      for (var yy = y - 1; yy <= y + 1 && du; yy++) {
        for (var xx = x - 1; xx <= x + 1; xx++) {
          if (yy < 0 || yy >= h || xx < 0 || xx >= w || mat[yy * w + xx] == 0) {
            du = false;
            break;
          }
        }
      }
      if (du) loi[y * w + x] = 1;
    }
  }
  final (nhan, tk) = _thanhPhan(loi, w, h);
  final chan = m.chanMau, dinh = chan - (hoa ? 1.4 : 1.0) * xh;
  final loai = Uint8List(tk.length);
  for (var i = 1; i < tk.length; i++) {
    final y0 = tk[i][1], y1 = tk[i][1] + tk[i][3];
    loai[i] = y1 <= dinh + 0.2 * xh ? 2 : (y0 >= chan + 0.05 * xh && y1 - y0 < 0.6 * xh ? 3 : 1);
  }
  final than = Uint8List(w * h), tren = Uint8List(w * h), duoi = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (mat[y * w + x] == 0) continue;
      var n = 0;
      for (var yy = math.max(0, y - 1); yy <= math.min(h - 1, y + 1); yy++) {
        for (var xx = math.max(0, x - 1); xx <= math.min(w - 1, x + 1); xx++) {
          n = math.max(n, nhan[yy * w + xx]);
        }
      }
      final l = loai[n];
      if (l == 2) {
        tren[y * w + x] = 1;
      } else if (l == 3) {
        duoi[y * w + x] = 1;
      } else if (l == 1) {
        than[y * w + x] = 1;
      }
    }
  }
  return (than, tren, duoi);
}

/// Mẫu chép sau khi phóng theo tỉ lệ cỡ (tiLe = 1).
Manh _phong(Manh m) {
  if (m.tiLe == 1.0) return m;
  final w2 = math.max(1, (m.mau!.w * m.tiLe).round()), h2 = math.max(1, (m.mau!.h * m.tiLe).round());
  final mat = Uint8List(w2 * h2);
  for (var y = 0; y < h2; y++) {
    final sy = math.min(m.mau!.h - 1, (y * m.mau!.h / h2).floor());
    for (var x = 0; x < w2; x++) {
      mat[y * w2 + x] = m.matMau![sy * m.mau!.w + math.min(m.mau!.w - 1, (x * m.mau!.w / w2).floor())];
    }
  }
  return Manh('chep', m.chu, mau: m.mau!.doiCo(w2, h2), matMau: mat, chanMau: m.chanMau * m.tiLe, chuaChac: m.chuaChac, diem: m.diem);
}

/// Khung (x0, y0, x1, y1) các điểm 1 của mặt nạ, null nếu trống.
(int, int, int, int)? _khungMat(Uint8List mat, int w, int h) {
  var l = w, t = h, r = -1, b = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (mat[y * w + x] == 0) continue;
      l = math.min(l, x);
      r = math.max(r, x);
      t = math.min(t, y);
      b = math.max(b, y);
    }
  }
  return r < 0 ? null : (l, t, r + 1, b + 1);
}

/// Chữ có dấu [ch] ghép từ mẫu: thân chữ (ưu tiên chữ không dấu; chữ cùng thân khác dấu thì bỏ dấu cũ) và cụm dấu trên,
/// dấu dưới chép từ chữ khác có đúng các dấu ấy (ưu tiên cùng thân). Cụm dấu đặt so với thân như ở chữ nguồn (cách đỉnh
/// thân, lệch ngang so với tâm thân). Dùng khi không có sẵn chữ đó hoặc chỉ có ở kiểu nét khác: chữ có dấu hiếm gặp
/// (ố, ặ, ữ…) thường chỉ có một hai mẫu trên trang. Như ghep_dau() bản PC.
Future<Manh?> ghepDau(List<TrangNguon> nguon, DongAnh dich, String ch, double khe, double damDich) async {
  final t = tachDau(ch);
  if (t == null) return null;
  final (than, tren, duoi) = t;
  Future<(Manh, (Uint8List, Uint8List, Uint8List))> mau(ChonMau k) async {
    final a = await nguon[k.trang].layAnh();
    final m = _phong(manhChep(a, k.dong, k.kyTu, khe, tiLe: k.tiLe, chuaChac: k.trang > 0, cacDong: nguon[k.trang].dong));
    final chu = k.kyTu.chu;
    return (m, _tachPhan(m, chu.toUpperCase() == chu && chu.toLowerCase() != chu, xCao(k.dong) * k.tiLe));
  }

  // thân
  Manh? mThan;
  Uint8List? matThan;
  var diem = 0.0;
  for (final k in _ungVien(nguon, dich, (x) => x == than || tachDau(x)?.$1 == than, damDich, them: (x) => x == than ? 0 : 0.4).take(6)) {
    final (m, (mt, mtr, md)) = await mau(k);
    final td = tachDau(k.kyTu.chu);
    // chữ có dấu làm thân: phải tách được đúng phần dấu của nó, không thì thân còn dính dấu cũ
    if (td != null && ((td.$2.isNotEmpty && !mtr.contains(1)) || (td.$3.isNotEmpty && !md.contains(1)))) continue;
    if (_khungMat(mt, m.mau!.w, m.mau!.h) == null) continue;
    mThan = m;
    matThan = mt;
    diem = k.diem;
    break;
  }
  if (mThan == null || matThan == null) return null;
  final w = mThan.mau!.w, h = mThan.mau!.h;
  final kThan = _khungMat(matThan, w, h)!;
  // nền: trung vị từng kênh các điểm sáng của mẫu thân; rồi dán nét thân
  final xam = mThan.mau!.xamVung(0, 0, w, h);
  final nguong = _nen(xam) - 3;
  final dem = [List<int>.filled(256, 0), List<int>.filled(256, 0), List<int>.filled(256, 0)];
  var n = 0;
  for (var i = 0; i < w * h; i++) {
    if (xam[i] < nguong) continue;
    for (var k = 0; k < 3; k++) {
      dem[k][mThan.mau!.bgr[i * 3 + k]]++;
    }
    n++;
  }
  final nen = [for (var k = 0; k < 3; k++) n == 0 ? 255 : _thuK(dem[k], (n - 1) ~/ 2)];
  final anhRa = AnhBgr(w, h, Uint8List(w * h * 3));
  final matRa = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    for (var k = 0; k < 3; k++) {
      anhRa.bgr[i * 3 + k] = matThan[i] == 1 ? mThan.mau!.bgr[i * 3 + k] : nen[k];
    }
    matRa[i] = matThan[i];
  }
  var chuaChac = mThan.chuaChac;
  for (final (dau, phan) in [(tren, 1), (duoi, 2)]) {
    if (dau.isEmpty) continue;
    var dat = false;
    // dấu thanh nhỏ, dáng gần như nhau ở chữ đậm, chữ thường: không xét độ đậm nét khi chọn dấu
    final ds = _ungVien(nguon, dich, (x) => (phan == 1 ? tachDau(x)?.$2 : tachDau(x)?.$3) == dau, damDich,
        them: (x) => tachDau(x)?.$1 == than ? 0 : 0.2, xetDam: false);
    for (final k in ds.take(6)) {
      final (m, parts) = await mau(k);
      final mw = m.mau!.w, mh = m.mau!.h;
      final md = phan == 1 ? parts.$2 : parts.$3;
      final kt = _khungMat(parts.$1, mw, mh), kd = _khungMat(md, mw, mh);
      if (kt == null || kd == null) continue;
      // vị trí cụm dấu so với thân ở chữ nguồn → áp sang thân mới
      final lechX = (kd.$1 + kd.$3) / 2 - (kt.$1 + kt.$3) / 2;
      final dy = phan == 1 ? (kThan.$2 - (kt.$2 - kd.$4)) - kd.$4 : (mThan.chanMau + (kd.$2 - m.chanMau)) - kd.$2;
      final dx = ((kThan.$1 + kThan.$3) / 2 + lechX - (kd.$1 + kd.$3) / 2).round(), dyr = dy.round();
      var tong = 0, trong = 0;
      for (var y = 0; y < mh; y++) {
        for (var x = 0; x < mw; x++) {
          if (md[y * mw + x] == 0) continue;
          tong++;
          final ty = y + dyr, tx = x + dx;
          if (ty >= 0 && ty < h && tx >= 0 && tx < w) trong++;
        }
      }
      if (tong == 0 || trong < 0.8 * tong) continue;
      for (var y = 0; y < mh; y++) {
        for (var x = 0; x < mw; x++) {
          if (md[y * mw + x] == 0) continue;
          final ty = y + dyr, tx = x + dx;
          if (ty < 0 || ty >= h || tx < 0 || tx >= w) continue;
          for (var c = 0; c < 3; c++) {
            anhRa.bgr[(ty * w + tx) * 3 + c] = m.mau!.bgr[(y * mw + x) * 3 + c];
          }
          matRa[ty * w + tx] = 1;
        }
      }
      chuaChac = chuaChac || m.chuaChac;
      dat = true;
      break;
    }
    if (!dat) return null;
  }
  return Manh('chep', ch, mau: anhRa, matMau: matRa, chanMau: mThan.chanMau, chuaChac: chuaChac, diem: diem + 0.3);
}

/// Dãy mảnh chấm dẫn (≥ 5 mảnh gốc "." liền nhau đầu tiên): (đầu, cuối không tính), hoặc null.
(int, int)? _dayCham(List<Manh> manh) {
  var i = 0;
  while (i < manh.length) {
    var j = i;
    while (j < manh.length && manh[j].chu == '.' && manh[j].loai == 'goc') {
      j++;
    }
    if (j - i >= 5) return (i, j);
    i = j + 1;
  }
  return null;
}

/// Dòng có dãy dấu chấm dẫn (mục lục): bớt, thêm dấu chấm ở cuối dãy để dòng dài đúng như cũ, nên số trang cuối
/// dòng đứng nguyên chỗ dù sửa chữ phía trước hay sửa chính số trang. Chấm thêm chép từ chấm cuối dãy (chấm đầu có
/// thể dính đuôi chữ đứng trước). Phần lẻ dưới một chấm chia vào khe các chấm cuối dãy.
List<Manh> canChamDan(List<Manh> manh, int rongCu) {
  final day = _dayCham(manh);
  if (day == null) return manh;
  var (i, j) = day;
  final kq = [for (final m in manh) m.banSao()];
  var lech = kq.fold<int>(0, (s, m) => s + m.rong) - rongCu;
  while (lech > 0 && j - i > 3) {
    lech -= kq[j - 1].rong;
    kq.removeAt(j - 1);
    j--;
  }
  final mau = kq[j - 1];
  while (mau.rong > 0 && lech <= -mau.rong) {
    kq.insert(j, mau.banSao());
    lech += mau.rong;
    j++;
  }
  // phần lẻ: nới, thu khe từng chấm 1 điểm ảnh, từ cuối dãy lên
  var k = j - 1;
  while (lech != 0 && k >= i) {
    final d = lech < 0 ? 1 : -1;
    kq[k].x1 += d;
    lech += d;
    k--;
  }
  return kq;
}

// ---------------------------------------------------------------- dựng lại dòng

double _nen(Uint8List xam) => _phanVi8(xam, 90);

/// Dựng lại một dòng từ các mảnh: mảnh gốc đứng yên thì không đụng tới; mảnh gốc phải dời thì chỉ nét mực của dòng
/// được xóa chỗ cũ (vá nền) và dán sang chỗ mới, đi theo độ dốc của dòng; mảnh chép hòa theo độ phủ mực.
class SuaDong {
  SuaDong(this.x0, this.x1Cu, this.dai0, this.dai1, this.chan, this.manh,
      {this.chuCu = '', this.nghieng = 0, this.xChan = 0, this.net, this.khac, this.netW = 0});

  final int x0; // mép trái dòng (mảnh đầu bắt đầu ở đây)
  final int x1Cu; // mép phải dòng cũ
  final int dai0, dai1; // dải dọc của dòng
  final double chan;
  final List<Manh> manh;
  final String chuCu;
  final double nghieng, xChan;
  final Uint8List? net; // nét của dòng: cột [x0, x0 + netW) × dải (netCuaDong)
  final Uint8List? khac; // nét chỗ khác trong cùng vùng
  final int netW;

  double chanTai(num x) => chan + nghieng * (x - xChan);

  String get chuMoi => manh.map((m) => m.chu).join();

  int get rong => manh.fold<int>(0, (s, m) => s + m.rong);

  String moTa() {
    String rut(String x) => x.length <= 40 ? x : '${x.substring(0, 38)}…';
    return 'Sửa ký tự: “${rut(chuCu)}” → “${rut(chuMoi)}”';
  }

  /// Ảnh trang sau khi sửa (bản sao; [anh] giữ nguyên).
  AnhBgr ap(AnhBgr anh) {
    final ra = anh.banSao();
    _dung(anh, ra, 0);
    return ra;
  }

  /// Các hàng ảnh bị vẽ lại: dải dòng, nới thêm chỗ chữ đổi cỡ, đổi phông nhô ra ngoài dải (chữ phóng to).
  (int, int) vungVe(int caoTrang) {
    var v0 = dai0, v1 = dai1, x = x0;
    for (final m in manh) {
      final w = m.rong;
      if (m.doiDinhDang) {
        if (m.loai == 'chep') {
          final h = math.max(1, (m.mau!.h * m.tiLe).round());
          final dy = (chanTai(x + w / 2) - m.chanMau * m.tiLe).round();
          v0 = math.min(v0, dy);
          v1 = math.max(v1, dy + h);
        } else if (m.hinh != null) {
          final oy = (chanTai(x) - m.hinh!.chan).round();
          v0 = math.min(v0, oy);
          v1 = math.max(v1, oy + m.hinh!.h);
        }
      }
      x += w;
    }
    return (math.max(0, v0), math.min(caoTrang, v1));
  }

  /// Chỉ các hàng bị vẽ lại ([vungVe], cả bề ngang trang): xem trước nhanh khi đang sửa.
  AnhBgr apDai(AnhBgr anh) {
    final (v0, v1) = vungVe(anh.h);
    final ra = anh.cat(0, v0, anh.w, v1);
    _dung(anh, ra, v0);
    return ra;
  }

  /// Dựng dòng vào [ra]: hàng r của [ra] ứng với hàng r + [yLech] của [nguon].
  void _dung(AnhBgr nguon, AnhBgr ra, int yLech) {
    final rongTrang = nguon.w;
    final y0 = dai0, y1 = dai1, h = y1 - y0;
    if (h <= 0) return;
    var nw = netW;
    Uint8List net, khac;
    if (this.net == null || this.net!.length != nw * h) {
      // thao tác tạo không qua phiên sửa: coi mọi nét trong dải là của dòng
      nw = math.max(0, math.min(rongTrang, x1Cu) - x0);
      net = _mucOtsu(nguon.xamVung(x0, y0, x0 + nw, y1));
      khac = Uint8List(net.length);
    } else {
      net = this.net!;
      khac = this.khac ?? Uint8List(net.length);
    }
    // viền nhòe quanh nét (1 điểm ảnh) đi cùng nét, nhưng không lấn nét chỗ khác
    final no = _no3(net, nw, h);
    for (var i = 0; i < no.length; i++) {
      if (khac[i] == 1) no[i] = 0;
    }
    final dat = <int>[];
    var x = x0;
    for (final m in manh) {
      dat.add(x);
      x += m.rong;
    }
    final xHet = math.min(rongTrang, math.max(x1Cu, x));
    final rw = math.max(0, xHet - x0);
    // mảnh gốc đứng nguyên chỗ: không đụng tới (chữ không sửa giữ nguyên từng điểm ảnh)
    final yen = List<bool>.filled(rw, false);
    for (var i = 0; i < manh.length; i++) {
      final m = manh[i];
      if (m.loai != 'goc' || m.x0 != dat[i]) continue;
      for (var c = math.max(0, dat[i] - x0); c < math.min(xHet, dat[i] + m.rong) - x0; c++) {
        yen[c] = true;
      }
    }
    // xóa nét của dòng ở các cột còn lại, vá nền
    final xoa = Uint8List(rw * h), dung = Uint8List(rw * h);
    for (var yy = 0; yy < h; yy++) {
      for (var c = 0; c < rw; c++) {
        final trong = c < nw;
        final laNet = trong && (no[yy * nw + c] == 1 || khac[yy * nw + c] == 1);
        if (trong && !yen[c] && no[yy * nw + c] == 1) xoa[yy * rw + c] = 1;
        if (!laNet) dung[yy * rw + c] = 1;
      }
    }
    _vaNen(ra, yLech, x0, y0, rw, h, xoa, dung);
    for (var i = 0; i < manh.length; i++) {
      final m = manh[i], xt = dat[i];
      if (xt >= rongTrang) break;
      if (m.loai == 'goc') {
        if (m.x0 == xt) continue;
        // dời nét của mảnh theo dòng: ngang dx, dọc theo độ dốc
        final dx = xt - m.x0, dy = (nghieng * dx).round();
        final c0 = m.x0 - x0;
        if (c0 < 0 || c0 >= nw) continue;
        final cHet = math.min(nw, c0 + m.rong);
        for (var yy = 0; yy < h; yy++) {
          final ty = y0 + yy + dy - yLech;
          if (ty < 0 || ty >= ra.h) continue;
          for (var c = c0; c < cHet; c++) {
            if (no[yy * nw + c] == 0) continue;
            final tx = x0 + c + dx;
            if (tx < 0 || tx >= ra.w) continue;
            // không đè lên nét dòng khác ở chỗ mới (đuôi chữ dòng trên, dấu dòng dưới)
            final rr = yy + dy, cc = c + dx;
            if (rr >= 0 && rr < h && cc >= 0 && cc < nw && khac[rr * nw + cc] == 1) continue;
            final p = (ty * ra.w + tx) * 3, q = ((y0 + yy) * rongTrang + x0 + c) * 3;
            ra.bgr[p] = nguon.bgr[q];
            ra.bgr[p + 1] = nguon.bgr[q + 1];
            ra.bgr[p + 2] = nguon.bgr[q + 2];
          }
        }
      } else if (m.loai == 'chep') {
        _danChep(ra, yLech, m, xt);
      } else if (m.hinh != null) {
        _danVe(ra, yLech, m.hinh!, xt, ngoaiDai: m.doiDinhDang);
      }
    }
  }

  /// Vá nền chỗ [xoa] (vùng rw × h bắt đầu ở cột [vx], hàng [vy] của trang): mỗi điểm lấy trung bình các điểm nền gần
  /// nhất theo bốn hướng trong vùng ([dung] = 1: điểm nền dùng được), nặng nhẹ theo nghịch đảo khoảng cách. Giữ được
  /// vân giấy, bóng sáng tối của ảnh chụp tốt hơn tô một màu.
  static void _vaNen(AnhBgr ra, int yLech, int vx, int vy, int rw, int h, Uint8List xoa, Uint8List dung) {
    if (!xoa.contains(1)) return;
    final n = rw * h;
    final trai = Int32List(n), phai = Int32List(n), len = Int32List(n), xuong = Int32List(n);
    for (var y = 0; y < h; y++) {
      var gan = -1;
      for (var c = 0; c < rw; c++) {
        final p = y * rw + c;
        if (dung[p] == 1) gan = c;
        trai[p] = gan;
      }
      gan = -1;
      for (var c = rw - 1; c >= 0; c--) {
        final p = y * rw + c;
        if (dung[p] == 1) gan = c;
        phai[p] = gan;
      }
    }
    for (var c = 0; c < rw; c++) {
      var gan = -1;
      for (var y = 0; y < h; y++) {
        final p = y * rw + c;
        if (dung[p] == 1) gan = y;
        len[p] = gan;
      }
      gan = -1;
      for (var y = h - 1; y >= 0; y--) {
        final p = y * rw + c;
        if (dung[p] == 1) gan = y;
        xuong[p] = gan;
      }
    }
    // đọc điểm nền từ bản chưa vá (điểm vá trước không làm nguồn cho điểm vá sau)
    final goc = Uint8List(n * 3);
    for (var y = 0; y < h; y++) {
      final ty = vy + y - yLech;
      if (ty < 0 || ty >= ra.h) continue;
      goc.setRange(y * rw * 3, (y + 1) * rw * 3, ra.bgr, (ty * ra.w + vx) * 3);
    }
    for (var y = 0; y < h; y++) {
      final ty = vy + y - yLech;
      if (ty < 0 || ty >= ra.h) continue;
      for (var c = 0; c < rw; c++) {
        final p = y * rw + c;
        if (xoa[p] == 0) continue;
        var sw = 0.0, s0 = 0.0, s1 = 0.0, s2 = 0.0;
        void them(int q, int kc) {
          final wt = 1 / kc;
          sw += wt;
          s0 += goc[q * 3] * wt;
          s1 += goc[q * 3 + 1] * wt;
          s2 += goc[q * 3 + 2] * wt;
        }

        if (trai[p] >= 0) them(y * rw + trai[p], c - trai[p]);
        if (phai[p] >= 0) them(y * rw + phai[p], phai[p] - c);
        if (len[p] >= 0) them(len[p] * rw + c, y - len[p]);
        if (xuong[p] >= 0) them(xuong[p] * rw + c, xuong[p] - y);
        if (sw == 0) continue;
        final o = (ty * ra.w + vx + c) * 3;
        ra.bgr[o] = (s0 / sw).round();
        ra.bgr[o + 1] = (s1 / sw).round();
        ra.bgr[o + 2] = (s2 / sw).round();
      }
    }
  }

  /// Chép ký tự mẫu: căn theo đường chân chữ, hòa theo độ phủ mực (nền của mẫu không đè lên dòng đích).
  void _danChep(AnhBgr ra, int yLech, Manh m, int x) {
    var mau = m.mau!;
    var chanMau = m.chanMau;
    var mat = Float32List.fromList([for (final v in m.matMau!) v.toDouble()]);
    if (m.tiLe != 1.0) {
      final w2 = math.max(1, (mau.w * m.tiLe).round()), h2 = math.max(1, (mau.h * m.tiLe).round());
      final cu = mau;
      mau = mau.doiCo(w2, h2);
      chanMau *= m.tiLe;
      mat = _doiCoMat(m.matMau!, cu.w, cu.h, w2, h2);
    }
    final w = mau.w, h = mau.h;
    final xam = mau.xamVung(0, 0, w, h);
    final nen = m.nenMuc?.$1 ?? _nen(xam), muc = m.nenMuc?.$2 ?? _phanVi8(xam, 3);
    // đặt sao cho đường chân của mẫu trùng đường chân dòng đích tại chỗ chèn; chữ đổi cỡ được nhô ra ngoài dải dòng
    final dy = (chanTai(x + w / 2) - chanMau).round();
    final lo = m.doiDinhDang ? yLech : dai0, hi = m.doiDinhDang ? yLech + ra.h : dai1;
    final ty0 = math.max(lo, dy), ty1 = math.min(hi, dy + h);
    final tx0 = math.max(0, x), tx1 = math.min(ra.w, x + w);
    final mauMuc = m.mauMuc, khac = this.khac;
    final kh = khac == null || netW == 0 ? 0 : khac.length ~/ netW;
    for (var y = ty0; y < ty1; y++) {
      for (var xx = tx0; xx < tx1; xx++) {
        final i = (y - dy) * w + xx - x;
        final a = ((nen - xam[i]) / math.max(nen - muc, 1)).clamp(0.0, 1.0) * mat[i];
        if (a <= 0) continue;
        // không phủ lên nét dòng khác (đuôi chữ dòng trên, dấu dòng dưới lọt vào dải)
        final rr = y - dai0, cc = xx - x0;
        if (khac != null && rr >= 0 && rr < kh && cc >= 0 && cc < netW && khac[rr * netW + cc] == 1) continue;
        final p = ((y - yLech) * ra.w + xx) * 3;
        for (var k = 0; k < 3; k++) {
          // tô bằng màu mực của chữ quanh chỗ chèn: mẫu chép từ chỗ ảnh sáng hơn, tối hơn vẫn đậm nhạt đều
          final mu = mauMuc != null ? mauMuc[k] : mau.bgr[i * 3 + k];
          ra.bgr[p + k] = (ra.bgr[p + k] * (1 - a) + mu * a).round().clamp(0, 255);
        }
      }
    }
  }

  /// Chữ vẽ bằng phông: gốc bút ở (x, đường chân dòng). [ngoaiDai]: chữ đổi cỡ, đổi phông được nhô ra ngoài dải dòng.
  void _danVe(AnhBgr ra, int yLech, HinhVe v, int x, {bool ngoaiDai = false}) {
    final ox = (x - v.gocX).round(), oy = (chanTai(x) - v.chan).round();
    final lo = ngoaiDai ? yLech : dai0, hi = ngoaiDai ? yLech + ra.h : dai1;
    final khac = this.khac;
    final kh = khac == null || netW == 0 ? 0 : khac.length ~/ netW;
    for (var y = math.max(lo, oy); y < math.min(hi, oy + v.h); y++) {
      for (var xx = math.max(0, ox); xx < math.min(ra.w, ox + v.w); xx++) {
        final al = v.phu[(y - oy) * v.w + xx - ox];
        if (al == 0) continue;
        // không vẽ đè lên nét dòng khác lọt vào dải
        final rr = y - dai0, cc = xx - x0;
        if (khac != null && rr >= 0 && rr < kh && cc >= 0 && cc < netW && khac[rr * netW + cc] == 1) continue;
        final p = ((y - yLech) * ra.w + xx) * 3;
        for (var k = 0; k < 3; k++) {
          ra.bgr[p + k] = (ra.bgr[p + k] * (255 - al) + v.mau[k] * al + 127) ~/ 255;
        }
      }
    }
  }
}

/// Phóng, thu mặt nạ 0/1 (nội suy tuyến tính) thành độ phủ 0–1.
Float32List _doiCoMat(Uint8List mat, int w, int h, int w2, int h2) {
  final m = cv.Mat.zeros(h, w, cv.MatType.CV_8UC1);
  final d = m.data;
  for (var i = 0; i < mat.length; i++) {
    d[i] = mat[i] * 255;
  }
  final r = cv.resize(m, (w2, h2), interpolation: cv.INTER_LINEAR);
  final ra = Float32List.fromList([for (final v in r.data) v / 255]);
  m.dispose();
  r.dispose();
  return ra;
}

// ---------------------------------------------------------------- phiên sửa một dòng (con trỏ, xóa, chèn)

/// Vẽ ký tự cả hồ sơ không có, bằng phông đoán theo dòng (cần dart:ui: ve_chu.dart cung cấp).
abstract class BoVeKyTu {
  /// Cỡ chữ (fontSize, điểm ảnh) đoán được.
  double get coPx;

  /// Chiều cao nét mực của [ch] vẽ ở cỡ [co].
  Future<double> caoMuc(String ch, double co);

  Future<HinhVe> ve(String ch, double co);

  /// Đoán phông, cỡ, màu của các ký tự [ky] (đoạn bôi chọn) trên trang.
  Future<DinhDangVe> doan(List<KyTu> ky);

  /// Vẽ [ch] theo phông, cỡ, màu người dùng chọn.
  Future<HinhVe> veTheo(String ch, DinhDangVe k);
}

/// Sửa một dòng bằng con trỏ: trái, phải, xóa lùi, xóa tới, chèn chuỗi, đặt mẫu tay. Xem trước bằng `thaoTac().apDai(anh)`.
class PhienSuaDong {
  /// [trangKhac]: các trang khác của hồ sơ (danh sách có thể dài thêm khi nhận dạng nền xong) để tìm ký tự mẫu khi
  /// trang này không có. [taoBoVe]: vẽ ký tự cả hồ sơ không có (null: để trống chỗ, vẫn đánh dấu chưa chắc).
  PhienSuaDong(this.anh, this.trang, this.dong, {double? xBam, List<TrangNguon>? trangKhac, this.taoBoVe})
      : trangKhac = trangKhac ?? [] {
    goc = manhDong(dong, anh);
    manh = [...goc];
    khe = trang.khe;
    x0 = goc.isEmpty ? dong.x0 : goc.first.x0;
    x1Cu = goc.isEmpty ? dong.x1 : goc.last.x1;
    final (cua, conLai) = netCuaDong(anh, trang.dong, dong, x0, x1Cu);
    net = cua;
    khac = conLai;
    netW = math.max(0, math.min(anh.w, x1Cu) - math.max(0, x0));
    conTro = xBam == null ? manh.length : _viTriGan(xBam);
    // nền, lõi mực đo trên cả dòng: cho nét gốc phóng, thu (mảnh hẹp như "i", "." đo riêng sẽ lệch)
    final xam = anh.xamVung(x0, dong.dai0, x0 + netW, dong.dai1);
    final loi = <int>[for (var i = 0; i < xam.length; i++) if (net[i] == 1) xam[i]];
    nenMuc = (_nen(xam), _phanVi8(Uint8List.fromList(loi.isEmpty ? xam : loi), 3));
  }

  final AnhBgr anh;
  final TrangKyTu trang;
  final DongAnh dong;
  final List<TrangNguon> trangKhac;
  final Future<BoVeKyTu> Function()? taoBoVe;
  late final TrangNguon _hien = TrangNguon(trang.dong, anh: anh);
  late final List<Manh> goc;
  late List<Manh> manh;
  late final double khe;
  late final int x0, x1Cu;
  late final Uint8List net, khac; // nét của dòng, nét chỗ khác trong vùng dòng (netCuaDong)
  late final int netW;
  late int conTro;
  final Map<String, Manh> mauTay = {}; // mẫu người dùng tự chọn cho từng ký tự
  final Set<String> thieu = {}; // ký tự cả hồ sơ không có, phải vẽ bằng phông
  Future<BoVeKyTu>? _boVe;
  int? moc; // đầu kia của đoạn bôi chọn (null: không chọn)
  (String, Object)? _kieuGo; // định dạng của đoạn chọn vừa xóa, cho chữ gõ thay vào
  late final (double, double) nenMuc;

  List<TrangNguon> get nguon => [_hien, ...trangKhac];

  /// Vị trí (x trên ảnh) của con trỏ ở từng chỗ 0..manh.length theo dòng đã dựng lại: dòng có dãy chấm dẫn co giãn
  /// thì phần sau dãy chấm neo theo mép phải như lúc dựng.
  List<int> bienConTro() {
    final b = <int>[x0];
    for (final m in manh) {
      b.add(b.last + m.rong);
    }
    final day = _dayCham(manh);
    if (day == null || !daDoi) return b;
    final cuoi = x0 + canChamDan(manh, x1Cu - x0).fold<int>(0, (s, m) => s + m.rong);
    var sau = 0;
    for (var k = manh.length; k >= day.$2; k--) {
      if (k < manh.length) sau += manh[k].rong;
      b[k] = cuoi - sau;
    }
    return b;
  }

  int xConTro() => bienConTro()[conTro];

  int _viTriGan(double x) {
    final b = bienConTro();
    var tot = 0;
    for (var i = 1; i < b.length; i++) {
      if ((b[i] - x).abs() < (b[tot] - x).abs()) tot = i;
    }
    return tot;
  }

  /// Đặt con trỏ; [chon]: giữ đầu kia, mở rộng đoạn bôi chọn.
  void _di(int vt, bool chon) {
    if (chon) {
      moc ??= conTro;
    } else {
      moc = null;
    }
    conTro = vt.clamp(0, manh.length);
    _kieuGo = null;
  }

  void datConTro(double x, {bool chon = false}) => _di(_viTriGan(x), chon);
  void trai({bool chon = false}) {
    final (a, b) = doanChon();
    _di(b > a && !chon ? a : conTro - 1, chon);
  }

  void phai({bool chon = false}) {
    final (a, b) = doanChon();
    _di(b > a && !chon ? b : conTro + 1, chon);
  }

  void dauDong({bool chon = false}) => _di(0, chon);
  void cuoiDong({bool chon = false}) => _di(manh.length, chon);

  /// Đoạn chọn [a, b) theo chỉ số mảnh; không chọn thì a = b = con trỏ.
  (int, int) doanChon() {
    final m = moc;
    return m == null ? (conTro, conTro) : (math.min(m, conTro), math.max(m, conTro));
  }

  bool get coChon {
    final (a, b) = doanChon();
    return b > a;
  }

  String get chuChon {
    final (a, b) = doanChon();
    return manh.sublist(a, b).map((m) => m.chu).join();
  }

  /// Bôi chọn bằng ngón tay: từ chỗ chạm [xa] tới chỗ kéo [xb] (tọa độ ảnh).
  void chonX(double xa, double xb) {
    moc = _viTriGan(xa);
    conTro = _viTriGan(xb);
    if (moc == conTro) moc = null;
    _kieuGo = null;
  }

  void chonCaDong() {
    moc = 0;
    conTro = manh.length;
  }

  /// Cột trên ảnh của hai đầu đoạn chọn.
  (int, int) xDoanChon() {
    final (a, b) = doanChon();
    final bien = bienConTro();
    return (bien[a], bien[b]);
  }

  bool _xoaChon() {
    final (a, b) = doanChon();
    moc = null;
    if (b <= a) return false;
    _kieuGo = _kieuCua(manh[a]);
    manh.removeRange(a, b);
    conTro = a;
    return true;
  }

  void xoaLui() {
    if (_xoaChon()) return;
    if (conTro > 0) {
      manh.removeAt(conTro - 1);
      conTro--;
    }
  }

  void xoaToi() {
    if (_xoaChon()) return;
    if (conTro < manh.length) manh.removeAt(conTro);
  }

  /// Chèn [chu] ở con trỏ (đang bôi chọn thì thay đoạn chọn, chữ gõ vào giữ định dạng của đoạn đó). Dấu thanh tổ hợp
  /// (bàn phím gõ dấu rời) đi kèm ký tự đứng trước.
  Future<void> go(String chu) async {
    // dấu rời (bàn phím gõ Unicode tổ hợp) ghép vào chữ đứng trước thành chữ dựng sẵn như máy đọc trả về; dấu rời gõ
    // sau một chữ vừa chèn thì gộp vào chữ đó
    final kyTu = <String>[];
    var dauRoi = <String>[];
    for (final r in chu.runes) {
      final s = String.fromCharCode(r);
      if (r >= 0x300 && r <= 0x36F) {
        final g = kyTu.isNotEmpty ? ghepDauRoi(kyTu.last, s) : null;
        if (g != null) {
          kyTu.last = g;
        } else if (kyTu.isEmpty) {
          dauRoi.add(s);
        }
      } else if (r != 0x0A && r != 0x0D) {
        kyTu.add(s == '\t' ? ' ' : s);
      }
    }
    if (kyTu.isNotEmpty) _xoaChon();
    if (dauRoi.isNotEmpty && conTro > 0 && manh[conTro - 1].loai != 'goc') {
      var g = manh[conTro - 1].chu;
      for (final d in dauRoi) {
        g = ghepDauRoi(g, d) ?? g;
      }
      if (g != manh[conTro - 1].chu) {
        conTro--;
        _kieuGo = _kieuCua(manh[conTro]);
        manh[conTro] = await _manhMoi(g);
        conTro++;
      }
    }
    dauRoi = [];
    for (final ch in kyTu) {
      final m = await _manhMoi(ch);
      manh.insert(conTro, m);
      conTro++;
      _kieuGo = null;
    }
    _kieuGo = null;
  }

  // ---------------------------------------------------------------- đổi cỡ, đổi phông đoạn chọn

  /// Định dạng người dùng đã đặt cho mảnh: ('ve', DinhDangVe) đổi phông, ('co', tỉ lệ) đổi cỡ, null giữ như gốc.
  static (String, Object)? _kieuCua(Manh m) {
    if (m.kieuVe != null) return ('ve', m.kieuVe!);
    if ((m.coDoi - 1).abs() > 1e-3) return ('co', m.coDoi);
    return null;
  }

  /// Chữ gõ thêm theo định dạng của chữ đứng trước con trỏ (đầu dòng thì chữ đứng sau), như trình soạn thảo.
  (String, Object)? _kieuTaiConTro() {
    if (_kieuGo != null) return _kieuGo;
    if (conTro > 0) return _kieuCua(manh[conTro - 1]);
    return manh.isEmpty ? null : _kieuCua(manh.first);
  }

  /// Mảnh gốc → mảnh chép chính nét của nó (để phóng, thu): chỉ nét mực của dòng, nền, mực đo trên cả dòng.
  Manh _gocSangChep(Manh m) {
    final y0 = dong.dai0, h = dong.dai1 - dong.dai0;
    final a0 = (m.x0 - x0).clamp(0, netW), a1 = (m.x1 - x0).clamp(0, netW);
    final w = math.max(1, a1 - a0);
    final cat = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var c = 0; c < a1 - a0; c++) {
        cat[y * w + c] = net[y * netW + a0 + c];
      }
    }
    final mat = _no3(cat, w, h);
    for (var y = 0; y < h; y++) {
      for (var c = 0; c < a1 - a0; c++) {
        if (khac[y * netW + a0 + c] == 1) mat[y * w + c] = 0;
      }
    }
    return Manh('chep', m.chu,
        mau: anh.cat(x0 + a0, y0, x0 + a0 + w, dong.dai1),
        matMau: mat,
        chanMau: dong.chanTai((m.x0 + m.x1) / 2) - y0,
        nenMuc: nenMuc);
  }

  /// Mảnh [g] (cỡ gốc) phóng, thu theo tỉ lệ [s] mà vẫn giữ nét: nét gốc, mẫu chép đổi cỡ điểm ảnh.
  Future<Manh> _phongTo(Manh g, double s) async {
    if ((s - 1).abs() <= 1e-3 && g.loai == 'goc') return g;
    final goc = g.loai == 'goc' ? g : g.banGoc;
    if (g.loai == 'goc' && g.chu.trim().isEmpty) return Manh('ve', g.chu, rongVe: g.rong * s, coDoi: s, banGoc: goc);
    if (g.loai == 'goc') {
      final c = _gocSangChep(g);
      return Manh('chep', c.chu, mau: c.mau, matMau: c.matMau, chanMau: c.chanMau, nenMuc: c.nenMuc, tiLe: s, coDoi: s, banGoc: goc);
    }
    if (g.loai == 'chep') return g.banSao(tiLe: g.tiLe * s, coDoi: s, banGoc: goc);
    // ký tự vẽ bằng phông (cả hồ sơ không có): vẽ lại ở cỡ mới
    final co = (g.coVe > 0 ? g.coVe : dong.co) * s;
    final tao = taoBoVe;
    HinhVe? hinh;
    if (tao != null && g.chu.trim().isNotEmpty) hinh = await (await (_boVe ??= tao())).ve(g.chu, co);
    return Manh('ve', g.chu,
        rongVe: g.rongVe * s, coVe: co, chuaChac: g.chuaChac, hinh: hinh ?? g.hinh, coDoi: s, banGoc: goc);
  }

  /// Mảnh như lúc chưa đổi cỡ, đổi phông: mảnh gốc của dòng, mẫu chép ở cỡ gốc, hoặc mẫu tìm lại cho chữ gõ thêm
  /// bằng phông.
  Future<Manh> _coGoc(Manh m) async {
    if (m.banGoc != null) return m.banGoc!;
    if (m.loai == 'goc') return m;
    if (m.kieuVe != null) return _manhMau(m.chu);
    if (m.loai == 'chep') return m.banSao(tiLe: m.tiLe / m.coDoi, coDoi: 1.0);
    return m.banSao(coDoi: 1.0, rongVe: m.rongVe / m.coDoi, coVe: m.coVe / m.coDoi);
  }

  Future<Manh> _manhPhong(String ch, DinhDangVe k, [Manh? banGoc]) async {
    final tao = taoBoVe;
    if (tao == null) return Manh('ve', ch, rongVe: 0.5 * k.co, coVe: k.co, kieuVe: k, banGoc: banGoc);
    final hinh = await (await (_boVe ??= tao())).veTheo(ch, k);
    return Manh('ve', ch, rongVe: hinh.rongChu, coVe: k.co, hinh: hinh, kieuVe: k, banGoc: banGoc);
  }

  /// Đổi định dạng đoạn bôi chọn. [kieu] null: giữ nét chữ gốc, chỉ phóng, thu theo [tiLe] (so với cỡ gốc; 1 là trả
  /// về như cũ, mảnh gốc đứng yên giữ nguyên từng điểm ảnh). Có [kieu]: vẽ lại đoạn chọn bằng phông, cỡ, màu đó (chữ
  /// theo nội dung máy đọc, người dùng soát lại). Phần sau đoạn chọn tự dồn theo bề rộng mới.
  Future<void> dinhDangChon({double tiLe = 1.0, DinhDangVe? kieu}) async {
    final (a, b) = doanChon();
    for (var i = a; i < b; i++) {
      final m = manh[i];
      final g = await _coGoc(m);
      manh[i] = kieu != null ? await _manhPhong(m.chu, kieu, g) : await _phongTo(g, tiLe);
    }
  }

  /// Định dạng đang có của đoạn chọn: (phông, cỡ, màu đoán trên nét gốc hoặc phông đã đặt; tỉ lệ cỡ so với gốc; đã
  /// đổi phông chưa). Đoán phông trên các ký tự gốc của đoạn; đoạn chỉ có chữ chèn thì đoán theo cả dòng. [boPhong]:
  /// bỏ qua phông đã đặt, đoán trên nét gốc (để trả đoạn về nét gốc ở một cỡ mới). Null nếu không có bộ vẽ phông.
  Future<(DinhDangVe, double, bool)?> kieuDoanChon({bool boPhong = false}) async {
    final (a, b) = doanChon();
    final doan = a < b ? manh.sublist(a, b) : manh.sublist(math.max(0, conTro - 1), math.min(manh.length, conTro + 1));
    final ve = [for (final m in doan) if (m.kieuVe != null) m.kieuVe!];
    if (ve.isNotEmpty && !boPhong) return (ve.first, 1.0, true);
    final tl = ve.isNotEmpty || doan.isEmpty ? 1.0 : _trungVi([for (final m in doan) m.coDoi]);
    final tao = taoBoVe;
    if (tao == null) return null;
    final cot = [
      for (final m in doan)
        if (m.loai == 'goc') (m.x0, m.x1) else if (m.banGoc?.loai == 'goc') (m.banGoc!.x0, m.banGoc!.x1)
    ];
    var ky = [
      for (final c in dong.kyTu)
        if (c.chu.trim().isNotEmpty && cot.any((k) => k.$1 <= (c.x0 + c.x1) / 2 && (c.x0 + c.x1) / 2 < k.$2)) c
    ];
    if (ky.isEmpty) ky = [for (final c in dong.kyTu) if (c.chu.trim().isNotEmpty) c];
    final k = await (await (_boVe ??= tao())).doan(ky);
    return (k, tl, false);
  }

  /// Mảnh cho ký tự gõ vào: mẫu chép từ hồ sơ, theo định dạng (đổi cỡ, đổi phông) của chữ ngay trước.
  Future<Manh> _manhMoi(String ch) async {
    final kieu = _kieuTaiConTro();
    if (kieu != null && kieu.$1 == 've') return _manhPhong(ch, kieu.$2 as DinhDangVe);
    final m = await _manhMau(ch);
    return kieu != null ? _phongTo(m, kieu.$2 as double) : m;
  }

  Future<Manh> _manhMau(String ch) async {
    if (ch == ' ') {
      // khoảng trắng: chép khoảng trắng gốc của chính dòng (đúng bề rộng, đúng vân nền)
      final trong = [for (final m in goc) if (m.chu == ' ') m]..sort((a, b) => a.rong.compareTo(b.rong));
      if (trong.isNotEmpty) {
        final m = trong[trong.length ~/ 2];
        return Manh('goc', ' ', x0: m.x0, x1: m.x1);
      }
      return Manh('ve', ' ', rongVe: math.max(2, (dong.co * 0.3).round()).toDouble());
    }
    final tay = mauTay[ch];
    if (tay != null) return tay.banSao()..mauMuc = mauMucTaiConTro();
    final nguon = this.nguon;
    final dam = damTaiConTro();
    final chon = chonKyTuMau(nguon, dong, ch, damDich: dam);
    Manh? mau;
    if (chon != null) {
      final a = await nguon[chon.trang].layAnh();
      mau = manhChep(a, chon.dong, chon.kyTu, khe, tiLe: chon.tiLe, chuaChac: chon.trang > 0, cacDong: nguon[chon.trang].dong)
        ..diem = chon.diem;
    }
    // chữ có dấu: mẫu sẵn có mà khác kiểu nét, ở trang khác, hoặc không có thì thử ghép thân chữ với dấu
    if (tachDau(ch) != null && (mau == null || mau.chuaChac || mau.diem > 0.9)) {
      final ghep = await ghepDau(nguon, dong, ch, khe, dam);
      if (ghep != null && (mau == null || ghep.diem <= mau.diem + 0.3 || (mau.chuaChac && !ghep.chuaChac))) mau = ghep;
    }
    if (mau != null) return mau..mauMuc = mauMucTaiConTro();
    thieu.add(ch);
    return _manhVe(ch);
  }

  /// Các chữ gốc của dòng gần con trỏ (trong khoảng 3 cỡ chữ), để lấy độ đậm nét, màu mực tại chỗ chèn.
  List<KyTu> _quanhConTro() {
    final x = xConTro(), r = 3 * dong.co;
    final gan = [for (final c in dong.kyTu) if (laChuSo(c.chu) && c.tinCay >= 50 && ((c.x0 + c.x1) / 2 - x).abs() <= r) c];
    return gan.length >= 2 ? gan : [for (final c in dong.kyTu) if (laChuSo(c.chu)) c];
  }

  /// Bề dày nét các chữ quanh con trỏ (điểm ảnh).
  double damTaiConTro() => damQuanh(dong, xConTro().toDouble(), anh: anh);

  /// Màu mực (BGR) của chữ quanh con trỏ: trung vị các điểm lõi nét (tối nhất 35%) của dòng; null nếu quá ít điểm.
  List<double>? mauMucTaiConTro() {
    final h = dong.dai1 - dong.dai0;
    final diem = <(int, int)>[]; // (độ xám, vị trí điểm ảnh)
    for (final c in _quanhConTro()) {
      final a0 = math.max(0, c.x0 - x0), a1 = math.min(netW, c.x1 - x0);
      for (var y = 0; y < h; y++) {
        for (var x = a0; x < a1; x++) {
          if (net[y * netW + x] == 0) continue;
          final px = x0 + x, py = dong.dai0 + y;
          diem.add((anh.xam(px, py), (py * anh.w + px) * 3));
        }
      }
    }
    if (diem.length < 20) return null;
    diem.sort((a, b) => a.$1.compareTo(b.$1));
    final loi = diem.sublist(0, math.max(1, (diem.length * 0.35).floor()));
    return [
      for (var k = 0; k < 3; k++) _trungVi([for (final (_, p) in loi) anh.bgr[p + k]])
    ];
  }

  /// Vẽ ký tự thiếu bằng phông đoán được; cỡ chỉnh theo ký tự gốc đứng cạnh con trỏ (vd. "5" cao bằng "7").
  Future<Manh> _manhVe(String ch) async {
    final tao = taoBoVe;
    if (tao == null) return Manh('ve', ch, rongVe: 0.5 * dong.co + khe, coVe: dong.co, chuaChac: true);
    final bo = await (_boVe ??= tao());
    var co = bo.coPx;
    final ben = [
      if (conTro > 0) manh[conTro - 1],
      if (conTro < manh.length) manh[conTro],
    ].where((m) => m.loai == 'goc' && m.cao > 0 && laChuSo(m.chu)).toList();
    if (ben.isNotEmpty && laChuSo(ch)) {
      final c = await bo.caoMuc(ben.first.chu, bo.coPx);
      if (c > 0) co = (bo.coPx * ben.first.cao / c).clamp(0.6 * bo.coPx, 1.6 * bo.coPx);
    }
    final hinh = await bo.ve(ch, co);
    return Manh('ve', ch, rongVe: hinh.rongChu + khe, coVe: co, chuaChac: true, hinh: hinh);
  }

  /// Người dùng chọn ký tự [c] (trên ảnh [anhMau], dòng [d]) làm mẫu cho [ch]: thay mọi chỗ đã chèn [ch] trong dòng.
  void datMau(String ch, AnhBgr anhMau, DongAnh d, KyTu c) {
    final cacDong = nguon.where((t) => t.dong.any((e) => identical(e, d))).firstOrNull?.dong;
    final m = mauTay[ch] = manhChep(anhMau, d, c, khe, tiLe: tiLeCo(dong, d), cacDong: cacDong);
    manh = [for (final x in manh) x.loai != 'goc' && x.chu == ch ? (m.banSao()..mauMuc = x.mauMuc) : x];
    thieu.remove(ch);
  }

  /// Các ký tự đã chèn (không phải mảnh gốc), không kể khoảng trắng.
  List<String> get daChen => {for (final m in manh) if (m.loai != 'goc' && m.chu.trim().isNotEmpty) m.chu}.toList()..sort();

  bool get daDoi => manh.length != goc.length || [for (var i = 0; i < manh.length; i++) i].any((i) => !identical(manh[i], goc[i]));

  SuaDong thaoTac() => SuaDong(x0, x1Cu, dong.dai0, dong.dai1, dong.chan, daDoi ? canChamDan(manh, x1Cu - x0) : [...manh],
      chuCu: dong.chu, nghieng: dong.nghieng, xChan: dong.xChan, net: net, khac: khac, netW: netW);

  bool vuotLe(int lePhai) => x0 + thaoTac().rong > lePhai + 2;
}

// ---------------------------------------------------------------- sau khi sửa

/// Dòng sau khi sửa (để sửa tiếp ngay, không phải nhận dạng lại cả trang): ký tự gốc dời theo mảnh của nó, ký tự
/// chép, vẽ lấy khung theo nét đã dán; mảnh khoảng trắng tách từ.
DongAnh dongSauSua(DongAnh cu, SuaDong tt) {
  final tu = <List<KyTu>>[[]];
  final goc = cu.kyTu;
  var x = tt.x0;
  for (final m in tt.manh) {
    final w = m.rong;
    if (m.chu == ' ') {
      if (tu.last.isNotEmpty) tu.add([]);
    } else if (m.loai == 'goc') {
      for (final c in goc) {
        final tam = (c.x0 + c.x1) / 2;
        if (m.x0 <= tam && tam < m.x1) tu.last.add(c.doi(x - m.x0, (tt.nghieng * (x - m.x0)).round()));
      }
    } else if (m.loai == 'chep') {
      // khung theo nét mẫu, đặt như lúc dán (căn đường chân chữ)
      final mat = m.matMau!, mw = m.mau!.w, mh = m.mau!.h;
      var t0 = mh, t1 = -1, l0 = mw, l1 = -1;
      for (var y = 0; y < mh; y++) {
        for (var xx = 0; xx < mw; xx++) {
          if (mat[y * mw + xx] == 0) continue;
          t0 = math.min(t0, y);
          t1 = math.max(t1, y);
          l0 = math.min(l0, xx);
          l1 = math.max(l1, xx);
        }
      }
      if (t1 >= 0) {
        final dy = tt.chanTai(x + w / 2) - m.chanMau * m.tiLe;
        tu.last.add(KyTu(m.chu, x + (l0 * m.tiLe).round(), (dy + t0 * m.tiLe).round(), x + ((l1 + 1) * m.tiLe).round(),
            (dy + (t1 + 1) * m.tiLe).round(), m.chuaChac ? 60.0 : 90.0));
      }
    } else {
      final cao = m.coVe > 0 ? m.coVe : cu.co;
      tu.last.add(KyTu(m.chu, x, (tt.chanTai(x) - 0.7 * cao).round(), x + math.max(1, w), tt.chanTai(x).round() + 1, 50.0));
    }
    x += w;
  }
  final ds = [for (final w in tu) if (w.isNotEmpty) w];
  return DongAnh(tt.x0, cu.y0, math.max(x, tt.x0 + 1), cu.y1, cu.chan, ds,
      dai0: cu.dai0, dai1: cu.dai1, dam: cu.dam, nghieng: cu.nghieng, xChan: cu.xChan, tren: cu.tren, duoi: cu.duoi);
}

/// Trang sau khi sửa dòng [cu] thành [moi] (cùng vị trí trong danh sách).
TrangKyTu trangSauSua(TrangKyTu t, DongAnh cu, DongAnh moi) =>
    TrangKyTu(t.rong, t.cao, [for (final d in t.dong) identical(d, cu) ? moi : d], t.khe);

/// Chữ (mức từ, để xem, chép, ghi lớp chữ PDF) của trang sau khi sửa ký tự: các dòng cũ nằm trong dải dòng đã sửa
/// thay bằng dòng mới. Dòng mới có khung từ theo khung ký tự.
TrangChu chuSauSua(TrangChu cu, DongAnh dongCu, DongAnh moi) {
  final x1 = math.max(dongCu.x1, moi.x1);
  bool trong(DongChu d) {
    final tam = (d.y0 + d.y1) / 2;
    return tam >= dongCu.dai0 && tam < dongCu.dai1 && d.x1 > dongCu.x0 && d.x0 < x1;
  }

  final tu = [
    for (final w in moi.tu)
      TuChu(w.map((c) => c.chu).join(), w.map((c) => c.x0).reduce(math.min).toDouble(), w.map((c) => c.y0).reduce(math.min).toDouble(),
          w.map((c) => c.x1).reduce(math.max).toDouble(), w.map((c) => c.y1).reduce(math.max).toDouble(),
          w.map((c) => c.tinCay).reduce(math.min).round().clamp(0, 100)),
  ];
  final ds = <DongChu>[];
  var daChen = false;
  for (final d in cu.dong) {
    if (trong(d)) {
      if (!daChen && tu.isNotEmpty) {
        ds.add(DongChu(tu, moi.x0.toDouble(), moi.y0.toDouble(), moi.x1.toDouble(), moi.y1.toDouble(),
            coChu: moi.co, lechChan: moi.chan - moi.y1, doanMoi: d.doanMoi));
      }
      daChen = true;
    } else {
      ds.add(d);
    }
  }
  return TrangChu(cu.rong, cu.cao, ds);
}
