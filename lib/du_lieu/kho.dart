// Kho hồ sơ: lưu ảnh gốc, ảnh kết quả, thông tin từng trang trong thư mục riêng của ứng dụng;
// hàng đợi xử lý chạy lần lượt từng trang trong isolate; nhận dạng chữ (Tesseract) có đệm theo từng ảnh trang.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../loi/anh.dart';
import '../loi/chat_luong.dart';
import '../loi/nhan_dang.dart';
import '../loi/quy_trinh.dart';
import '../loi/sua_ky_tu.dart';
import '../loi/xuat_pdf.dart';

class TrangTL {
  TrangTL({required this.id, required this.tepGoc, TuyChon? tc}) : tc = tc ?? TuyChon();

  final String id;
  final String tepGoc;
  List<String> tepKq = [];
  String? tepNho;
  int xoay = 0;
  int xoayChu = 0; // lần xử lý gần nhất đã tự xoay dòng chữ dọc về ngang (0 / 90)
  bool daTuLat = false; // đã tự xoay theo Tesseract một lần (không tự xoay lại nữa)
  List<Diem>? khungTay;
  List<Diem>? khungDung;
  int rongGoc = 0, caoGoc = 0;
  TuyChon tc;
  String trangThai = 'cho'; // cho, dang, xong, loi
  String? loi;
  int phienBan = 0;
  int rongKq = 0, caoKq = 0; // kích thước trang kết quả đầu
  int goiYXoay = -1; // góc nên xoay cùng chiều kim đồng hồ cho chữ đứng thẳng; −1: không đủ chữ để đoán
  int pbGoiY = -1; // phiên bản xử lý đã đoán chiều
  List<(int, String)> lichSuSua = []; // các lần sửa chữ: (ảnh thứ mấy trong tepKq, tệp kết quả trước khi sửa), để hoàn tác
  List<String> canhBaoAnh = []; // lần xử lý gần nhất: 'nhoe' (chữ nhòe), 'tay' (tay che trang): nên chụp lại
  String? trungVoi; // mã trang đứng trước mà trang này giống hệt (chụp trùng)
  List<bool> suaKyTu = []; // cùng thứ tự lichSuSua: lần sửa đó là Sửa ký tự (giữ nguyên bản gốc) hay viết lại khối

  bool get dangXuLy => trangThai == 'cho' || trangThai == 'dang';
  bool get daKiemChieu => pbGoiY == phienBan && trangThai == 'xong';
  bool get saiChieu => daKiemChieu && goiYXoay > 0;
  bool get ngang => rongKq > caoKq;
  bool get daSuaNoiDung => lichSuSua.isNotEmpty;

  static List<double>? _phang(List<Diem>? k) => k == null ? null : [for (final (x, y) in k) ...[x, y]];
  static List<Diem>? _diem(List? v) =>
      v == null ? null : [for (var i = 0; i < 8; i += 2) ((v[i] as num).toDouble(), (v[i + 1] as num).toDouble())];

  Map<String, Object?> toJson() => {
        'id': id,
        'tepGoc': tepGoc,
        'tepKq': tepKq,
        'tepNho': tepNho,
        'xoay': xoay,
        'xoayChu': xoayChu,
        'daTuLat': daTuLat,
        'khungTay': _phang(khungTay),
        'khungDung': _phang(khungDung),
        'rongGoc': rongGoc,
        'caoGoc': caoGoc,
        'tc': tc.toJson(),
        'trangThai': trangThai == 'xong' ? 'xong' : 'cho',
        'phienBan': phienBan,
        'kt': [rongKq, caoKq],
        'goiY': [goiYXoay, pbGoiY],
        if (lichSuSua.isNotEmpty) 'suaChu': [for (final (i, tep) in lichSuSua) [i, tep]],
        if (suaKyTu.contains(true)) 'suaKyTu': suaKyTu,
        if (canhBaoAnh.isNotEmpty) 'cbAnh': canhBaoAnh,
        'trung': ?trungVoi,
      };

  factory TrangTL.fromJson(Map j) => TrangTL(id: j['id'] as String, tepGoc: j['tepGoc'] as String, tc: TuyChon.fromJson(j['tc'] as Map))
    ..tepKq = [for (final t in j['tepKq'] as List) t as String]
    ..tepNho = j['tepNho'] as String?
    ..xoay = j['xoay'] as int? ?? 0
    ..xoayChu = j['xoayChu'] as int? ?? 0
    ..daTuLat = j['daTuLat'] as bool? ?? false
    ..khungTay = _diem(j['khungTay'] as List?)
    ..khungDung = _diem(j['khungDung'] as List?)
    ..rongGoc = j['rongGoc'] as int? ?? 0
    ..caoGoc = j['caoGoc'] as int? ?? 0
    ..trangThai = j['trangThai'] as String? ?? 'cho'
    ..phienBan = j['phienBan'] as int? ?? 0
    ..rongKq = (j['kt'] as List?)?[0] as int? ?? 0
    ..caoKq = (j['kt'] as List?)?[1] as int? ?? 0
    ..goiYXoay = (j['goiY'] as List?)?[0] as int? ?? -1
    ..pbGoiY = (j['goiY'] as List?)?[1] as int? ?? -1
    ..lichSuSua = [for (final e in j['suaChu'] as List? ?? []) ((e as List)[0] as int, e[1] as String)]
    ..suaKyTu = [for (final e in j['suaKyTu'] as List? ?? []) e as bool]
    ..canhBaoAnh = [for (final e in j['cbAnh'] as List? ?? []) e as String]
    ..trungVoi = j['trung'] as String?;

  /// Số lần Sửa ký tự trong lịch sử sửa (hồ sơ bản cũ không có trường này: đều là viết lại khối).
  int get soSuaKyTu {
    while (suaKyTu.length < lichSuSua.length) {
      suaKyTu.insert(0, false);
    }
    return suaKyTu.where((v) => v).length;
  }
}

class HoSo {
  HoSo({required this.id, required this.ten, required this.taoLuc, this.loai = 'giay'});

  final String id;
  String ten;
  final DateTime taoLuc;
  String loai; // giay | sach
  final List<TrangTL> trang = [];
  int soTuTrang = 1, soDau = 1; // đánh số trang khi xuất: trang đầu được đánh số, số in trên trang đó

  int get soTrangKq => trang.fold(0, (s, t) => s + (t.tepKq.isEmpty ? 1 : t.tepKq.length));
  int get soDangXuLy => trang.where((t) => t.dangXuLy).length;
  int get soChoSua => trang.fold(0, (s, t) => s + t.lichSuSua.length);
  int get soSuaKyTu => trang.fold(0, (s, t) => s + t.soSuaKyTu);

  /// Khổ của đa số trang (true: ngang); null khi chưa đủ 3 trang để so.
  bool? get ngangDaSo {
    final ds = [for (final t in trang) if (t.rongKq > 0) t.ngang];
    if (ds.length < 3) return null;
    return ds.where((n) => n).length * 2 > ds.length;
  }

  /// Trang đứng trước mà [t] giống hệt (chụp trùng), nếu trang đó còn trong hồ sơ.
  TrangTL? trangTrungVoi(TrangTL t) {
    final id = t.trungVoi;
    if (id == null || t.trangThai != 'xong') return null;
    for (final k in trang) {
      if (k.id == id) return k;
    }
    return null;
  }

  /// Những điều cần xem lại ở một trang, để người dùng sửa nhanh (màn Xem nhanh).
  List<String> canhBao(TrangTL t) {
    final daSo = ngangDaSo;
    final trung = trangTrungVoi(t);
    return [
      if (trung != null) 'Giống hệt trang ${trang.indexOf(trung) + 1}, có thể chụp trùng',
      if (t.trangThai == 'loi') 'Xử lý lỗi',
      if (t.trangThai == 'xong' && t.canhBaoAnh.contains('nhoe')) 'Chữ nhòe, nên chụp lại',
      if (t.trangThai == 'xong' && t.canhBaoAnh.contains('tay')) 'Tay che trang, nên chụp lại',
      if (t.saiChieu) t.goiYXoay == 180 ? 'Ngược chiều' : 'Chữ nằm nghiêng 90°',
      if (t.trangThai == 'xong' && t.tc.timMep && t.khungTay == null && t.khungDung == null) 'Chưa thấy mép giấy',
      if (t.trangThai == 'xong' && t.rongKq > 0 && daSo != null && t.ngang != daSo) t.ngang ? 'Khổ ngang' : 'Khổ dọc',
    ];
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'ten': ten,
        'taoLuc': taoLuc.toIso8601String(),
        'loai': loai,
        'danhSo': [soTuTrang, soDau],
        'trang': [for (final t in trang) t.toJson()],
      };

  factory HoSo.fromJson(Map j) =>
      HoSo(id: j['id'] as String, ten: j['ten'] as String, taoLuc: DateTime.parse(j['taoLuc'] as String), loai: j['loai'] as String? ?? 'giay')
        ..trang.addAll([for (final t in j['trang'] as List) TrangTL.fromJson(t as Map)])
        ..soTuTrang = (j['danhSo'] as List?)?[0] as int? ?? 1
        ..soDau = (j['danhSo'] as List?)?[1] as int? ?? 1;
}

class CaiDat {
  String cheDo = 'giu_mau';
  String doNhay = 'vua'; // nhanh | vua | chac
  bool tuDongChup = true;
  bool rung = true; // rung khi tự chụp bắt được trang và khi chụp
  bool xuLySauChup = true; // đang ở màn chụp thì chỉ lưu ảnh gốc, rời màn chụp mới cắt, nắn, làm sạch (chụp nhanh hơn)
  String le = 'vua'; // lề trang khi cắt theo chữ cho trang mới: sat | vua | trang
  bool lopChu = false; // (cũ, không còn dùng) xuất PDF kèm lớp chữ ẩn: nay chọn ở màn Nhận dạng chữ
  bool xuatTxt = false; // xuất kèm văn bản .txt
  bool danhSo = false; // xuất PDF có số trang
  final DanhSo kieuSo = DanhSo(); // vị trí, căn, so le (trang bắt đầu, số đầu lưu theo hồ sơ)

  double get thoiGianGiu => switch (doNhay) { 'nhanh' => 0.3, 'chac' => 0.9, _ => 0.5 };

  Map<String, Object?> toJson() =>
      {'cheDo': cheDo, 'doNhay': doNhay, 'tuDongChup': tuDongChup, 'rung': rung, 'xuLySauChup': xuLySauChup, 'le': le, 'lopChu': lopChu, 'xuatTxt': xuatTxt, 'danhSo': danhSo, 'kieuSo': kieuSo.toJson()};

  void napJson(Map j) {
    cheDo = j['cheDo'] as String? ?? cheDo;
    doNhay = j['doNhay'] as String? ?? doNhay;
    tuDongChup = j['tuDongChup'] as bool? ?? tuDongChup;
    rung = j['rung'] as bool? ?? rung;
    xuLySauChup = j['xuLySauChup'] as bool? ?? xuLySauChup;
    le = j['le'] as String? ?? le;
    lopChu = j['lopChu'] as bool? ?? lopChu;
    xuatTxt = j['xuatTxt'] as bool? ?? xuatTxt;
    danhSo = j['danhSo'] as bool? ?? danhSo;
    if (j['kieuSo'] is Map) kieuSo.napJson(j['kieuSo'] as Map);
  }
}

class Kho extends ChangeNotifier {
  late Directory _goc;
  final List<HoSo> hoSo = [];
  final CaiDat caiDat = CaiDat();
  final List<(HoSo, TrangTL)> _hang = [];
  final List<(HoSo, TrangTL)> _hangChieu = [];
  bool _dangChay = false, _dangKiemChieu = false;
  int _soManChup = 0;

  /// Đang ở màn chụp và chọn xử lý sau khi chụp: hàng đợi xử lý, đoán chiều chữ tạm dừng (máy dành cho camera,
  /// tự chụp bắt trang nhanh hơn); rời màn chụp thì chạy tiếp.
  bool get tamDung => _soManChup > 0 && caiDat.xuLySauChup;

  void batDauChup() => _soManChup++;

  void ketThucChup() {
    if (_soManChup > 0) _soManChup--;
    notifyListeners();
    _chay();
    _chayKiemChieu();
  }
  int _dem = 0;

  Future<void> mo() async {
    _goc = Directory('${(await getApplicationDocumentsDirectory()).path}/ho_so');
    await _goc.create(recursive: true);
    final cd = File('${_goc.path}/cai_dat.json');
    if (await cd.exists()) caiDat.napJson(jsonDecode(await cd.readAsString()) as Map);
    await for (final d in _goc.list()) {
      final f = File('${d.path}/ho_so.json');
      if (d is Directory && await f.exists()) {
        try {
          hoSo.add(HoSo.fromJson(jsonDecode(await f.readAsString()) as Map));
        } catch (_) {
          // hồ sơ hỏng: bỏ qua, không làm hỏng cả kho
        }
      }
    }
    hoSo.sort((a, b) => b.taoLuc.compareTo(a.taoLuc));
    for (final h in hoSo) {
      for (final t in h.trang) {
        if (t.trangThai != 'xong') {
          xuLy(h, t);
        } else if (!t.daKiemChieu) {
          _xepKiemChieu(h, t);
        }
      }
    }
    notifyListeners();
  }

  /// Báo giao diện vẽ lại (sau khi sửa trực tiếp một trường của hồ sơ).
  void capNhat() => notifyListeners();

  String _maMoi() => '${DateTime.now().microsecondsSinceEpoch}${(_dem++).toRadixString(36)}';
  String duongDan(HoSo h, String tep) => '${_goc.path}/${h.id}/$tep';

  Future<void> luuCaiDat() async {
    await File('${_goc.path}/cai_dat.json').writeAsString(jsonEncode(caiDat.toJson()));
    notifyListeners();
  }

  final _hangLuu = <String, Future<void>>{};

  /// Lưu hồ sơ. Các lần lưu cùng một hồ sơ xếp hàng lần lượt: hai lần lưu chạy đồng thời cùng ghi một tệp tạm thì
  /// lần sau không đổi tên được (PathNotFoundException) khi thao tác nhanh (xoay, xử lý lại liên tiếp).
  Future<void> luu(HoSo h) {
    Future<void> ghi() async {
      final f = File(duongDan(h, 'ho_so.json'));
      final tam = File('${f.path}.tam');
      await tam.writeAsString(jsonEncode(h.toJson()), flush: true);
      await tam.rename(f.path);
    }

    final truoc = _hangLuu[h.id] ?? Future<void>.value();
    final sau = truoc.catchError((_) {}).then((_) => ghi());
    _hangLuu[h.id] = sau;
    return sau;
  }

  Future<HoSo> taoHoSo({String loai = 'giay'}) async {
    final bay = DateTime.now();
    final h = HoSo(
        id: _maMoi(),
        ten: 'Hồ sơ ${bay.day.toString().padLeft(2, '0')}/${bay.month.toString().padLeft(2, '0')} '
            '${bay.hour.toString().padLeft(2, '0')}:${bay.minute.toString().padLeft(2, '0')}',
        taoLuc: bay,
        loai: loai);
    await Directory('${_goc.path}/${h.id}').create(recursive: true);
    hoSo.insert(0, h);
    await luu(h);
    notifyListeners();
    return h;
  }

  Future<void> xoaHoSo(HoSo h) async {
    hoSo.remove(h);
    _hang.removeWhere((e) => e.$1 == h);
    notifyListeners();
    final d = Directory('${_goc.path}/${h.id}');
    if (await d.exists()) await d.delete(recursive: true);
  }

  Future<TrangTL> themAnh(HoSo h, Uint8List duLieu, {String duoi = 'jpg'}) async {
    final id = _maMoi();
    final t = TrangTL(
      id: id,
      tepGoc: 'goc_$id.$duoi',
      tc: TuyChon(cheDo: caiDat.cheDo, tachTrangDoi: h.loai == 'sach', le: caiDat.le),
    );
    await File(duongDan(h, t.tepGoc)).writeAsBytes(duLieu, flush: true);
    h.trang.add(t);
    await luu(h);
    xuLy(h, t);
    return t;
  }

  /// Chụp lại một trang: ảnh mới thay ảnh gốc, trang giữ chỗ trong hồ sơ; khung, xoay tay, chỗ sửa chữ của ảnh cũ
  /// bỏ đi, tùy chọn xử lý giữ nguyên.
  Future<TrangTL?> thayAnh(HoSo h, TrangTL t, Uint8List duLieu, {String duoi = 'jpg'}) async {
    final i = h.trang.indexOf(t);
    if (i < 0) return null;
    final id = _maMoi();
    final tm = TrangTL(id: id, tepGoc: 'goc_$id.$duoi', tc: t.tc.chep()..tuXoay = true);
    await File(duongDan(h, tm.tepGoc)).writeAsBytes(duLieu, flush: true);
    h.trang[i] = tm;
    _hang.removeWhere((e) => e.$2 == t);
    await luu(h);
    xuLy(h, tm);
    await _xoaTep(h, [t.tepGoc, ...t.tepKq, ?t.tepNho, ...t.lichSuSua.map((e) => e.$2)]);
    return tm;
  }

  Future<void> xoaTrang(HoSo h, TrangTL t) async {
    h.trang.remove(t);
    _hang.removeWhere((e) => e.$2 == t);
    await luu(h);
    notifyListeners();
    await _xoaTep(h, [t.tepGoc, ...t.tepKq, ?t.tepNho, ...t.lichSuSua.map((e) => e.$2)]);
  }

  /// Xóa các tệp ảnh của hồ sơ, kèm đệm nhận dạng chữ của chúng.
  Future<void> _xoaTep(HoSo h, List<String> tep) async {
    for (final ten in [...tep, ...tep.map(tepChu), ...tep.map(tepKyTu)]) {
      final f = File(duongDan(h, ten));
      if (await f.exists()) await f.delete();
    }
  }

  Future<void> doiCho(HoSo h, int tu, int den) async {
    final t = h.trang.removeAt(tu);
    h.trang.insert(den, t);
    await luu(h);
    notifyListeners();
  }

  /// Đưa trang vào hàng đợi xử lý (sau khi đổi tùy chọn, khung, xoay).
  void xuLy(HoSo h, TrangTL t) {
    t.phienBan++;
    t.trangThai = 'cho';
    _hang.removeWhere((e) => e.$2 == t);
    _hang.add((h, t));
    notifyListeners();
    _chay();
  }

  /// Xử lý lại mọi trang của hồ sơ từ ảnh gốc theo thuật toán hiện tại, lề [le]. Trang đã sửa chữ thì bỏ qua (xử lý
  /// lại sẽ mất chỗ sửa). Trả (số trang đưa vào xử lý, số trang bỏ qua).
  (int, int) xuLyLaiHoSo(HoSo h, String le) {
    var so = 0, bo = 0;
    for (final t in [...h.trang]) {
      if (t.lichSuSua.isNotEmpty) {
        bo++;
        continue;
      }
      t.tc.le = le;
      xuLy(h, t);
      so++;
    }
    return (so, bo);
  }

  Future<void> _chay() async {
    if (_dangChay) return;
    _dangChay = true;
    while (_hang.isNotEmpty && !tamDung) {
      final (h, t) = _hang.removeAt(0);
      final pb = t.phienBan;
      t.trangThai = 'dang';
      notifyListeners();
      try {
        final goc = await File(duongDan(h, t.tepGoc)).readAsBytes();
        final tc = t.tc.chep(), khung = t.khungTay, xoay = t.xoay;
        final kq = await _xuLyNen(goc, tc, khung, xoay);
        final nho = await _anhNhoNen(kq.trang.first);
        if (t.phienBan != pb || !h.trang.contains(t)) continue; // đã có yêu cầu mới hơn
        // xử lý lại từ ảnh gốc: các chỗ sửa chữ (nếu có) mất, giao diện đã hỏi người dùng trước
        final cu = [...t.tepKq, ?t.tepNho, ...t.lichSuSua.map((e) => e.$2)];
        t
          ..tepKq = []
          ..lichSuSua = []
          ..suaKyTu = [];
        for (var i = 0; i < kq.trang.length; i++) {
          final tep = 'kq_${t.id}_${i}_$pb.jpg';
          await File(duongDan(h, tep)).writeAsBytes(kq.trang[i], flush: true);
          t.tepKq.add(tep);
        }
        t.tepNho = 'nho_${t.id}_$pb.jpg';
        await File(duongDan(h, t.tepNho!)).writeAsBytes(nho, flush: true);
        // xóa tệp cũ (kèm đệm chữ, khung ký tự) trước khi báo xong: đã báo xong thì không còn tệp thừa
        await _xoaTep(h, cu);
        t
          ..khungDung = kq.khung
          ..rongGoc = kq.rong
          ..xoayChu = kq.xoayChu
          ..caoGoc = kq.cao
          ..rongKq = kq.kichThuoc.first.$1
          ..caoKq = kq.kichThuoc.first.$2
          ..canhBaoAnh = {for (final c in kq.canhBao) ...c}.toList()
          ..trangThai = 'xong'
          ..loi = null;
        await luu(h);
        if (!t.daKiemChieu) _xepKiemChieu(h, t);
        await _doTrung(h, t);
      } catch (e) {
        if (t.phienBan == pb) {
          t
            ..trangThai = 'loi'
            ..loi = '$e';
        }
      }
      notifyListeners();
    }
    _dangChay = false;
  }

  /// So trang vừa xử lý với 3 trang hai bên: giống hệt (chụp trùng) thì đánh dấu trang đứng sau.
  Future<void> _doTrung(HoSo h, TrangTL t) async {
    final i = h.trang.indexOf(t);
    if (i < 0 || t.tepKq.isEmpty) return;
    final lanCan = [
      for (var j = math.max(0, i - 3); j < math.min(h.trang.length, i + 4); j++)
        if (j != i && h.trang[j].trangThai == 'xong' && h.trang[j].tepKq.isNotEmpty) h.trang[j],
    ];
    if (lanCan.isEmpty) return;
    final moi = [for (final f in t.tepKq) duongDan(h, f)];
    final ds = [for (final k in lanCan) [for (final f in k.tepKq) duongDan(h, f)]];
    final List<int> trung;
    try {
      trung = await Isolate.run(() => trangTrung(moi, ds));
    } catch (_) {
      return; // tệp vừa bị xóa, xử lý lại: bỏ qua
    }
    if (!h.trang.contains(t)) return;
    t.trungVoi = null;
    for (final k in trung.map((x) => lanCan[x])) {
      final j = h.trang.indexOf(k);
      if (j < 0) continue;
      if (j < h.trang.indexOf(t)) {
        t.trungVoi = k.id;
      } else {
        k.trungVoi = t.id;
      }
    }
    await luu(h);
  }

  /// Xoay trang thêm [goc] độ cùng chiều kim đồng hồ rồi xử lý lại; khung cắt tay (nếu có) xoay theo.
  /// [chapNhan]: người dùng chủ động chọn chiều này (Xoay toàn bộ theo khổ), không cảnh báo sai chiều nữa.
  /// [theoChu]: xoay theo chiều chữ máy đoán (tự lật, Sửa chiều); không thì là người dùng tự xoay: tắt tự xoay của trang
  /// và gộp phần đã tự xoay (dòng chữ dọc) vào góc xoay tay để trang ra quay đúng [goc] so với lúc người dùng nhìn.
  void xoayTrang(HoSo h, TrangTL t, int goc, {bool chapNhan = false, bool theoChu = false}) {
    goc %= 360;
    if (goc == 0) return;
    var gocThuc = goc;
    if (!theoChu && t.tc.tuXoay) {
      gocThuc = (goc + t.xoayChu) % 360;
      t.tc = t.tc.chep()..tuXoay = false;
      t.xoayChu = 0;
    }
    var k = t.khungTay;
    var w = t.rongGoc.toDouble(), c = t.caoGoc.toDouble();
    if (k != null && w > 0) {
      for (var i = 0; i < gocThuc ~/ 90; i++) {
        final cu = c;
        k = [for (final (x, y) in k!) (cu - 1 - y, x)]; // xoay 90° cùng chiều kim đồng hồ
        c = w;
        w = cu;
      }
    }
    final daBiet = t.daKiemChieu, goiY = t.goiYXoay;
    t
      ..khungTay = k
      ..khungDung = null
      ..xoay = (t.xoay + gocThuc) % 360;
    xuLy(h, t);
    if (chapNhan) {
      t.goiYXoay = 0;
      t.pbGoiY = t.phienBan;
    } else if (daBiet && goiY >= 0) {
      t.goiYXoay = (goiY - goc) % 360; // đã biết chiều chữ: không cần đoán lại
      t.pbGoiY = t.phienBan;
    }
    luu(h);
  }

  /// Xoay mọi trang đã xử lý. cheDo: 'chu' theo chiều chữ; 'doc' / 'ngang': chữ đứng thẳng rồi trang nào
  /// còn khác khổ đã chọn thì xoay thêm 90°. Trả số trang đã xoay.
  Future<int> xoayToanBo(HoSo h, String cheDo, {void Function(int xong, int tong)? tienDo}) async {
    final ds = [for (final t in h.trang) if (t.trangThai == 'xong' && t.tepKq.isNotEmpty) t];
    var soXoay = 0;
    for (var i = 0; i < ds.length; i++) {
      tienDo?.call(i, ds.length);
      final t = ds[i];
      if (!h.trang.contains(t) || t.trangThai != 'xong') continue;
      if (!t.daKiemChieu) await kiemChieu(h, t);
      final chu = t.goiYXoay > 0 ? t.goiYXoay : 0;
      var them = 0;
      if (cheDo != 'chu' && t.rongKq > 0) {
        final ngangSau = chu % 180 == 0 ? t.ngang : !t.ngang;
        if (cheDo == 'doc' && ngangSau) them = 270;
        if (cheDo == 'ngang' && !ngangSau) them = 90;
      }
      if ((chu + them) % 360 != 0) {
        xoayTrang(h, t, chu + them, chapNhan: them != 0, theoChu: them == 0);
        soXoay++;
      }
    }
    tienDo?.call(ds.length, ds.length);
    return soXoay;
  }

  void _xepKiemChieu(HoSo h, TrangTL t) {
    if (!_hangChieu.any((e) => e.$2 == t)) _hangChieu.add((h, t));
    _chayKiemChieu();
  }

  Future<void> _chayKiemChieu() async {
    if (_dangKiemChieu) return;
    _dangKiemChieu = true;
    while (_hangChieu.isNotEmpty && !tamDung) {
      final (h, t) = _hangChieu.removeAt(0);
      if (!h.trang.contains(t) || t.daKiemChieu || t.trangThai != 'xong') continue;
      try {
        await kiemChieu(h, t);
      } catch (_) {
        // không đoán được thì thôi, trang vẫn dùng bình thường
      }
    }
    _dangKiemChieu = false;
  }

  /// Đoán chiều chữ của trang bằng Tesseract psm 1 trên ảnh xám thu nhỏ (khoảng 1 giây một trang).
  Future<void> kiemChieu(HoSo h, TrangTL t) async {
    final pb = t.phienBan;
    if (t.tepKq.isEmpty) return;
    final nho = File('${(await getTemporaryDirectory()).path}/chieu_${t.id}.png');
    final TrangChu kq;
    try {
      await _ghiAnhKiemChieuNen(duongDan(h, t.tepKq.first), nho.path);
      kq = await nhanDangAnh(nho.path, psm: 1);
    } finally {
      if (await nho.exists()) await nho.delete();
    }
    if (t.phienBan != pb || !h.trang.contains(t)) return;
    final (goc, soTu) = kq.gocXoay;
    t
      ..goiYXoay = soTu >= 8 ? goc : -1
      ..pbGoiY = pb;
    // tự lật cho chữ đứng thẳng (một lần mỗi trang, đủ chữ để tin, chưa sửa chữ, người dùng chưa tự xoay)
    if (goc > 0 && soTu >= 12 && t.tc.tuXoay && !t.daTuLat && t.lichSuSua.isEmpty) {
      t.daTuLat = true;
      xoayTrang(h, t, goc, theoChu: true);
      notifyListeners();
      return;
    }
    await luu(h);
    notifyListeners();
  }

  /// Ghi ảnh trang đã sửa chữ thành tệp kết quả mới (PNG; tên mới nên đệm nhận dạng cũ tự hết hiệu lực), lưu sẵn
  /// chữ của ảnh mới vào đệm (nếu có: [chu] mức từ, [dongKyTu] khung ký tự cho Sửa ký tự); giữ tệp cũ để hoàn tác.
  /// [kyTu]: lần sửa này là Sửa ký tự (giữ nguyên bản gốc), ghi chú PDF đếm riêng.
  Future<void> ghiSuaChu(HoSo h, TrangTL t, int i, Uint8List anh, TrangChu? chu, {bool kyTu = false, TrangKyTu? dongKyTu}) async {
    final tep = 'sua_${t.id}_${i}_${_maMoi()}.png';
    await File(duongDan(h, tep)).writeAsBytes(anh, flush: true);
    if (chu != null) await File(duongDan(h, tepChu(tep))).writeAsString(jsonEncode(chu.toJson()), flush: true);
    if (dongKyTu != null) await File(duongDan(h, tepKyTu(tep))).writeAsString(jsonEncode(dongKyTu.toJson()), flush: true);
    t.soSuaKyTu; // bù cờ cho lịch sử của hồ sơ bản cũ
    t.lichSuSua.add((i, t.tepKq[i]));
    t.suaKyTu.add(kyTu);
    t.tepKq[i] = tep;
    if (i == 0) await _lamAnhNho(h, t);
    await luu(h);
    notifyListeners();
  }

  /// Bỏ lần sửa chữ gần nhất của trang.
  Future<void> hoanTacSua(HoSo h, TrangTL t) async {
    if (t.lichSuSua.isEmpty) return;
    final (i, cu) = t.lichSuSua.removeLast();
    if (t.suaKyTu.length > t.lichSuSua.length) t.suaKyTu.removeLast();
    final hien = t.tepKq[i];
    t.tepKq[i] = cu;
    if (i == 0) await _lamAnhNho(h, t);
    await luu(h);
    notifyListeners();
    await _xoaTep(h, [hien]);
  }

  /// Làm lại ảnh nhỏ của trang theo ảnh kết quả đầu (tên mới để ảnh đệm trên màn hình không còn ảnh cũ).
  Future<void> _lamAnhNho(HoSo h, TrangTL t) async {
    final nho = await _anhNhoNen(await File(duongDan(h, t.tepKq.first)).readAsBytes());
    final cu = t.tepNho;
    t.tepNho = 'nho_${t.id}_${t.phienBan}_${_maMoi()}.jpg';
    await File(duongDan(h, t.tepNho!)).writeAsBytes(nho, flush: true);
    if (cu != null) {
      final f = File(duongDan(h, cu));
      if (await f.exists()) await f.delete();
    }
  }

  /// Tệp ảnh từng trang xuất ra, theo thứ tự của hồ sơ (trang chưa xử lý xong thì dùng ảnh gốc).
  List<String> tepTrang(HoSo h) => [for (final t in h.trang) ...(t.tepKq.isEmpty ? [t.tepGoc] : t.tepKq)];

  /// Ảnh kết quả theo thứ tự trang của hồ sơ (dùng khi xuất PDF).
  Future<List<Uint8List>> anhKetQua(HoSo h) async => [for (final tep in tepTrang(h)) await File(duongDan(h, tep)).readAsBytes()];

  /// Tệp đệm kết quả nhận dạng của một ảnh trang. Tên ảnh kết quả đổi theo phiên bản xử lý,
  /// nên trang xử lý lại thì đệm cũ tự hết hiệu lực.
  static String tepChu(String tepAnh) => 'chu_${tepAnh.contains('.') ? tepAnh.substring(0, tepAnh.lastIndexOf('.')) : tepAnh}.json';

  /// Tệp đệm dòng, khung ký tự (Sửa ký tự) của một ảnh trang.
  static String tepKyTu(String tepAnh) => 'kt_${tepAnh.contains('.') ? tepAnh.substring(0, tepAnh.lastIndexOf('.')) : tepAnh}.json';

  /// Đệm dòng, khung ký tự đã có của ảnh trang (null nếu chưa nhận dạng hoặc đệm của thuật toán cũ).
  Future<TrangKyTu?> kyTuDaCo(HoSo h, String tepAnh) async {
    final dem = File(duongDan(h, tepKyTu(tepAnh)));
    if (!await dem.exists()) return null;
    try {
      return TrangKyTu.fromJson(jsonDecode(await dem.readAsString()) as Map);
    } catch (_) {
      return null; // đệm hỏng: nhận dạng lại
    }
  }

  /// Nhận dạng dòng, khung từng ký tự (Sửa ký tự) một ảnh trang của hồ sơ; dùng đệm nếu đã có.
  Future<TrangKyTu> nhanDangKyTu(HoSo h, String tepAnh) async {
    final co = await kyTuDaCo(h, tepAnh);
    if (co != null) return co;
    final kq = await docKyTuAnh(duongDan(h, tepAnh));
    if (await File(duongDan(h, tepAnh)).exists()) {
      await File(duongDan(h, tepKyTu(tepAnh))).writeAsString(jsonEncode(kq.toJson()), flush: true);
    }
    return kq;
  }

  /// Chữ đã nhận dạng (đệm) của ảnh trang, null nếu chưa có.
  Future<TrangChu?> chuDaCo(HoSo h, String tepAnh) async {
    final dem = File(duongDan(h, tepChu(tepAnh)));
    if (!await dem.exists()) return null;
    try {
      return TrangChu.fromJson(jsonDecode(await dem.readAsString()) as Map);
    } catch (_) {
      return null; // đệm hỏng: nhận dạng lại
    }
  }

  /// Nhận dạng chữ một ảnh trang của hồ sơ; dùng đệm nếu đã nhận dạng.
  Future<TrangChu> nhanDang(HoSo h, String tepAnh) async {
    final dem = File(duongDan(h, tepChu(tepAnh)));
    final co = await chuDaCo(h, tepAnh);
    if (co != null) return co;
    final kq = await nhanDangAnh(duongDan(h, tepAnh));
    if (await File(duongDan(h, tepAnh)).exists()) {
      await dem.writeAsString(jsonEncode(kq.toJson()), flush: true);
    }
    return kq;
  }

  /// Nhận dạng chữ mọi trang xuất ra của hồ sơ, theo thứ tự trang.
  Future<List<TrangChu>> nhanDangHoSo(HoSo h, {void Function(int xong, int tong)? tienDo}) async {
    final tep = tepTrang(h);
    final kq = <TrangChu>[];
    for (var i = 0; i < tep.length; i++) {
      tienDo?.call(i, tep.length);
      kq.add(await nhanDang(h, tep[i]));
    }
    tienDo?.call(tep.length, tep.length);
    return kq;
  }
}

const _kenhNhanDang = MethodChannel('xlpdf/nhan_dang'); // MainActivity.kt
Future<String>? _thuMucTess;

/// Chép dữ liệu ngôn ngữ (và osd để đoán chiều chữ) từ assets ra thư mục riêng, vì Tesseract chỉ đọc
/// được tệp thật; chép lại khi đổi bản.
Future<String> _chuanBiTess() async {
  final goc = '${(await getApplicationSupportDirectory()).path}/tesseract';
  for (final ten in [ngonNguNhanDang, 'osd']) {
    final tep = File('$goc/tessdata/$ten.traineddata');
    final duLieu = await rootBundle.load('assets/tessdata/$ten.traineddata');
    if (!await tep.exists() || await tep.length() != duLieu.lengthInBytes) {
      await tep.parent.create(recursive: true);
      final tam = File('${tep.path}.tam');
      await tam.writeAsBytes(duLieu.buffer.asUint8List(duLieu.offsetInBytes, duLieu.lengthInBytes), flush: true);
      await tam.rename(tep.path);
    }
  }
  return goc;
}

/// Nhận dạng chữ một tệp ảnh (JPEG, PNG) bằng Tesseract trên máy. Bên Android các lượt chạy lần lượt trên một luồng.
/// psm 3: tự chia khối; psm 1: thêm đoán chiều chữ (DongChu.gocChu).
Future<TrangChu> nhanDangAnh(String duongDanAnh, {int psm = 3}) async {
  return compute(TrangChu.docHocr, await _hocr(duongDanAnh, psm: psm));
}

/// hOCR của Tesseract cho một tệp ảnh; [kyTu]: kèm khung từng ký tự (hocr_char_boxes).
Future<String> _hocr(String duongDanAnh, {int psm = 3, bool kyTu = false}) async {
  final String thuMuc;
  try {
    thuMuc = await (_thuMucTess ??= _chuanBiTess());
  } catch (_) {
    _thuMucTess = null;
    rethrow;
  }
  final hocr = await _kenhNhanDang.invokeMethod<String>(
      'hocr', {'anh': duongDanAnh, 'thuMuc': thuMuc, 'ngonNgu': ngonNguNhanDang, 'psm': psm, 'kyTu': kyTu});
  return hocr ?? '';
}

/// Nhận dạng dòng kèm khung từng ký tự (Sửa ký tự): ảnh nhỏ được phóng tới cỡ A4 300 dpi chỉ để nhận dạng, khung quy
/// về ảnh gốc; sau đó gộp, nối dòng, thay dãy chấm dẫn, đo độ đậm nét (trong isolate).
Future<TrangKyTu> docKyTuAnh(String duongDanAnh) async {
  final tam = '${(await getTemporaryDirectory()).path}/kytu_${DateTime.now().microsecondsSinceEpoch}.png';
  try {
    final phong = await Isolate.run(() => ghiAnhNhanDangKyTu(duongDanAnh, tam));
    final hocr = await _hocr(phong > 1 ? tam : duongDanAnh, kyTu: true);
    return await Isolate.run(() => docTrangKyTu(hocr, AnhBgr.docTep(duongDanAnh), phong));
  } finally {
    final f = File(tam);
    if (await f.exists()) await f.delete();
  }
}

/// Phông TTF có chữ Việt để ghi lớp chữ ẩn trong PDF.
Future<Uint8List> phongLopChu() async {
  final d = await rootBundle.load('assets/phong/DejaVuSans.ttf');
  return d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
}

// Hàm cấp cao nhất: closure gửi sang isolate chỉ mang theo tham số, không dính đối tượng Kho.
Future<KetQuaXuLy> _xuLyNen(Uint8List goc, TuyChon tc, List<Diem>? khung, int xoay) =>
    Isolate.run(() => xuLyAnh(goc, tc, khungTay: khung, xoayTay: xoay));
Future<Uint8List> _anhNhoNen(Uint8List anh) => Isolate.run(() => anhNho(anh));
Future<void> _ghiAnhKiemChieuNen(String vao, String ra) => Isolate.run(() => ghiAnhKiemChieu(vao, ra));
