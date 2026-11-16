package vn.xulypdf.xu_ly_pdf_anh

import android.content.Context
import android.os.Build
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.system.Os
import android.util.Log
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

// Kênh nhận dạng chữ: Tesseract 5.5.1 (Tesseract4Android, libs/tesseract4android-5.5.1.aar) chạy trên một luồng riêng,
// trả hOCR để phía Dart đọc vị trí từng từ, chiều chữ (lib/loi/nhan_dang.dart).
class MainActivity : FlutterActivity() {
    private val luong = Executors.newSingleThreadExecutor()
    private var tess: TessBaseAPI? = null
    private var daNap = ""

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Kênh rung: báo khi tự chụp bắt được trang và khi chụp (rung thật bằng Vibrator, không phụ thuộc cài đặt
        // "rung khi chạm" của máy như HapticFeedback)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xlpdf/rung").setMethodCallHandler { call, result ->
            try {
                val ms = (call.argument<Int>("ms") ?: 40).toLong()
                val bienDo = call.argument<Int>("bienDo") ?: VibrationEffect.DEFAULT_AMPLITUDE
                val may = if (Build.VERSION.SDK_INT >= 31) {
                    (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
                } else {
                    @Suppress("DEPRECATION") getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                }
                if (Build.VERSION.SDK_INT >= 26) {
                    may.vibrate(VibrationEffect.createOneShot(ms, bienDo))
                } else {
                    @Suppress("DEPRECATION") may.vibrate(ms)
                }
                result.success(null)
            } catch (e: Exception) {
                result.success(null) // máy không rung được: bỏ qua
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xlpdf/nhan_dang").setMethodCallHandler { call, result ->
            if (call.method != "hocr") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val anh = call.argument<String>("anh")!!
            val thuMuc = call.argument<String>("thuMuc")!! // thư mục chứa tessdata/
            val ngonNgu = call.argument<String>("ngonNgu") ?: "vie"
            // 3: tự chia khối; 1: tự chia khối và đoán chiều chữ (cần tessdata/osd.traineddata, hOCR ghi "textangle")
            val psm = call.argument<Int>("psm") ?: TessBaseAPI.PageSegMode.PSM_AUTO
            // true: hOCR kèm khung từng ký tự (ocrx_cinfo), dùng cho Sửa ký tự (lib/loi/sua_ky_tu.dart)
            val kyTu = call.argument<Boolean>("kyTu") ?: false
            luong.execute {
                try {
                    val batDau = SystemClock.elapsedRealtime()
                    val api = nap(thuMuc, ngonNgu)
                    api.setPageSegMode(psm)
                    api.setVariable("hocr_char_boxes", if (kyTu) "1" else "0")
                    api.setImage(File(anh))
                    val hocr = api.getHOCRText(0)
                    api.clear()
                    Log.i("xlpdf", "nhận dạng ${File(anh).name}: ${SystemClock.elapsedRealtime() - batDau} ms")
                    runOnUiThread { result.success(hocr) }
                } catch (e: Throwable) {
                    runOnUiThread { result.error("nhan_dang", e.message ?: e.toString(), null) }
                }
            }
        }
    }

    // Nạp dữ liệu ngôn ngữ một lần, dùng lại cho các trang sau.
    private fun nap(thuMuc: String, ngonNgu: String): TessBaseAPI {
        // OpenMP nhiều luồng chờ quay vòng, tranh CPU với luồng vẽ giao diện: đo trên máy ảo chậm 9 lần.
        // Phải đặt trước lần chạy Tesseract đầu tiên.
        Os.setenv("OMP_THREAD_LIMIT", "1", true)
        val khoa = "$thuMuc|$ngonNgu"
        tess?.let { if (daNap == khoa) return it }
        tess?.recycle()
        tess = null
        val api = TessBaseAPI()
        if (!api.init(thuMuc, ngonNgu)) {
            api.recycle()
            throw IllegalStateException("Không nạp được dữ liệu nhận dạng '$ngonNgu'")
        }
        tess = api
        daNap = khoa
        return api
    }

    override fun onDestroy() {
        luong.execute {
            tess?.recycle()
            tess = null
        }
        luong.shutdown()
        super.onDestroy()
    }
}
