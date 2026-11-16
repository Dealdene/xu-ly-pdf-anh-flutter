// Khối "Đánh số trang" ở màn Xuất: chạm ảnh trang để chọn trang đầu tiên được đánh số; mỗi ảnh hiện số sẽ in
// đúng vị trí (xem trước). Chọn số đầu, vị trí (lề trên/dưới), căn (giữa/trái/phải/so le).
import 'dart:io';

import 'package:flutter/material.dart';

import '../du_lieu/kho.dart';
import '../giao_dien/mau.dart';
import '../loi/xuat_pdf.dart';
import '../main.dart';

/// Cách đánh số của hồ sơ theo cài đặt hiện tại; null nếu không đánh số.
DanhSo? danhSoCua(HoSo h) {
  final cd = kho.caiDat;
  if (!cd.danhSo) return null;
  final k = cd.kieuSo;
  return DanhSo(tuTrang: h.soTuTrang, soDau: h.soDau, viTri: k.viTri, can: k.can, chanTrai: k.chanTrai);
}

class TheDanhSo extends StatefulWidget {
  const TheDanhSo({super.key, required this.hoSo});
  final HoSo hoSo;

  @override
  State<TheDanhSo> createState() => _TheDanhSoState();
}

class _TheDanhSoState extends State<TheDanhSo> {
  HoSo get h => widget.hoSo;

  void _doi(void Function() viec, {bool hoSo = false}) {
    setState(viec);
    hoSo ? kho.luu(h) : kho.luuCaiDat();
  }

  void _chonTrangDau(int tuTrang) {
    _doi(() {
      // số đang theo vị trí trang (mặc định) thì đi theo trang mới chọn: chọn trang 2 → in số 2
      if (h.soDau == h.soTuTrang) h.soDau = tuTrang;
      h.soTuTrang = tuTrang;
    }, hoSo: true);
  }

  Widget _nhan(String s) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Text(s, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Mau.chuVua)),
      );

  @override
  Widget build(BuildContext context) {
    final cd = kho.caiDat;
    final k = cd.kieuSo;
    final tep = kho.tepTrang(h);
    if (h.soTuTrang > tep.length && tep.isNotEmpty) h.soTuTrang = tep.length;
    final ds = danhSoCua(h);
    final tomTat = ds == null
        ? 'In số trang ở lề trên hoặc lề dưới'
        : 'Từ trang ${h.soTuTrang} (in số ${h.soDau}) · ${tenViTriSo[k.viTri]!.toLowerCase()} · '
            '${k.can == 'so_le' ? (k.chanTrai ? 'so le, chẵn trái' : 'so le, chẵn phải') : tenCanSo[k.can]!.toLowerCase()}';
    return The(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: cd.danhSo,
          onChanged: (v) => _doi(() => cd.danhSo = v),
          title: const Text('Đánh số trang', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text(tomTat, style: const TextStyle(fontSize: 12)),
        ),
        if (ds != null) ...[
          _nhan('Trang đầu tiên được đánh số · chạm ảnh trang để chọn'),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tep.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _AnhTrang(
                duongDan: kho.duongDan(h, tep[i]),
                thuTu: i + 1,
                so: ds.soCua(i),
                danhSo: ds,
                laTrangDau: i + 1 == h.soTuTrang,
                onTap: () => _chonTrangDau(i + 1),
              ),
            ),
          ),
          _nhan('Số in trên trang ${h.soTuTrang}'),
          Row(children: [
            IconButton.outlined(
                tooltip: 'Giảm số đầu',
                onPressed: h.soDau <= 1 ? null : () => _doi(() => h.soDau--, hoSo: true),
                icon: const Icon(Icons.remove)),
            SizedBox(
                width: 52,
                child: Text('${h.soDau}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            IconButton.outlined(
                tooltip: 'Tăng số đầu', onPressed: () => _doi(() => h.soDau++, hoSo: true), icon: const Icon(Icons.add)),
            const SizedBox(width: 10),
            if (h.soDau != h.soTuTrang)
              TextButton(onPressed: () => _doi(() => h.soDau = h.soTuTrang, hoSo: true), child: Text('Theo thứ tự trang (${h.soTuTrang})'))
            else if (h.soDau != 1)
              TextButton(onPressed: () => _doi(() => h.soDau = 1, hoSo: true), child: const Text('Bắt đầu từ 1')),
          ]),
          _nhan('Vị trí'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in tenViTriSo.entries)
              ChoiceChip(label: Text(e.value), selected: k.viTri == e.key, showCheckmark: false, onSelected: (_) => _doi(() => k.viTri = e.key)),
          ]),
          _nhan('Căn'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in tenCanSo.entries)
              ChoiceChip(label: Text(e.value), selected: k.can == e.key, showCheckmark: false, onSelected: (_) => _doi(() => k.can = e.key)),
          ]),
          if (k.can == 'so_le') ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (v, ten) in const [(true, 'Chẵn trái, lẻ phải'), (false, 'Chẵn phải, lẻ trái')])
                ChoiceChip(label: Text(ten), selected: k.chanTrai == v, showCheckmark: false, onSelected: (_) => _doi(() => k.chanTrai = v)),
            ]),
          ],
        ],
      ]),
    );
  }
}

/// Ảnh nhỏ một trang kèm số sẽ in (đúng vị trí, căn); trang trước trang đầu được đánh số thì mờ đi.
class _AnhTrang extends StatelessWidget {
  const _AnhTrang(
      {required this.duongDan, required this.thuTu, required this.so, required this.danhSo, required this.laTrangDau, required this.onTap});
  final String duongDan;
  final int thuTu;
  final int? so;
  final DanhSo danhSo;
  final bool laTrangDau;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = so;
    final tren = danhSo.viTri == 'tren';
    final can = s == null ? 'giua' : danhSo.canCua(s);
    return Semantics(
      button: true,
      selected: laTrangDau,
      label: 'Trang $thuTu${s == null ? ', không đánh số' : ', in số $s'}',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 88,
          child: Column(children: [
            Expanded(
              child: Opacity(
                opacity: s == null ? 0.45 : 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: laTrangDau ? Mau.nhan : Mau.vien, width: laTrangDau ? 3 : 1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(fit: StackFit.expand, children: [
                    Padding(padding: const EdgeInsets.all(2), child: Image.file(File(duongDan), fit: BoxFit.contain, cacheWidth: 200)),
                    if (s != null)
                      Align(
                        alignment: switch ((tren, can)) {
                          (true, 'trai') => Alignment.topLeft,
                          (true, 'phai') => Alignment.topRight,
                          (true, _) => Alignment.topCenter,
                          (false, 'trai') => Alignment.bottomLeft,
                          (false, 'phai') => Alignment.bottomRight,
                          (false, _) => Alignment.bottomCenter,
                        },
                        child: Container(
                          margin: const EdgeInsets.all(3),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(color: Mau.nhan, borderRadius: BorderRadius.circular(4)),
                          child: Text('$s', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(laTrangDau ? 'Bắt đầu' : 'Trang $thuTu',
                style: TextStyle(fontSize: 11, fontWeight: laTrangDau ? FontWeight.w700 : FontWeight.w400, color: laTrangDau ? Mau.nhan : Mau.chuPhu)),
          ]),
        ),
      ),
    );
  }
}
