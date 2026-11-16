# Xử lý PDF ảnh – bản Android (Flutter)

Ứng dụng điện thoại quét, làm sạch, nắn phẳng, nhận dạng chữ và xuất PDF. Mọi xử lý chạy trên máy, không gửi tài liệu đi đâu. Giao diện theo bản thiết kế trên canvas *Giao diện Xử lý PDF ảnh – Android* (5 màn hình). Lõi xử lý chuyển từ nguyên mẫu Python `ung-dung/loi_xu_ly/` sang Dart + OpenCV (`opencv_dart`). Nhận dạng chữ dùng Tesseract 5.5.1 (Tesseract4Android) với dữ liệu `vie`.

## Làm được gì
- **Chụp**: hai chế độ chọn ngay trên màn camera.
  - *Tự chụp*: tự chụp khi trang đứng yên, rõ nét, đủ sáng; không chụp trùng khi chưa lật trang.
  - *Bấm chụp*: người dùng bấm nút tròn; ứng dụng vẫn vẽ khung trang và nhắc *Đủ rõ, bấm nút tròn để chụp*.
  - Lời nhắc như *Đưa máy lại gần*, *Giữ yên*, *Bị lóa*; có đèn. Chế độ mở mặc định chọn trong Cài đặt.
- **Nhập**: ảnh từ thư viện; ảnh và PDF từ tệp. PDF tải về từ Zalo hay email cũng nhập theo cách này.
- **Làm sạch**: giữ màu dấu, chữ ký; có thêm chế độ xám, đen trắng, không làm sạch. Ba thanh chỉnh: độ trắng nền, độ đậm chữ, khử nhiễu.
  - Tương phản chữ cao hơn bản PC (đường cong dốc gấp đôi), lọc trung vị 3×3 khử nhiễu hạt.
  - Xóa đốm bụi đứng riêng, khoảng "gần chữ" tính theo cỡ chữ đo được nên giữ dấu thanh và dấu câu.
- **Báo nhòe ngay trên màn camera, trang chụp trùng** (0.7.9): `kiemTraAnhChup` (quy_trinh) chạy trong isolate sau mỗi ảnh, thanh báo + nút Chụp lại ở `ManChup`; `doMoMep`/`laNhoeGoc`, `dacTrung`/`diemKhop`/`trangTrung` (chat_luong); `Kho._doTrung`, `TrangTL.trungVoi`, nút xóa trang trùng ở Xem nhanh. OpenCV dựng thêm `features2d`, `flann` (pubspec `hooks`). Kiểm thử `integration_test/chat_luong_test.dart`.
- **Báo trang nên chụp lại** (0.7.8): `lib/loi/chat_luong.dart` (`laNhoe`, `doTay`), `xuLyAnh` trả `KetQuaXuLy.canhBao`, lưu `TrangTL.canhBaoAnh`; Xem nhanh có nút Chụp lại (`ManChup(thayTrang:)`, `Kho.thayAnh`). Kiểm thử `integration_test/chat_luong_test.dart`.
- **Tách cặp trang, lề, chụp xong mới xử lý** (0.7.7): `tachTrangDoi` cắt giữa khe gáy theo đường xiên (`kheGay`, `catTheoDuong` trong `lib/loi/nan_phang.dart`); `catSatChu(le:, giuKho:)` lề "Vừa" mặc định, trang ít chữ giữ khổ; `Kho.batDauChup`/`ketThucChup` tạm dừng hàng đợi xử lý khi đang ở màn chụp (Cài đặt › Chụp xong mới xử lý); `Kho.xuLyLaiHoSo` + nút *Xử lý lại cả hồ sơ* ở màn Các trang. Kiểm thử `integration_test/tach_trang_test.dart`.
- **Nắn vuông khối chữ** (0.7.6): `nanLe` trong `lib/loi/nan_cong.dart` làm hai lề thẳng, vuông góc dòng chữ; cặp trang sách mở được xoay thẳng từng trang (`_xoayThang`); `lamPhang(noi: noiKhung)` nới khung tự tìm 2,5% để không cắt lẹm chữ ở mép trang cong, nền trong dải nới được xóa (`_xoaNenNoi`). Nhập lại PDF cũ ở màn Hồ sơ để nắn lại. Kiểm thử `integration_test/le_khoi_test.dart`.
- **Sách mở, nửa cặp trang** (0.7.5): chụp sát mà một trang lọt ra ngoài khung thì `timTuGiac` nối thêm trang bên kia gáy tới biên ảnh (`_canhNoi`); tự chụp thấy khung chạm mép nên nhắc lùi máy. Kiểm thử `integration_test/nua_trang_test.dart` (ảnh `xlpdf_kiemthu/sach_mo`, tạo bằng `ung-dung/kiem_thu/tao_anh_sach_mo.py`).
- **Tự chụp** (0.7.4): đo rung theo độ dời (không phụ thuộc tương phản, xét cả từng ô để bắt tay đang vuốt trang); khung tìm mép trượt dưới 0,4 giây không làm đếm lại; nhận động tác lật trang để nhận cặp trang sách giống nhau; không chụp khi tay đặt trên trang ("Bỏ tay ra khỏi trang"); giữ yên Nhanh/Vừa/Chắc = 0,3/0,5/0,9 giây; rung nhẹ khi bắt được trang, rung khi chụp (Cài đặt › Rung báo; kênh `xlpdf/rung` trong `MainActivity.kt`).
- **Chụp** (0.7.1): camera ở độ phân giải tối đa của máy (không mở được thì 1080p); chạm vào khung xem trước để lấy nét; trước khi chụp lấy nét vào giữa khung và chờ xong; chụp xong đo độ mờ (`tiLeNet`, ngưỡng 0,55), mờ thì lấy nét lại và chụp lại một lần. Tự chụp dùng bộ tìm mép bản nhanh (ảnh 400 px), chỉ báo "lùi máy" khi trang bị cắt (cạnh hoặc góc trang nằm trên mép khung).
- **Tự xoay đúng chiều** (0.7.3): ảnh chụp cầm máy ngang (dòng chữ dọc) được xoay về ngang ngay sau nắn phối cảnh (`lib/loi/chieu_chu.dart`); sau khi xử lý, Tesseract đoán chiều và kho tự lật một lần (đủ 12 từ, chưa sửa chữ). Người dùng tự xoay trang thì tắt tự xoay của trang đó (`TuyChon.tuXoay`).
- **Cắt sát chữ** (0.7.2, nút *Cắt sát chữ* ở màn Chỉnh trang, bật sẵn): bước cuối sau sửa nghiêng, cắt sát vùng chữ (giữ số trang, chú thích, dấu, chữ ký) chừa lề trắng nhỏ, xóa vết ngoài vùng chữ: dải nền tối, nêm đen ở gáy sách, góc đen, ngón tay giữ sách (`lib/loi/cat_chu.dart`; 0.7.3: ngón tay màu da tô trắng kể cả khi đè lên chữ, vệt bóng cong, mẩu đen sát mép, đường gáy giữa hai trang; giữ tiêu đề cách xa thân bài). Trang không còn đúng tỉ lệ A4 (xuất A4 thì co giãn vừa trang).
- **Nắn phẳng, xoay**:
  - (0.7.0) tự tìm mép giấy kiểu CamScanner (`lib/loi/tim_mep.dart`): gom tứ giác ứng viên từ ảnh cạnh Canny, vùng Otsu, phân cụm màu k-means và ghép đường thẳng Hough; chấm điểm theo độ bám mép dọc từng cạnh (ngưỡng theo độ nhiễu hai bên mép), phần diện tích và phần "giống giấy"; tờ giấy nằm trên tờ giấy trắng khác hay trên bìa sổ thì chọn tứ giác trong; tinh chỉnh từng cạnh ở ảnh 1280 px. Tìm được mép giấy trên bàn trắng, nền lộn xộn, có ngón tay đè, bóng đổ, góc ra ngoài khung;
  - sửa phối cảnh về đúng tỉ lệ A4; (0.7.0) **nắn trang cong** theo dòng chữ (`lib/loi/nan_cong.dart`; 0.7.2: ảnh sách mở hai trang thì tách ở gáy, nắn từng trang; nút *Nắn trang cong* ở màn Chỉnh trang, bật sẵn): trang phẳng để nguyên; sửa nghiêng, xóa viền nền bàn;
  - chế độ *Sách* tự tách trang đôi; thẻ *Cắt, nắn phẳng*: kéo 4 góc hoặc giữa cạnh, có kính lúp phóng to chỗ đang kéo, phần ngoài khung tối đi;
  - sau khi xử lý, mỗi trang được Tesseract đoán chiều chữ (chạy nền, khoảng 1 giây một trang);
  - **Xoay toàn bộ**: theo chiều chữ, hoặc ép *Tất cả khổ dọc* / *Tất cả khổ ngang*. Xoay giữ khung cắt tay.
- **Xem nhanh** (cho hồ sơ nhiều trang): lưới ảnh trang cỡ Lớn / Vừa / Nhỏ, lọc *Cần xem*. Trang có vấn đề có viền cam và nhãn: *Ngược chiều*, *Chữ nằm nghiêng 90°*, *Khổ ngang/Khổ dọc* (khác đa số), *Chưa thấy mép giấy*, *Xử lý lỗi*. Xoay trái, phải, sửa chiều ngay trên ô; *Sửa chiều tất cả* một lần bấm. Ô trang ở màn Các trang cũng có dấu "!".
- **Nhận dạng chữ (OCR)** (từ 0.7.1 là chức năng riêng, nút *Nhận dạng chữ* ở màn Các trang; xuất PDF không tự nhận dạng; từ màn này có *Lưu .txt* và *PDF có chữ* để xuất kèm lớp chữ ẩn; báo trang máy đọc kém dưới 70%):
  - nút *Văn bản* ở màn Chỉnh trang và nút nhận dạng cả hồ sơ ở màn Các trang: xem, chọn, chép, chia sẻ chữ;
  - kết quả lưu đệm theo từng ảnh trang, trang xử lý lại thì nhận dạng lại;
  - khi xuất: *Thêm lớp chữ* (PDF tìm kiếm, chép chữ được, phông DejaVu Sans nhúng phần chữ đã dùng) và *Xuất kèm văn bản .txt*.
- **Sửa chữ trên trang** (nút *Sửa chữ* ở màn Chỉnh trang) có hai cách, chọn ở đầu màn:
- **Sửa ký tự (giữ nguyên bản gốc)**, cách mặc định:
  - giữ nguyên nội dung, hình dạng, cỡ chữ của bản scan, bản chụp; chỉ thêm, bớt ký tự. Ký tự không sửa giữ nguyên từng điểm ảnh (chỉ dời ngang khi có chèn, xóa phía trước), máy đọc sai cũng không làm đổi chỗ không sửa;
  - (0.6.0) đổi phông, cỡ chữ đoạn bôi chọn: chạm giữ rồi kéo trong dòng, hoặc nút Bôi chọn + ← →; thanh định dạng A− / cỡ (pt) / A+ (`dinhDangChon(tiLe:)`: phóng, thu chính nét gốc) và menu phông (`dinhDangChon(kieu: DinhDangVe(...))`: vẽ lại đoạn chọn bằng phông Liberation, màu mực, viền đậm đoán bằng `BoVeKyTu.doan`); chữ phóng to được vẽ ra ngoài dải dòng (`SuaDong.vungVe`); kiểm thử `sua_ky_tu_test.dart` (i);
  - (0.5.2) gõ tiếng Việt không lẫn phông, lẫn đậm nhạt: khung ký tự máy đọc nắn theo nét mực thật (`nanKhung`); chọn mẫu theo bề dày nét các chữ quanh chỗ chèn (`damQuanh`, đo riêng từng ký tự, đệm trong `kt_*.json`), loại mẫu dáng lạ; tô theo màu mực chỗ chèn; chữ có dấu thiếu ghép thân + dấu (`ghepDau`, bảng tách dấu sinh từ unicodedata); dấu rời ghép thành chữ dựng sẵn (`ghepDauRoi`);
  - (0.5.1) ảnh chụp có dòng nghiêng, dòng sát nhau: đường chân chữ là đường xiên đo riêng từng dòng; khi dời, chỉ nét mực của chính dòng bị xóa chỗ cũ (vá nền) và dán sang chỗ mới theo độ dốc của dòng, nét dòng trên, dòng dưới lọt vào cùng dải giữ nguyên (`netCuaDong`); khung dòng, con trỏ vẽ nghiêng theo dòng;
  - chạm vào dòng: dòng có viền cam, con trỏ đỏ ở chỗ chạm, ảnh tự phóng cho dòng cao khoảng 56 điểm (phóng thêm được để chạm chính xác); chạm trong dòng để dời con trỏ;
  - thanh dưới: ← → (dời con trỏ), ⌫ (xóa lùi), ⌦ (xóa tới), ô gõ chữ cần chèn + *Chèn* (bộ gõ tiếng Việt của bàn phím dùng bình thường), *Hủy*, *Xong*; xem trước ngay trên ảnh sau mỗi thao tác; ảnh tự cuộn cho con trỏ luôn hiện;
  - ký tự chèn được **chép nguyên hình** từ chỗ khác trên trang (cùng cỡ, nét, độ nhòe), căn đúng đường chân chữ; trang không có thì chép từ trang khác của hồ sơ (các trang khác được nhận dạng dần ở nền), cả hồ sơ không có mới vẽ bằng phông đoán được. Hai trường hợp sau có viền vàng và dòng nhắc *chạm giữ vào một ký tự đúng như vậy trên trang để dùng làm mẫu*; chạm giữ một ký tự trên trang là dùng nó làm mẫu (chèn nhiều loại ký tự thì hỏi cho ký tự nào);
  - dòng mục lục có dãy chấm dẫn: dãy chấm tự co giãn (thêm, bớt chấm ở cuối dãy) để số trang đứng nguyên chỗ, dù sửa chữ phía trước hay sửa chính số trang;
  - dòng dài quá lề phải thì nhắc; dòng có mực màu (con dấu, chữ ký, bút phê) bị khóa (viền cam);
  - *Xong* ghi thành ảnh kết quả mới, *Hoàn tác* được; PDF ghi chú *n chỗ sửa ký tự* trong Subject.
- **Vẽ lại bằng phông** (cách phụ, cách cũ của bản 0.4.0): viết lại cả khối chữ bằng phông Liberation, mất nét gốc:
  - chữ trên trang gộp thành **khối**: mỗi đoạn (các dòng liền nhau cùng đoạn) hoặc dòng đứng riêng (tiêu đề) là một khối; khung mờ quanh từng khối trên ảnh, phóng to, kéo được;
  - chạm một khối là **sửa ngay tại chỗ**: ô nhập phủ đúng vị trí khối, điền sẵn chữ máy đọc, chữ trong ô theo phông, cỡ, màu, căn lề của khối; *Xong* để áp, *Hủy* để bỏ; bàn phím hiện thì ảnh tự phóng, cuộn cho ô nhập hiện rõ;
  - tự đoán phông trong 8 phông Liberation Serif / Sans × thường, đậm, nghiêng, đậm nghiêng (cùng kích thước chữ với Times New Roman / Arial), cỡ chữ, độ đậm nét, màu mực; đổi phông được ở thanh dưới;
  - cả khối được dàn lại trong bề ngang cũ: ngắt dòng theo từ, giữ thụt đầu dòng, căn trái / giữa / đều hai bên / phải như cũ, cùng khoảng cách dòng; dòng ngắt cứng (hai dòng quốc hiệu, mỗi câu một dòng) giữ xuống dòng;
  - số dòng thay đổi thì phần trang bên dưới dời lên, xuống đúng số dòng chênh; tràn mép dưới thì vẫn làm và báo;
  - khối có mực màu (con dấu, chữ ký, bút phê) bị khóa (viền cam): *Chỗ này có con dấu, chữ ký, không cho sửa để tránh làm sai lệch giấy tờ*;
  - **Hoàn tác** từng lần sửa; trang đã sửa mà xử lý lại (xoay, đổi khung, đổi làm sạch) thì hỏi trước vì chỗ sửa sẽ mất;
  - PDF xuất từ hồ sơ có chỗ sửa ghi thuộc tính Subject *Đã chỉnh sửa nội dung bằng Xử lý PDF ảnh: n chỗ sửa ký tự, m chỗ sửa chữ* (chỗ sửa ký tự và chỗ vẽ lại bằng phông đếm riêng).
- **Hồ sơ**: nhiều trang, sắp xếp, xoay, xóa trang. Hồ sơ lưu trong máy và vẫn còn sau khi tắt ứng dụng.
- **Xuất PDF**: chọn khổ A4, A5, Letter hoặc theo ảnh; chọn lề và chất lượng (300, 200, 150 dpi). Có thể lưu vào máy hoặc chia sẻ sang Zalo, email.
- **Đánh số trang** (khi xuất):
  - chạm ảnh trang trong dải ảnh để chọn *trang đầu tiên được đánh số*; các trang trước để trống (vd. bỏ trang bìa);
  - *số in trên trang đó*: mặc định bằng thứ tự trang (chọn trang 2 thì in số 2), chỉnh được, có nút *Bắt đầu từ 1*;
  - *Vị trí*: lề trên, lề dưới; *Căn*: giữa, trái, phải, so le (*chẵn trái, lẻ phải* hoặc *chẵn phải, lẻ trái*, xét theo số in);
  - mỗi ảnh trang hiện luôn số sẽ in ở đúng chỗ để xem trước;
  - số in phông Times cỡ 13, cách mép giấy nửa lề (ít nhất 8 mm); căn trái, phải theo mép vùng nội dung (ít nhất 20 mm từ mép giấy). Khi lề nhỏ, số in đè lên phần trắng của ảnh trang;
  - vị trí, căn, so le lưu trong Cài đặt; trang bắt đầu và số đầu lưu theo từng hồ sơ.

**Chưa có**: nắn trang cong khi trang không có dòng chữ (ảnh, bảng), giãn ngang phần chữ bị co gần gáy sách; sửa ký tự trên dòng có mực màu (bị khóa có chủ ý), sửa chữ trên trang có nền màu, chữ viết tay, phông ngoài Times / Arial; nhận tệp chia sẻ trực tiếp từ Zalo (hiện phải lưu tệp rồi bấm *Nhập ảnh, PDF*). Chưa thử trên điện thoại thật.

## Cấu trúc
```
lib/
  main.dart               khởi động, chủ đề màu
  giao_dien/mau.dart      bảng màu, thành phần dùng chung
  du_lieu/kho.dart        hồ sơ, trang, hàng đợi xử lý (isolate), đoán chiều chạy nền,
                          xoay trang, nhận dạng chữ có đệm, gọi kênh Tesseract
  loi/                    lõi xử lý (chuyển từ Python)
    anh.dart              giải mã, mã hóa, tiện ích
    lam_sach.dart         tính năng 2, khử nhiễu (xoaDom)
    nan_phang.dart        tính năng 3
    nhan_dang.dart        đọc hOCR thành dòng, từ, vị trí, góc chữ; văn bản thuần
    sua_ky_tu.dart        Sửa ký tự giữ nguyên bản gốc: đọc hOCR có khung ký tự, gộp, nối dòng, dãy chấm dẫn,
                          chia mảnh, chọn ký tự mẫu, dựng lại dòng, phiên sửa một dòng (chuyển từ sua_ky_tu.py)
    sua_chu.dart          sửa chữ: gộp khối, đoán căn lề; đo nét mực, màu, mực màu; xóa chữ cũ,
                          dời phần dưới, phủ chữ mới, ghi PNG (thuần Dart + OpenCV, chạy trong isolate)
    ve_chu.dart           sửa chữ: đoán phông, cỡ, độ đậm; dàn chữ, vẽ bằng dart:ui (isolate chính);
                          vẽ ký tự cả hồ sơ không có cho Sửa ký tự (boVeKyTu)
    tu_chup.dart          tự động chụp (BoTuChup), đổi YUV → BGR
    quy_trinh.dart        ghép các bước một trang
    xuat_pdf.dart         ghi PDF, lớp chữ ẩn, đánh số trang (DanhSo)
  man_hinh/               màn hình: trang chủ, chụp, các trang, chỉnh trang, xuất,
                          xem nhanh (xem_nhanh.dart), văn bản (van_ban.dart), chế độ Sửa chữ: Sửa ký tự và
                          Vẽ lại bằng phông (trong sua_trang.dart),
                          khối đánh số trang ở màn xuất (danh_so.dart)
android/app/libs/tesseract4android-5.5.1.aar          Tesseract 5.5.1 (Apache 2.0)
android/app/src/main/kotlin/.../MainActivity.kt        kênh "xlpdf/nhan_dang": chạy Tesseract, trả hOCR (tham số kyTu:
                                                       bật hocr_char_boxes, kèm khung từng ký tự)
assets/tessdata/          vie.traineddata (nhận dạng), osd.traineddata (đoán chiều)
assets/phong/             DejaVuSans.ttf cho lớp chữ PDF; Liberation Serif, Sans (8 tệp, SIL OFL) để vẽ chữ sửa; GIAY-PHEP.txt
integration_test/         kiểm thử trên máy thật hoặc máy ảo (xem dưới)
```

Ghi chú kỹ thuật:
- Tesseract dùng OpenMP nhiều luồng chờ quay vòng, tranh CPU với luồng vẽ giao diện: trên máy ảo một trang mất 9–10 giây. `MainActivity` đặt `OMP_THREAD_LIMIT=1` trước khi nạp, còn khoảng 2,5 giây.
- Không dùng `vie+eng` (mất dấu tiếng Việt); `vie` đọc được cả tiếng Anh.
- Sửa chữ:
  - ảnh trang đã sửa lưu thành tệp kết quả mới dạng PNG (`sua_<trang>_<ảnh>_<mã>.png`): không mất dữ liệu nên chỗ không sửa giữ nguyên từng điểm ảnh, sửa nhiều lần không mờ dần; tên mới nên đệm nhận dạng cũ tự hết hiệu lực. Tệp trước khi sửa giữ trong `suaChu` của JSON hồ sơ để hoàn tác;
  - chữ của ảnh mới được dựng sẵn (khối sửa thay bằng các dòng vừa vẽ, phần dưới dời theo) và ghi vào đệm, nên không phải nhận dạng lại; lớp chữ PDF dùng luôn bản này;
  - module `photo` của OpenCV (có `inpaint`) bị loại khi dựng; trang kết quả đã làm sạch nền nên xóa chữ chỉ tô màu nền (trung vị điểm không phải mực quanh khối);
  - đoán phông: vẽ thử chữ cũ của dòng dài nhất bằng 8 phông ở cỡ khớp bề rộng nét mực, so hình nét (giao / hợp độ phủ, làm mờ nhẹ) và chiều cao; độ đậm: viền thêm cho số điểm mực đậm bằng chữ thật;
  - khối một dòng khi dài ra dùng khoảng cách dòng chung của trang (trung vị các đoạn nhiều dòng), không có thì 1,2 × cỡ chữ.
- Sửa ký tự (thuật toán chuẩn là bản PC `ung-dung/loi_xu_ly/sua_ky_tu.py`, đã kiểm chứng trên tệp thật):
  - mỗi dòng chia thành các **mảnh** liền nhau (mỗi ký tự, mỗi khoảng trắng là một dải điểm ảnh gốc); sửa = xếp lại mảnh: mảnh gốc dán nguyên điểm ảnh, xóa = bỏ mảnh, chèn = mảnh chép (chỉ lấy nét chạm khung ký tự mẫu, không dính nét chữ bên cạnh hay dòng khác; hòa theo độ phủ mực, căn đường chân chữ); mảnh rộng 0 bị bỏ;
  - ảnh 100–150 dpi chữ quá nhỏ, Tesseract đọc rất sai: phóng ảnh tới cạnh ngắn ≈ 2480 px (tối đa ×3) **chỉ để nhận dạng** (ảnh xám PNG tạm), tọa độ quy về ảnh gốc;
  - Tesseract đọc dãy chấm dẫn thành hàng chục "chữ" độ tin cậy cao: dãy chấm tìm theo **hình dạng** (chấm nhỏ ≤ 0,45 cỡ chữ, bước 0,5–1,8 lần bước trung bình, chấm liền nhau gần cùng độ cao vì scan nghiêng), chữ đọc nhầm trong vùng đó thay bằng chấm;
  - Tesseract bỏ sót số trang đứng lẻ ở mép phải: dòng được nối dài theo nét mực (ký tự chưa biết tên "?", sửa, xóa được nhưng không làm mẫu); các dòng Tesseract tách rời trên cùng hàng được gộp (khoảng hở < 30% bề rộng trang hoặc nối bằng dãy chấm);
  - cỡ chữ dòng lấy theo nhóm ký tự lớn đọc chắc; so cỡ hai dòng bằng chiều cao chữ thường không dấu (a c e m n o r s u v w x z), chênh ≤ 12% coi như bằng; đường chân chữ tính lại sau cùng từ đáy khung ký tự thật;
  - chọn mẫu: loại mẫu chữ, số cao < 55% cỡ dòng hoặc lệch hình so với các mẫu cùng tên; ưu tiên cùng trang, cùng cỡ, độ đậm nét gần (đo bằng biến đổi khoảng cách, lưu sẵn trong đệm cho mọi dòng);
  - khác bản PC: khe chữ chuẩn (nửa khe hai bên mẫu chép) không tính khe giữa các chấm dẫn, nếu không chữ chèn trên trang mục lục bị giãn thưa; con trỏ ở phần sau dãy chấm hiện đúng chỗ đã neo theo mép phải;
  - kết quả nhận dạng khung ký tự lưu đệm `kt_<ảnh>.json` (kèm số phiên bản thuật toán `banDocKyTu`, đổi thì đệm cũ tự bỏ); sau khi sửa, dòng vừa sửa được dựng lại từ các mảnh (không phải nhận dạng lại) và ghi vào đệm của ảnh mới, chữ mức từ (lớp chữ PDF) cũng thay dòng đó;
  - xem trước chỉ dựng lại dải dọc của dòng (PNG nhỏ) phủ lên ảnh trang, nên mỗi thao tác chỉ vài chục mili giây; mẫu ở trang khác chỉ giải mã ảnh trang đó khi thật sự chép;
  - khác bản PC: gỡ khung ký tự chồng nhau theo mảnh còn giữ gần nhất (tệp thật: từ máy đọc chồng lên từ sau làm vài cột điểm ảnh bị dán hai lần thành vệt lạ); chạm giữ nhận ký tự gần chỗ chạm nhất, trên dòng đang sửa thì quy về ảnh gốc qua mảnh đang hiện;
  - đã biết: làm sạch (xóa đốm bụi đứng riêng) có thể xóa bớt chấm dẫn nhỏ của mục lục chụp bằng máy (thấy ở `mau5-muc-luc.png` khi nhập qua ứng dụng); khi đó dãy chấm không được nhận, số trang không tự neo mép phải;
  - trên máy ảo: nhận dạng khung ký tự trang công văn 1503×2126 (phóng ×1,65) khoảng 2,2 giây; chèn một ký tự khoảng 10 ms.
- Gói `flutter_tesseract_ocr` không dựng được với AGP 9 (jcenter, AGP 7), nên gọi thẳng `.aar` qua kênh riêng.

## Dựng APK
Đường dẫn chứa chữ có dấu làm Gradle lỗi, nên mã đặt ở `D:\DevTools\src\xlpdf`. Thư mục `ung-dung-flutter` trong dự án là liên kết (junction) tới đây.

```bash
cd /d/DevTools/src/xlpdf
export JAVA_HOME="/c/Program Files/Microsoft/jdk-17.0.21.21-hotspot" ANDROID_HOME="D:/DevTools/Android"
/d/DevTools/flutter/bin/flutter build apk --release --target-platform android-arm64,android-x64
```

- APK ra ở `build/app/outputs/flutter-apk/app-release.apk` (khoảng 96 MB, gồm arm64 cho điện thoại và x86_64 cho máy ảo). Phần lớn là OpenCV, Flutter, Tesseract và 18 MB dữ liệu nhận dạng.
- Lần đầu dựng sẽ biên dịch OpenCV từ mã nguồn, mất khoảng 10–20 phút.
- Bản phát hành thử đang ký bằng khóa debug. Trước khi phát hành thật cần tạo khóa ký riêng.

## Kiểm thử trên máy ảo
`flutter test` gỡ ứng dụng sau mỗi lần chạy (mất cả hồ sơ đang có trên máy ảo), nên dùng script: cài bản debug, đẩy thư mục `D:\DevTools\src\xlpdf_kiemthu` vào thư mục tài liệu của ứng dụng, rồi chạy. Bộ nào ghi tệp vào `kiem_thu/ra/` (qua `integration_test/ra.dart`) thì script lấy về `build/kiem_thu_ra/`.

```bash
bash integration_test/chay_kiem_thu.sh loi_test.dart
```

| Bộ | Kiểm gì |
|---|---|
| `loi_test.dart` | tìm mép, xử lý trọn trang, tách trang đôi, tự động chụp, xuất PDF |
| `tu_chup_test.dart` | tự chụp trên 688 khung hình video chụp thật (sách mở trên nền đen, `xlpdf_kiemthu/video`): chụp đủ 6 cặp trang đúng lúc, không chụp khi tay trên trang |
| `cat_chu_test.dart` | cắt sát chữ, xóa vết, tìm gáy trên 8 + 11 trang sách chụp thật (`xlpdf_kiemthu/sach`, `sach2`: nhận dòng chữ dọc; so với bản Python); công văn mẫu giữ đủ dấu đỏ, chữ ký |
| `mep_cong_test.dart` | tự chụp: trang ôm sát khung vẫn chụp, trang bị cắt thì báo lùi máy; đo ảnh mờ; tìm mép kiểu CamScanner trên 17 ảnh tổng hợp khó (`xlpdf_kiemthu/mep`, tạo bằng `ung-dung/kiem_thu/tao_anh_mep.py`); nắn trang cong: dòng chữ thẳng lại, trang phẳng để nguyên. Ảnh trước/sau ra `build/kiem_thu_ra/nan-cong-*` |
| `nhan_dang_test.dart` | đọc hOCR; Tesseract trên máy so với PC; PDF có lớp chữ (lấy ra `build/kiem_thu_ra/lop_chu.pdf`) |
| `lam_sach_test.dart` | độ đen chữ, đốm nhiễu, nền trắng, dấu đỏ, nhận dạng trên ảnh chụp tốt và ảnh chụp kém |
| `chieu_test.dart` | đoán chiều chữ 4 góc; trang ngược tự phát hiện, Xoay toàn bộ, xoay giữ khung cắt tay, ép khổ dọc |
| `so_trang_test.dart` | quy tắc đánh số, căn so le; tạo 3 PDF có số trang. Sau đó chạy `python integration_test/kiem_so_trang.py` để đo vị trí số bằng PDFium |
| `sua_ky_tu_test.dart` | Sửa ký tự giữ nguyên bản gốc: đọc hOCR có khung ký tự (quy tọa độ khi phóng); công văn "ngày 15" → "ngày 20" (ngoài dải dòng và phần trước chỗ sửa không đổi điểm ảnh nào, "2", "0" chép từ chính trang, phần sau dời đúng chênh bề rộng, đọc lại đúng); trang mục lục `mau5-muc-luc.png`: dãy chấm theo hình dạng, "156" → "15" số trang vẫn căn phải, dãy chấm giãn; chèn "các " trước "Mục tiêu": số trang đứng nguyên, chữ chèn đúng cỡ, đúng đường chân; mẫu từ trang khác (chưa chắc), mẫu tay, vẽ bằng phông; dòng có mực màu bị khóa; kho: đệm, lưu, ghi chú PDF, sửa tiếp trên dòng dựng lại, hoàn tác. Ảnh ra `build/kiem_thu_ra/sk_*` |
| `sua_chu_test.dart` | sửa chữ theo khối trên trang mẫu: gộp khối, căn lề; đoán phông (Serif thường / đậm); sửa "Kính gửi" dài ra (đọc lại đúng, phần trên giữ nguyên từng điểm ảnh, phần dưới dời nguyên vẹn); tiêu đề vẫn ở giữa; đoạn thêm dòng không chồng chữ; khối có con dấu bị khóa; lưu, hoàn tác, ghi chú PDF, xử lý lại thì bỏ sửa. Ảnh trước, sau lấy ra `build/kiem_thu_ra/sc_*` |
