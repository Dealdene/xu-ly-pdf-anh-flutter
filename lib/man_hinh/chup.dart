// Màn 2 · Chụp, tự động chụp. Khung hình xem trước được phân tích trong một isolate riêng
// (BoTuChup); đủ điều kiện thì gọi takePicture() lấy ảnh độ phân giải gốc.
import 'dart:async';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../du_lieu/kho.dart';
import '../giao_dien/mau.dart';
import '../loi/quy_trinh.dart';
import '../loi/tu_chup.dart';
import '../main.dart';

class ManChup extends StatefulWidget {
  const ManChup({super.key, required this.hoSo, this.thayTrang});
  final HoSo hoSo;

  /// Chụp lại trang này (trang nhòe, có tay): chụp một ảnh thay ảnh gốc rồi quay về.
  final TrangTL? thayTrang;

  @override
  State<ManChup> createState() => _ManChupState();
}

class _ManChupState extends State<ManChup> with WidgetsBindingObserver {
  CameraController? _cam;
  String? _loiCam;
  final _phanTich = _BoPhanTich();
  final _dongHo = Stopwatch()..start();
  bool _banPhanTich = false, _dangChup = false, _den = false, _nhay = false;
  // Hộp thoại xin quyền camera làm ứng dụng tạm dừng rồi chạy lại giữa lúc đang mở camera:
  // hai cờ này giữ cho chỉ có một bộ điều khiển camera và một luồng khung hình.
  bool _dangMo = false, _daTamDung = false, _luongBat = false;
  late bool _tuDong = kho.caiDat.tuDongChup;
  TrangThaiTuChup? _tt;
  Uint8List? _anhCuoi;
  Offset? _diemNet; // chỗ vừa chạm để lấy nét (tỉ lệ 0..1 trên khung xem trước), hiện vòng tròn một lúc
  String? _nhacTam; // lời nhắc tạm khi đang chụp (lấy nét lại, ảnh mờ)
  double _rungLuc = -9; // lần rung báo "bắt được trang" gần nhất (giây, theo _dongHo)
  // Kiểm tra ảnh vừa chụp (nhòe, tay che) ngay trên màn camera: trang bị báo, lời báo; chụp lại thì lần chụp tới thay
  // ảnh của trang đó (trang giữ chỗ trong hồ sơ).
  TrangTL? _trangBao, _thayTiep;
  List<String> _loiBao = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    kho.batDauChup();
    _phanTich.moi().then((_) => _phanTich.ketQua.listen(_khiCoKetQua));
    _moCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    kho.ketThucChup();
    _phanTich.dong();
    _cam?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cam = _cam;
    if (state == AppLifecycleState.paused && cam != null) {
      _cam = null;
      _luongBat = false;
      _daTamDung = true;
      cam.dispose();
      setState(() {});
    } else if (state == AppLifecycleState.resumed && _daTamDung) {
      _daTamDung = false;
      _moCamera();
    }
  }

  Future<void> _moCamera() async {
    if (_dangMo || _cam != null) return;
    _dangMo = true;
    try {
      final ds = await availableCameras();
      final sau = ds.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => ds.first);
      // Độ phân giải tối đa của cảm biến (trước đây veryHigh = 1080p: trang A4 chỉ ~1000 điểm ảnh bề ngang, mờ,
      // nhận dạng chữ kém); máy không mở được mức tối đa thì lùi về 1080p.
      CameraController? moDuoc;
      for (final mucDo in const [ResolutionPreset.max, ResolutionPreset.veryHigh]) {
        final c = CameraController(sau, mucDo, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
        try {
          await c.initialize();
          moDuoc = c;
          break;
        } on CameraException catch (e) {
          await c.dispose();
          if (mucDo == ResolutionPreset.veryHigh || e.code == 'CameraAccessDenied') rethrow;
        }
      }
      final cam = moDuoc!;
      await cam.setFlashMode(FlashMode.off);
      try {
        await cam.setFocusMode(FocusMode.auto);
      } catch (_) {}
      if (!mounted) {
        cam.dispose();
        return;
      }
      setState(() {
        _cam = cam;
        _loiCam = null;
      });
      _batLuong();
    } on CameraException catch (e) {
      setState(
        () => _loiCam = e.code == 'CameraAccessDenied'
            ? 'Ứng dụng chưa được phép dùng camera. Mở Cài đặt của máy để cấp quyền.'
            : 'Không mở được camera: ${e.description ?? e.code}',
      );
    } catch (e) {
      setState(() => _loiCam = 'Không mở được camera: $e');
    } finally {
      _dangMo = false;
    }
  }

  /// Luồng khung hình chạy ở cả hai chế độ: Bấm chụp vẫn hiện khung trang và lời nhắc, chỉ không tự bấm.
  Future<void> _batLuong() async {
    final cam = _cam;
    if (cam == null || _luongBat) return;
    _luongBat = true;
    _phanTich.datLai(quenTrangCuoi: false);
    try {
      await cam.startImageStream(_khiCoKhung);
    } catch (e) {
      _luongBat = false;
      if (mounted) {
        setState(() => _tuDong = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Máy này không phân tích được khung hình, vẫn bấm chụp được. ($e)')));
      }
    }
  }

  Future<void> _tatLuong() async {
    final cam = _cam;
    if (cam != null && _luongBat) {
      _luongBat = false;
      await cam.stopImageStream();
    }
  }

  void _khiCoKhung(CameraImage img) {
    if (_banPhanTich || _dangChup || img.planes.length < 3) return;
    _banPhanTich = true;
    _phanTich.gui(img, _cam!.description.sensorOrientation, _dongHo.elapsedMicroseconds / 1e6, kho.caiDat.thoiGianGiu);
  }

  void _khiCoKetQua(TrangThaiTuChup tt) {
    _banPhanTich = false;
    if (!mounted) return;
    // rung nhẹ khi vừa bắt được trang (bắt đầu đếm giữ yên); không rung lại trong 1,5 giây
    final batDauGiu = tt.ma == 'dang_giu' && _tt?.ma != 'dang_giu' && _tt?.ma != 'da_chup';
    final bay = _dongHo.elapsedMilliseconds / 1000;
    if (batDauGiu && bay - _rungLuc > 1.5) {
      _rungLuc = bay;
      rung(25, bienDo: 90);
    }
    setState(() => _tt = tt);
    if (tt.ma != 'da_chup') return;
    if (_tuDong) {
      _chup();
    } else {
      _phanTich.datLai(quenTrangCuoi: true); // Bấm chụp: chỉ báo đủ điều kiện, người dùng tự bấm
    }
  }

  Future<void> _chup() async {
    final cam = _cam;
    if (cam == null || _dangChup || !cam.value.isInitialized) return;
    setState(() {
      _dangChup = true;
      _nhacTam = 'Giữ yên, đang chụp…';
    });
    try {
      await _tatLuong();
      // lấy nét vào giữa khung hình và chờ lấy nét xong rồi mới chụp. Rung, nháy, tiếng chụp chỉ phát khi đã chụp
      // xong ảnh dùng được: trước đây rung ngay lúc bắt đầu lấy nét nên người dùng tưởng đã chụp, lật trang luôn.
      await _layNet(cam, const Offset(0.5, 0.5));
      var duLieu = await (await cam.takePicture()).readAsBytes();
      var tiLe = await _tiLeNet(duLieu);
      if (tiLe < nguongTiLeNet) {
        // lấy nét hụt: lấy nét lại, chụp lại một lần, giữ ảnh nét hơn
        if (mounted) setState(() => _nhacTam = 'Ảnh mờ, đang lấy nét lại…');
        await _layNet(cam, const Offset(0.5, 0.5));
        final lan2 = await (await cam.takePicture()).readAsBytes();
        final tiLe2 = await _tiLeNet(lan2);
        if (tiLe2 > tiLe) {
          duLieu = lan2;
          tiLe = tiLe2;
        }
      }
      _baoDaChup(); // sau lần chụp cuối (lấy nét hụt thì chụp lại một lần): người dùng lật trang được rồi
      final thay = widget.thayTrang;
      if (thay != null) {
        await kho.thayAnh(widget.hoSo, thay, duLieu);
        if (mounted) Navigator.pop(context);
        return;
      }
      final TrangTL t;
      final thayTiep = _thayTiep;
      if (thayTiep != null && widget.hoSo.trang.contains(thayTiep)) {
        t = await kho.thayAnh(widget.hoSo, thayTiep, duLieu) ?? await kho.themAnh(widget.hoSo, duLieu);
      } else {
        t = await kho.themAnh(widget.hoSo, duLieu);
      }
      _thayTiep = null;
      _anhCuoi = duLieu;
      _kiemTraSauChup(t, duLieu, mo: tiLe < nguongTiLeNet);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chụp không được: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _dangChup = false;
          _nhay = false;
          _nhacTam = null;
        });
        _batLuong();
      }
    }
  }

  /// Máy vừa chụp xong: rung, nháy trắng, tiếng chụp (người dùng biết là đã lật trang được).
  void _baoDaChup() {
    rung(70);
    SystemSound.play(SystemSoundType.click);
    if (!mounted) return;
    setState(() => _nhay = true);
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _nhay = false);
    });
  }

  /// Kiểm tra ảnh vừa chụp trong isolate (chừng 1–3 giây, không chặn lần chụp sau): nhòe, tay che thì rung hai lần và
  /// hiện thanh báo có nút Chụp lại.
  Future<void> _kiemTraSauChup(TrangTL t, Uint8List duLieu, {bool mo = false}) async {
    if (mounted && _trangBao != null) setState(() => _trangBao = null);
    var loi = <String>[];
    try {
      loi = await _kiemTraNen(duLieu, widget.hoSo.loai == 'sach');
    } catch (_) {}
    if (mo && !loi.contains('nhoe')) loi.insert(0, 'nhoe');
    if (!mounted || loi.isEmpty || !widget.hoSo.trang.contains(t)) return;
    rung(60, bienDo: 255);
    Future<void>.delayed(const Duration(milliseconds: 160), () => rung(60, bienDo: 255));
    setState(() {
      _trangBao = t;
      _loiBao = loi;
    });
  }

  /// Bấm Chụp lại ở thanh báo: lần chụp tới thay ảnh của trang bị báo.
  void _chupLai() {
    setState(() {
      _thayTiep = _trangBao;
      _trangBao = null;
    });
    _phanTich.datLai(quenTrangCuoi: true); // cho tự chụp chụp lại đúng trang vừa rồi
  }

  Widget _thanhBao() {
    final dangThay = _thayTiep != null && widget.hoSo.trang.contains(_thayTiep);
    final t = dangThay ? _thayTiep! : _trangBao!;
    final so = widget.hoSo.trang.indexOf(t) + 1;
    final ten = {'nhoe': 'chữ nhòe', 'tay': 'tay che trang'};
    final chu = dangThay
        ? 'Đặt lại trang $so rồi chụp: ảnh mới sẽ thay ảnh cũ'
        : 'Trang $so: ${_loiBao.map((c) => ten[c] ?? c).join(', ')}. Nên chụp lại.';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(color: dangThay ? const Color(0xFF1F6F43) : Mau.cam, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(dangThay ? Icons.photo_camera : Icons.warning_amber_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(chu, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        if (!dangThay)
          TextButton(
            style: TextButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Mau.chu, shape: const StadiumBorder()),
            onPressed: _chupLai,
            child: const Text('Chụp lại', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        IconButton(
          tooltip: dangThay ? 'Thôi, chụp trang mới' : 'Bỏ qua',
          icon: const Icon(Icons.close, color: Colors.white, size: 20),
          onPressed: () => setState(() {
            _trangBao = null;
            _thayTiep = null;
          }),
        ),
      ]),
    );
  }

  /// Lấy nét (và đo sáng) tại [p] (tỉ lệ 0..1 trên khung xem trước), chờ lấy nét xong tối đa 1,5 giây.
  Future<void> _layNet(CameraController cam, Offset p) async {
    try {
      await cam.setFocusMode(FocusMode.auto);
      await Future.wait([cam.setFocusPoint(p), cam.setExposurePoint(p)]).timeout(const Duration(milliseconds: 1500));
    } catch (_) {
      // máy không hỗ trợ chọn điểm lấy nét: vẫn chụp được, CameraX tự lấy nét liên tục
    }
  }

  /// Chạm vào khung xem trước: lấy nét tại chỗ chạm, hiện vòng tròn.
  Future<void> _chamLayNet(Offset p) async {
    final cam = _cam;
    if (cam == null || _dangChup) return;
    setState(() => _diemNet = p);
    await _layNet(cam, p);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (mounted && _diemNet == p) setState(() => _diemNet = null);
  }

  void _doiTuDong(bool v) {
    setState(() {
      _tuDong = v;
      _tt = null;
    });
    _phanTich.datLai(quenTrangCuoi: false);
    kho.caiDat.tuDongChup = v;
    kho.luuCaiDat();
  }

  Future<void> _doiDen() async {
    final cam = _cam;
    if (cam == null) return;
    _den = !_den;
    await cam.setFlashMode(_den ? FlashMode.torch : FlashMode.off);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final soTrang = widget.hoSo.trang.length;
    return Scaffold(
      backgroundColor: Mau.camera,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  _NutTron(icon: Icons.arrow_back, nhan: 'Quay lại', onTap: () => Navigator.pop(context)),
                  const SizedBox(width: 8),
                  ChonNhom<String>(
                    toi: true,
                    giaTri: widget.hoSo.loai,
                    cacMuc: const {'giay': 'Giấy rời', 'sach': 'Sách'},
                    khiChon: (v) {
                      setState(() => widget.hoSo.loai = v);
                      kho.luu(widget.hoSo);
                    },
                  ),
                  const Spacer(),
                  _NutTron(icon: _den ? Icons.flash_on : Icons.flash_off, nhan: 'Đèn', onTap: _doiDen),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    color: Colors.black,
                    child: _loiCam != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _loiCam!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          )
                        : _cam == null
                        ? const Center(child: CircularProgressIndicator(color: Colors.white))
                        : _xemTruoc(_cam!),
                  ),
                ),
              ),
            ),
            if ((_trangBao != null && widget.hoSo.trang.contains(_trangBao)) ||
                (_thayTiep != null && widget.hoSo.trang.contains(_thayTiep)))
              _thanhBao(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Center(
                child: ChonNhom<bool>(
                  toi: true,
                  giaTri: _tuDong,
                  cacMuc: const {true: 'Tự chụp', false: 'Bấm chụp'},
                  khiChon: _doiTuDong,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Semantics(
                    label: 'Xem $soTrang trang đã chụp',
                    button: true,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: SizedBox(
                        width: 58,
                        height: 70,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: 0,
                              top: 6,
                              child: Container(
                                width: 46,
                                height: 62,
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5)),
                                clipBehavior: Clip.antiAlias,
                                child: _anhCuoi == null
                                    ? null
                                    : Image.memory(_anhCuoi!, fit: BoxFit.cover, cacheWidth: 120),
                              ),
                            ),
                            if (soTrang > 0)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 22),
                                  height: 22,
                                  padding: const EdgeInsets.symmetric(horizontal: 5),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(color: Mau.nhan, borderRadius: BorderRadius.circular(11)),
                                  child: Text(
                                    '$soTrang',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Semantics(
                    label: 'Chụp ngay',
                    button: true,
                    child: GestureDetector(
                      onTap: _chup,
                      child: Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _dangChup ? Colors.white54 : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Mau.chu,
                        minimumSize: const Size(64, 44),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Xong', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _xemTruoc(CameraController cam) {
    final tt = _tt;
    final dat = tt?.ma == 'dang_giu' || tt?.ma == 'da_chup';
    final loiNhac =
        _nhacTam ??
        (_tuDong
            ? (tt?.loiNhac ?? 'Đưa trang vào khung hình')
            : dat
            ? 'Đủ rõ, bấm nút tròn để chụp'
            : (tt == null || tt.ma == 'khong_thay' ? 'Bấm nút tròn để chụp' : tt.loiNhac));
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: 1 / cam.value.aspectRatio,
            child: LayoutBuilder(
              builder: (context, hop) => GestureDetector(
                onTapUp: (e) => _chamLayNet(
                  Offset(
                    (e.localPosition.dx / hop.maxWidth).clamp(0.0, 1.0),
                    (e.localPosition.dy / hop.maxHeight).clamp(0.0, 1.0),
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(cam),
                    if (tt != null) CustomPaint(painter: _VeKhung(tt)),
                    if (_diemNet != null)
                      Positioned(
                        left: _diemNet!.dx * hop.maxWidth - 32,
                        top: _diemNet!.dy * hop.maxHeight - 32,
                        child: IgnorePointer(
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.amber, width: 2),
                            ),
                          ),
                        ),
                      ),
                    AnimatedOpacity(
                      opacity: _nhay ? 0.8 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: const ColoredBox(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 18,
          child: Center(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
              decoration: BoxDecoration(color: const Color(0xD10E1316), borderRadius: BorderRadius.circular(999)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_tuDong && tt?.ma == 'dang_giu') ...[
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        value: tt!.tienDo,
                        strokeWidth: 3,
                        color: Mau.xanhLa,
                        backgroundColor: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    loiNhac,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NutTron extends StatelessWidget {
  const _NutTron({required this.icon, required this.nhan, required this.onTap});
  final IconData icon;
  final String nhan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: nhan,
    button: true,
    child: InkResponse(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    ),
  );
}

/// Vẽ khung trang tìm được lên ảnh xem trước: xanh khi đang giữ yên chờ chụp, cam khi chưa đạt.
class _VeKhung extends CustomPainter {
  _VeKhung(this.tt);
  final TrangThaiTuChup tt;

  @override
  void paint(Canvas canvas, Size size) {
    final k = tt.khung;
    if (k == null || tt.rong == 0) return;
    final s = size.width / tt.rong;
    final duong = Path()..moveTo(k[0].$1 * s, k[0].$2 * s);
    for (final (x, y) in k.skip(1)) {
      duong.lineTo(x * s, y * s);
    }
    duong.close();
    final dat = tt.ma == 'dang_giu' || tt.ma == 'da_chup';
    final mau = dat ? Mau.xanhLa : const Color(0xFFFFA030);
    canvas.drawPath(duong, Paint()..color = mau.withValues(alpha: 0.12));
    canvas.drawPath(
      duong,
      Paint()
        ..color = mau
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_VeKhung old) => old.tt != tt;
}

const _kenhRung = MethodChannel('xlpdf/rung');

/// Rung máy [ms] mili giây (bienDo 1–255, bỏ trống: mức mặc định của máy) nếu người dùng bật Rung báo.
void rung(int ms, {int? bienDo}) {
  if (!kho.caiDat.rung) return;
  _kenhRung.invokeMethod('rung', {'ms': ms, 'bienDo': ?bienDo}).catchError((_) => null);
}

/// Kiểm tra ảnh vừa chụp (nhòe, tay che), chạy trong isolate. Hàm cấp cao nhất để closure không dính State.
Future<List<String>> _kiemTraNen(Uint8List jpeg, bool tachTrang) =>
    Isolate.run(() => kiemTraAnhChup(jpeg, tachTrang: tachTrang));

/// Tỉ lệ chi tiết của ảnh vừa chụp (đo độ mờ), chạy trong isolate. Hàm cấp cao nhất để closure không dính State.
Future<double> _tiLeNet(Uint8List jpeg) => Isolate.run(() => tiLeNetAnhChup(jpeg));

/// Isolate phân tích khung hình: giữ một BoTuChup suốt lượt chụp.
class _BoPhanTich {
  final _nhan = ReceivePort();
  final _ketQua = StreamController<TrangThaiTuChup>.broadcast();
  Isolate? _iso;
  SendPort? _gui;

  Stream<TrangThaiTuChup> get ketQua => _ketQua.stream;

  Future<void> moi() async {
    final xong = Completer<void>();
    _nhan.listen((m) {
      if (m is SendPort) {
        _gui = m;
        xong.complete();
      } else if (m is Map) {
        _ketQua.add(TrangThaiTuChup.fromMap(m));
      }
    });
    _iso = await Isolate.spawn(_luongPhanTich, _nhan.sendPort);
    return xong.future;
  }

  void gui(CameraImage img, int xoay, double t, double giu) {
    final g = _gui;
    if (g == null) {
      _ketQua.add(TrangThaiTuChup('khong_thay'));
      return;
    }
    final p = img.planes;
    g.send({
      'lenh': 'khung',
      'y': TransferableTypedData.fromList([p[0].bytes]),
      'u': TransferableTypedData.fromList([p[1].bytes]),
      'v': TransferableTypedData.fromList([p[2].bytes]),
      'rong': img.width,
      'cao': img.height,
      'buocY': p[0].bytesPerRow,
      'buocUV': p[1].bytesPerRow,
      'buocDiemUV': p[1].bytesPerPixel ?? 1,
      'xoay': xoay,
      't': t,
      'giu': giu,
    });
  }

  void datLai({bool quenTrangCuoi = true}) => _gui?.send({'lenh': 'datLai', 'quen': quenTrangCuoi});

  void dong() {
    _iso?.kill(priority: Isolate.immediate);
    _nhan.close();
    _ketQua.close();
  }
}

void _luongPhanTich(SendPort ra) {
  final vao = ReceivePort();
  ra.send(vao.sendPort);
  final bo = BoTuChup();
  vao.listen((m) {
    final mm = m as Map;
    if (mm['lenh'] == 'datLai') {
      bo.datLai(quenTrangCuoi: mm['quen'] as bool);
      return;
    }
    try {
      bo.ch.thoiGianGiu = mm['giu'] as double;
      final anh = bgrTuYuv(
        y: (mm['y'] as TransferableTypedData).materialize().asUint8List(),
        u: (mm['u'] as TransferableTypedData).materialize().asUint8List(),
        v: (mm['v'] as TransferableTypedData).materialize().asUint8List(),
        rong: mm['rong'] as int,
        cao: mm['cao'] as int,
        buocY: mm['buocY'] as int,
        buocUV: mm['buocUV'] as int,
        buocDiemUV: mm['buocDiemUV'] as int,
        xoay: mm['xoay'] as int,
      );
      ra.send(bo.nhanKhung(anh, mm['t'] as double).toMap());
    } catch (_) {
      ra.send(TrangThaiTuChup('khong_thay').toMap());
    }
  });
}
