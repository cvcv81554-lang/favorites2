// المزامنة عبر الشبكة المحلية غير متاحة في نسخة الويب.
import '../domain/performer.dart';
import 'library_repo.dart';

const bool syncSupported = false;
class SyncServer {
  String code = '', address = '';
  Future<void> start({required LibraryRepo repo, required Future<List<Performer>> Function() current, required void Function(String) onEvent}) async { throw UnsupportedError('غير متاح على الويب'); }
  Future<void> stop() async {}
  bool get running => false;
}
Future<String> pushToTv({required String host, required String code, required String json}) async => throw UnsupportedError('غير متاح على الويب');
