// Ghép các bước xử lý một trang; chạy trong isolate riêng để giao diện không bị đứng.
// Tương ứng ung-dung/loi_xu_ly/quy_trinh.py. Tự xoay 90°/180° không làm ở đây: kho chạy Tesseract đoán chiều (psm 1) sau khi xử lý.
import 'dart:io';
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'anh.dart';
import 'cat_chu.dart';
import 'chat_luong.dart';
import 'chieu_chu.dart';
import 'lam_sach.dart';
import 'nan_cong.dart';
import 'nan_phang.dart';

class TuyChon {
  TuyChon({
    this.timMep = true,
    this.suaNghieng = true,
    this.nanCong = true,
    this.catSatChu = true,
    this.tuXoay = true,
    this.tachTrangDoi = false,
    this.le = 'vua',
    this.cheDo = 'giu_mau',
    this.doTrang = 0.5,
    this.doDam = 0.5,
    this.khuNhieu = 0.5,
  });

  bool timMep, suaNghieng, nanCong, catSatChu, tachTrangDoi;

  /// Tự xoay theo chiều chữ: dòng chữ dọc thì xoay về ngang trước khi xử lý, sau đó kho tự lật theo Tesseract.
  /// Tắt khi người dùng tự xoay trang (để không xoay ngược ý người dùng).
  bool tuXoay;

  /// Lề khi cắt theo chữ: 'sat', 'vua', 'trang' (xem catSatChu).
  String le;
  String cheDo;
  double doTrang, doDam, khuNhieu;

  TuyChon chep() => TuyChon.fromJson(toJson());

  Map<String, Object?> toJson() => {
        'timMep': timMep,
        'suaNghieng': suaNghieng,
        'nanCong': nanCong,
        'catSatChu': catSatChu,
        'tuXoay': tuXoay,
        'tachTrangDoi': tachTrangDoi,
        'le': le,
        'cheDo': cheDo,
        'doTrang': doTrang,
        'doDam': doDam,
        'khuNhieu': khuNhieu,
      };

  factory TuyChon.fromJson(Map j) => TuyChon(
        timMep: j['timMep'] as bool? ?? true,
        suaNghieng: j['suaNghieng'] as bool? ?? true,
        nanCong: j['nanCong'] as bool? ?? true,
        catSatChu: j['catSatChu'] as bool? ?? true,
        tuXoay: j['tuXoay'] as bool? ?? true,
        tachTrangDoi: j['tachTrangDoi'] as bool? ?? false,
        le: j['le'] as String? ?? 'vua',
        cheDo: j['cheDo'] as String? ?? 'giu_mau',
        doTrang: (j['doTrang'] as num?)?.toDouble() ?? 0.5,
        doDam: (j['doDam'] as num?)?.toDouble() ?? 0.5,
        khuNhieu: (j['khuNhieu'] as num?)?.toDouble() ?? 0.5,
      );
}

class KetQuaXuLy {
  KetQuaXuLy(this.trang, this.khung, this.rong, this.cao, this.kichThuoc, {this.xoayChu = 0, this.canhBao = const []});

  final List<Uint8List> trang; // JPEG từng trang kết quả (1 trang, hoặc 2 khi tách trang đôi)
  final List<(int, int)> kichThuoc; // (rộng, cao) từng trang kết quả
  final List<Diem>? khung; // 4 góc đã dùng, theo tọa độ ảnh gốc đã xoay
  final int rong, cao; // kích thước ảnh gốc đã xoay
  final int xoayChu; // 90 nếu đã tự xoay dòng chữ dọc về ngang (sau nắn phối cảnh), 0 nếu không
  final List<List<String>> canhBao; // từng trang kết quả: 'nhoe' (chữ nhòe), 'tay' (tay che trang): nên chụp lại
}

/// Luồng: xoay tay → tìm mép → nắn phối cảnh → xoay dòng chữ dọc về ngang → tách trang đôi → nắn trang cong → làm sạch → xóa viền → sửa nghiêng → cắt sát chữ.
KetQuaXuLy xuLyAnh(Uint8List goc, TuyChon tc, {List<Diem>? khungTay, int xoayTay = 0}) {
  var anh = xoay90(giaiMa(goc), xoayTay);
  final rong = anh.cols, cao = anh.rows;
  List<Diem>? khung = khungTay;
  if (khung == null && tc.timMep) khung = timMepGiay(anh);
  // khung máy tự tìm: nới ra một chút cho chữ ở mép trang cong không bị cắt lẹm (cắt sát chữ bỏ phần thừa);
  // khung người dùng tự kéo thì cắt đúng khung
  if (khung != null) {
    anh = lamPhang(anh, khung, noi: khungTay == null && tc.catSatChu && tc.cheDo != 'khong' ? noiKhung : 0);
  }
  // ảnh chụp cầm máy ngang (dòng chữ chạy dọc): xoay về ngang trước, vì tìm gáy, nắn cong, sửa nghiêng, cắt sát chữ
  // đều dựa vào dòng chữ nằm ngang; xuôi hay ngược do bước đoán chiều bằng Tesseract (kho) lo
  final xoayChu = tc.tuXoay && chuDoc(anh) ? 90 : 0;
  if (xoayChu != 0) anh = xoay90(anh, xoayChu);

  final cacTrang = tc.tachTrangDoi ? tachTrangDoi(anh) : [anh];
  final kq = <Uint8List>[];
  final kt = <(int, int)>[];
  final cb = <List<String>>[];
  for (var trang in cacTrang) {
    if (tc.nanCong) trang = nanTrangCong(trang);
    // trang nên chụp lại: tay che trang (đo trên ảnh màu trước khi làm sạch); chữ nhòe: độ rộng mép nét trên ảnh
    // gốc (mọi chế độ), thêm lõi nét xám sau khi làm sạch Giữ màu / Xám
    final canhBao = <String>[if (doTay(trang) > nguongTay) 'tay'];
    final nhoe = laNhoeGoc(trang);
    var sach = lamSach(trang, cheDo: tc.cheDo, doTrang: tc.doTrang, doDam: tc.doDam, khuNhieu: tc.khuNhieu);
    if (nhoe || ((tc.cheDo == 'giu_mau' || tc.cheDo == 'xam') && laNhoe(sach))) canhBao.insert(0, 'nhoe');
    cb.add(canhBao);
    if (khung != null && tc.cheDo != 'khong') sach = xoaVienToi(sach);
    if (tc.suaNghieng) {
      final nghieng = doNghieng(sach);
      if (nghieng != 0) {
        sach = xoayAnh(sach, nghieng, mauNen: tc.cheDo == 'khong' ? null : cv.Scalar.all(255));
        if (tc.cheDo == 'den_trang') {
          sach = cv.threshold(sach, 127, 255, cv.THRESH_BINARY).$2;
        }
      }
    }
    // cắt sát chữ, xóa vết ngoài vùng chữ (sau sửa nghiêng để vùng chữ thẳng hàng)
    // ảnh đã cắt theo mép giấy (hoặc là một nửa cặp trang): trang ít chữ vẫn giữ khổ trang
    if (tc.catSatChu && tc.cheDo != 'khong') {
      sach = catSatChu(sach, le: tc.le, giuKho: khung != null || cacTrang.length == 2);
    }
    kq.add(maHoa(sach, chatLuong: 90));
    kt.add((sach.cols, sach.rows));
  }
  return KetQuaXuLy(kq, khung, rong, cao, kt, xoayChu: xoayChu, canhBao: cb);
}

/// Kiểm tra nhanh ảnh vừa chụp (màn camera): 'nhoe' (chữ nhòe), 'tay' (tay che trang); rỗng nếu ổn. Không nắn cong,
/// không sửa nghiêng, không cắt chữ: chỉ tìm mép, nắn phối cảnh, tách cặp trang rồi đo như xuLyAnh. Luôn làm sạch kiểu
/// Giữ màu để đo lõi nét (kể cả khi hồ sơ để chế độ Đen trắng), trên trang thu nhỏ 1600 px. Giống
/// quy_trinh.kiem_tra_anh_chup. Chạy trong isolate.
List<String> kiemTraAnhChup(Uint8List goc, {bool tachTrang = false}) {
  var anh = giaiMa(goc, canh: 3000);
  final khung = timMepGiay(anh);
  if (khung != null) anh = lamPhang(anh, khung);
  final kq = <String>[];
  for (final trang in tachTrang ? tachTrangDoi(anh) : [anh]) {
    if (!kq.contains('tay') && doTay(trang) > nguongTay) kq.add('tay');
    if (!kq.contains('nhoe') && (laNhoeGoc(trang) || laNhoe(lamSach(thuNho(trang, 1600).$1)))) kq.insert(0, 'nhoe');
  }
  return kq;
}

/// Ảnh xám thu nhỏ (cạnh dài 1400 px) của trang kết quả để Tesseract đoán chiều chữ nhanh.
void ghiAnhKiemChieu(String vao, String ra) {
  final xam = cv.cvtColor(giaiMa(File(vao).readAsBytesSync(), canh: 1400), cv.COLOR_BGR2GRAY);
  if (!cv.imwrite(ra, xam)) throw StateError('Không ghi được ảnh tạm');
}

/// Ảnh nhỏ để hiện trong danh sách (cạnh dài 360 px).
Uint8List anhNho(Uint8List duLieu) => maHoa(giaiMa(duLieu, canh: 360), chatLuong: 80);
