// الويب: لا ذاكرة ملفات — يُشغَّل المقطع من الشبكة مباشرة.
Future<String?> cachedClipPath(String url) async => null;
Future<String?> downloadClip(String url, {void Function(double)? onProgress}) async => null;
bool get clipCacheSupported => false;
Object? fileVideoSource(String path) => null;
