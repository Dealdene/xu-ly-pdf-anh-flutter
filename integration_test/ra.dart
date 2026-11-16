// Ghi tệp kết quả kiểm thử ra <tài liệu ứng dụng>/kiem_thu/ra/ để chay_kiem_thu.sh lấy về build/kiem_thu_ra/.
import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String> _thuMucRa() async {
  final d = Directory('${(await getApplicationDocumentsDirectory()).path}/kiem_thu/ra');
  await d.create(recursive: true);
  return d.path;
}

Future<void> ghiRa(String ten, List<int> duLieu) async => File('${await _thuMucRa()}/$ten').writeAsBytes(duLieu, flush: true);

/// Gọi ở phép thử cuối: đánh dấu xong rồi chờ script lấy tệp trước khi `flutter test` gỡ ứng dụng.
Future<void> xongRa() async {
  await File('${await _thuMucRa()}/xong').writeAsString('xong', flush: true);
  await Future<void>.delayed(const Duration(seconds: 3));
}
