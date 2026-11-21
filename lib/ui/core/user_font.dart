import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/platform/db_factory.dart';

/// خط يختاره المستخدم (مثل «ثمانية»): رخصته تمنع إعادة توزيعه، لذلك **لا يُضمَّن** في التطبيق ولا في المستودع العام.
/// المستخدم ينزّله من موقعه الرسمي ثم يستورده هنا؛ يُحفظ على جهازه فقط ويُستخدم في كل التطبيق.
const userFontFamily = 'UserFont';

/// يتحقق أن الملف خط فعلًا (OpenType/TrueType).
bool isFontFile(Uint8List b) => b.length > 12 && (
  (b[0] == 0x4F && b[1] == 0x54 && b[2] == 0x54 && b[3] == 0x4F) ||          // OTTO (OpenType CFF)
  (b[0] == 0x00 && b[1] == 0x01 && b[2] == 0x00 && b[3] == 0x00) ||          // TrueType
  (b[0] == 0x74 && b[1] == 0x72 && b[2] == 0x75 && b[3] == 0x65));           // 'true'

Future<bool> _register(List<Uint8List> fonts) async {
  if (fonts.isEmpty) return false;
  final l = FontLoader(userFontFamily);
  for (final f in fonts) { l.addFont(Future.value(ByteData.sublistView(f))); }
  await l.load();
  return true;
}

class UserFontN extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async { if (kIsWeb) return false; try { return await _register(await readUserFonts()); } catch (_) { return false; } }

  /// يستورد ملفات الخط (كل الأوزان معًا: عادي، متوسط، عريض…). يعيد عدد الملفات المقبولة.
  Future<int> import() async {
    final picked = await FilePicker.pickFiles(type: FileType.any, dialogTitle: 'اختر ملفات الخط (OTF/TTF)');
    var n = 0; final ok = <Uint8List>[];
    for (final f in picked) {
      if (!RegExp(r'\.(otf|ttf)$', caseSensitive: false).hasMatch(f.name)) continue;
      final b = await f.readAsBytes();
      if (!isFontFile(b) || b.length > 20 * 1024 * 1024) continue;
      await saveUserFont(f.name, b); ok.add(b); n++;
    }
    if (n > 0) { await _register(await readUserFonts()); state = const AsyncData(true); }
    return n;
  }

  /// الرجوع للخط الافتراضي (يحذف ملفات الخط المستوردة من الجهاز فقط).
  Future<void> reset() async { await clearUserFonts(); state = const AsyncData(false); }
}
final userFontProvider = AsyncNotifierProvider<UserFontN, bool>(UserFontN.new);
