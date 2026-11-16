// Màn 4 · Chỉnh trang: xem kết quả hoặc ảnh gốc, kéo 4 góc khung cắt, xoay, chọn kiểu làm sạch.
// Chế độ Sửa chữ có hai cách:
// - Sửa ký tự (giữ nguyên bản gốc, cách chính): chạm vào dòng, con trỏ đỏ ở chỗ chạm; xóa, chèn ký tự; ký tự không sửa
//   giữ nguyên từng điểm ảnh, ký tự chèn chép nguyên hình từ chỗ khác trên trang (lib/loi/sua_ky_tu.dart); chạm giữ
//   rồi kéo trong dòng (hoặc bật Bôi chọn) để chọn một đoạn, đổi cỡ (phóng, thu nét gốc) hoặc đổi phông đoạn đó;
// - Vẽ lại bằng phông (cách phụ): chữ trên trang gộp thành khối (đoạn, dòng tiêu đề); chạm khối để viết lại cả khối
//   ngay tại chỗ trên ảnh.
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../du_lieu/kho.dart';
import '../giao_dien/mau.dart';
import '../loi/anh.dart';
import '../loi/lam_sach.dart';
import '../loi/nhan_dang.dart';
import '../loi/sua_chu.dart';
import '../loi/sua_ky_tu.dart';
import '../loi/ve_chu.dart';
import '../main.dart';
import 'van_ban.dart';

/// Trang đã sửa chữ mà xử lý lại (xoay, đổi khung, đổi làm sạch) thì các chỗ sửa mất: hỏi trước.
Future<bool> xacNhanBoSua(BuildContext context, Iterable<TrangTL> trang) async {
  final n = trang.fold(0, (s, t) => s + t.lichSuSua.length);
  if (n == 0) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Bỏ các chỗ sửa chữ?'),
      content: Text('Trang sẽ được xử lý lại từ ảnh gốc nên $n chỗ sửa chữ sẽ mất.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Thôi')),
        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Vẫn xử lý lại', style: TextStyle(color: Mau.do_))),
      ],
    ),
  );
  return ok == true;
}

class ManSuaTrang extends StatefulWidget {
  const ManSuaTrang({super.key, required this.hoSo, required this.trang});
  final HoSo hoSo;
  final TrangTL trang;

  @override
  State<ManSuaTrang> createState() => _ManSuaTrangState();
}

class _ManSuaTrangState extends State<ManSuaTrang> {
  bool _xemGoc = false;
  List<Diem>? _goc; // 4 góc đang kéo, theo tọa độ ảnh gốc đã xoay
  int? _dangKeo; // tay cầm đang kéo: 0..3 góc, 4..7 giữa cạnh
  List<Diem>? _gocLucDau; // 4 góc lúc bắt đầu kéo (kéo cạnh tính theo độ dời từ lúc này)
  Offset? _batDauKeo;
  late double _doTrang = widget.trang.tc.doTrang, _doDam = widget.trang.tc.doDam, _khuNhieu = widget.trang.tc.khuNhieu;

  // chế độ Sửa chữ
  bool _suaChu = false;
  bool _veLai = false; // false: Sửa ký tự (giữ nguyên bản gốc); true: viết lại cả khối, vẽ lại bằng phông
  int _anh = 0; // ảnh thứ mấy của trang (trang sách tách đôi có 2 ảnh)
  String? _tepChu; // tệp ảnh đang sửa

  // Sửa ký tự
  TrangKyTu? _kt; // dòng, khung từng ký tự của ảnh đang sửa
  AnhBgr? _anhKt; // ảnh đang sửa đã giải mã
  String? _loiKt;
  PhienSuaDong? _phien; // dòng đang sửa
  Uint8List? _xemTruoc; // dải dòng đang sửa đã dựng lại (PNG), phủ lên ảnh trang
  (int, int) _vungXem = (0, 0); // các hàng ảnh của [_xemTruoc] (chữ phóng to nhô ra ngoài dải dòng)
  bool _boiChon = false; // ← →, chạm trong dòng thì mở rộng đoạn chọn
  double? _keoChon; // chạm giữ rồi kéo trong dòng đang sửa: cột bắt đầu bôi chọn
  bool _daKeo = false;
  (DinhDangVe, double, bool)? _kieuChon; // định dạng đoạn chọn: phông, cỡ đoán được; tỉ lệ cỡ; đã đổi phông chưa
  final List<TrangNguon> _trangKhac = []; // các ảnh trang khác đã nhận dạng: chỗ tìm ký tự mẫu
  int _soTrangKhac = 0; // số ảnh trang khác cần đọc
  int _luotKt = 0; // lượt tải: đổi ảnh, thoát thì việc nền của lượt cũ dừng
  bool _dangGo = false;
  final _oChen = TextEditingController();
  double _sKt = 1; // tỉ lệ hiện ảnh (chưa phóng), góc ảnh trong vùng, cỡ vùng ảnh lần dựng trước
  Offset _gocKt = Offset.zero;
  Size? _vungKt;

  // Vẽ lại bằng phông (theo khối)
  TrangChu? _chu;
  List<KhoiChu> _khoi = [];
  List<bool> _khoa = []; // khối có mực màu (con dấu, chữ ký): không cho sửa
  String? _loiSua;
  int? _chon; // khối đang sửa
  final _oNhap = TextEditingController();
  KieuChu? _kieu; // kiểu chữ đoán được của khối đang sửa
  PhongChu? _phongChon; // phông người dùng chọn (null: tự đoán)
  bool _dangAp = false, _canHien = false;
  Size? _coVung; // cỡ vùng ảnh lần dựng trước: đổi (bàn phím hiện, ẩn) thì cuộn lại cho khối đang sửa hiện rõ
  final _bienDoi = TransformationController();

  TrangTL get t => widget.trang;

  @override
  void dispose() {
    _oChen.dispose();
    _oNhap.dispose();
    _bienDoi.dispose();
    super.dispose();
  }

  void _xuLy() {
    kho.xuLy(widget.hoSo, t);
    kho.luu(widget.hoSo);
  }

  /// Đổi tùy chọn, khung, chiều rồi xử lý lại; trang đã sửa chữ thì hỏi trước. Trả false nếu người dùng thôi.
  Future<bool> _doi(void Function() thayDoi, {bool xuLyLai = true}) async {
    if (!await xacNhanBoSua(context, [t])) return false;
    thayDoi();
    if (xuLyLai) _xuLy();
    if (mounted) setState(() {});
    return true;
  }

  void _bao(String s) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(s)));

  List<Diem> _khungHien() {
    final w = t.rongGoc.toDouble(), h = t.caoGoc.toDouble();
    return _goc ?? t.khungTay ?? t.khungDung ?? [(0, 0), (w - 1, 0), (w - 1, h - 1), (0, h - 1)];
  }

  Future<void> _xoaTrang() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xóa trang này?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Thôi')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Xóa', style: TextStyle(color: Mau.do_))),
        ],
      ),
    );
    if (ok == true) {
      await kho.xoaTrang(widget.hoSo, t);
      if (mounted) Navigator.pop(context);
    }
  }

  // ---------------------------------------------------------------- sửa chữ

  Future<void> _vaoSuaChu() async {
    _bienDoi.value = Matrix4.identity();
    setState(() {
      _suaChu = true;
      _xemGoc = false;
      _anh = _anh.clamp(0, t.tepKq.length - 1);
    });
    await _taiLai();
  }

  void _thoatSuaChu() {
    FocusScope.of(context).unfocus();
    _bienDoi.value = Matrix4.identity();
    _luotKt++;
    setState(() {
      _suaChu = false;
      _chon = null;
      _phien = null;
      _xemTruoc = null;
      _kt = null;
      _anhKt = null;
      _trangKhac.clear();
    });
  }

  /// Nạp lại chữ của ảnh đang sửa theo cách sửa đang chọn.
  Future<void> _taiLai() => _veLai ? _taiKhoi() : _taiKyTu();

  void _doiCachSua(bool veLai) {
    if (veLai == _veLai || _phien != null || _chon != null || _dangAp) return;
    FocusScope.of(context).unfocus();
    _bienDoi.value = Matrix4.identity();
    setState(() => _veLai = veLai);
    _taiLai();
  }

  // ---------------------------------------------------------------- sửa ký tự (giữ nguyên bản gốc)

  /// Nhận dạng dòng, khung từng ký tự của ảnh đang sửa (có đệm), giải mã ảnh; rồi đọc dần các trang khác ở nền để có
  /// thêm ký tự mẫu.
  Future<void> _taiKyTu() async {
    if (t.tepKq.isEmpty) return;
    final tep = t.tepKq[_anh];
    final luot = ++_luotKt;
    setState(() {
      _tepChu = tep;
      _kt = null;
      _anhKt = null;
      _loiKt = null;
      _phien = null;
      _xemTruoc = null;
      _trangKhac.clear();
      _soTrangKhac = 0;
    });
    try {
      final duong = kho.duongDan(widget.hoSo, tep);
      final kt = await kho.nhanDangKyTu(widget.hoSo, tep);
      final anh = await _docAnhNen(duong);
      if (!mounted || luot != _luotKt) return;
      setState(() {
        _kt = kt;
        _anhKt = anh;
      });
      _taiTrangKhac(luot, tep);
    } catch (e) {
      if (mounted && luot == _luotKt) setState(() => _loiKt = 'Không nhận dạng được chữ: $e');
    }
  }

  /// Nhận dạng (có đệm) lần lượt các ảnh trang khác của hồ sơ: trang đang sửa không có ký tự cần chèn thì chép từ đó.
  Future<void> _taiTrangKhac(int luot, String tepHien) async {
    final h = widget.hoSo;
    final ds = [
      for (final tr in h.trang)
        if (tr.trangThai == 'xong')
          for (final tep in tr.tepKq)
            if (tep != tepHien) tep
    ];
    setState(() => _soTrangKhac = ds.length);
    for (final tep in ds) {
      if (!mounted || luot != _luotKt) return;
      try {
        final kt = await kho.nhanDangKyTu(h, tep);
        if (!mounted || luot != _luotKt) return;
        final duong = kho.duongDan(h, tep);
        setState(() => _trangKhac.add(TrangNguon(kt.dong, tai: () => _docAnhNen(duong))));
      } catch (_) {
        // trang không nhận dạng được: bỏ qua, chỉ bớt chỗ tìm mẫu
      }
    }
  }

  Offset _raAnh(Offset p) => (p - _gocKt) / _sKt;

  /// Chạm vào ảnh: chạm dòng đang sửa thì dời con trỏ; chạm dòng khác thì bắt đầu sửa dòng đó.
  void _chamKyTu(Offset viTri) {
    final kt = _kt, anh = _anhKt, tep = _tepChu;
    if (kt == null || anh == null || tep == null || _dangAp || _dangGo) return;
    final a = _raAnh(viTri);
    final d = kt.dongTai(a.dx, a.dy);
    final p = _phien;
    if (p != null && identical(d, p.dong)) {
      p.datConTro(a.dx, chon: _boiChon);
      _capNhatPhien();
      if (p.coChon) _napKieuChon();
      return;
    }
    if (p != null && p.daDoi) {
      _bao('Bấm Xong để giữ chỗ vừa sửa, hoặc Hủy, rồi mới chọn dòng khác');
      return;
    }
    if (d == null) {
      if (p != null) _huyKyTu();
      return;
    }
    if (d.mucMau) {
      _bao(baoMucMau);
      return;
    }
    final duong = kho.duongDan(widget.hoSo, tep);
    setState(() {
      _phien = PhienSuaDong(anh, kt, d,
          xBam: a.dx, trangKhac: _trangKhac, taoBoVe: () async => boVeKyTu(await File(duong).readAsBytes(), d));
      _xemTruoc = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _hienConTro(phong: true));
  }

  /// Xem trước ngay trên ảnh: dựng lại dải dòng sau mỗi thao tác.
  void _capNhatPhien() {
    final p = _phien, anh = _anhKt;
    if (p == null || anh == null || !mounted) return;
    final tt = p.thaoTac();
    setState(() {
      _vungXem = tt.vungVe(anh.h);
      _xemTruoc = p.daDoi ? tt.apDai(anh).png(nen: 1) : null;
      if (!p.coChon) _kieuChon = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _hienConTro());
  }

  void _thaoTac(void Function(PhienSuaDong p) viec) {
    final p = _phien;
    if (p == null || _dangGo || _dangAp) return;
    viec(p);
    _capNhatPhien();
  }

  // ---------------------------------------------------------------- đổi cỡ, đổi phông đoạn bôi chọn

  /// Hệ số cỡ chữ điểm ảnh → pt, ước theo trang rộng bằng A4.
  double get _pt => 72 * 8.2677 / (_kt?.rong ?? 1);

  /// Đoán phông, cỡ của đoạn vừa bôi chọn (nạp lên thanh định dạng).
  Future<void> _napKieuChon() async {
    final p = _phien;
    if (p == null || !p.coChon) return;
    final chon = p.doanChon();
    setState(() => _kieuChon = null);
    try {
      final k = await p.kieuDoanChon();
      if (mounted && identical(_phien, p) && p.doanChon() == chon) setState(() => _kieuChon = k);
    } catch (e) {
      if (mounted) _bao('Không đoán được phông của đoạn chọn: $e');
    }
  }

  /// Chạy một việc đổi định dạng (bất đồng bộ: vẽ chữ bằng phông) rồi dựng lại xem trước.
  Future<void> _doiDinhDang(Future<(DinhDangVe, double, bool)?> Function(PhienSuaDong p, (DinhDangVe, double, bool) k) viec) async {
    final p = _phien, k = _kieuChon;
    if (p == null || k == null || !p.coChon || _dangGo || _dangAp) return;
    setState(() => _dangGo = true);
    try {
      final moi = await viec(p, k);
      if (mounted && moi != null) _kieuChon = moi;
    } catch (e) {
      if (mounted) _bao('Không đổi được định dạng: $e');
    } finally {
      if (mounted) setState(() => _dangGo = false);
    }
    _capNhatPhien();
  }

  /// Tăng, giảm cỡ đoạn chọn [buoc] pt: còn nét gốc thì phóng, thu chính nét đó; đã đổi phông thì vẽ lại ở cỡ mới.
  void _doiCoChon(double buoc) => _doiDinhDang((p, k) async {
        final (kc, tl, ve) = k;
        final ptMoi = math.max(3.0, ((kc.co * tl * _pt + buoc) * 2).round() / 2);
        if (ve) {
          final moi = kc.doiCo(ptMoi / _pt);
          await p.dinhDangChon(kieu: moi);
          return (moi, 1.0, true);
        }
        final tlMoi = ptMoi / (kc.co * _pt);
        await p.dinhDangChon(tiLe: tlMoi);
        return (kc, tlMoi, false);
      });

  /// Đổi phông đoạn chọn ([phong] < 0: trả về nét gốc, giữ cỡ đang đặt).
  void _doiPhongChon(int phong) => _doiDinhDang((p, k) async {
        final (kc, tl, ve) = k;
        final co = kc.co * tl;
        if (phong < 0) {
          if (!ve) return k;
          final goc = await p.kieuDoanChon(boPhong: true);
          if (goc == null) return k;
          final tlMoi = co / goc.$1.co;
          await p.dinhDangChon(tiLe: tlMoi);
          return (goc.$1, tlMoi, false);
        }
        final moi = DinhDangVe(phong, co, kc.mau, vien: kc.vien * tl);
        await p.dinhDangChon(kieu: moi);
        return (moi, 1.0, true);
      });

  void _giuBatDau(Offset viTri) {
    final p = _phien, kt = _kt;
    if (p != null && kt != null && !_dangGo && !_dangAp) {
      final a = _raAnh(viTri);
      if (identical(kt.dongTai(a.dx, a.dy), p.dong)) {
        // chạm giữ trong dòng đang sửa: kéo để bôi chọn; không kéo thì chọn mẫu như cũ
        _keoChon = a.dx;
        _daKeo = false;
        return;
      }
    }
    _chamGiuKyTu(viTri);
  }

  void _giuKeo(Offset viTri) {
    final p = _phien, xa = _keoChon;
    if (p == null || xa == null) return;
    final xb = _raAnh(viTri).dx;
    if ((xb - xa).abs() * _sKt * _bienDoi.value.getMaxScaleOnAxis() < 6 && !_daKeo) return;
    _daKeo = true;
    setState(() => p.chonX(xa, xb));
  }

  void _giuXong(Offset viTri) {
    final xa = _keoChon;
    _keoChon = null;
    if (xa == null) return;
    if (_daKeo) {
      _capNhatPhien();
      _napKieuChon();
    } else {
      _chamGiuKyTu(viTri);
    }
  }

  /// Chèn chữ trong ô gõ vào chỗ con trỏ.
  Future<void> _chen() async {
    final p = _phien, chu = _oChen.text;
    if (p == null || chu.isEmpty || _dangGo || _dangAp) return;
    setState(() => _dangGo = true);
    try {
      await p.go(chu);
      _oChen.clear();
    } catch (e) {
      if (mounted) _bao('Không chèn được: $e');
    } finally {
      if (mounted) setState(() => _dangGo = false);
    }
    _capNhatPhien();
  }

  /// Chạm giữ một ký tự trên trang khi đang sửa: dùng ký tự đó làm mẫu cho ký tự đã chèn (chèn nhiều loại thì hỏi).
  Future<void> _chamGiuKyTu(Offset viTri) async {
    final p = _phien, kt = _kt, anh = _anhKt;
    if (p == null || kt == null || anh == null || _dangGo || _dangAp) return;
    final a = _raAnh(viTri);
    final d = kt.dongTai(a.dx, a.dy);
    if (d == null) return;
    // dòng đang sửa hiện theo bản đã dựng lại: quy chỗ chạm về cột của ảnh gốc qua mảnh gốc nằm ở đó
    var xGoc = a.dx;
    if (identical(d, p.dong)) {
      final tt = p.thaoTac();
      var x = tt.x0.toDouble();
      double? quy;
      for (final m in tt.manh) {
        if (a.dx >= x && a.dx < x + m.rong) {
          if (m.loai == 'goc') quy = m.x0 + a.dx - x;
          break;
        }
        x += m.rong;
      }
      if (quy == null) return; // chạm vào ký tự vừa chèn: không làm mẫu được
      xGoc = quy;
    }
    // ký tự gần chỗ chạm nhất (chạm vào khe giữa hai ký tự vẫn nhận), không xa quá 0,3 cỡ chữ
    KyTu? c;
    var kc = math.max(2.0, 0.3 * d.co);
    for (final k in d.kyTu) {
      final x = xGoc < k.x0 ? k.x0 - xGoc : (xGoc > k.x1 ? xGoc - k.x1 : 0.0);
      if (x <= kc && k.chu != '?') {
        kc = x;
        c = k;
      }
    }
    if (c == null) return;
    final ky = c;
    final chen = p.daChen;
    if (chen.isEmpty) {
      _bao('Chưa chèn ký tự nào để chọn mẫu');
      return;
    }
    final ch = chen.length == 1
        ? chen.first
        : await showDialog<String>(
            context: context,
            builder: (h) => SimpleDialog(
              title: Text('Dùng “${ky.chu}” trên trang làm mẫu cho ký tự nào?', style: const TextStyle(fontSize: 16)),
              children: [
                for (final x in chen)
                  SimpleDialogOption(
                      onPressed: () => Navigator.pop(h, x), child: Text('Ký tự đã chèn “$x”', style: const TextStyle(fontSize: 15))),
              ],
            ),
          );
    if (ch == null || !mounted || !identical(_phien, p)) return;
    p.datMau(ch, anh, d, ky);
    _capNhatPhien();
    _bao('Đã dùng “${ky.chu}” trên trang làm mẫu cho “$ch”');
  }

  void _huyKyTu() {
    FocusScope.of(context).unfocus();
    _oChen.clear();
    setState(() {
      _phien = null;
      _xemTruoc = null;
      _kieuChon = null;
    });
  }

  /// Áp dòng đang sửa: ghi thành ảnh kết quả mới của trang (hoàn tác được); dòng, chữ của ảnh mới dựng sẵn vào đệm.
  Future<void> _xongKyTu() async {
    final p = _phien, kt = _kt, tep = _tepChu;
    if (p == null || kt == null || tep == null || _dangAp || _dangGo) return;
    if (!p.daDoi) {
      _huyKyTu();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _dangAp = true);
    try {
      final tt = p.thaoTac();
      final anhMoi = tt.ap(p.anh);
      final png = await _pngNen(anhMoi);
      final dongMoi = dongSauSua(p.dong, tt);
      final ktMoi = trangSauSua(kt, p.dong, dongMoi);
      final chuCu = await kho.chuDaCo(widget.hoSo, tep);
      await kho.ghiSuaChu(widget.hoSo, t, _anh, png, chuCu == null ? null : chuSauSua(chuCu, p.dong, dongMoi),
          kyTu: true, dongKyTu: ktMoi);
      if (!mounted) return;
      final vuot = p.vuotLe(kt.lePhai);
      _oChen.clear();
      setState(() {
        _tepChu = t.tepKq[_anh];
        _kt = ktMoi;
        _anhKt = anhMoi;
        _phien = null;
        _xemTruoc = null;
      });
      _bao('Đã sửa. ${tt.moTa()}${vuot ? '. Chú ý: dòng đã dài quá lề phải' : ''}');
    } catch (e) {
      if (mounted) _bao('Không sửa được: $e');
    } finally {
      if (mounted) setState(() => _dangAp = false);
    }
  }

  /// Phóng, cuộn để con trỏ đang sửa luôn hiện ra (cả khi bàn phím làm vùng ảnh thấp đi). [phong]: lúc bắt đầu sửa,
  /// phóng to cho dòng cao khoảng 56 điểm trên màn hình để chạm chính xác.
  void _hienConTro({bool phong = false}) {
    final p = _phien, vung = _vungKt;
    if (p == null || vung == null || !mounted) return;
    final m = _bienDoi.value;
    var z = m.getMaxScaleOnAxis();
    var tx = m.getTranslation().x, ty = m.getTranslation().y;
    final caoDong = (p.dong.dai1 - p.dong.dai0) * _sKt;
    if (phong) z = math.max(z, (56 / math.max(caoDong, 1)).clamp(1.0, 8.0));
    final (dTren, dDuoi) = p.dong.daiTai(p.xConTro());
    final cx = _gocKt.dx + p.xConTro() * _sKt, cy = _gocKt.dy + (dTren + dDuoi) / 2 * _sKt;
    final x = z * cx + tx, y = z * cy + ty;
    if (phong || x < 40 || x > vung.width - 40) tx = vung.width / 2 - z * cx;
    if (phong || y < caoDong * z || y > vung.height - caoDong * z) ty = vung.height * 0.4 - z * cy;
    tx = tx.clamp(vung.width - z * vung.width, 0.0);
    ty = ty.clamp(vung.height - z * vung.height, 0.0);
    _bienDoi.value = Matrix4(z, 0, 0, 0, 0, z, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1);
  }

  // ---------------------------------------------------------------- vẽ lại bằng phông (theo khối)

  /// Nhận dạng ảnh đang sửa (có đệm), gộp khối, đánh dấu khối có mực màu.
  Future<void> _taiKhoi() async {
    if (t.tepKq.isEmpty) return;
    final tep = t.tepKq[_anh];
    setState(() {
      _tepChu = tep;
      _chu = null;
      _khoi = [];
      _khoa = [];
      _loiSua = null;
      _chon = null;
    });
    try {
      final chu = await kho.nhanDang(widget.hoSo, tep);
      final khoi = timKhoi(chu);
      final khoa = await kiemMucMauNen(await File(kho.duongDan(widget.hoSo, tep)).readAsBytes(), khoi);
      if (!mounted || _tepChu != tep) return;
      setState(() {
        _chu = chu;
        _khoi = khoi;
        _khoa = khoa;
      });
    } catch (e) {
      if (mounted && _tepChu == tep) setState(() => _loiSua = 'Không nhận dạng được chữ: $e');
    }
  }

  Future<void> _chamKhoi(int i) async {
    if (_dangAp || _chon == i) return;
    if (_khoa[i]) {
      _bao(baoMucMau);
      return;
    }
    final k = _khoi[i];
    setState(() {
      _chon = i;
      _kieu = null;
      _phongChon = null;
      _oNhap.text = k.chu;
      _canHien = true;
    });
    try {
      final kieu = await doKieuChu(await File(kho.duongDan(widget.hoSo, _tepChu!)).readAsBytes(), k);
      if (mounted && _chon == i) setState(() => _kieu = kieu);
    } on LoiSuaChu catch (e) {
      if (mounted && _chon == i) {
        _bao(e.loi);
        _huy();
      }
    } catch (_) {
      // chưa đoán được phông: lúc áp sẽ đo lại
    }
  }

  void _huy() {
    FocusScope.of(context).unfocus();
    setState(() => _chon = null);
  }

  Future<void> _doiPhong(PhongChu? p) async {
    final i = _chon, kieu = _kieu;
    if (i == null) return;
    setState(() => _phongChon = p);
    if (kieu == null) return;
    final moi = await doKieuChuTheoPhong(kieu, _khoi[i], p);
    if (mounted && _chon == i) setState(() => _kieu = moi);
  }

  /// Áp chữ mới cho khối đang sửa, ghi thành ảnh kết quả mới của trang.
  Future<void> _xong() async {
    final i = _chon, chu = _chu, tep = _tepChu;
    if (i == null || chu == null || tep == null || _dangAp) return;
    final k = _khoi[i];
    final moi = _oNhap.text
        .split('\n')
        .map((d) => d.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where((d) => d.isNotEmpty)
        .join('\n');
    if (moi == k.chu && _phongChon == null) {
      _huy();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _dangAp = true);
    try {
      final anh = await File(kho.duongDan(widget.hoSo, tep)).readAsBytes();
      final kq = await suaKhoi(anh, chu, k, moi, kieu: _kieu, phong: _phongChon);
      await kho.ghiSuaChu(widget.hoSo, t, _anh, kq.anh, kq.chu);
      final khoi = timKhoi(kq.chu);
      final khoa = await kiemMucMauNen(kq.anh, khoi);
      if (!mounted) return;
      setState(() {
        _tepChu = t.tepKq[_anh];
        _chu = kq.chu;
        _khoi = khoi;
        _khoa = khoa;
        _chon = null;
      });
      _bao(kq.tran
          ? 'Đã sửa. Chữ mới dài hơn nên phần cuối trang bị đẩy ra ngoài mép dưới; bấm Hoàn tác nếu không muốn'
          : 'Đã sửa chữ · ${kq.kieu.phong.ten}, khoảng ${kq.kieu.coPt(chu.rong).toStringAsFixed(1)} pt');
    } on LoiSuaChu catch (e) {
      if (mounted) _bao(e.loi);
    } catch (e) {
      if (mounted) _bao('Không sửa được: $e');
    } finally {
      if (mounted) setState(() => _dangAp = false);
    }
  }

  Future<void> _hoanTac() async {
    if (_dangAp) return;
    FocusScope.of(context).unfocus();
    setState(() => _chon = null);
    await kho.hoanTacSua(widget.hoSo, t);
    if (mounted) await _taiLai();
  }

  /// Phóng, cuộn để khối đang sửa hiện rõ ở đầu vùng ảnh (cả khi bàn phím làm vùng ảnh thấp đi).
  void _hienKhoi(Size vung, double s, Offset goc) {
    final i = _chon;
    if (i == null || !mounted || i >= _khoi.length) return;
    final k = _khoi[i];
    final le = 0.3 * k.coChu;
    final bx = goc.dx + (k.xTrai - le) * s, by = goc.dy + (k.y0 - le) * s;
    final bw = (k.xPhai - k.xTrai + 2 * le) * s, bh = (k.y1 - k.y0 + 2 * le) * s;
    final z = math.min((vung.width - 16) / bw, vung.height * 0.6 / bh).clamp(1.0, 6.0);
    final tx = (vung.width - z * bw) / 2 - z * bx, ty = 12 - z * by;
    _bienDoi.value = Matrix4(z, 0, 0, 0, 0, z, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1);
  }

  // ---------------------------------------------------------------- giao diện

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_suaChu,
      onPopInvokedWithResult: (daVe, _) {
        if (daVe) return;
        final p = _phien;
        if (p != null) {
          // dòng đã sửa: không bỏ ngang vì lỡ tay bấm quay lại, phải chọn Xong hoặc Hủy
          p.daDoi ? _bao('Bấm Xong để giữ chỗ vừa sửa, hoặc Hủy để bỏ') : _huyKyTu();
        } else if (_chon != null) {
          _huy();
        } else {
          _thoatSuaChu();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: ListenableBuilder(
            listenable: kho,
            builder: (context, _) {
              final viTri = widget.hoSo.trang.indexOf(t) + 1;
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
                  child: Row(children: [
                    IconButton(tooltip: 'Quay lại', icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.maybePop(context)),
                    Expanded(
                      child: Text(
                          _suaChu ? '${_veLai ? 'Sửa chữ' : 'Sửa ký tự'} · trang $viTri' : 'Trang $viTri / ${widget.hoSo.trang.length}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                    if (!_suaChu)
                      FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size(64, 40), shape: const StadiumBorder()),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Xong'),
                      ),
                  ]),
                ),
                if (_suaChu)
                  _dauSuaChu()
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ChonNhom<bool>(
                      giaTri: _xemGoc,
                      cacMuc: const {false: 'Kết quả', true: 'Cắt, nắn phẳng'},
                      khiChon: (v) => setState(() => _xemGoc = v),
                    ),
                  ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: _xemGoc ? const Color(0xFF5A4433) : const Color(0xFFDCE2E7),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(fit: StackFit.expand, children: [
                      _suaChu ? (_veLai ? _vungSuaChu() : _vungKyTu()) : (_xemGoc ? _vungGoc() : _vungKetQua()),
                      if (t.dangXuLy || _dangAp)
                        const Positioned(
                          top: 12,
                          right: 12,
                          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                        ),
                    ]),
                  ),
                ),
                if (_suaChu) (_veLai ? _chanSuaChu() : _chanKyTu()) else ..._chanThuong(),
              ]);
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _chanThuong() => [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(
            t.trangThai == 'loi'
                ? 'Xử lý lỗi: ${t.loi ?? ''}'
                : _xemGoc
                    ? 'Kéo góc hoặc giữa cạnh cho khớp mép giấy (có kính lúp); thả tay là trang được nắn lại'
                    : (t.tepKq.length > 1 ? 'Đã tách thành 2 trang theo gáy sách' : 'Nền trắng đều, giữ màu con dấu và chữ ký'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: t.trangThai == 'loi' ? Mau.do_ : Mau.chuPhu),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            _CongCu(icon: Icons.rotate_right, ten: 'Xoay', onTap: () => _doi(() => kho.xoayTrang(widget.hoSo, t, 90), xuLyLai: false)),
            _CongCu(
                icon: Icons.crop_free,
                ten: 'Tự tìm khung',
                onTap: () => _doi(() {
                      t.khungTay = null;
                      t.tc.timMep = true;
                    })),
            _CongCu(icon: Icons.crop_square, ten: 'Không cắt', onTap: () {
              if (t.rongGoc == 0) return;
              final w = t.rongGoc - 1.0, h = t.caoGoc - 1.0;
              _doi(() => t.khungTay = [(0, 0), (w, 0), (w, h), (0, h)]);
            }),
            _CongCu(
              icon: Icons.text_snippet_outlined,
              ten: 'Văn bản',
              onTap: t.trangThai != 'xong' || t.tepKq.isEmpty
                  ? null
                  : () => xemVanBan(context, widget.hoSo, [...t.tepKq], 'Văn bản · trang ${widget.hoSo.trang.indexOf(t) + 1}'),
            ),
            _CongCu(icon: Icons.edit_note, ten: 'Sửa chữ', onTap: t.trangThai != 'xong' || t.tepKq.isEmpty ? null : _vaoSuaChu),
            _CongCu(icon: Icons.delete_outline, ten: 'Xóa trang', mau: Mau.do_, onTap: _xoaTrang),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: The(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in cheDoLamSach.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: t.tc.cheDo == e.key,
                    showCheckmark: false,
                    onSelected: (_) => _doi(() => t.tc.cheDo = e.key),
                  ),
                FilterChip(
                  avatar: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text('Nắn trang cong'),
                  tooltip: 'Kéo thẳng dòng chữ bị võng (trang sách mở, giấy cong)',
                  selected: t.tc.nanCong,
                  showCheckmark: false,
                  onSelected: (v) => _doi(() => t.tc.nanCong = v),
                ),
                FilterChip(
                  avatar: const Icon(Icons.crop, size: 18),
                  label: const Text('Cắt sát chữ'),
                  tooltip: 'Cắt sát vùng chữ, xóa vết, nền tối, ngón tay ngoài vùng chữ',
                  selected: t.tc.catSatChu,
                  showCheckmark: false,
                  onSelected: (v) => _doi(() => t.tc.catSatChu = v),
                ),
              ]),
              const SizedBox(height: 6),
              _ThanhTruot(
                ten: 'Độ trắng nền',
                giaTri: _doTrang,
                khiDoi: (v) => setState(() => _doTrang = v),
                khiXong: (v) async {
                  if (!await _doi(() => t.tc.doTrang = v)) setState(() => _doTrang = t.tc.doTrang);
                },
              ),
              _ThanhTruot(
                ten: 'Độ đậm chữ',
                giaTri: _doDam,
                khiDoi: (v) => setState(() => _doDam = v),
                khiXong: (v) async {
                  if (!await _doi(() => t.tc.doDam = v)) setState(() => _doDam = t.tc.doDam);
                },
              ),
              _ThanhTruot(
                ten: 'Khử nhiễu',
                giaTri: _khuNhieu,
                khiDoi: (v) => setState(() => _khuNhieu = v),
                khiXong: (v) async {
                  if (!await _doi(() => t.tc.khuNhieu = v)) setState(() => _khuNhieu = t.tc.khuNhieu);
                },
              ),
            ]),
          ),
        ),
      ];

  /// Dòng nhắc ở đầu chế độ Sửa chữ: chọn cách sửa; trang sách tách đôi thì chọn ảnh trái, phải.
  Widget _dauSuaChu() {
    final String nhac;
    if (_veLai) {
      final nghi = _chon == null ? <String>[] : [for (final d in _khoi[_chon!].dong) for (final w in d.tu) if (w.tinCay < 70) w.chu];
      nhac = _chon != null
          ? 'Sửa ngay trong ô rồi bấm Xong; Enter để xuống dòng. Cả khối được vẽ lại bằng phông nên soát cả chữ máy đọc'
              '${nghi.isEmpty ? '' : ' · máy đọc chưa chắc: ${nghi.take(4).join(', ')}${nghi.length > 4 ? '…' : ''}'}'
          : _khoi.isEmpty
              ? 'Đang tìm chữ trên trang…'
              : 'Cả khối chữ được vẽ lại bằng phông (không giữ nét gốc). Chạm một khối để viết lại. Khối viền cam có con dấu, chữ ký nên bị khóa';
    } else {
      final doc = _soTrangKhac > _trangKhac.length ? ' · đang đọc trang khác để có thêm ký tự mẫu (${_trangKhac.length}/$_soTrangKhac)' : '';
      nhac = _phien != null
          ? 'Con trỏ đỏ trong dòng viền cam; chạm trong dòng để dời con trỏ, chạm giữ rồi kéo để bôi chọn (đổi cỡ, '
              'phông). Chữ không sửa giữ nguyên từng điểm ảnh'
          : _kt == null
              ? 'Đang tìm chữ, khung từng ký tự trên trang…'
              : 'Chạm vào dòng cần sửa (phóng to để chạm đúng chỗ). Dòng viền cam có con dấu, chữ ký nên bị khóa$doc';
    }
    final ranh = _phien == null && _chon == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(children: [
        if (ranh)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ChonNhom<bool>(
                giaTri: _veLai,
                cacMuc: const {false: 'Sửa ký tự (giữ nguyên bản gốc)', true: 'Vẽ lại bằng phông'},
                khiChon: _doiCachSua,
              ),
            ),
          ),
        if (t.tepKq.length > 1 && ranh)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ChonNhom<int>(
              giaTri: _anh,
              cacMuc: {for (var i = 0; i < t.tepKq.length; i++) i: i == 0 ? 'Trang trái' : 'Trang phải'},
              khiChon: (v) {
                if (v == _anh) return;
                _bienDoi.value = Matrix4.identity();
                _anh = v;
                _taiLai();
              },
            ),
          ),
        Text(nhac, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Mau.chuPhu)),
      ]),
    );
  }

  /// Thanh dưới của chế độ Sửa chữ: đang sửa khối thì Hủy, phông, Xong; không thì Hoàn tác, Thoát.
  Widget _chanSuaChu() {
    final i = _chon;
    if (i == null) {
      final coHoanTac = t.lichSuSua.isNotEmpty && !_dangAp;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(children: [
          _CongCu(icon: Icons.undo, ten: coHoanTac ? 'Hoàn tác (${t.lichSuSua.length})' : 'Hoàn tác', onTap: coHoanTac ? _hoanTac : null),
          _CongCu(icon: Icons.check_circle_outline, ten: 'Thoát sửa chữ', onTap: _dangAp ? null : _thoatSuaChu),
        ]),
      );
    }
    final kieu = _kieu, k = _khoi[i];
    final p = _phongChon ?? kieu?.phong;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(children: [
        TextButton(onPressed: _dangAp ? null : _huy, child: const Text('Hủy')),
        Expanded(
          child: PopupMenuButton<int>(
            tooltip: 'Đổi phông',
            enabled: !_dangAp,
            onSelected: (v) => _doiPhong(v < 0 ? null : PhongChu.tatCa[v]),
            itemBuilder: (_) => [
              const PopupMenuItem(value: -1, child: Text('Tự đoán theo chữ cũ')),
              for (var j = 0; j < PhongChu.tatCa.length; j++)
                PopupMenuItem(value: j, child: Text(PhongChu.tatCa[j].ten, style: PhongChu.tatCa[j].kieu(16))),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(p == null ? 'Đang đoán phông…' : '${p.ten} ▾',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                    [
                      if (kieu != null && _chu != null) 'khoảng ${kieu.coPt(_chu!.rong).toStringAsFixed(1)} pt',
                      tenCanLe[k.can] ?? '',
                    ].join(' · '),
                    maxLines: 1,
                    style: const TextStyle(fontSize: 11, color: Mau.chuPhu)),
              ]),
            ),
          ),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
          onPressed: _dangAp ? null : _xong,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Xong'),
        ),
      ]),
    );
  }

  /// Thanh dưới của Sửa ký tự: đang sửa dòng thì ← → ⌫ ⌦, ô gõ chữ cần chèn + Chèn, Hủy, Xong; không thì Hoàn tác, Thoát.
  Widget _chanKyTu() {
    final p = _phien;
    if (p == null) {
      final coHoanTac = t.lichSuSua.isNotEmpty && !_dangAp;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(children: [
          _CongCu(icon: Icons.undo, ten: coHoanTac ? 'Hoàn tác (${t.lichSuSua.length})' : 'Hoàn tác', onTap: coHoanTac ? _hoanTac : null),
          _CongCu(icon: Icons.check_circle_outline, ten: 'Thoát sửa chữ', onTap: _dangAp ? null : _thoatSuaChu),
        ]),
      );
    }
    final tt = p.thaoTac();
    final chuaChac = {for (final m in tt.manh) if (m.chuaChac && m.chu.trim().isNotEmpty) m.chu};
    final kt = _kt;
    final nhac = [
      if (chuaChac.isNotEmpty)
        'Ký tự ${chuaChac.map((c) => '“$c”').join(', ')} chưa có mẫu tốt trên trang (viền vàng): chạm giữ vào một ký tự '
            'đúng như vậy trên trang để dùng làm mẫu',
      if (kt != null && p.vuotLe(kt.lePhai)) 'Chú ý: dòng đã dài quá lề phải',
    ];
    final ban = _dangGo || _dangAp;
    Widget nut(IconData icon, String ten, void Function(PhienSuaDong p) viec, {bool lat = false}) => IconButton(
          tooltip: ten,
          visualDensity: VisualDensity.compact,
          onPressed: ban ? null : () => _thaoTac(viec),
          icon: lat ? Transform.flip(flipX: true, child: Icon(icon)) : Icon(icon),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (nhac.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Mau.camNen, borderRadius: BorderRadius.circular(10)),
            child: Text(nhac.join('. '), style: const TextStyle(fontSize: 12, color: Mau.camChu)),
          ),
        if (p.coChon) _thanhDinhDang(p),
        Row(children: [
          nut(Icons.arrow_back, 'Lùi con trỏ', (p) {
            p.trai(chon: _boiChon);
            if (_boiChon) _napKieuChon();
          }),
          nut(Icons.arrow_forward, 'Tiến con trỏ', (p) {
            p.phai(chon: _boiChon);
            if (_boiChon) _napKieuChon();
          }),
          nut(Icons.backspace_outlined, 'Xóa lùi (ký tự trước con trỏ)', (p) => p.xoaLui()),
          nut(Icons.backspace_outlined, 'Xóa tới (ký tự sau con trỏ)', (p) => p.xoaToi(), lat: true),
          const Spacer(),
          TextButton(onPressed: ban ? null : _huyKyTu, child: const Text('Hủy')),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
            onPressed: ban ? null : _xongKyTu,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Xong'),
          ),
        ]),
        Row(children: [
          IconButton(
            tooltip: _boiChon ? 'Đang bôi chọn: ← → mở rộng đoạn chọn' : 'Bôi chọn (đổi cỡ, đổi phông một đoạn)',
            visualDensity: VisualDensity.compact,
            isSelected: _boiChon,
            style: IconButton.styleFrom(backgroundColor: _boiChon ? Mau.nhanNhat : null),
            onPressed: ban ? null : () => setState(() => _boiChon = !_boiChon),
            icon: Icon(Icons.highlight_alt, color: _boiChon ? Mau.nhan : null),
          ),
          Expanded(
            child: TextField(
              controller: _oChen,
              enabled: !_dangAp,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _chen(),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Chữ cần chèn ở con trỏ',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 44), backgroundColor: Mau.nhanNhat, foregroundColor: Mau.nhanDam),
            onPressed: ban ? null : _chen,
            child: _dangGo ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Chèn'),
          ),
        ]),
      ]),
    );
  }

  /// Thanh định dạng đoạn bôi chọn: cỡ (− +, theo pt) và phông (giữ nét gốc hoặc một trong 8 phông Liberation).
  Widget _thanhDinhDang(PhienSuaDong p) {
    final k = _kieuChon, ban = _dangGo || _dangAp || k == null;
    final chu = p.chuChon;
    final String phong, co;
    if (k == null) {
      phong = 'Đang đoán phông…';
      co = '…';
    } else {
      final (kc, tl, ve) = k;
      phong = ve ? PhongChu.tatCa[kc.phong].ten : 'Giữ nét gốc';
      co = '${(kc.co * tl * _pt).toStringAsFixed(1)} pt';
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Mau.nhanNhat, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Flexible(
          child: Text('“${chu.length > 14 ? '${chu.substring(0, 13)}…' : chu}”',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Mau.nhanDam)),
        ),
        IconButton(
            tooltip: 'Nhỏ hơn 0,5 pt',
            visualDensity: VisualDensity.compact,
            onPressed: ban ? null : () => _doiCoChon(-0.5),
            icon: const Icon(Icons.text_decrease)),
        Text(co, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        IconButton(
            tooltip: 'Lớn hơn 0,5 pt',
            visualDensity: VisualDensity.compact,
            onPressed: ban ? null : () => _doiCoChon(0.5),
            icon: const Icon(Icons.text_increase)),
        Expanded(
          child: PopupMenuButton<int>(
            tooltip: 'Đổi phông đoạn chọn',
            enabled: !ban,
            onSelected: _doiPhongChon,
            itemBuilder: (_) => [
              const PopupMenuItem(value: -1, child: Text('Giữ nét gốc (chỉ đổi cỡ)')),
              for (var j = 0; j < PhongChu.tatCa.length; j++)
                PopupMenuItem(value: j, child: Text(PhongChu.tatCa[j].ten, style: PhongChu.tatCa[j].kieu(16))),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text('$phong ▾',
                  maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ]),
    );
  }

  /// Ảnh trang (phóng to, kéo được): chạm vào dòng để sửa; dòng đang sửa được dựng lại ngay trên ảnh sau mỗi thao tác.
  Widget _vungKyTu() {
    final kt = _kt, anh = _anhKt, tep = _tepChu;
    if (_loiKt != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_loiKt!, style: const TextStyle(color: Mau.do_))));
    }
    if (kt == null || anh == null || tep == null) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          SizedBox(height: 12),
          Text('Đang tìm chữ, khung từng ký tự…', style: TextStyle(color: Mau.chuPhu)),
        ]),
      );
    }
    return LayoutBuilder(builder: (context, hop) {
      const le = 8.0;
      final vung = Size(hop.maxWidth, hop.maxHeight);
      final s = math.min((vung.width - 2 * le) / kt.rong, (vung.height - 2 * le) / kt.cao);
      final goc = Offset((vung.width - kt.rong * s) / 2, (vung.height - kt.cao * s) / 2);
      final doi = _vungKt != null && _vungKt != vung;
      _sKt = s;
      _gocKt = goc;
      _vungKt = vung;
      if (doi && _phien != null) WidgetsBinding.instance.addPostFrameCallback((_) => _hienConTro());
      final p = _phien, xem = _xemTruoc;
      return InteractiveViewer(
        transformationController: _bienDoi,
        maxScale: 10,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (e) => _chamKyTu(e.localPosition),
          onLongPressStart: (e) => _giuBatDau(e.localPosition),
          onLongPressMoveUpdate: (e) => _giuKeo(e.localPosition),
          onLongPressEnd: (e) => _giuXong(e.localPosition),
          child: SizedBox(
            width: vung.width,
            height: vung.height,
            child: Stack(children: [
              Positioned(
                left: goc.dx,
                top: goc.dy,
                width: kt.rong * s,
                height: kt.cao * s,
                child: Image.file(File(kho.duongDan(widget.hoSo, tep)), fit: BoxFit.fill, gaplessPlayback: true),
              ),
              if (p != null && xem != null)
                Positioned(
                  left: goc.dx,
                  top: goc.dy + _vungXem.$1 * s,
                  width: kt.rong * s,
                  height: (_vungXem.$2 - _vungXem.$1) * s,
                  child: Image.memory(xem, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium),
                ),
              Positioned.fill(
                child: IgnorePointer(
                  child: ListenableBuilder(
                    listenable: _bienDoi,
                    builder: (_, _) => CustomPaint(painter: _VeKyTu(kt, p, s, goc, _bienDoi.value.getMaxScaleOnAxis())),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }

  /// Ảnh trang với khung mờ quanh từng khối chữ; khối đang sửa có ô nhập phủ đúng chỗ, phóng to, kéo được.
  Widget _vungSuaChu() {
    final chu = _chu, tep = _tepChu;
    if (_loiSua != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_loiSua!, style: const TextStyle(color: Mau.do_))));
    }
    if (chu == null || tep == null || chu.rong == 0) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          SizedBox(height: 12),
          Text('Đang nhận dạng chữ…', style: TextStyle(color: Mau.chuPhu)),
        ]),
      );
    }
    return LayoutBuilder(builder: (context, hop) {
      const le = 8.0;
      final vung = Size(hop.maxWidth, hop.maxHeight);
      final s = math.min((vung.width - 2 * le) / chu.rong, (vung.height - 2 * le) / chu.cao);
      final goc = Offset((vung.width - chu.rong * s) / 2, (vung.height - chu.cao * s) / 2);
      if (_chon != null && (_canHien || _coVung != vung)) {
        _canHien = false;
        WidgetsBinding.instance.addPostFrameCallback((_) => _hienKhoi(vung, s, goc));
      }
      _coVung = vung;
      return InteractiveViewer(
        transformationController: _bienDoi,
        maxScale: 8,
        child: SizedBox(
          width: vung.width,
          height: vung.height,
          child: Stack(children: [
            Positioned(
              left: goc.dx,
              top: goc.dy,
              width: chu.rong * s,
              height: chu.cao * s,
              child: Image.file(File(kho.duongDan(widget.hoSo, tep)), fit: BoxFit.fill, gaplessPlayback: true),
            ),
            for (var i = 0; i < _khoi.length; i++)
              if (i != _chon) _oKhoi(i, s, goc),
            if (_chon != null) _oSua(_khoi[_chon!], s, goc),
          ]),
        ),
      );
    });
  }

  Widget _oKhoi(int i, double s, Offset goc) {
    final k = _khoi[i];
    final khoa = i < _khoa.length && _khoa[i];
    final m = khoa ? Mau.cam : Mau.nhan;
    final le = 0.25 * k.coChu;
    return Positioned(
      left: goc.dx + (k.x0 - le) * s,
      top: goc.dy + (k.y0 - le) * s,
      width: (k.x1 - k.x0 + 2 * le) * s,
      height: (k.y1 - k.y0 + 2 * le) * s,
      child: Semantics(
        button: true,
        label: khoa ? 'Khối chữ ${i + 1}, có con dấu, chữ ký' : 'Khối chữ ${i + 1}: ${k.chu}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _chamKhoi(i),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: m.withValues(alpha: 0.07),
              border: Border.all(color: m.withValues(alpha: 0.55), width: 1),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }

  /// Ô nhập phủ đúng chỗ khối trên ảnh: nền trắng, rộng bằng bề ngang dàn chữ của khối, chữ theo phông, cỡ,
  /// màu, khoảng cách dòng, căn lề đoán được (theo tỉ lệ phóng của ảnh).
  Widget _oSua(KhoiChu k, double s, Offset goc) {
    final kieu = _kieu;
    final co = kieu?.co ?? k.coChu;
    final p = _phongChon ?? kieu?.phong ?? PhongChu.tatCa.first;
    // dàn ô nhập theo điểm ảnh của trang rồi thu theo tỉ lệ hiện ảnh: chữ cỡ nhỏ trên màn hình bị làm tròn
    // khoảng cách ký tự nên rộng hơn chữ thật; vẽ ở cỡ thật rồi thu thì ngắt dòng giống bản sẽ áp hơn
    final le = 0.3 * k.coChu;
    return Positioned(
      left: goc.dx + (k.xTrai - le) * s,
      top: goc.dy + (k.y0 - le) * s,
      child: Transform.scale(
        scale: s,
        alignment: Alignment.topLeft,
        child: MediaQuery.withNoTextScaling(
          child: Container(
            // chừa 2% như lúc dàn chữ thật (ve_chu.dart), cộng chỗ cho con trỏ
            width: (k.xPhai - k.xTrai) * 1.02 + math.max(2, co * 0.08) + 2 * le,
            padding: EdgeInsets.all(le),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Mau.nhan, width: 1 / s),
              boxShadow: [BoxShadow(color: const Color(0x33000000), blurRadius: 6 / s)],
            ),
            child: TextField(
              controller: _oNhap,
              autofocus: true,
              enabled: !_dangAp,
              maxLines: null,
              minLines: k.dong.length,
              keyboardType: TextInputType.multiline,
              textAlign: switch (k.can) {
                'giua' => TextAlign.center,
                'phai' => TextAlign.right,
                'deu' => TextAlign.justify,
                _ => TextAlign.left,
              },
              style: p.kieu(co, mau: kieu?.mauHien ?? Mau.chu, cao: k.khoangDong / co),
              cursorWidth: math.max(2, co * 0.08),
              decoration: const InputDecoration.collapsed(hintText: 'Nhập chữ mới'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _vungKetQua() {
    if (t.tepKq.isEmpty) {
      return const Center(child: Text('Đang xử lý…', style: TextStyle(color: Mau.chuPhu)));
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        for (final tep in t.tepKq)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InteractiveViewer(
                maxScale: 5,
                child: Image.file(File(kho.duongDan(widget.hoSo, tep)), fit: BoxFit.contain, gaplessPlayback: true),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _vungGoc() {
    if (t.rongGoc == 0) {
      return const Center(child: Text('Đang đọc ảnh…', style: TextStyle(color: Colors.white)));
    }
    return LayoutBuilder(builder: (context, hop) {
      const le = 20.0;
      final w = t.rongGoc.toDouble(), h = t.caoGoc.toDouble();
      final s = math.min((hop.maxWidth - 2 * le) / w, (hop.maxHeight - 2 * le) / h);
      final dx = (hop.maxWidth - w * s) / 2, dy = (hop.maxHeight - h * s) / 2;
      final khung = _khungHien();
      Offset raMan(Diem p) => Offset(p.$1 * s + dx, p.$2 * s + dy);
      Diem raAnh(Offset o) => (((o.dx - dx) / s).clamp(0.0, w - 1), ((o.dy - dy) / s).clamp(0.0, h - 1));
      // tay cầm: 0..3 là góc, 4..7 là giữa cạnh i → i+1 (kéo cạnh thì dời cả hai góc theo pháp tuyến cạnh)
      final tayCam = [
        for (final p in khung) raMan(p),
        for (var i = 0; i < 4; i++) (raMan(khung[i]) + raMan(khung[(i + 1) % 4])) / 2,
      ];
      final keo = _dangKeo;
      // kính lúp soi góc đang kéo (hoặc giữa cạnh đang kéo), đặt ở góc trên phía không có ngón tay
      final soi = keo == null ? null : tayCam[keo];
      const coKinh = 120.0;
      final kinhBenPhai = soi != null && soi.dx < hop.maxWidth / 2;
      final tamKinh = Offset(kinhBenPhai ? hop.maxWidth - coKinh / 2 - 12 : coKinh / 2 + 12, coKinh / 2 + 12);

      return GestureDetector(
        onPanStart: (e) {
          var gan = -1;
          var kc = 44.0;
          for (var i = 0; i < 8; i++) {
            // góc được ưu tiên hơn giữa cạnh khi hai tay cầm gần nhau
            final d = (tayCam[i] - e.localPosition).distance + (i >= 4 ? 8 : 0);
            if (d < kc) {
              kc = d;
              gan = i;
            }
          }
          if (gan >= 0) {
            setState(() {
              _dangKeo = gan;
              _goc = [...khung];
              _batDauKeo = e.localPosition;
              _gocLucDau = [...khung];
            });
          }
        },
        onPanUpdate: (e) {
          final i = _dangKeo;
          final g0 = _gocLucDau, p0 = _batDauKeo;
          if (i == null || _goc == null || g0 == null || p0 == null) return;
          setState(() {
            if (i < 4) {
              _goc![i] = raAnh(e.localPosition);
            } else {
              final a = i - 4, b = (a + 1) % 4;
              final ux = g0[b].$1 - g0[a].$1, uy = g0[b].$2 - g0[a].$2;
              final l = math.max(math.sqrt(ux * ux + uy * uy), 1e-6);
              final nx = -uy / l, ny = ux / l;
              final d = (e.localPosition.dx - p0.dx) / s * nx + (e.localPosition.dy - p0.dy) / s * ny;
              _goc![a] = ((g0[a].$1 + nx * d).clamp(0.0, w - 1), (g0[a].$2 + ny * d).clamp(0.0, h - 1));
              _goc![b] = ((g0[b].$1 + nx * d).clamp(0.0, w - 1), (g0[b].$2 + ny * d).clamp(0.0, h - 1));
            }
          });
        },
        onPanEnd: (_) {
          if (_dangKeo == null) return;
          final moi = _goc;
          setState(() {
            _dangKeo = null;
            _goc = null;
            _gocLucDau = null;
            _batDauKeo = null;
          });
          _doi(() => t.khungTay = moi);
        },
        child: Stack(children: [
          Positioned(
            left: dx,
            top: dy,
            width: w * s,
            height: h * s,
            child: RotatedBox(
              quarterTurns: t.xoay ~/ 90,
              child: Image.file(File(kho.duongDan(widget.hoSo, t.tepGoc)), fit: BoxFit.fill, cacheWidth: 1600),
            ),
          ),
          Positioned.fill(child: CustomPaint(painter: _VeKhungCat([for (final p in khung) raMan(p)], keo))),
          // kính lúp kiểu CamScanner: phóng to chỗ đang kéo, có dấu chữ thập để đặt góc đúng mép giấy
          if (soi != null)
            Positioned(
              left: tamKinh.dx - coKinh / 2,
              top: tamKinh.dy - coKinh / 2,
              child: IgnorePointer(
                child: Stack(alignment: Alignment.center, children: [
                  RawMagnifier(
                    size: const Size(coKinh, coKinh),
                    magnificationScale: 2.5,
                    focalPointOffset: soi - tamKinh,
                    decoration: const MagnifierDecoration(
                      shape: CircleBorder(side: BorderSide(color: Colors.white, width: 3)),
                      shadows: [BoxShadow(color: Color(0x66000000), blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(width: 22, height: 22, child: CustomPaint(painter: _ChuThap())),
                ]),
              ),
            ),
        ]),
      );
    });
  }
}

/// Lớp vẽ của Sửa ký tự: chưa sửa thì viền mờ quanh từng dòng (dòng có mực màu viền cam); đang sửa thì dải dòng viền
/// cam nét đứt, ký tự chưa chắc viền vàng, con trỏ đỏ. Nét vẽ giữ cỡ trên màn hình dù phóng to ([z]).
class _VeKyTu extends CustomPainter {
  _VeKyTu(this.kt, this.p, this.s, this.goc, this.z);
  final TrangKyTu kt;
  final PhienSuaDong? p;
  final double s, z;
  final Offset goc;

  Offset _diem(num x, double y) => Offset(goc.dx + x * s, goc.dy + y * s);

  /// Dải dòng từ cột [x0] tới [x1], nghiêng theo dòng (ảnh chụp lệch), co vào [lui] điểm ảnh trên, dưới.
  Path _dai(DongAnh d, double x0, double x1, [double lui = 0]) {
    final (t0, d0) = d.daiTai(x0);
    final (t1, d1) = d.daiTai(x1);
    return Path()
      ..moveTo(_diem(x0, t0 + lui).dx, _diem(x0, t0 + lui).dy)
      ..lineTo(_diem(x1, t1 + lui).dx, _diem(x1, t1 + lui).dy)
      ..lineTo(_diem(x1, d1 - lui).dx, _diem(x1, d1 - lui).dy)
      ..lineTo(_diem(x0, d0 - lui).dx, _diem(x0, d0 - lui).dy)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = this.p;
    final net = 1.5 / z;
    if (p == null) {
      for (final d in kt.dong) {
        final m = d.mucMau ? Mau.cam : Mau.nhan;
        final r = _dai(d, d.x0 - 3.0, d.x1 + 3.0, 1);
        canvas.drawPath(r, Paint()..color = m.withValues(alpha: 0.06));
        canvas.drawPath(
            r,
            Paint()
              ..color = m.withValues(alpha: 0.45)
              ..style = PaintingStyle.stroke
              ..strokeWidth = net);
      }
      return;
    }
    final tt = p.thaoTac();
    if (p.coChon) {
      final (xa, xb) = p.xDoanChon();
      canvas.drawPath(_dai(p.dong, xa.toDouble(), xb.toDouble()), Paint()..color = const Color(0x553D8BFD));
    }
    var x = tt.x0.toDouble();
    final vang = Paint()
      ..color = const Color(0xFFF2B705)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 / z;
    for (final m in tt.manh) {
      if (m.chuaChac) canvas.drawPath(_dai(p.dong, x, x + m.rong, 1), vang);
      x += m.rong;
    }
    // dải dòng: viền cam nét đứt, nghiêng theo dòng
    final xa = tt.x0 - 3.0, xb = math.max(tt.x1Cu.toDouble(), x) + 3;
    final (t0, d0) = p.dong.daiTai(xa);
    final (t1, d1) = p.dong.daiTai(xb);
    final cam = Paint()
      ..color = Mau.cam
      ..strokeWidth = net;
    final buoc = 6 / z;
    void netDut(Offset a, Offset b) {
      final dai = (b - a).distance;
      if (dai == 0) return;
      final huong = (b - a) / dai;
      for (var t = 0.0; t < dai; t += 2 * buoc) {
        canvas.drawLine(a + huong * t, a + huong * math.min(t + buoc, dai), cam);
      }
    }

    netDut(_diem(xa, t0), _diem(xb, t1));
    netDut(_diem(xa, d0), _diem(xb, d1));
    canvas.drawLine(_diem(xa, t0), _diem(xa, d0), cam);
    canvas.drawLine(_diem(xb, t1), _diem(xb, d1), cam);
    // con trỏ đỏ
    final xc = p.xConTro();
    final (ct, cd) = p.dong.daiTai(xc);
    canvas.drawLine(
        _diem(xc, ct) + Offset(0, net),
        _diem(xc, cd) - Offset(0, net),
        Paint()
          ..color = const Color(0xFFD0021B)
          ..strokeWidth = 2.5 / z);
  }

  @override
  bool shouldRepaint(_VeKyTu old) => true;
}

class _VeKhungCat extends CustomPainter {
  _VeKhungCat(this.goc, this.dangKeo);
  final List<Offset> goc;
  final int? dangKeo;

  @override
  void paint(Canvas canvas, Size size) {
    // làm tối phần ngoài khung để thấy rõ phần sẽ giữ lại
    final ngoai = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPolygon(goc, true);
    canvas.drawPath(ngoai, Paint()..color = const Color(0x66000000));
    canvas.drawPath(
        Path()..addPolygon(goc, true),
        Paint()
          ..color = Mau.cam
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
    for (var i = 0; i < 4; i++) {
      // góc đang kéo không vẽ vòng tay cầm để kính lúp thấy rõ góc giấy bên dưới (dấu chữ thập trong kính đánh dấu)
      if (dangKeo == i) continue;
      canvas.drawCircle(goc[i], 11, Paint()..color = Colors.white);
      canvas.drawCircle(
          goc[i],
          11,
          Paint()
            ..color = Mau.cam
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    }
    // tay cầm giữa cạnh: thanh ngắn nằm dọc theo cạnh
    for (var i = 0; i < 4; i++) {
      final a = goc[i], b = goc[(i + 1) % 4];
      final u = b - a;
      if (u.distance < 60 || dangKeo == i + 4) continue;
      final m = (a + b) / 2, huong = u / u.distance * 14;
      canvas.drawLine(
          m - huong,
          m + huong,
          Paint()
            ..color = Colors.white
            ..strokeWidth = 8
            ..strokeCap = StrokeCap.round);
      canvas.drawLine(
          m - huong,
          m + huong,
          Paint()
            ..color = Mau.cam
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_VeKhungCat old) => true;
}

/// Dấu chữ thập giữa kính lúp.
class _ChuThap extends CustomPainter {
  const _ChuThap();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = Paint()
      ..color = Mau.cam
      ..strokeWidth = 2;
    canvas.drawLine(c - Offset(size.width / 2, 0), c + Offset(size.width / 2, 0), p);
    canvas.drawLine(c - Offset(0, size.height / 2), c + Offset(0, size.height / 2), p);
  }

  @override
  bool shouldRepaint(_ChuThap old) => false;
}

class _CongCu extends StatelessWidget {
  const _CongCu({required this.icon, required this.ten, required this.onTap, this.mau = Mau.chu});
  final IconData icon;
  final String ten;
  final VoidCallback? onTap; // null: tạm khóa
  final Color mau;

  @override
  Widget build(BuildContext context) {
    final m = onTap == null ? mau.withValues(alpha: 0.35) : mau;
    return Expanded(
      child: InkResponse(
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: m, size: 22),
            const SizedBox(height: 4),
            Text(ten, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: m)),
          ]),
        ),
      ),
    );
  }
}

class _ThanhTruot extends StatelessWidget {
  const _ThanhTruot({required this.ten, required this.giaTri, required this.khiDoi, required this.khiXong});
  final String ten;
  final double giaTri;
  final ValueChanged<double> khiDoi, khiXong;

  @override
  Widget build(BuildContext context) => Row(children: [
        SizedBox(width: 96, child: Text(ten, style: const TextStyle(fontSize: 13, color: Mau.chuVua))),
        Expanded(child: Slider(value: giaTri, onChanged: khiDoi, onChangeEnd: khiXong)),
      ]);
}

// Hàm cấp cao nhất: closure gửi sang isolate chỉ mang theo tham số, không dính State của màn hình.
Future<AnhBgr> _docAnhNen(String duong) => Isolate.run(() => AnhBgr.docTep(duong));
Future<Uint8List> _pngNen(AnhBgr anh) => Isolate.run(() => anh.png());
