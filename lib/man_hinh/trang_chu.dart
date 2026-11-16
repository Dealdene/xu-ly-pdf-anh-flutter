// Màn 1 · Hồ sơ (trang chủ): chụp mới, nhập ảnh/PDF, danh sách hồ sơ gần đây.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

import '../du_lieu/kho.dart';
import '../giao_dien/mau.dart';
import '../loi/cat_chu.dart';
import '../loi/lam_sach.dart';
import '../main.dart';
import 'chup.dart';
import 'ds_trang.dart';

class ManTrangChu extends StatefulWidget {
  const ManTrangChu({super.key});

  @override
  State<ManTrangChu> createState() => _ManTrangChuState();
}

class _ManTrangChuState extends State<ManTrangChu> {
  bool _dangNhap = false;

  Future<void> _chupMoi() async {
    final h = await kho.taoHoSo();
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ManChup(hoSo: h)));
    if (h.trang.isEmpty) {
      await kho.xoaHoSo(h);
    } else if (mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ManDanhSachTrang(hoSo: h)));
    }
  }

  Future<void> _nhap(Future<List<(XFile, String)>> Function() chon) async {
    final tep = await chon(); // (tệp, đuôi)
    if (tep.isEmpty || !mounted) return;
    setState(() => _dangNhap = true);
    try {
      final h = await kho.taoHoSo();
      for (final (x, duoi) in tep) {
        final d = await x.readAsBytes();
        if (duoi == 'pdf') {
          // Kết xuất từng trang PDF thành ảnh 200 dpi bằng bộ đọc PDF của Android.
          await for (final trang in Printing.raster(d, dpi: 200)) {
            await kho.themAnh(h, await trang.toPng(), duoi: 'png');
          }
        } else {
          await kho.themAnh(h, d, duoi: duoi);
        }
      }
      if (h.trang.isEmpty) {
        await kho.xoaHoSo(h);
      } else if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => ManDanhSachTrang(hoSo: h)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không mở được tệp: $e')));
    } finally {
      if (mounted) setState(() => _dangNhap = false);
    }
  }

  Future<List<(XFile, String)>> _chonTep() async {
    final ds = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'],
    );
    return [for (final f in ds) (f.xFile, (f.extension ?? 'jpg').replaceAll('.', '').toLowerCase())];
  }

  Future<List<(XFile, String)>> _chonAnh() async {
    final ds = await ImagePicker().pickMultiImage();
    return [for (final x in ds) (x, x.path.split('.').last.toLowerCase())];
  }

  void _moCaiDat() =>
      showModalBottomSheet(context: context, showDragHandle: true, isScrollControlled: true, builder: (_) => const _CaiDat());

  Future<void> _tuyChonHoSo(HoSo h) async {
    final chon = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Đổi tên'), onTap: () => Navigator.pop(c, 'ten')),
          ListTile(
              leading: const Icon(Icons.delete_outline, color: Mau.do_),
              title: const Text('Xóa hồ sơ', style: TextStyle(color: Mau.do_)),
              onTap: () => Navigator.pop(c, 'xoa')),
        ]),
      ),
    );
    if (!mounted) return;
    if (chon == 'ten') {
      final ten = await hoiTen(context, h.ten);
      if (ten != null && ten.trim().isNotEmpty) {
        h.ten = ten.trim();
        await kho.luu(h);
        setState(() {});
      }
    } else if (chon == 'xoa') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Xóa hồ sơ?'),
          content: Text('“${h.ten}” và toàn bộ ${h.trang.length} trang sẽ bị xóa khỏi máy.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Thôi')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Xóa', style: TextStyle(color: Mau.do_))),
          ],
        ),
      );
      if (ok == true) await kho.xoaHoSo(h);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: kho,
          builder: (context, _) => CustomScrollView(slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              sliver: SliverToBoxAdapter(
                child: Row(children: [
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Quét · làm sạch · PDF', style: TextStyle(fontSize: 13, color: Mau.chuPhu)),
                      SizedBox(height: 2),
                      Text('Hồ sơ của tôi', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  if (_dangNhap) const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              sliver: SliverToBoxAdapter(
                child: Column(children: [
                  Material(
                    color: Mau.nhan,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: _chupMoi,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
                            child: const Icon(Icons.photo_camera_outlined, color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 16),
                          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Chụp tài liệu', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
                            SizedBox(height: 3),
                            Text('Tự chụp khi trang đứng yên, hoặc bấm chụp', style: TextStyle(fontSize: 13, color: Color(0xFFD6E8F2))),
                          ]),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: _OChon(
                            icon: Icons.upload_file_outlined,
                            ten: 'Nhập ảnh, PDF',
                            mo: 'Từ tệp tải về, Zalo, email',
                            onTap: _dangNhap ? null : () => _nhap(_chonTep))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _OChon(
                            icon: Icons.photo_library_outlined,
                            ten: 'Thư viện ảnh',
                            mo: 'Chọn nhiều ảnh một lúc',
                            onTap: _dangNhap ? null : () => _nhap(_chonAnh))),
                  ]),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              sliver: SliverToBoxAdapter(
                child: Row(children: [
                  const Expanded(child: Text('Gần đây', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                  Text('${kho.hoSo.length} hồ sơ', style: const TextStyle(fontSize: 13, color: Mau.chuPhu)),
                ]),
              ),
            ),
            if (kho.hoSo.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(32, 32, 32, 0),
                  child: Text('Chưa có hồ sơ nào. Bấm “Chụp tài liệu” hoặc nhập ảnh, PDF để bắt đầu.',
                      textAlign: TextAlign.center, style: TextStyle(color: Mau.chuPhu, height: 1.4)),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              sliver: SliverList.separated(
                itemCount: kho.hoSo.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _DongHoSo(
                  hoSo: kho.hoSo[i],
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManDanhSachTrang(hoSo: kho.hoSo[i]))),
                  onLongPress: () => _tuyChonHoSo(kho.hoSo[i]),
                ),
              ),
            ),
          ]),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          height: 72,
          decoration: const BoxDecoration(color: Mau.beMat, border: Border(top: BorderSide(color: Mau.vienNhat))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _NutDuoi(icon: Icons.folder_outlined, ten: 'Hồ sơ', chon: true, onTap: () {}),
            Semantics(
              label: 'Chụp',
              button: true,
              child: GestureDetector(
                onTap: _chupMoi,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Mau.nhan,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Mau.nhan.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: const Icon(Icons.photo_camera_outlined, color: Colors.white, size: 26),
                ),
              ),
            ),
            _NutDuoi(icon: Icons.settings_outlined, ten: 'Cài đặt', chon: false, onTap: _moCaiDat),
          ]),
        ),
      ),
    );
  }
}

Future<String?> hoiTen(BuildContext context, String hienTai) {
  final ctl = TextEditingController(text: hienTai);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Tên hồ sơ'),
      content: TextField(controller: ctl, autofocus: true, textCapitalization: TextCapitalization.sentences),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Thôi')),
        TextButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('Lưu')),
      ],
    ),
  );
}

class _OChon extends StatelessWidget {
  const _OChon({required this.icon, required this.ten, required this.mo, this.onTap});
  final IconData icon;
  final String ten, mo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Mau.beMat,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Mau.vien)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: Mau.nhan, size: 22),
              const SizedBox(height: 8),
              Text(ten, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(mo, style: const TextStyle(fontSize: 12, color: Mau.chuPhu)),
            ]),
          ),
        ),
      );
}

class _NutDuoi extends StatelessWidget {
  const _NutDuoi({required this.icon, required this.ten, required this.chon, required this.onTap});
  final IconData icon;
  final String ten;
  final bool chon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkResponse(
        onTap: onTap,
        child: SizedBox(
          width: 72,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: chon ? Mau.nhan : Mau.chuPhu),
            const SizedBox(height: 3),
            Text(ten,
                style: TextStyle(fontSize: 12, fontWeight: chon ? FontWeight.w600 : FontWeight.w500, color: chon ? Mau.nhan : Mau.chuPhu)),
          ]),
        ),
      );
}

class _DongHoSo extends StatelessWidget {
  const _DongHoSo({required this.hoSo, required this.onTap, required this.onLongPress});
  final HoSo hoSo;
  final VoidCallback onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    final dau = hoSo.trang.isEmpty ? null : hoSo.trang.first;
    final ngay = '${hoSo.taoLuc.day.toString().padLeft(2, '0')}/${hoSo.taoLuc.month.toString().padLeft(2, '0')}/${hoSo.taoLuc.year}';
    final dang = hoSo.soDangXuLy;
    return Material(
      color: Mau.beMat,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Mau.vienNhat)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 46,
              height: 62,
              decoration: BoxDecoration(
                color: Mau.beMat,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Mau.vien),
              ),
              clipBehavior: Clip.antiAlias,
              child: dau?.tepNho == null
                  ? const Icon(Icons.description_outlined, color: Mau.vien)
                  : Image.file(File(kho.duongDan(hoSo, dau!.tepNho!)), fit: BoxFit.cover),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(hoSo.ten, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('${hoSo.soTrangKq} trang · $ngay · ${hoSo.loai == 'sach' ? 'sách' : 'giấy rời'}',
                    style: const TextStyle(fontSize: 12, color: Mau.chuPhu)),
                if (dang > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Mau.camNen, borderRadius: BorderRadius.circular(999)),
                    child: Text('Đang xử lý ${hoSo.trang.length - dang}/${hoSo.trang.length}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Mau.camChu)),
                  ),
                ],
              ]),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF8994A0)),
          ]),
        ),
      ),
    );
  }
}

class _CaiDat extends StatefulWidget {
  const _CaiDat();

  @override
  State<_CaiDat> createState() => _CaiDatState();
}

class _CaiDatState extends State<_CaiDat> {
  @override
  Widget build(BuildContext context) {
    final cd = kho.caiDat;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Cài đặt', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          const Text('Làm sạch mặc định cho trang mới', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Mau.chuVua)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in cheDoLamSach.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: cd.cheDo == e.key,
                onSelected: (_) => setState(() {
                  cd.cheDo = e.key;
                  kho.luuCaiDat();
                }),
              ),
          ]),
          const SizedBox(height: 18),
          const Text('Lề trang', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Mau.chuVua)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in tenLe.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: cd.le == e.key,
                onSelected: (_) => setState(() {
                  cd.le = e.key;
                  kho.luuCaiDat();
                }),
              ),
          ]),
          const SizedBox(height: 4),
          const Text('Áp dụng cho trang chụp mới; hồ sơ đã có: nút Xử lý lại ở màn Các trang.',
              style: TextStyle(fontSize: 12, color: Mau.chuPhu)),
          const SizedBox(height: 18),
          const Text('Độ nhạy tự động chụp', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Mau.chuVua)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (final e in const {'nhanh': 'Nhanh (0,3 giây)', 'vua': 'Vừa (0,5 giây)', 'chac': 'Chắc (0,9 giây)'}.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: cd.doNhay == e.key,
                onSelected: (_) => setState(() {
                  cd.doNhay = e.key;
                  kho.luuCaiDat();
                }),
              ),
          ]),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mở camera ở chế độ Tự chụp'),
            subtitle: const Text('Tắt thì mở ở chế độ Bấm chụp; đổi được ngay trên màn camera'),
            value: cd.tuDongChup,
            onChanged: (v) => setState(() {
              cd.tuDongChup = v;
              kho.luuCaiDat();
            }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Chụp xong mới xử lý'),
            subtitle: const Text('Lúc chụp chỉ lưu ảnh gốc; rời màn camera mới cắt, nắn vuông, làm sạch. Tự chụp nhanh hơn'),
            value: cd.xuLySauChup,
            onChanged: (v) => setState(() {
              cd.xuLySauChup = v;
              kho.luuCaiDat();
            }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Rung báo'),
            subtitle: const Text('Rung nhẹ khi bắt được trang, rung khi chụp'),
            value: cd.rung,
            onChanged: (v) => setState(() {
              cd.rung = v;
              kho.luuCaiDat();
            }),
          ),
          const SizedBox(height: 4),
          const Text('Mọi xử lý chạy trên máy, không gửi tài liệu đi đâu.', style: TextStyle(fontSize: 12, color: Mau.chuPhu)),
        ]),
      ),
    );
  }
}
