// Ghi PDF nhiều trang theo khổ giấy, lề, chất lượng ảnh (thư viện `pdf`, chạy được trong isolate).
// Có thể kèm lớp chữ ẩn từ kết quả nhận dạng để tìm kiếm, chép chữ trong PDF, và đánh số trang.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'anh.dart';
import 'nhan_dang.dart';

const tenKhoGiay = {'a4': 'A4', 'a5': 'A5', 'letter': 'Letter', 'theo_anh': 'Theo ảnh'};
const chatLuongXuat = {
  'cao': ('Cao', 300, 90),
  'vua': ('Vừa', 200, 80),
  'nho': ('Nhỏ', 150, 65),
};

const tenViTriSo = {'tren': 'Lề trên', 'duoi': 'Lề dưới'};
const tenCanSo = {'giua': 'Giữa', 'trai': 'Trái', 'phai': 'Phải', 'so_le': 'So le'};

/// Cách đánh số trang khi xuất PDF.
class DanhSo {
  DanhSo({this.tuTrang = 1, this.soDau = 1, this.viTri = 'duoi', this.can = 'giua', this.chanTrai = true, this.coChu = 13});

  int tuTrang; // trang đầu tiên được đánh số (1 = trang đầu hồ sơ); các trang trước để trống
  int soDau; // số in trên trang đó
  String viTri; // tren | duoi
  String can; // giua | trai | phai | so_le
  bool chanTrai; // so le: số chẵn bên trái, số lẻ bên phải (false: ngược lại)
  double coChu;

  /// Số in trên trang thứ [i] (tính từ 0) của tệp xuất; null nếu trang không đánh số.
  int? soCua(int i) => i + 1 < tuTrang ? null : soDau + i + 1 - tuTrang;

  /// Căn của một số trang cụ thể: trai | giua | phai (so le tùy số chẵn, lẻ).
  String canCua(int so) => can != 'so_le' ? can : ((so.isEven == chanTrai) ? 'trai' : 'phai');

  Map<String, Object> toJson() => {'viTri': viTri, 'can': can, 'chanTrai': chanTrai};

  void napJson(Map j) {
    viTri = j['viTri'] as String? ?? viTri;
    can = j['can'] as String? ?? can;
    chanTrai = j['chanTrai'] as bool? ?? chanTrai;
  }
}

/// Ghi chú trong thuộc tính Subject của PDF khi có trang đã sửa chữ. [soChoSua]: tổng số chỗ sửa, trong đó [kyTu] chỗ
/// sửa ký tự giữ nguyên bản gốc (Sửa ký tự), còn lại là chỗ viết lại cả khối bằng phông.
String ghiChuSua(int soChoSua, {int kyTu = 0}) => 'Đã chỉnh sửa nội dung bằng Xử lý PDF ảnh: '
    '${[if (kyTu > 0) '$kyTu chỗ sửa ký tự', if (soChoSua - kyTu > 0) '${soChoSua - kyTu} chỗ sửa chữ'].join(', ')}';

PdfPageFormat? _kho(String kho) => switch (kho) {
      'a4' => PdfPageFormat.a4,
      'a5' => PdfPageFormat.a5,
      'letter' => PdfPageFormat.letter,
      _ => null,
    };

/// Tạo PDF từ các ảnh trang (JPEG). Ảnh được thu nhỏ theo dpi của mức chất lượng rồi nén lại.
/// [chu]: kết quả nhận dạng từng trang (cùng thứ tự với [trang]) để ghi lớp chữ ẩn; cần [phong] là tệp TTF có chữ Việt.
/// [danhSo]: in số trang (Times, cỡ 13) ở lề trên hoặc dưới.
/// [soChoSua]: số chỗ đã sửa chữ trên ảnh trang (trong đó [soSuaKyTu] chỗ sửa ký tự); khác 0 thì ghi vào thuộc tính
/// Subject của PDF.
Future<Uint8List> taoPdf(List<Uint8List> trang,
    {String kho = 'a4',
    double leMm = 0,
    String chatLuong = 'vua',
    String tieuDe = '',
    int soChoSua = 0,
    int soSuaKyTu = 0,
    List<TrangChu?>? chu,
    Uint8List? phong,
    DanhSo? danhSo}) async {
  final (_, dpi, q) = chatLuongXuat[chatLuong] ?? chatLuongXuat['vua']!;
  final doc = pw.Document(title: tieuDe, creator: 'Xử lý PDF ảnh', subject: soChoSua > 0 ? ghiChuSua(soChoSua, kyTu: soSuaKyTu) : null);
  final le = leMm * PdfPageFormat.mm;
  final font = (chu != null && phong != null) ? PdfTtfFont(doc.document, ByteData.sublistView(phong)) : null;
  final phongSo = pw.Font.times();
  for (var i = 0; i < trang.length; i++) {
    final anh = giaiMa(trang[i]);
    final lop = (font != null && i < chu!.length) ? chu[i] : null;
    final ngang = anh.cols > anh.rows;
    var dang = _kho(kho);
    if (dang != null && ngang) dang = dang.landscape;
    // khổ "theo ảnh": giữ tỉ lệ ảnh, rộng bằng A4
    dang ??= PdfPageFormat(PdfPageFormat.a4.width, PdfPageFormat.a4.width * anh.rows / anh.cols);
    final canhPx = (math.max(dang.width, dang.height) - 2 * le) / PdfPageFormat.inch * dpi;
    final nen = maHoa(gioiHan(anh, canhPx.round()), chatLuong: q);
    final so = danhSo?.soCua(i);
    final noiDung = pw.CustomPaint(
      foregroundPainter: lop == null || lop.trong ? null : (canvas, khung) => _veLopChu(canvas, khung, lop, anh.cols, anh.rows, font!),
      child: pw.Center(child: pw.Image(pw.MemoryImage(nen), fit: pw.BoxFit.contain)),
    );
    doc.addPage(pw.Page(
      pageFormat: dang.copyWith(marginLeft: 0, marginRight: 0, marginTop: 0, marginBottom: 0),
      build: (_) => pw.Stack(children: [
        pw.Padding(padding: pw.EdgeInsets.all(le), child: noiDung),
        if (so != null) _soTrang(danhSo!, so, le, phongSo),
      ]),
    ));
  }
  return doc.save();
}

/// Số trang nằm giữa khoảng lề (ít nhất 8 mm tính từ mép giấy khi lề nhỏ); căn trái, phải theo mép vùng nội dung
/// (ít nhất 20 mm từ mép giấy). Nếu lề hẹp hơn chỗ đặt số thì số in đè lên phần trắng của ảnh trang.
pw.Widget _soTrang(DanhSo ds, int so, double le, pw.Font phong) {
  final doc = math.max(le / 2, 8 * PdfPageFormat.mm) - ds.coChu * 0.5;
  final ngang = math.max(le, 20 * PdfPageFormat.mm);
  final tren = ds.viTri == 'tren';
  final can = ds.canCua(so);
  return pw.Positioned.fill(
    child: pw.Padding(
      padding: pw.EdgeInsets.fromLTRB(ngang, tren ? doc : 0, ngang, tren ? 0 : doc),
      child: pw.Align(
        alignment: switch ((tren, can)) {
          (true, 'trai') => pw.Alignment.topLeft,
          (true, 'phai') => pw.Alignment.topRight,
          (true, _) => pw.Alignment.topCenter,
          (false, 'trai') => pw.Alignment.bottomLeft,
          (false, 'phai') => pw.Alignment.bottomRight,
          (false, _) => pw.Alignment.bottomCenter,
        },
        child: pw.Text('$so', style: pw.TextStyle(font: phong, fontSize: ds.coChu, color: PdfColors.black)),
      ),
    ),
  );
}

/// Ghi chữ ẩn trùng vị trí từng từ trên ảnh. Gốc tọa độ ở góc dưới trái vùng nội dung (trong lề);
/// ảnh nằm giữa vùng này, co theo tỉ lệ (BoxFit.contain).
void _veLopChu(PdfGraphics canvas, PdfPoint khung, TrangChu lop, int rongAnh, int caoAnh, PdfFont font) {
  final s = math.min(khung.x / rongAnh, khung.y / caoAnh);
  final x0 = (khung.x - rongAnh * s) / 2, y0 = (khung.y - caoAnh * s) / 2;
  // ảnh nhận dạng có thể khác cỡ ảnh đưa vào PDF
  final k = s * (lop.rong > 0 ? rongAnh / lop.rong : 1.0);
  final day = caoAnh * s;
  for (final d in lop.dong) {
    final co = d.coChu * k;
    if (co <= 0) continue;
    for (final t in d.tu) {
      final rong = (t.x1 - t.x0) * k;
      final chuan = font.stringMetrics(t.chu).advanceWidth * co;
      canvas.drawString(font, co, t.chu, x0 + t.x0 * k, y0 + day - d.chanChuTai(t.x0) * k,
          mode: PdfTextRenderingMode.invisible, scale: chuan > 0 ? rong / chuan : null);
    }
  }
}
