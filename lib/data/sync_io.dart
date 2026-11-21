import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../domain/performer.dart';
import 'backup.dart';
import 'library_repo.dart';

/// المزامنة الجوال ← الشاشة على الشبكة المحلية:
///  - الشاشة تشغّل خادمًا صغيرًا (منفذ 8787…8791) وتعرض العنوان ورمزًا من 6 أرقام يتغير كل جلسة.
///  - الجوال يرسل مكتبته بصيغة النسخة الاحتياطية نفسها؛ الشاشة تطبّق قواعد الاستيراد (لا حذف، الأحدث يفوز، بوابة +18).
///  - 5 محاولات رمز خاطئة ⇒ يتوقف الخادم. حد أقصى للحجم. لا مفاتيح API ولا رمز القفل.
const bool syncSupported = true;
const _maxBytes = 300 * 1024 * 1024;   // حد واقعي لذاكرة التلفاز

class SyncServer {
  HttpServer? _srv; String code = '', address = ''; int _fails = 0;
  bool get running => _srv != null;

  Future<void> start({required LibraryRepo repo, required Future<List<Performer>> Function() current, required void Function(String) onEvent}) async {
    await stop();
    final r = Random.secure(); code = List.generate(6, (_) => r.nextInt(10)).join(); _fails = 0;
    for (var port = 8787; port <= 8791 && _srv == null; port++) { try { _srv = await HttpServer.bind(InternetAddress.anyIPv4, port); } catch (_) {} }
    if (_srv == null) throw StateError('تعذّر فتح منفذ للمزامنة');
    address = '${await _localIp() ?? 'العنوان غير معروف'}:${_srv!.port}';
    _srv!.listen((req) async {
      final res = req.response;
      if (_fails >= 5) { res.statusCode = 429; await res.close(); return; }
      try {
        if (req.method == 'GET' && req.uri.path == '/v1/ping') { res.write(jsonEncode({'app': 'favorites2', 'ok': true})); }
        else if (req.method == 'POST' && req.uri.path == '/v1/push') {
          if (req.headers.value('x-code') != code) {
            _fails++; res.statusCode = 403; res.write('{"err":"code"}');
            if (_fails >= 5) { unawaited(_srv?.close()); }   // لا اتصالات جديدة
            onEvent('رمز خاطئ ($_fails/5)'); if (_fails >= 5) { onEvent('أُوقفت المزامنة بعد 5 محاولات خاطئة'); }
          } else if (req.contentLength > _maxBytes) { res.statusCode = 413; }
          else {
            onEvent('جارٍ الاستقبال…');
            final bytes = BytesBuilder(copy: false); var n = 0;
            await for (final chunk in req) { n += chunk.length; if (n > _maxBytes) throw StateError('الحجم أكبر من المسموح'); bytes.add(chunk); }
            final body = utf8.decode(bytes.takeBytes());
            final f = Backup.parse(body);
            final out = await Backup.apply(repo, f, await current());
            res.write(jsonEncode({'added': out.added, 'updated': out.updated, 'skippedMinors': f.minorsSkipped}));
            onEvent('وصلت المزامنة: أُضيفت ${out.added} · حُدّثت ${out.updated}');
          }
        } else { res.statusCode = 404; }
      } catch (e) { res.statusCode = 400; res.write(jsonEncode({'err': '$e'})); onEvent('فشل الاستقبال: $e'); }
      await res.close();
      if (_fails >= 5) await stop();   // يُرد أولًا ثم يُغلق
    });
  }

  Future<void> stop() async { await _srv?.close(force: true); _srv = null; }

  static Future<String?> _localIp() async {
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final a in i.addresses) { if (!a.isLoopback && RegExp(r'^(192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.)').hasMatch(a.address)) return a.address; }
    }
    return null;
  }
}

/// عنوان شبكة محلية خاصة (RFC1918) مع منفذ اختياري.
bool isLanHost(String h) => RegExp(r'^(192\.168\.\d{1,3}|10\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3})\.\d{1,3}(:\d{2,5})?$').hasMatch(h.trim());

/// الجوال: يرسل المكتبة للشاشة. يقبل عناوين الشبكة المحلية فقط.
Future<String> pushToTv({required String host, required String code, required String json}) async {
  final h = host.trim();
  if (!isLanHost(h)) throw ArgumentError('أدخل عنوان الشاشة كما يظهر عليها (مثل 192.168.1.20:8787)');
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await c.postUrl(Uri.parse('http://${h.contains(':') ? h : '$h:8787'}/v1/push'));
    req.headers.set('x-code', code.trim()); req.headers.contentType = ContentType.json;
    req.add(utf8.encode(json));
    final res = await req.close();
    final body = await utf8.decodeStream(res);
    if (res.statusCode == 403) throw StateError('الرمز غير صحيح');
    if (res.statusCode != 200) throw StateError('الشاشة ردّت بخطأ ${res.statusCode}');
    final j = jsonDecode(body) as Map;
    return 'وصلت للشاشة: أُضيفت ${j['added']} · حُدّثت ${j['updated']}';
  } finally { c.close(force: true); }
}
