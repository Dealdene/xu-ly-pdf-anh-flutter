// Phần riêng iOS của Xử lý PDF ảnh, cùng tên kênh, cùng tham số với MainActivity.kt của bản Android:
// - xlpdf/nhan_dang, hàm "hocr": nhận dạng chữ một tệp ảnh bằng Tesseract, trả hOCR (kèm khung từng ký tự khi kyTu).
// - xlpdf/rung, hàm "rung": rung báo. iOS không cho chọn thời gian, độ mạnh như Android: rung ngắn (≤ 40 ms) dùng
//   chạm nhẹ, rung dài hơn dùng chạm mạnh; độ mạnh (bienDo 1–255) đổi thành cường độ chạm.
import Flutter
import UIKit
import libtesseract

public class XlpdfIosPlugin: NSObject, FlutterPlugin {
  private let hang = DispatchQueue(label: "xlpdf.nhan_dang") // Tesseract không chạy song song trên một đối tượng
  private var tess: OpaquePointer?
  private var daNap = ""

  public static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = XlpdfIosPlugin()
    let nhanDang = FlutterMethodChannel(name: "xlpdf/nhan_dang", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(plugin, channel: nhanDang)
    let rung = FlutterMethodChannel(name: "xlpdf/rung", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(plugin, channel: rung)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let ts = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "rung":
      rung(ms: ts["ms"] as? Int ?? 40, bienDo: ts["bienDo"] as? Int)
      result(nil)
    case "hocr":
      guard let anh = ts["anh"] as? String, let thuMuc = ts["thuMuc"] as? String else {
        result(FlutterError(code: "nhan_dang", message: "Thiếu đường dẫn ảnh hoặc thư mục dữ liệu", details: nil))
        return
      }
      let ngonNgu = ts["ngonNgu"] as? String ?? "vie"
      let psm = ts["psm"] as? Int ?? 3 // 3: tự chia khối; 1: tự chia khối và đoán chiều chữ (cần osd)
      let kyTu = ts["kyTu"] as? Bool ?? false
      hang.async {
        do {
          let hocr = try self.hocr(anh: anh, thuMuc: thuMuc, ngonNgu: ngonNgu, psm: psm, kyTu: kyTu)
          DispatchQueue.main.async { result(hocr) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "nhan_dang", message: "\(error)", details: nil))
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func rung(ms: Int, bienDo: Int?) {
    DispatchQueue.main.async {
      let kieu: UIImpactFeedbackGenerator.FeedbackStyle = ms <= 40 ? .light : (ms <= 70 ? .medium : .heavy)
      let may = UIImpactFeedbackGenerator(style: kieu)
      may.prepare()
      if let b = bienDo, #available(iOS 13.0, *) {
        may.impactOccurred(intensity: CGFloat(max(1, min(255, b))) / 255)
      } else {
        may.impactOccurred()
      }
    }
  }

  struct LoiNhanDang: Error, CustomStringConvertible {
    let description: String
  }

  // Nạp dữ liệu ngôn ngữ một lần, dùng lại cho các trang sau. thuMuc là thư mục chứa tessdata/ (như bản Android).
  private func nap(thuMuc: String, ngonNgu: String) throws -> OpaquePointer {
    let khoa = "\(thuMuc)|\(ngonNgu)"
    if let t = tess, daNap == khoa { return t }
    if let t = tess {
      TessBaseAPIDelete(t)
      tess = nil
    }
    setenv("OMP_THREAD_LIMIT", "1", 1)
    guard let api = TessBaseAPICreate() else { throw LoiNhanDang(description: "Không tạo được Tesseract") }
    // Như TessBaseAPI.init(thuMuc, ngonNgu) của bản Android (chế độ máy mặc định). Tesseract 4 tự thêm "tessdata/"
    // vào đường dẫn; thử cả thư mục tessdata cho chắc
    var ok = TessBaseAPIInit3(api, thuMuc, ngonNgu) == 0
    if !ok { ok = TessBaseAPIInit3(api, thuMuc + "/tessdata", ngonNgu) == 0 }
    if !ok {
      TessBaseAPIDelete(api)
      throw LoiNhanDang(description: "Không nạp được dữ liệu nhận dạng '\(ngonNgu)'")
    }
    tess = api
    daNap = khoa
    return api
  }

  private func hocr(anh: String, thuMuc: String, ngonNgu: String, psm: Int, kyTu: Bool) throws -> String {
    let batDau = Date()
    let api = try nap(thuMuc: thuMuc, ngonNgu: ngonNgu)
    TessBaseAPISetPageSegMode(api, TessPageSegMode(rawValue: UInt32(psm)))
    TessBaseAPISetVariable(api, "hocr_char_boxes", kyTu ? "1" : "0")
    var pix: UnsafeMutablePointer<PIX>? = pixRead(anh)
    if pix == nil { throw LoiNhanDang(description: "Không đọc được ảnh \(anh)") }
    defer { pixDestroy(&pix) }
    TessBaseAPISetImage2(api, pix)
    guard let chu = TessBaseAPIGetHOCRText(api, 0) else {
      TessBaseAPIClear(api)
      throw LoiNhanDang(description: "Tesseract không trả kết quả")
    }
    let kq = String(cString: chu)
    TessDeleteText(chu)
    TessBaseAPIClear(api)
    NSLog("xlpdf: nhận dạng %@: %.0f ms", (anh as NSString).lastPathComponent, Date().timeIntervalSince(batDau) * 1000)
    return kq
  }
}
