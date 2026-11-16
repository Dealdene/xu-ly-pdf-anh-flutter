// Báo trang nên chụp lại (góp ý 15/11/2026, hồ sơ 214 trang: hai trang chụp lúc tay đang lật trang, chữ nhòe, ngón tay
// che chữ, ứng dụng không báo). Giống ung-dung/kiem_thu/kiem_thu_chat_luong.py:
// - nhòe: 12 trang kết quả của người dùng (xlpdf_kiemthu/chat_luong): chỉ t145, t146 bị báo;
// - tay: ảnh sách mở tổng hợp (sach_mo): ngón cái giữ mép sách không báo, tay đặt lên trang (21-tung-trang-go) báo.
// - kiểm tra ngay sau khi chụp (kiemTraAnhChup): ảnh chụp thật (sach, sach2, mau1/3/4) không bị báo; các ảnh đó làm
//   nhòe như rung tay, lấy nét hụt (mo_chup, tạo bằng ung-dung/kiem_thu/tao_anh_rung.py) bị báo nhòe.
// - trùng trang (diemKhop): đoạn trang của hồ sơ 214 trang (trung): so mỗi trang với 3 trang trước, đúng 10 cặp trùng
//   (cặp 146–148: trang 146 có tay che nửa trang, dưới ngưỡng).
// Chạy:  bash integration_test/chay_kiem_thu.sh chat_luong_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xu_ly_pdf_anh/loi/anh.dart';
import 'package:xu_ly_pdf_anh/loi/chat_luong.dart';
import 'package:xu_ly_pdf_anh/loi/nan_phang.dart';
import 'package:xu_ly_pdf_anh/loi/quy_trinh.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('báo trang nhòe, tay che trang', () async {
    final goc = '${(await getApplicationDocumentsDirectory()).path}/kiem_thu';
    final truot = <String>[];
    final tep = Directory('$goc/chat_luong').listSync().whereType<File>().where((f) => f.path.endsWith('.jpg')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(tep.length, 12);
    for (final f in tep) {
      final ten = f.uri.pathSegments.last.split('.').first;
      final anh = giaiMa(await f.readAsBytes());
      final sw = Stopwatch()..start();
      final d = doNhoe(anh);
      final ms = sw.elapsedMilliseconds;
      final bao = laNhoe(anh);
      final can = ten == 't145' || ten == 't146';
      if (bao != can) truot.add(ten);
      // ignore: avoid_print
      print('NHOE $ten: ô lõi xám ${d?.$1.toStringAsFixed(2)}, lõi trung vị ${d?.$2.toStringAsFixed(0)} → '
          '${bao ? 'BÁO' : 'không'}${bao == can ? '' : ' TRƯỢT'}, $ms ms');
    }
    for (final f in Directory('$goc/sach_mo').listSync().whereType<File>().where((f) => f.path.endsWith('.jpg')).toList()
      ..sort((a, b) => a.path.compareTo(b.path))) {
      final ten = f.uri.pathSegments.last.split('.').first;
      var anh = giaiMa(await f.readAsBytes());
      final khung = timMepGiay(anh);
      if (khung != null) anh = lamPhang(anh, khung, noi: noiKhung);
      final tay = tachTrangDoi(anh).map(doTay).reduce((a, b) => a > b ? a : b);
      final can = ten == '21-tung-trang-go';
      if ((tay > nguongTay) != can) truot.add(ten);
      // ignore: avoid_print
      print('TAY $ten: ${tay.toStringAsFixed(3)}${(tay > nguongTay) == can ? '' : ' TRƯỢT'}');
    }
    // kiểm tra ngay sau khi chụp
    final chup = <(File, bool)>[
      for (final f in Directory('$goc/sach').listSync().whereType<File>().where((f) => f.path.endsWith('.png'))) (f, true),
      for (final f in Directory('$goc/sach2').listSync().whereType<File>().where((f) => f.path.endsWith('.jpg'))) (f, false),
      (File('$goc/mau1-chup-nghieng.jpg'), false),
      (File('$goc/mau4-chup-kem.jpg'), false),
      (File('$goc/mau3-trang-doi.jpg'), true),
    ];
    for (final (f, doi) in chup) {
      final sw = Stopwatch()..start();
      final kq = kiemTraAnhChup(await f.readAsBytes(), tachTrang: doi);
      final ten = f.uri.pathSegments.last;
      if (kq.isNotEmpty) truot.add(ten);
      // ignore: avoid_print
      print('CHUP $ten: ${kq.isEmpty ? 'ổn' : kq}${kq.isEmpty ? '' : ' TRƯỢT'}, ${sw.elapsedMilliseconds} ms');
    }
    for (final f in Directory('$goc/mo_chup').listSync().whereType<File>().where((f) => f.path.endsWith('.jpg')).toList()
      ..sort((a, b) => a.path.compareTo(b.path))) {
      final ten = f.uri.pathSegments.last;
      final sw = Stopwatch()..start();
      final kq = kiemTraAnhChup(await f.readAsBytes(), tachTrang: ten.contains('_doi'));
      if (!kq.contains('nhoe')) truot.add(ten);
      // ignore: avoid_print
      print('CHUP $ten: $kq${kq.contains('nhoe') ? '' : ' TRƯỢT'}, ${sw.elapsedMilliseconds} ms');
    }
    // trùng trang
    const capTrung = {'26-27', '56-58', '57-59', '90-92', '91-93', '137-139', '138-140', '141-143', '142-144',
      '176-177'};
    final dt = <int, DacTrung>{};
    for (final f in Directory('$goc/trung').listSync().whereType<File>().where((f) => f.path.endsWith('.jpg'))) {
      dt[int.parse(f.uri.pathSegments.last.substring(1, 4))] = dacTrung(giaiMa(await f.readAsBytes()));
    }
    final thay = <String>{};
    final sw = Stopwatch()..start();
    var soLan = 0;
    for (final i in dt.keys.toList()..sort()) {
      for (var j = i - 3; j < i; j++) {
        if (!dt.containsKey(j)) continue;
        final k = diemKhop(dt[i]!, dt[j]!);
        soLan++;
        if (k >= nguongTrung) thay.add('$j-$i');
        // ignore: avoid_print
        if (k >= 20) print('TRUNG t$j–t$i: $k điểm khớp');
      }
    }
    final thieu = capTrung.difference(thay), thua = thay.difference(capTrung);
    // ignore: avoid_print
    print('TRUNG: thấy ${thay.length} cặp, thiếu $thieu, thừa $thua, ${sw.elapsedMilliseconds ~/ soLan} ms/lần so');
    if (thieu.isNotEmpty || thua.isNotEmpty) truot.add('trung');
    // ignore: avoid_print
    print('KQ chất lượng: ${truot.isEmpty ? 'đạt hết' : 'trượt $truot'}');
    expect(truot, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
