import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/models/play_order.dart';

void main() {
  for (final count in [0, 1, 2, 51, 200]) {
    test(
      '$count-track shuffle covers one cycle without repeats and retraces history',
      () {
        final queue = List.generate(count, (i) => '$i');
        final order = PlayOrder(random: Random(7));
        String? current = queue.firstOrNull;
        order.reset(queue, current);
        if (count == 0) {
          expect(order.next(queue, current), isNull);
          return;
        }
        final played = [current!];
        for (var i = 1; i < count; i++) {
          current = order.next(queue, current);
          played.add(current!);
        }
        expect(played.toSet().length, count);
        expect(played.toSet(), queue.toSet());
        if (count > 1) {
          final last = current;
          final previous = order.next(queue, current, previous: true);
          expect(previous, played[count - 2]);
          expect(order.next(queue, previous), last);
          expect(order.next(queue, last), isNot(last));
        } else {
          expect(order.next(queue, current), '0');
        }
      },
    );
  }
  test('51-track shuffle covers every member in every subsequent cycle', () {
    final ids = List.generate(51, (i) => '$i');
    final order = PlayOrder(random: Random(14))..reset(ids, '0');
    String current = '0';
    for (var i = 1; i < 51; i++) {
      current = order.next(ids, current)!;
    }
    for (var cycle = 0; cycle < 5; cycle++) {
      final previous = current;
      final seen = <String>{};
      for (var i = 0; i < 51; i++) {
        current = order.next(ids, current)!;
        if (i == 0) expect(current, isNot(previous));
        expect(seen.add(current), isTrue);
      }
      expect(seen, ids.toSet());
    }
  });
  test('roundtrip preserves the unfinished cycle and upcoming priority', () {
    final queue = List.generate(51, (i) => '$i');
    final order = PlayOrder(random: Random(8))..reset(queue, '0');
    var current = '0';
    final seen = {current};
    for (var i = 0; i < 20; i++) {
      current = order.next(queue, current)!;
      seen.add(current);
    }
    final restored = PlayOrder(random: Random(9))
      ..restore(order.toJson(), queue, current);
    for (var i = 0; i < 30; i++) {
      current = restored.next(queue, current)!;
      expect(seen.add(current), isTrue);
    }
    expect(seen.length, 51);
    restored.prioritize('new');
    queue.add('new');
    expect(restored.next(queue, current), 'new');
  });
  test(
    'queue edits and aliases do not resurrect removed tracks or repeat canonical aliases',
    () {
      final order = PlayOrder(random: Random(3));
      final queue = ['old', 'b', 'c', 'd'];
      order.reset(queue, 'old');
      order.alias('old', 'real');
      queue[0] = 'real';
      queue.remove('b');
      queue.add('e');
      order.sync(queue);
      final seen = {'real'};
      var current = 'real';
      for (var i = 0; i < 3; i++) {
        current = order.next(queue, current)!;
        expect(seen.add(current), isTrue);
      }
      expect(seen, {'real', 'c', 'd', 'e'});
    },
  );
}
