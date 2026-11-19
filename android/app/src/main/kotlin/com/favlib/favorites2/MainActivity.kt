package com.favlib.favorites2

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity: مطلوب لقفل البصمة (local_auth).
// قناة «favorites2/privacy»: منع لقطات الشاشة وإخفاء المحتوى في قائمة التطبيقات الأخيرة (FLAG_SECURE) حسب إعداد المستخدم.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "favorites2/privacy").setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecure" -> {
                    val on = call.argument<Boolean>("on") ?: true
                    if (on) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE) else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
