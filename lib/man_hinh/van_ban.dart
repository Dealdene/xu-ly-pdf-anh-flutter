// Nhận dạng chữ (OCR), chức năng riêng: người dùng tự mở khi cần (xuất PDF không tự nhận dạng nữa).
// Xem, chọn chữ, chép, chia sẻ, lưu .txt; báo trang máy đọc kém; với cả hồ sơ thì xuất PDF tìm kiếm được.
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../du_lieu/kho.dart';
import '../giao_dien/mau.dart';
import '../loi/nhan_dang.dart';
import '../main.dart';
import 'xuat.dart';

/// Mở bảng Nhận dạng chữ cho các ảnh trang [tepAnh] của hồ sơ; nhận dạng những ảnh chưa có đệm.
/// [caHoSo]: đang nhận dạng cả hồ sơ (hiện nút xuất PDF tìm kiếm được).
Future<void> xemVanBan(BuildContext context, HoSo hoSo, List<String> tepAnh, String tieuDe, {bool caHoSo = false}) =>
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(c).size.height * 0.85,
          child: _BangVanBan(hoSo: hoSo, tepAnh: tepAnh, tieuDe: tieuDe, caHoSo: caHoSo),
        ),
      ),
    );

class _BangVanBan extends StatefulWidget {
  const _BangVanBan({required this.hoSo, required this.tepAnh, required this.tieuDe, required this.caHoSo});
  final HoSo hoSo;
  final List<String> tepAnh;
  final String tieuDe;
  final bool caHoSo;

  @override
  State<_BangVanBan> createState() => _BangVanBanState();
}

class _BangVanBanState extends State<_BangVanBan> {
  int _xong = 0;
  String? _vanBan, _loi;
  List<int> _trangKem = []; // số thứ tự (từ 1) các trang máy đọc kém

  @override
  void initState() {
    super.initState();
    _nhanDang();
  }

  Future<void> _nhanDang() async {
    try {
      final kq = <TrangChu>[];
      for (final tep in widget.tepAnh) {
        kq.add(await kho.nhanDang(widget.hoSo, tep));
        if (mounted) setState(() => _xong = kq.length);
      }
      final kem = <int>[];
      for (var i = 0; i < kq.length; i++) {
        final (n, tb) = kq[i].tinCay;
        if (n >= 5 && tb < 70) kem.add(i + 1);
      }
      if (mounted) {
        setState(() {
          _vanBan = vanBanNhieuTrang(kq);
          _trangKem = kem;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loi = '$e');
    }
  }

  Future<void> _luuTxt(String vb) async {
    final ten = '${widget.hoSo.ten.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').trim()}.txt';
    final noi = await FilePicker.saveFile(
      fileName: ten,
      bytes: Uint8List.fromList(utf8.encode(vb)),
      mimeType: 'text/plain',
      dialogTitle: 'Lưu văn bản',
    );
    if (noi != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã lưu $ten')));
  }

  @override
  Widget build(BuildContext context) {
    final vb = _vanBan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(widget.tieuDe, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Mau.beMat,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Mau.vienNhat),
            ),
            child: _loi != null
                ? Center(
                    child: Text('Không nhận dạng được: $_loi', style: const TextStyle(color: Mau.do_)),
                  )
                : vb == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 14),
                        Text(
                          widget.tepAnh.length > 1
                              ? 'Đang nhận dạng chữ trang ${_xong + 1}/${widget.tepAnh.length}…'
                              : 'Đang nhận dạng chữ…',
                          style: const TextStyle(color: Mau.chuPhu),
                        ),
                      ],
                    ),
                  )
                : vb.isEmpty
                ? const Center(
                    child: Text('Không thấy chữ trên trang', style: TextStyle(color: Mau.chuPhu)),
                  )
                : SingleChildScrollView(child: SelectableText(vb, style: const TextStyle(fontSize: 15, height: 1.45))),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            _trangKem.isEmpty
                ? 'Chữ do máy đọc, có thể sai; nên soát lại trước khi dùng.'
                : '${widget.tepAnh.length > 1 ? 'Trang ${_trangKem.join(', ')}' : 'Trang này'}: máy đọc kém (ảnh mờ, nhòe hoặc chữ nhỏ), '
                      'nhiều chữ có thể sai. Nên chụp lại cho nét rồi nhận dạng lại.',
            style: TextStyle(fontSize: 12, color: _trangKem.isEmpty ? Mau.chuPhu : Mau.camChu),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: vb == null || vb.isEmpty ? null : () => _luuTxt(vb),
                  icon: const Icon(Icons.save_alt, size: 18),
                  label: const Text('Lưu .txt'),
                ),
              ),
              if (widget.caHoSo) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: vb == null || vb.isEmpty
                        ? null
                        : () {
                            final nav = Navigator.of(context);
                            nav.pop();
                            nav.push(MaterialPageRoute(builder: (_) => ManXuat(hoSo: widget.hoSo, lopChu: true)));
                          },
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('PDF có chữ', maxLines: 1, softWrap: false, overflow: TextOverflow.fade),
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: vb == null || vb.isEmpty
                      ? null
                      : () => SharePlus.instance.share(ShareParams(text: vb, title: widget.tieuDe)),
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Chia sẻ'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: vb == null || vb.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: vb));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(content: Text('Đã chép văn bản')));
                          }
                        },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Chép tất cả'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
