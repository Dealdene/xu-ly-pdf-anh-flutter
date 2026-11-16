// Màn 5 · Xuất PDF: tên tệp, khổ giấy, chất lượng, lề, đánh số trang; lưu vào máy hoặc chia sẻ (Zalo, email…).
// Xuất không tự nhận dạng chữ (chậm, ảnh kém thì sai): nhận dạng là chức năng riêng (van_ban.dart); từ đó mở màn này
// với lopChu = true để xuất PDF kèm lớp chữ ẩn đã nhận dạng.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../du_lieu/kho.dart';
import '../giao_dien/mau.dart';
import '../loi/nhan_dang.dart';
import '../loi/xuat_pdf.dart';
import '../main.dart';
import 'danh_so.dart';

class ManXuat extends StatefulWidget {
  const ManXuat({super.key, required this.hoSo, this.lopChu = false});
  final HoSo hoSo;
  final bool lopChu; // kèm lớp chữ ẩn (mở từ Nhận dạng chữ)

  @override
  State<ManXuat> createState() => _ManXuatState();
}

class _ManXuatState extends State<ManXuat> {
  late final _ten = TextEditingController(text: _tenTep(widget.hoSo.ten));
  String _kho = 'a4', _chatLuong = 'vua';
  double _le = 0;
  bool _dangTao = false;
  String _trangThai = '';

  static String _tenTep(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// PDF và văn bản .txt (null nếu không chọn xuất kèm).
  Future<(Uint8List, String?)?> _taoPdf() async {
    setState(() {
      _dangTao = true;
      _trangThai = 'Đang tạo PDF…';
    });
    try {
      List<TrangChu>? chu;
      final lopChu = widget.lopChu;
      if (lopChu) {
        chu = await kho.nhanDangHoSo(
          widget.hoSo,
          tienDo: (xong, tong) {
            if (mounted) {
              setState(
                () => _trangThai = xong < tong ? 'Đang nhận dạng chữ trang ${xong + 1}/$tong…' : 'Đang tạo PDF…',
              );
            }
          },
        );
      }
      final anh = await kho.anhKetQua(widget.hoSo);
      final phong = lopChu ? await phongLopChu() : null;
      final pdf = await _taoPdfNen(
        anh,
        _kho,
        _le,
        _chatLuong,
        widget.hoSo.ten,
        lopChu ? chu : null,
        phong,
        danhSoCua(widget.hoSo),
        widget.hoSo.soChoSua,
        widget.hoSo.soSuaKyTu,
      );
      return (pdf, null);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không tạo được PDF: $e')));
      return null;
    } finally {
      if (mounted) setState(() => _dangTao = false);
    }
  }

  String get _tenGoc => _tenTep(_ten.text).isEmpty ? 'tai-lieu' : _tenTep(_ten.text);
  String get _tenDayDu => '$_tenGoc.pdf';

  Future<void> _luu() async {
    final kq = await _taoPdf();
    if (kq == null || !mounted) return;
    final (pdf, txt) = kq;
    final noi = await FilePicker.saveFile(
      fileName: _tenDayDu,
      bytes: pdf,
      mimeType: 'application/pdf',
      dialogTitle: 'Lưu PDF',
    );
    if (noi == null || !mounted) return;
    var daLuu = _tenDayDu;
    if (txt != null) {
      final noiTxt = await FilePicker.saveFile(
        fileName: '$_tenGoc.txt',
        bytes: Uint8List.fromList(utf8.encode(txt)),
        mimeType: 'text/plain',
        dialogTitle: 'Lưu văn bản',
      );
      if (noiTxt != null) daLuu += ' và $_tenGoc.txt';
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã lưu $daLuu')));
  }

  Future<void> _chiaSe() async {
    final kq = await _taoPdf();
    if (kq == null) return;
    final (pdf, txt) = kq;
    final tam = (await getTemporaryDirectory()).path;
    final tep = File('$tam/$_tenDayDu');
    await tep.writeAsBytes(pdf, flush: true);
    final cacTep = [XFile(tep.path, mimeType: 'application/pdf')];
    if (txt != null) {
      final tepTxt = File('$tam/$_tenGoc.txt');
      await tepTxt.writeAsString(txt, flush: true);
      cacTep.add(XFile(tepTxt.path, mimeType: 'text/plain'));
    }
    await SharePlus.instance.share(ShareParams(files: cacTep, title: _tenDayDu));
  }

  Widget _nhan(String s) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      s,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Mau.chuVua),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 6),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Quay lại',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text('Xuất PDF', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('${widget.hoSo.soTrangKq} trang', style: const TextStyle(color: Mau.chuPhu)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                children: [
                  _nhan('Tên tệp'),
                  TextField(
                    controller: _ten,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Mau.beMat,
                      suffixText: '.pdf',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFC9D2DA)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  The(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _nhan('Khổ giấy'),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final e in tenKhoGiay.entries)
                              ChoiceChip(
                                label: Text(e.value),
                                selected: _kho == e.key,
                                showCheckmark: false,
                                onSelected: (_) => setState(() => _kho = e.key),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _nhan('Chất lượng ảnh'),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final e in chatLuongXuat.entries)
                              ChoiceChip(
                                label: Text('${e.value.$1} · ${e.value.$2} dpi'),
                                selected: _chatLuong == e.key,
                                showCheckmark: false,
                                onSelected: (_) => setState(() => _chatLuong = e.key),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Lề (mm)',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Mau.chuVua),
                              ),
                            ),
                            IconButton.outlined(
                              tooltip: 'Giảm lề',
                              onPressed: _le <= 0 ? null : () => setState(() => _le -= 5),
                              icon: const Icon(Icons.remove),
                            ),
                            SizedBox(
                              width: 40,
                              child: Text(
                                _le.toStringAsFixed(0),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                            ),
                            IconButton.outlined(
                              tooltip: 'Tăng lề',
                              onPressed: _le >= 30 ? null : () => setState(() => _le += 5),
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TheDanhSo(hoSo: widget.hoSo),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(widget.lopChu ? Icons.manage_search : Icons.info_outline, size: 16, color: Mau.chuPhu),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.lopChu
                              ? 'Kèm lớp chữ đã nhận dạng: tìm kiếm, chép được chữ trong PDF. Chữ máy đọc có thể sai.'
                              : 'PDF gồm ảnh trang, không nhận dạng chữ. Cần chữ (chép, tìm kiếm, .txt): dùng Nhận dạng chữ ở màn Các trang.',
                          style: const TextStyle(fontSize: 12, color: Mau.chuPhu),
                        ),
                      ),
                    ],
                  ),
                  if (widget.hoSo.soChoSua > 0) ...[
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.edit_note, size: 16, color: Mau.camChu),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Hồ sơ có ${widget.hoSo.soChoSua} chỗ sửa${widget.hoSo.soSuaKyTu > 0 ? ' (${widget.hoSo.soSuaKyTu} chỗ sửa ký tự)' : ' chữ'}; '
                            'PDF sẽ ghi chú điều này trong thuộc tính tài liệu (Subject).',
                            style: const TextStyle(fontSize: 12, color: Mau.camChu),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_outline, size: 16, color: Mau.chuPhu),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Mọi xử lý chạy trên máy, không gửi tài liệu đi đâu.',
                          style: TextStyle(fontSize: 12, color: Mau.chuPhu),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: _dangTao
                  ? SizedBox(
                      height: 52,
                      child: Center(
                        child: Text(_trangThai, style: const TextStyle(color: Mau.chuPhu)),
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          flex: 10,
                          child: OutlinedButton.icon(
                            onPressed: _chiaSe,
                            icon: const Icon(Icons.share_outlined, size: 18),
                            label: const Text('Chia sẻ'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 14,
                          child: FilledButton.icon(
                            onPressed: _luu,
                            icon: const Icon(Icons.download_outlined, size: 18),
                            label: const Text('Lưu vào máy'),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hàm cấp cao nhất: closure gửi sang isolate chỉ mang theo tham số, không dính State của màn hình.
Future<Uint8List> _taoPdfNen(
  List<Uint8List> anh,
  String kho,
  double le,
  String cl,
  String td,
  List<TrangChu>? chu,
  Uint8List? phong,
  DanhSo? danhSo,
  int soChoSua,
  int soSuaKyTu,
) => Isolate.run(
  () => taoPdf(
    anh,
    kho: kho,
    leMm: le,
    chatLuong: cl,
    tieuDe: td,
    chu: chu,
    phong: phong,
    danhSo: danhSo,
    soChoSua: soChoSua,
    soSuaKyTu: soSuaKyTu,
  ),
);
