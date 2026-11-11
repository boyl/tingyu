import 'package:flutter_test/flutter_test.dart';
import 'support/fakes.dart';
import 'discovery_policy_test.dart' show t;

void main() {
  test(
    'natural completion and timer stop never become an early skip',
    () async {
      final f = await TestLibrary.create();
      addTearDown(f.close);
      for (final finish in ['completed', 'timer']) {
        await f.controller.play(firstTrack);
        f.controller.mode = 'once';
        f.controller.discoveryListening.seconds = 2;
        if (finish == 'completed') {
          f.playback.onCompleted!();
          await Future<void>.delayed(Duration.zero);
        } else {
          await f.controller.sleepTimer.onExpire!(false);
        }
        await f.controller.play(secondTrack);
        expect(
          f.controller.discoveryPreferences.behavior[firstTrack.bvid]?['skips'],
          isNull,
        );
      }
    },
  );

  test(
    'exposure and explicit feedback survive restart, undo and clear preserve library',
    () async {
      var f = await TestLibrary.create();
      final directory = f.directory;
      await f.controller.setLiked(t(1), true);
      f.controller.recordDiscoveryExposure(t(2));
      await f.controller.setDiscoveryBlocked('BV3', true);
      await f.controller.save();
      await f.close(deleteData: false);
      f = await TestLibrary.create(dataDirectory: directory);
      try {
        expect(
          f.controller.discoveryPreferences.exposures.keys,
          contains('BV2'),
        );
        expect(f.controller.discoveryPreferences.blocked, {'BV3'});
        await f.controller.setDiscoveryBlocked('BV3', false);
        expect(f.controller.discoveryPreferences.blocked, isEmpty);
        await f.controller.clearDiscoveryPreferences();
        expect(f.controller.discoveryPreferences.exposures, isEmpty);
        expect(f.controller.likes, isNotEmpty);
        expect((await f.db.readState('discovery'))!['exposures'], isEmpty);
      } finally {
        await f.close();
      }
    },
  );
  test(
    'failed save never applies explicit block or clear; retry remains possible',
    () async {
      final f = await TestLibrary.create();
      addTearDown(f.close);
      await f.controller.setDiscoveryBlocked('BV1', true);
      await f.db.customStatement(
        "CREATE TRIGGER reject_discovery BEFORE INSERT ON app_state WHEN NEW.key = 'discovery' BEGIN SELECT RAISE(ABORT, 'fixture'); END",
      );
      await expectLater(
        f.controller.setDiscoveryBlocked('BV2', true),
        throwsException,
      );
      await expectLater(
        f.controller.clearDiscoveryPreferences(),
        throwsException,
      );
      expect(f.controller.discoveryPreferences.blocked, {'BV1'});
      expect(f.controller.discoverySaveError, isNotEmpty);
      await f.db.customStatement('DROP TRIGGER reject_discovery');
      await f.controller.setDiscoveryBlocked('BV2', true);
      expect(f.controller.discoveryPreferences.blocked, {'BV1', 'BV2'});
      expect(f.controller.discoverySaveError, isEmpty);
    },
  );
  test(
    'concurrent exposure, block and undo persist in submission order',
    () async {
      final f = await TestLibrary.create();
      addTearDown(f.close);
      final block = f.controller.setDiscoveryBlocked('BV1', true);
      f.controller.recordDiscoveryExposure(t(2));
      final undo = f.controller.setDiscoveryBlocked('BV1', false);
      await Future.wait([block, undo]);
      final state = (await f.db.readState('discovery'))!;
      expect(state['blocked'], isEmpty);
      expect((state['exposures'] as Map).containsKey('BV2'), true);
    },
  );
}
