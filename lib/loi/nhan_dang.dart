// Kết quả nhận dạng chữ (OCR) một trang: đọc hOCR của Tesseract thành dòng, từ kèm vị trí.
// Vị trí từ dùng để ghi lớp chữ ẩn trong PDF; văn bản thuần dùng để xem, chép, xuất .txt.
// Tương ứng ung-dung/loi_xu_ly/nhan_dang.py. Thuần Dart, chạy được trong isolate.

/// Ngôn ngữ nhận dạng: chỉ `vie` (đọc được cả tiếng Anh); `vie+eng` làm mất dấu tiếng Việt.
const ngonNguNhanDang = 'vie';

class TuChu {
  TuChu(this.chu, this.x0, this.y0, this.x1, this.y1, this.tinCay);

  final String chu;
  final double x0, y0, x1, y1; // khung từ, theo điểm ảnh của ảnh đã nhận dạng
  final int tinCay; // 0–100

  List<Object> toJson() => [chu, x0, y0, x1, y1, tinCay];

  factory TuChu.fromJson(List j) => TuChu(j[0] as String, (j[1] as num).toDouble(), (j[2] as num).toDouble(),
      (j[3] as num).toDouble(), (j[4] as num).toDouble(), j[5] as int);
}

class DongChu {
  DongChu(this.tu, this.x0, this.y0, this.x1, this.y1,
      {required this.coChu, this.doDoc = 0, this.lechChan = 0, this.doanMoi = false, this.gocChu = 0});

  final List<TuChu> tu;
  final double x0, y0, x1, y1;
  final double coChu; // cỡ chữ theo điểm ảnh (x_size của hOCR)
  final double doDoc, lechChan; // đường chân chữ: y = y1 + lechChan + doDoc·(x − x0)
  final bool doanMoi; // dòng đầu của một đoạn
  final int gocChu; // góc cần xoay cùng chiều kim đồng hồ cho dòng đứng thẳng (textangle, chỉ có khi psm 1)

  double chanChuTai(double x) => y1 + lechChan + doDoc * (x - x0);

  String get vanBan => tu.map((t) => t.chu).join(' ');

  Map<String, Object> toJson() => {
        'k': [x0, y0, x1, y1],
        'c': coChu,
        'b': [doDoc, lechChan],
        'd': doanMoi,
        if (gocChu != 0) 'g': gocChu,
        't': [for (final t in tu) t.toJson()],
      };

  factory DongChu.fromJson(Map j) {
    final k = [for (final v in j['k'] as List) (v as num).toDouble()];
    final b = j['b'] as List;
    return DongChu([for (final t in j['t'] as List) TuChu.fromJson(t as List)], k[0], k[1], k[2], k[3],
        coChu: (j['c'] as num).toDouble(),
        doDoc: (b[0] as num).toDouble(),
        lechChan: (b[1] as num).toDouble(),
        doanMoi: j['d'] as bool? ?? false,
        gocChu: j['g'] as int? ?? 0);
  }
}

class TrangChu {
  TrangChu(this.rong, this.cao, this.dong);

  final int rong, cao; // kích thước ảnh đã nhận dạng
  final List<DongChu> dong;

  bool get trong => dong.isEmpty;

  /// Số từ và độ tin cậy trung bình (0–100) của máy đọc trên trang; trang mờ, chụp kém thường dưới 70.
  (int, double) get tinCay {
    var n = 0, t = 0;
    for (final d in dong) {
      for (final w in d.tu) {
        n++;
        t += w.tinCay;
      }
    }
    return (n, n == 0 ? 0.0 : t / n);
  }

  /// (góc cần xoay cùng chiều kim đồng hồ cho trang đứng thẳng, số từ ủng hộ góc đó): bầu theo số từ của từng dòng.
  (int, int) get gocXoay {
    final phieu = <int, int>{};
    for (final d in dong) {
      phieu[d.gocChu] = (phieu[d.gocChu] ?? 0) + d.tu.length;
    }
    if (phieu.isEmpty) return (0, 0);
    final tot = phieu.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return (tot.key, tot.value);
  }

  /// Văn bản thuần: từ cách nhau một dấu cách, dòng xuống dòng, đoạn cách một dòng trống.
  String get vanBan {
    final b = StringBuffer();
    for (final d in dong) {
      if (b.isNotEmpty) b.write(d.doanMoi ? '\n\n' : '\n');
      b.write(d.vanBan);
    }
    return b.toString();
  }

  Map<String, Object> toJson() => {'w': rong, 'h': cao, 'dong': [for (final d in dong) d.toJson()]};

  factory TrangChu.fromJson(Map j) =>
      TrangChu(j['w'] as int, j['h'] as int, [for (final d in j['dong'] as List) DongChu.fromJson(d as Map)]);

  /// Đọc hOCR (Tesseract 4, 5). Bỏ dòng không có chữ.
  factory TrangChu.docHocr(String hocr) {
    final the = RegExp(r'''<(?:div|p|span)\s+class=['"](ocr_page|ocr_par|ocr_line|ocr_header|ocr_textfloat|ocr_caption|ocrx_word)['"][^>]*?title=(['"])(.*?)\2[^>]*>''',
        dotAll: true);
    var rong = 0, cao = 0;
    final dong = <DongChu>[];
    var doanMoi = true;
    // dòng đang đọc: khung, tiêu đề, các từ
    List<double>? khungDong;
    String tieuDeDong = '';
    var tuDong = <TuChu>[];
    var dauDoan = false;

    void xongDong() {
      final k = khungDong;
      if (k != null && tuDong.isNotEmpty) {
        final b = RegExp(r'baseline (-?[\d.]+) (-?[\d.]+)').firstMatch(tieuDeDong);
        final c = RegExp(r'x_size ([\d.]+)').firstMatch(tieuDeDong);
        final g = RegExp(r'textangle (\d+)').firstMatch(tieuDeDong);
        dong.add(DongChu(tuDong, k[0], k[1], k[2], k[3],
            coChu: c != null ? double.parse(c[1]!) : k[3] - k[1],
            doDoc: b != null ? double.parse(b[1]!) : 0,
            lechChan: b != null ? double.parse(b[2]!) : 0,
            doanMoi: dauDoan,
            gocChu: g != null ? int.parse(g[1]!) % 360 : 0));
        doanMoi = false;
      }
      khungDong = null;
      tuDong = <TuChu>[];
    }

    for (final m in the.allMatches(hocr)) {
      final loai = m[1]!, tieuDe = m[3]!;
      final k = _khung(tieuDe);
      switch (loai) {
        case 'ocr_page':
          if (k != null) {
            rong = k[2].round();
            cao = k[3].round();
          }
        case 'ocr_par':
          xongDong();
          doanMoi = true;
        case 'ocrx_word':
          if (k == null) continue;
          final cuoi = hocr.indexOf('</span>', m.end);
          final chu = _boThe(hocr.substring(m.end, cuoi < 0 ? m.end : cuoi)).trim();
          if (chu.isEmpty) continue;
          final tc = RegExp(r'x_wconf (\d+)').firstMatch(tieuDe);
          tuDong.add(TuChu(chu, k[0], k[1], k[2], k[3], tc != null ? int.parse(tc[1]!) : 0));
        default: // các loại dòng
          xongDong();
          if (k == null) continue;
          khungDong = k;
          tieuDeDong = tieuDe;
          dauDoan = doanMoi;
      }
    }
    xongDong();
    return TrangChu(rong, cao, dong);
  }
}

List<double>? _khung(String tieuDe) {
  final m = RegExp(r'bbox (-?\d+) (-?\d+) (-?\d+) (-?\d+)').firstMatch(tieuDe);
  return m == null ? null : [for (var i = 1; i <= 4; i++) double.parse(m[i]!)];
}

String _boThe(String s) => s
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// Văn bản cả hồ sơ: các trang cách nhau hai dòng trống.
String vanBanNhieuTrang(Iterable<TrangChu> trang) => trang.map((t) => t.vanBan).where((s) => s.isNotEmpty).join('\n\n\n');
