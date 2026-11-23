import Flutter
import UIKit
import Vision
import CoreML
import CoreImage
import workmanager_apple
#if canImport(FoundationModels)
import FoundationModels
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // التحديث في الخلفية: محرك Flutter الخلفي يحتاج كل الإضافات، والمهمة الدورية (iOS يقرر توقيتها)
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in GeneratedPluginRegistrant.register(with: registry) }
    WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "com.favlib.favorites2.check", earliestBeginInSeconds: NSNumber(value: 2 * 60 * 60))
    // التحميل الليلي للمقاطع: مهمة معالجة (أثناء الشحن والاتصال — iOS يقرر التوقيت)
    WorkmanagerPlugin.registerBGProcessingTask(withIdentifier: "com.favlib.favorites2.clips")
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    // بيانات المستخدم تبقى على جهازه: مجلد التطبيق (القاعدة والصور ونموذج الوجوه) خارج نسخ iCloud
    if var dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
      var v = URLResourceValues(); v.isExcludedFromBackup = true
      try? dir.setResourceValues(v)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // جسر التطبيق الأصلي: نموذج Apple اللغوي على الجهاز + تمييز الوجوه (كله على الجهاز)
    if let reg = engineBridge.pluginRegistry.registrar(forPlugin: "FavNative") {
      let ch = FlutterMethodChannel(name: "favorites2/native", binaryMessenger: reg.messenger())
      ch.setMethodCallHandler { call, result in FavNative.shared.handle(call, result) }
    }
  }
}

/// نموذج Apple اللغوي (iOS 26 + Apple Intelligence) لتحويل البحث إلى فلاتر، وتمييز الوجوه:
/// Vision يكتشف الوجه ونقاطه ← محاذاة قالب ArcFace (112×112) ← نموذج Core ML (AuraFace، Apache-2.0) ← بصمة 512 رقمًا مُطبَّعة.
final class FavNative {
  static let shared = FavNative()
  private var faceModel: MLModel?
  private let queue = DispatchQueue(label: "favorites2.face", qos: .userInitiated)
  private let ciContext = CIContext(options: nil)

  static var compiledURL: URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return dir.appendingPathComponent("FaceEmbedding.mlmodelc")
  }

  func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "aiStatus":
      result(aiStatus())
    case "aiParse":
      aiParse(args["text"] as? String ?? "", args["instructions"] as? String ?? "") { result($0) }
    case "faceStatus":
      result(FileManager.default.fileExists(atPath: FavNative.compiledURL.path) ? "ready" : "missing")
    case "faceInstall":
      let path = args["path"] as? String ?? ""
      queue.async { let ok = self.install(path); DispatchQueue.main.async { result(ok) } }
    case "faceEmbed":
      guard let d = args["image"] as? FlutterStandardTypedData else { result(nil); return }
      queue.async { let r = self.embed(d.data); DispatchQueue.main.async { result(r) } }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // ===== نموذج Apple اللغوي =====
  private func aiStatus() -> String {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      switch SystemLanguageModel.default.availability {
      case .available:
        return "available"
      case .unavailable(let reason):
        switch reason {
        case .deviceNotEligible: return "device"
        case .appleIntelligenceNotEnabled: return "disabled"
        case .modelNotReady: return "downloading"
        @unknown default: return "unavailable"
        }
      @unknown default:
        return "unavailable"
      }
    }
    #endif
    return "unsupported"
  }

  private func aiParse(_ text: String, _ instructions: String, _ done: @escaping (String?) -> Void) {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      guard case .available = SystemLanguageModel.default.availability else { done(nil); return }
      Task {
        do {
          let session = LanguageModelSession(instructions: instructions)
          let response = try await session.respond(to: text)
          let content = response.content
          DispatchQueue.main.async { done(content) }
        } catch {
          DispatchQueue.main.async { done(nil) }
        }
      }
      return
    }
    #endif
    done(nil)
  }

  // ===== تمييز الوجوه =====
  private func install(_ path: String) -> Bool {
    let src = URL(fileURLWithPath: path)
    do {
      let compiled = try MLModel.compileModel(at: src)
      let fm = FileManager.default
      let dest = FavNative.compiledURL
      try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
      if fm.fileExists(atPath: dest.path) {
        _ = try fm.replaceItemAt(dest, withItemAt: compiled)
      } else {
        try fm.moveItem(at: compiled, to: dest)
      }
      faceModel = nil
      return model() != nil
    } catch {
      return false
    }
  }

  private func model() -> MLModel? {
    if let m = faceModel { return m }
    guard FileManager.default.fileExists(atPath: FavNative.compiledURL.path) else { return nil }
    let cfg = MLModelConfiguration()
    cfg.computeUnits = .all
    faceModel = try? MLModel(contentsOf: FavNative.compiledURL, configuration: cfg)
    return faceModel
  }

  /// قالب ArcFace (112×112، أصل أعلى اليسار): العين اليسرى، اليمنى، الأنف، زاويتا الفم.
  private static let template: [CGPoint] = [
    CGPoint(x: 38.2946, y: 51.6963), CGPoint(x: 73.5318, y: 51.5014), CGPoint(x: 56.0252, y: 71.7366),
    CGPoint(x: 41.5493, y: 92.3655), CGPoint(x: 70.7299, y: 92.2041),
  ]

  private func embed(_ data: Data) -> [String: Any]? {
    guard let m = model() else { return nil }
    guard var ci = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
    ci = ci.transformed(by: CGAffineTransform(translationX: -ci.extent.origin.x, y: -ci.extent.origin.y))
    let size = ci.extent.size
    let req = VNDetectFaceLandmarksRequest()
    do { try VNImageRequestHandler(ciImage: ci, options: [:]).perform([req]) } catch { return nil }
    guard let faces = req.results, !faces.isEmpty else { return nil }
    guard let face = faces.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }),
          let lm = face.landmarks else { return nil }

    // نقاط Vision بإحداثيات الصورة (الأصل أسفل اليسار، مثل Core Image)
    func pts(_ r: VNFaceLandmarkRegion2D?) -> [CGPoint] { r?.pointsInImage(imageSize: size) ?? [] }
    func mean(_ p: [CGPoint]) -> CGPoint? {
      guard !p.isEmpty else { return nil }
      return CGPoint(x: p.map { $0.x }.reduce(0, +) / CGFloat(p.count), y: p.map { $0.y }.reduce(0, +) / CGFloat(p.count))
    }
    guard let e1 = mean(pts(lm.leftPupil)) ?? mean(pts(lm.leftEye)),
          let e2 = mean(pts(lm.rightPupil)) ?? mean(pts(lm.rightEye)) else { return nil }
    let eyes = [e1, e2].sorted { $0.x < $1.x }
    let nosePts = pts(lm.nose)
    guard let nose = nosePts.min(by: { $0.y < $1.y }) ?? mean(pts(lm.noseCrest)) else { return nil }
    let lips = pts(lm.outerLips)
    guard let ml = lips.min(by: { $0.x < $1.x }), let mr = lips.max(by: { $0.x < $1.x }) else { return nil }
    let src = [eyes[0], eyes[1], nose, ml, mr]
    // القالب بإحداثيات أصلها أسفل اليسار
    let dst = FavNative.template.map { CGPoint(x: $0.x, y: 112 - $0.y) }

    // تحويل تشابه (تكبير + دوران + إزاحة) بالمربعات الصغرى
    let n = CGFloat(src.count)
    let mx = src.map { $0.x }.reduce(0, +) / n, my = src.map { $0.y }.reduce(0, +) / n
    let mu = dst.map { $0.x }.reduce(0, +) / n, mv = dst.map { $0.y }.reduce(0, +) / n
    var num1: CGFloat = 0, num2: CGFloat = 0, den: CGFloat = 0
    for i in 0..<src.count {
      let xc = src[i].x - mx, yc = src[i].y - my, uc = dst[i].x - mu, vc = dst[i].y - mv
      num1 += xc * uc + yc * vc; num2 += xc * vc - yc * uc; den += xc * xc + yc * yc
    }
    guard den > 0 else { return nil }
    let a = num1 / den, b = num2 / den
    let tx = mu - (a * mx - b * my), ty = mv - (b * mx + a * my)
    let aligned = ci.transformed(by: CGAffineTransform(a: a, b: b, c: -b, d: a, tx: tx, ty: ty))
      .cropped(to: CGRect(x: 0, y: 0, width: 112, height: 112))

    guard let inName = m.modelDescription.inputDescriptionsByName.keys.first,
          let inDesc = m.modelDescription.inputDescriptionsByName[inName] else { return nil }
    let provider: MLFeatureProvider
    do {
      if inDesc.type == .image {
        var pb: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, 112, 112, kCVPixelFormatType_32BGRA, attrs, &pb)
        guard let buffer = pb else { return nil }
        ciContext.render(aligned, to: buffer)
        provider = try MLDictionaryFeatureProvider(dictionary: [inName: MLFeatureValue(pixelBuffer: buffer)])
      } else {
        // مصفوفة [1,3,112,112] بقيم 0–255 (التطبيع داخل النموذج)
        var px = [UInt8](repeating: 0, count: 112 * 112 * 4)
        ciContext.render(aligned, toBitmap: &px, rowBytes: 112 * 4, bounds: CGRect(x: 0, y: 0, width: 112, height: 112),
                         format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let arr = try MLMultiArray(shape: [1, 3, 112, 112], dataType: .float32)
        for y in 0..<112 { for x in 0..<112 { for c in 0..<3 {
          arr[c * 112 * 112 + y * 112 + x] = NSNumber(value: Float(px[(y * 112 + x) * 4 + c]))
        } } }
        provider = try MLDictionaryFeatureProvider(dictionary: [inName: MLFeatureValue(multiArray: arr)])
      }
      let out = try m.prediction(from: provider)
      let outName = m.modelDescription.outputDescriptionsByName.keys.first ?? "embedding"
      guard let e = out.featureValue(for: outName)?.multiArrayValue, e.count > 0 else { return nil }
      var v = [Float](repeating: 0, count: e.count)
      for i in 0..<e.count { v[i] = e[i].floatValue }
      let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
      guard norm > 0 else { return nil }
      v = v.map { $0 / norm }
      let bytes = v.withUnsafeBufferPointer { Data(buffer: $0) }
      return ["v": FlutterStandardTypedData(float32: bytes), "faces": faces.count]
    } catch {
      return nil
    }
  }
}
