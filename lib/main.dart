// Ứng dụng xử lý PDF ảnh – bản Android (Flutter). Mọi xử lý chạy trên máy.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'du_lieu/kho.dart';
import 'giao_dien/mau.dart';
import 'man_hinh/trang_chu.dart';

final kho = Kho();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await kho.mo();
  runApp(const UngDung());
}

class UngDung extends StatelessWidget {
  const UngDung({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Xử lý PDF ảnh',
        debugShowCheckedModeBanner: false,
        theme: chuDe(),
        home: const ManTrangChu(),
      );
}
