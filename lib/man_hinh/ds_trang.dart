// Màn 3 · Các trang của hồ sơ: lưới ảnh trang, chụp thêm, sắp xếp, xuất PDF.
import 'dart:io';

import 'package:flutter/material.dart';

import '../du_lieu/kho.dart';
import '../giao_dien/mau.dart';
import '../loi/cat_chu.dart';
import '../main.dart';
import 'chup.dart';
import 'sua_trang.dart';
import 'trang_chu.dart';
import 'van_ban.dart';
import 'xem_nhanh.dart';
import 'xuat.dart';

class ManDanhSachTrang extends StatelessWidget {
  const ManDanhSachTrang({super.key, required this.hoSo});
  final HoSo hoSo;

  Future<void> _sapXep(BuildContext context) => showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(c).size.height * 0.7,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Giữ và kéo để đổi thứ tự trang', style: TextStyle(color: Mau.chuPhu)),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: kho,
                builder: (c, _) => ReorderableListView.builder(
                  itemCount: hoSo.trang.length,
                  onReorderItem: (tu, den) => kho.doiCho(hoSo, tu, den),
                  itemBuilder: (c, i) {
                    final t = hoSo.trang[i];
                    return ListTile(
                      key: ValueKey(t.id),
                      leading: SizedBox(
                        width: 40,
                        height: 54,
                        child: t.tepNho == null
                            ? const Icon(Icons.hourglass_empty)
                            : Image.file(File(kho.duongDan(hoSo, t.tepNho!)), fit: BoxFit.cover),
                      ),
                      title: Text('Trang ${i + 1}'),
                      trailing: const Icon(Icons.drag_handle),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// Xử lý lại mọi trang từ ảnh gốc (cách cắt, nắn, tách trang mới nhất), chọn lề trang.
  Future<void> _xuLyLai(BuildContext context) async {
    var le = kho.caiDat.le;
    final daSua = hoSo.trang.where((t) => t.lichSuSua.isNotEmpty).length;
    final dongY = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, datLai) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Xử lý lại cả hồ sơ', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                'Cắt, nắn vuông, tách trang, làm sạch lại mọi trang từ ảnh gốc đã chụp, theo cách mới nhất của ứng dụng. '
                'Không phải chụp lại.',
                style: TextStyle(fontSize: 13, color: Mau.chuVua),
              ),
              if (daSua > 0) ...[
                const SizedBox(height: 6),
                Text('$daSua trang đã sửa chữ sẽ được giữ nguyên (xử lý lại sẽ mất chỗ sửa).',
                    style: const TextStyle(fontSize: 13, color: Mau.camChu)),
              ],
              const SizedBox(height: 14),
              const Text('Lề trang', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Mau.chuVua)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [
                for (final e in tenLe.entries)
                  ChoiceChip(label: Text(e.value), selected: le == e.key, onSelected: (_) => datLai(() => le = e.key)),
              ]),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.auto_fix_high),
                  label: Text('Xử lý lại ${hoSo.trang.length - daSua} trang'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    if (dongY != true) return;
    final (so, bo) = kho.xuLyLaiHoSo(hoSo, le);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đang xử lý lại $so trang${bo > 0 ? ', giữ nguyên $bo trang đã sửa chữ' : ''}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: kho,
          builder: (context, _) {
            final dang = hoSo.soDangXuLy;
            final coLoi = hoSo.trang.any((t) => t.trangThai == 'loi');
            final canXem = hoSo.trang.where((t) => hoSo.canhBao(t).isNotEmpty).length;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Quay lại',
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () async {
                            final ten = await hoiTen(context, hoSo.ten);
                            if (ten != null && ten.trim().isNotEmpty) {
                              hoSo.ten = ten.trim();
                              await kho.luu(hoSo);
                              kho.capNhat();
                            }
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hoSo.ten,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                              ),
                              Text(
                                '${hoSo.soTrangKq} trang · chạm một trang để chỉnh',
                                style: const TextStyle(fontSize: 12, color: Mau.chuPhu),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Xem nhanh, tìm trang lệch',
                        icon: Badge(
                          isLabelVisible: canXem > 0,
                          backgroundColor: Mau.cam,
                          label: Text('$canXem'),
                          child: const Icon(Icons.grid_view),
                        ),
                        onPressed: hoSo.trang.isEmpty
                            ? null
                            : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManXemNhanh(hoSo: hoSo))),
                      ),
                      IconButton(
                        tooltip: 'Xử lý lại cả hồ sơ',
                        icon: const Icon(Icons.auto_fix_high),
                        onPressed: hoSo.trang.isEmpty ? null : () => _xuLyLai(context),
                      ),
                      IconButton(
                        tooltip: 'Xoay toàn bộ trang',
                        icon: const Icon(Icons.screen_rotation_alt),
                        onPressed: hoSo.trang.isEmpty ? null : () => moXoayToanBo(context, hoSo),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.62,
                    ),
                    itemCount: hoSo.trang.length + 1,
                    itemBuilder: (context, i) {
                      if (i == hoSo.trang.length) {
                        return _OChupThem(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManChup(hoSo: hoSo))),
                        );
                      }
                      final t = hoSo.trang[i];
                      return _OTrang(
                        hoSo: hoSo,
                        trang: t,
                        so: i + 1,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ManSuaTrang(hoSo: hoSo, trang: t),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: The(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(
                              dang > 0
                                  ? Icons.autorenew
                                  : (coLoi
                                        ? Icons.error_outline
                                        : (canXem > 0 ? Icons.warning_amber_rounded : Icons.check)),
                              size: 16,
                              color: dang > 0 || canXem > 0 ? Mau.camChu : (coLoi ? Mau.do_ : Mau.xanhLaChu),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                dang > 0
                                    ? (kho.tamDung ? 'Chụp xong sẽ xử lý $dang trang' : 'Đang xử lý $dang trang…')
                                    : coLoi
                                    ? 'Có trang xử lý lỗi; mở trang đó để thử lại'
                                    : canXem > 0
                                    ? '$canXem trang nên xem lại (ngược chiều, lệch khổ…) · bấm Xem nhanh'
                                    : 'Nền đã làm trắng, giữ màu dấu và chữ ký',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: dang > 0 || canXem > 0 ? Mau.camChu : (coLoi ? Mau.do_ : Mau.xanhLaChu),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: hoSo.trang.length < 2 ? null : () => _sapXep(context),
                                icon: const Icon(Icons.swap_vert, size: 18),
                                label: const Text('Sắp xếp', maxLines: 1, softWrap: false, overflow: TextOverflow.fade),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: hoSo.trang.isEmpty || dang > 0
                                    ? null
                                    : () => xemVanBan(
                                        context,
                                        hoSo,
                                        kho.tepTrang(hoSo),
                                        'Nhận dạng chữ · ${hoSo.ten}',
                                        caHoSo: true,
                                      ),
                                icon: const Icon(Icons.text_snippet_outlined, size: 18),
                                label: const Text('Nhận dạng chữ', maxLines: 1, softWrap: false, overflow: TextOverflow.fade),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: hoSo.trang.isEmpty || dang > 0
                                ? null
                                : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManXuat(hoSo: hoSo))),
                            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                            label: const Text('Xuất PDF'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OTrang extends StatelessWidget {
  const _OTrang({required this.hoSo, required this.trang, required this.so, required this.onTap});
  final HoSo hoSo;
  final TrangTL trang;
  final int so;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Chỉnh trang $so',
    button: true,
    child: GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Mau.beMat,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Mau.vien),
                boxShadow: const [BoxShadow(color: Color(0x0F15202B), blurRadius: 2, offset: Offset(0, 1))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (trang.tepNho != null) Image.file(File(kho.duongDan(hoSo, trang.tepNho!)), fit: BoxFit.contain),
                  if (trang.dangXuLy)
                    Container(
                      color: const Color(0xC7F4F6F8),
                      alignment: Alignment.center,
                      child: const Text(
                        'Đang xử lý',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Mau.camChu),
                      ),
                    ),
                  if (trang.trangThai == 'loi')
                    Container(
                      color: const Color(0xC7F4F6F8),
                      alignment: Alignment.center,
                      child: const Text(
                        'Lỗi',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Mau.do_),
                      ),
                    ),
                  if (hoSo.canhBao(trang).isNotEmpty)
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Tooltip(
                        message: hoSo.canhBao(trang).join(', '),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(color: Mau.cam, shape: BoxShape.circle),
                          child: const Icon(Icons.priority_high, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  if (trang.tepKq.length > 1)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: Mau.nhan, borderRadius: BorderRadius.circular(999)),
                        child: const Text(
                          '2 trang',
                          style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$so',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Mau.chuPhu),
          ),
        ],
      ),
    ),
  );
}

class _OChupThem extends StatelessWidget {
  const _OChupThem({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF9DB9CB), width: 2),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, color: Mau.nhan),
                SizedBox(height: 6),
                Text(
                  'Chụp thêm',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Mau.nhan),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(' ', style: TextStyle(fontSize: 12)),
      ],
    ),
  );
}
