import 'package:flutter_test/flutter_test.dart';
import 'support/fakes.dart';

void main() {
  test(
    'new installs and missing theme use Bilibili pink; saved choices survive reopen',
    () async {
      var fixture = await TestLibrary.create();
      final directory = fixture.directory;
      try {
        expect(fixture.controller.theme, 'bili');
        await fixture.controller.setTheme('night');
        await fixture.close(deleteData: false);
        fixture = await TestLibrary.create(dataDirectory: directory);
        expect(fixture.controller.theme, 'night');
        await fixture.controller.setTheme('bili');
        await fixture.close(deleteData: false);
        fixture = await TestLibrary.create(dataDirectory: directory);
        expect(fixture.controller.theme, 'bili');
        await fixture.controller.setTheme('unknown');
        expect(fixture.controller.theme, 'bili');
        final stored = (await fixture.db.readState('library'))!
          ..remove('theme');
        await fixture.db.writeState('library', stored);
        await fixture.close(deleteData: false);
        fixture = await TestLibrary.create(dataDirectory: directory);
        expect(fixture.controller.theme, 'bili');
      } finally {
        await fixture.close();
      }
    },
  );
}
