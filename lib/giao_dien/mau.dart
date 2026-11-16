// Bảng màu và kiểu chữ theo thiết kế (canvas "Giao diện Xử lý PDF ảnh – Android").
import 'package:flutter/material.dart';

class Mau {
  static const nen = Color(0xFFF4F6F8);
  static const beMat = Color(0xFFFFFFFF);
  static const chu = Color(0xFF15202B);
  static const chuPhu = Color(0xFF5A6672);
  static const chuVua = Color(0xFF3B4752);
  static const vien = Color(0xFFDDE3E8);
  static const vienNhat = Color(0xFFE6EAEE);
  static const nhan = Color(0xFF0A5F8F);
  static const nhanDam = Color(0xFF074A70);
  static const nhanNhat = Color(0xFFE3F0F7);
  static const cam = Color(0xFFE07A00);
  static const camChu = Color(0xFF8A4B00);
  static const camNen = Color(0xFFFDF0DC);
  static const xanhLa = Color(0xFF3CCB7F);
  static const xanhLaChu = Color(0xFF1B6B43);
  static const do_ = Color(0xFFA33A31);
  static const camera = Color(0xFF0E1316);
}

ThemeData chuDe() {
  final goc = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: Mau.nhan, primary: Mau.nhan, surface: Mau.beMat),
    scaffoldBackgroundColor: Mau.nen,
  );
  return goc.copyWith(
    textTheme: goc.textTheme.apply(bodyColor: Mau.chu, displayColor: Mau.chu),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Mau.nhan,
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Mau.chu,
        backgroundColor: Mau.beMat,
        minimumSize: const Size(64, 48),
        side: const BorderSide(color: Mau.vien),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: goc.chipTheme.copyWith(
      side: const BorderSide(color: Mau.vien),
      selectedColor: Mau.nhanNhat,
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Mau.chu),
    ),
  );
}

/// Khung thẻ trắng bo góc dùng chung.
class The extends StatelessWidget {
  const The({super.key, required this.child, this.padding = const EdgeInsets.all(14)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Mau.beMat,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Mau.vienNhat),
        ),
        child: child,
      );
}

/// Nút chọn một trong vài giá trị, kiểu viên thuốc (dùng trên nền tối hoặc sáng).
class ChonNhom<T> extends StatelessWidget {
  const ChonNhom({super.key, required this.giaTri, required this.cacMuc, required this.khiChon, this.toi = false});
  final T giaTri;
  final Map<T, String> cacMuc;
  final ValueChanged<T> khiChon;
  final bool toi;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: toi ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE3E8EC),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final e in cacMuc.entries)
            Semantics(
              selected: e.key == giaTri,
              button: true,
              child: GestureDetector(
                onTap: () => khiChon(e.key),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 38),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: e.key == giaTri ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(e.value,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: e.key == giaTri ? Mau.chu : (toi ? Colors.white : Mau.chuVua),
                      )),
                ),
              ),
            ),
        ]),
      );
}
