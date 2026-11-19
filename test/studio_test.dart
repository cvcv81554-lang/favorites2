// الاستديو: اكتشاف صور المشاهد بلا شبكة، عدم التكرار، بوابة +18، الحذف مع بقاء المعجَبة، ومقاس StashDB.
import 'package:favorites2/data/studio_repo.dart';
import 'package:favorites2/domain/performer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  test('صور المشاهد تُضاف مرة واحدة، والقاصر لا تُعالج', () async {
    final r = StudioRepo.withDb(await databaseFactoryMemory.openDatabase('s1'));
    final lib = [
      Performer({'id': 'a', 'name': 'A', 'birth': '1990-01-01', 'works': [{'t': 'W1', 'p': 'https://img.test/1.jpg'}, {'t': 'W2', 'p': 'https://img.test/1.jpg'}, {'t': 'W3', 'p': 'http://insecure/x.jpg'}]}),
      Performer({'id': 'm', 'name': 'M', 'birth': '2015-01-01', 'works': [{'t': 'X', 'p': 'https://img.test/minor.jpg'}]}),
    ];
    expect(await r.discover(lib, network: false), 1);
    expect(await r.discover(lib, network: false), 0); // لا تكرار
    final all = await r.all();
    expect(all.single.pid, 'a'); expect(all.single.kind, 'still');
  });

  test('حذف ممثلة يحذف صورها إلا المعجَبة', () async {
    final r = StudioRepo.withDb(await databaseFactoryMemory.openDatabase('s2'));
    await r.put([StudioImg(id: '1', pid: 'a', url: 'https://x/1', src: 'stash', kind: 'portrait', found: 1), StudioImg(id: '2', pid: 'a', url: 'https://x/2', src: 'stash', kind: 'portrait', found: 1, like: true), StudioImg(id: '3', pid: 'b', url: 'https://x/3', src: 'stash', kind: 'portrait', found: 1)]);
    await r.removePerformer('a');
    expect((await r.all()).map((x) => x.id).toSet(), {'2', '3'});
  });

  test('مقاس StashDB الرسمي للشبكات فقط', () {
    expect(StudioImg.sized('https://stashdb.org/images/ab/cd', 600), 'https://stashdb.org/images/ab/cd?size=600');
    expect(StudioImg.sized('https://cdn.example.com/images/a', 600), 'https://cdn.example.com/images/a');
    expect(StudioImg.sized('https://stashdb.org/images/a?size=300', 600), 'https://stashdb.org/images/a?size=300');
  });
}
