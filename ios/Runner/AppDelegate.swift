import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // التحديث في الخلفية: محرك Flutter الخلفي يحتاج كل الإضافات، والمهمة الدورية (iOS يقرر توقيتها)
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in GeneratedPluginRegistrant.register(with: registry) }
    WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "com.favlib.favorites2.check", earliestBeginInSeconds: NSNumber(value: 6 * 60 * 60))
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    // بيانات المستخدم تبقى على جهازه: مجلد التطبيق (القاعدة والصور) خارج نسخ iCloud
    if var dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
      var v = URLResourceValues(); v.isExcludedFromBackup = true
      try? dir.setResourceValues(v)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
