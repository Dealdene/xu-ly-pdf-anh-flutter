#!/usr/bin/env bash
# Chạy một bộ kiểm thử trên máy ảo hoặc điện thoại đang cắm.
# `flutter test` gỡ ứng dụng sau mỗi lần chạy (mất dữ liệu kiểm thử), nên script cài bản debug,
# đẩy thư mục D:\DevTools\src\xlpdf_kiemthu vào thư mục tài liệu của ứng dụng, rồi mới chạy.
# Cách dùng (Git Bash):  bash integration_test/chay_kiem_thu.sh [loi_test.dart|nhan_dang_test.dart] [thiết bị]
set -euo pipefail
cd "$(dirname "$0")/.."
BO=${1:-nhan_dang_test.dart}
THIET_BI=${2:-emulator-5554}
export JAVA_HOME="/c/Program Files/Microsoft/jdk-17.0.21.21-hotspot" ANDROID_HOME="D:/DevTools/Android" MSYS_NO_PATHCONV=1
ADB=/d/DevTools/Android/platform-tools/adb.exe
GOI=vn.xulypdf.xu_ly_pdf_anh
NEN=$($ADB -s "$THIET_BI" shell getprop ro.product.cpu.abi | tr -d '\r')
[ "$NEN" = "x86_64" ] && NEN=android-x64 || NEN=android-arm64

/d/DevTools/flutter/bin/flutter build apk --debug --target-platform "$NEN"
$ADB -s "$THIET_BI" install -r build/app/outputs/flutter-apk/app-debug.apk
$ADB -s "$THIET_BI" push "D:/DevTools/src/xlpdf_kiemthu" /data/local/tmp/ >/dev/null
$ADB -s "$THIET_BI" shell "run-as $GOI sh -c 'mkdir -p app_flutter/kiem_thu && cp -r /data/local/tmp/xlpdf_kiemthu/* app_flutter/kiem_thu/'"
# Bộ kiểm thử ghi tệp vào kiem_thu/ra/ rồi tạo tệp đánh dấu ra/xong (xem ra.dart); theo dõi ở nền và lấy hết
# ra build/kiem_thu_ra/ trước khi `flutter test` gỡ ứng dụng
mkdir -p build/kiem_thu_ra
(for _ in $(seq 1 1200); do
   if $ADB -s "$THIET_BI" shell "run-as $GOI ls app_flutter/kiem_thu/ra/xong" >/dev/null 2>&1; then
     for f in $($ADB -s "$THIET_BI" shell "run-as $GOI ls app_flutter/kiem_thu/ra" | tr -d '\r'); do
       [ "$f" = xong ] || $ADB -s "$THIET_BI" exec-out run-as $GOI cat "app_flutter/kiem_thu/ra/$f" > "build/kiem_thu_ra/$f"
     done
     echo "Đã lấy tệp kiểm thử ra build/kiem_thu_ra/"
     break
   fi
   sleep 0.5
 done) &
THEO_DOI=$!
/d/DevTools/flutter/bin/flutter test integration_test/"$BO" -d "$THIET_BI"
sleep 1
kill $THEO_DOI 2>/dev/null || true
wait
