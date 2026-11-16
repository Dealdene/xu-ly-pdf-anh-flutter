// Xem nhanh cả hồ sơ: ảnh trang cỡ lớn, đánh dấu trang ngược chiều, nằm nghiêng, khác khổ, chưa thấy mép giấy;
// xoay, sửa chiều ngay trên lưới. Có Xoay toàn bộ (theo chiều chữ, hoặc ép khổ dọc / ngang).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../du_lieu/kho.dart';
import '../giao_dien/mau.dart';
import '../main.dart';
import 'chup.dart';
import 'sua_trang.dart';

/// Hỏi kiểu xoay rồi xoay mọi trang đã xử lý của hồ sơ, có hộp tiến độ.
Future<void> moXoayToanBo(BuildContext context, HoSo hoSo) async {
  final cheDo = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text('Xoay toàn bộ trang', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        for (final (ma, icon, ten, mo) in const [
          ('chu', Icons.text_rotation_none, 'Theo chiều chữ', 'Tự nhận ra trang ngược, nằm nghiêng và xoay cho chữ đứng thẳng'),
          ('doc', Icons.stay_current_portrait, 'Tất cả khổ dọc', 'Chữ đứng thẳng trước; trang nào còn nằm ngang thì xoay về dọc'),
          ('ngang', Icons.stay_current_landscape, 'Tất cả khổ ngang', 'Chữ đứng thẳng trước; trang nào còn dọc thì xoay về ngang'),
        ])
          ListTile(
            leading: Icon(icon, color: Mau.nhan),
            title: Text(ten, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(mo, style: const TextStyle(fontSize: 12)),
            onTap: () => Navigator.pop(c, ma),
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (cheDo == null || !context.mounted) return;
  if (!await xacNhanBoSua(context, hoSo.trang) || !context.mounted) return;
  final tienDo = ValueNotifier('Đang kiểm tra chiều trang…');
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 16),
          Expanded(child: ValueListenableBuilder(valueListenable: tienDo, builder: (_, s, _) => Text(s))),
        ]),
      ),
    ),
  );
  var so = 0;
  Object? loi;
  try {
    so = await kho.xoayToanBo(hoSo, cheDo,
        tienDo: (x, n) => tienDo.value = 'Đang kiểm tra chiều trang ${math.min(x + 1, n)}/$n…');
  } catch (e) {
    loi = e;
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  final dang = hoSo.soDangXuLy;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(loi != null
        ? 'Không xoay được: $loi'
        : (so == 0 ? 'Các trang đã đúng chiều' : 'Đã xoay $so trang, đang xử lý lại') +
            (dang > so ? ' · còn ${dang - so} trang đang xử lý, xoay lại sau' : '')),
  ));
}

class ManXemNhanh extends StatefulWidget {
  const ManXemNhanh({super.key, required this.hoSo});
  final HoSo hoSo;

  @override
  State<ManXemNhanh> createState() => _ManXemNhanhState();
}

class _ManXemNhanhState extends State<ManXemNhanh> {
  int _cot = 2;
  bool _chiCanXem = false;

  HoSo get h => widget.hoSo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: kho,
          builder: (context, _) {
            final canXem = [for (final t in h.trang) if (h.canhBao(t).isNotEmpty) t];
            final saiChieu = [for (final t in h.trang) if (t.saiChieu) t];
            final daKiem = h.trang.where((t) => t.daKiemChieu).length;
            final ds = _chiCanXem ? canXem : h.trang;
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                child: Row(children: [
                  IconButton(tooltip: 'Quay lại', icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Xem nhanh', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      Text(
                        '${h.trang.length} trang · ${canXem.length} cần xem'
                        '${daKiem < h.trang.length ? ' · đang kiểm tra chiều $daKiem/${h.trang.length}' : ''}',
                        style: const TextStyle(fontSize: 12, color: Mau.chuPhu),
                      ),
                    ]),
                  ),
                  IconButton(
                    tooltip: 'Xoay toàn bộ trang',
                    icon: const Icon(Icons.screen_rotation_alt),
                    onPressed: h.trang.isEmpty ? null : () => moXoayToanBo(context, h),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(children: [
                  ChonNhom<bool>(
                    giaTri: _chiCanXem,
                    cacMuc: {false: 'Tất cả', true: 'Cần xem (${canXem.length})'},
                    khiChon: (v) => setState(() => _chiCanXem = v),
                  ),
                  const Spacer(),
                  ChonNhom<int>(giaTri: _cot, cacMuc: const {1: 'Lớn', 2: 'Vừa', 3: 'Nhỏ'}, khiChon: (v) => setState(() => _cot = v)),
                ]),
              ),
              if (saiChieu.isNotEmpty)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                  decoration: BoxDecoration(color: Mau.camNen, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    const Icon(Icons.screen_rotation_alt, size: 18, color: Mau.camChu),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${saiChieu.length} trang sai chiều chữ',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Mau.camChu)),
                    ),
                    TextButton(
                      onPressed: () async {
                        if (!await xacNhanBoSua(context, saiChieu)) return;
                        for (final t in saiChieu) {
                          kho.xoayTrang(h, t, t.goiYXoay, theoChu: true);
                        }
                      },
                      child: const Text('Sửa chiều tất cả'),
                    ),
                  ]),
                ),
              Expanded(
                child: ds.isEmpty
                    ? Center(
                        child: Text(_chiCanXem ? 'Không có trang nào cần xem lại' : 'Hồ sơ chưa có trang',
                            style: const TextStyle(color: Mau.chuPhu)))
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: _cot, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: _cot == 1 ? 0.78 : 0.62),
                        itemCount: ds.length,
                        itemBuilder: (context, i) => _OXemNhanh(hoSo: h, trang: ds[i], so: h.trang.indexOf(ds[i]) + 1, cot: _cot),
                      ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _OXemNhanh extends StatelessWidget {
  const _OXemNhanh({required this.hoSo, required this.trang, required this.so, required this.cot});
  final HoSo hoSo;
  final TrangTL trang;
  final int so, cot;

  Future<void> _xoay(BuildContext context, int goc) async {
    if (await xacNhanBoSua(context, [trang])) kho.xoayTrang(hoSo, trang, goc);
  }

  /// Xóa trang chụp trùng (giống hệt một trang đứng trước).
  Future<void> _xoaTrung(BuildContext context) async {
    final goc = hoSo.trangTrungVoi(trang);
    if (goc == null) return;
    final dongY = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Xóa trang $so?'),
        content: Text('Trang $so giống hệt trang ${hoSo.trang.indexOf(goc) + 1}, có thể đã chụp hai lần. '
            'Xóa trang $so khỏi hồ sơ (ảnh gốc cũng bị xóa, không hoàn tác được)?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Giữ lại')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Xóa trang')),
        ],
      ),
    );
    if (dongY == true) await kho.xoaTrang(hoSo, trang);
  }

  @override
  Widget build(BuildContext context) {
    final t = trang;
    final canhBao = hoSo.canhBao(t);
    final tep = t.tepKq.isEmpty ? [t.tepNho ?? t.tepGoc] : t.tepKq;
    final rongAnh = cot == 1 ? 1100 : (cot == 2 ? 640 : 420);
    final nho = cot == 3;
    return Column(children: [
      Expanded(
        child: GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManSuaTrang(hoSo: hoSo, trang: t))),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFDCE2E7), // nền xám để thấy rõ mép, khổ trang trắng
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: canhBao.isEmpty ? Mau.vien : Mau.cam, width: canhBao.isEmpty ? 1 : 2.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(fit: StackFit.expand, children: [
              Row(children: [
                for (final f in tep)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Image.file(File(kho.duongDan(hoSo, f)), fit: BoxFit.contain, cacheWidth: rongAnh ~/ tep.length, gaplessPlayback: true),
                    ),
                  ),
              ]),
              if (t.dangXuLy)
                Container(
                  color: const Color(0xC7F4F6F8),
                  alignment: Alignment.center,
                  child: const Text('Đang xử lý', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Mau.camChu)),
                ),
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xCC15202B), borderRadius: BorderRadius.circular(999)),
                  child: Text('$so', style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
              if (canhBao.isNotEmpty)
                Positioned(
                  left: 4,
                  right: 4,
                  bottom: 4,
                  child: Wrap(spacing: 4, runSpacing: 4, children: [
                    for (final c in nho ? canhBao.take(1) : canhBao)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: Mau.cam, borderRadius: BorderRadius.circular(999)),
                        child: Text(c, style: TextStyle(fontSize: nho ? 10 : 11, color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                  ]),
                ),
            ]),
          ),
        ),
      ),
      SizedBox(
        height: 40,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _Nut(icon: Icons.rotate_left, ten: 'Xoay trái trang $so', onTap: () => _xoay(context, 270)),
          _Nut(icon: Icons.rotate_right, ten: 'Xoay phải trang $so', onTap: () => _xoay(context, 90)),
          if (t.saiChieu)
            _Nut(icon: Icons.auto_fix_high, ten: 'Sửa chiều trang $so', mau: Mau.cam, onTap: () => _xoay(context, t.goiYXoay)),
          if (hoSo.trangTrungVoi(t) != null)
            _Nut(icon: Icons.delete_outline, ten: 'Xóa trang $so (chụp trùng)', mau: Mau.cam, onTap: () => _xoaTrung(context)),
          if (t.trangThai == 'xong' && t.canhBaoAnh.isNotEmpty)
            _Nut(
              icon: Icons.photo_camera_outlined,
              ten: 'Chụp lại trang $so',
              mau: Mau.cam,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManChup(hoSo: hoSo, thayTrang: t))),
            ),
        ]),
      ),
    ]);
  }
}

class _Nut extends StatelessWidget {
  const _Nut({required this.icon, required this.ten, required this.onTap, this.mau = Mau.chuVua});
  final IconData icon;
  final String ten;
  final VoidCallback onTap;
  final Color mau;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: ten,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 38, height: 38),
        padding: EdgeInsets.zero,
        iconSize: 21,
        icon: Icon(icon, color: mau),
        onPressed: onTap,
      );
}
