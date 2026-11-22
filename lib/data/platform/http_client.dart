// عميل HTTP حسب المنصة: على iPhone/Mac نظام الشبكات الأصلي من Apple (URLSession) — نفس ما كان يستخدمه التطبيق السابق،
// ويدعم HTTP/3 تلقائيًا (ThePornDB على شبكة تقطع اتصالات TCP إليه يصل عبره كما في التطبيق السابق). غير ذلك: العميل المعتاد.
export 'http_client_io.dart' if (dart.library.js_interop) 'http_client_web.dart';
