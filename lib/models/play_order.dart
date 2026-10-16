import 'dart:math';

/// Shuffle traverses every queue member before starting another cycle.
/// History is separate from the visible queue so previous/next can retrace it.
class PlayOrder {
  PlayOrder({Random? random}) : _random = random ?? Random();
  final Random _random;
  final List<String> _remaining = [], _trail = [], _priority = [];
  int _cursor = -1;
  final Set<String> _members = {};

  Map<String, dynamic> toJson() => {
    'remaining': List.of(_remaining),
    'trail': List.of(_trail),
    'priority': List.of(_priority),
    'cursor': _cursor,
  };
  void restore(Map<String, dynamic> json, List<String> queue, String? current) {
    _remaining
      ..clear()
      ..addAll(List<String>.from(json['remaining'] ?? []));
    _trail
      ..clear()
      ..addAll(List<String>.from(json['trail'] ?? []));
    _priority
      ..clear()
      ..addAll(List<String>.from(json['priority'] ?? []));
    _cursor = (json['cursor'] as int? ?? -1);
    if (_cursor < -1 || _cursor >= _trail.length) _cursor = -1;
    _members
      ..clear()
      ..addAll(queue);
    sync(queue);
    if (_cursor < 0 || _trail[_cursor] != current) reset(queue, current);
  }

  void reset(List<String> queue, String? current) {
    _members
      ..clear()
      ..addAll(queue);
    _remaining
      ..clear()
      ..addAll(
        queue.where((id) => id != current).toSet().toList()..shuffle(_random),
      );
    _trail
      ..clear()
      ..addAll(current == null ? [] : [current]);
    _cursor = _trail.length - 1;
    _priority.clear();
  }

  void sync(List<String> queue) {
    final allowed = queue.toSet();
    final added = allowed.difference(_members);
    _members
      ..clear()
      ..addAll(allowed);
    _remaining.removeWhere((id) => !allowed.contains(id));
    _priority.removeWhere((id) => !allowed.contains(id));
    final before = _trail.take(_cursor + 1).where(allowed.contains).length;
    _trail.removeWhere((id) => !allowed.contains(id));
    _cursor = before - 1;
    // Newly added tracks are eligible in the current cycle exactly once.
    for (final id in added) {
      if (!_remaining.contains(id)) {
        _remaining.insert(_random.nextInt(_remaining.length + 1), id);
      }
    }
  }

  void prioritize(String id) {
    _priority.remove(id);
    _priority.insert(0, id);
  }

  void alias(String oldId, String newId) {
    if (_members.remove(oldId)) _members.add(newId);
    for (final list in [_remaining, _trail, _priority]) {
      for (var i = 0; i < list.length; i++) {
        if (list[i] == oldId) list[i] = newId;
      }
    }
    final seen = <String>{};
    _remaining.removeWhere((id) => !seen.add(id));
  }

  String? next(List<String> queue, String? current, {bool previous = false}) {
    sync(queue);
    if (queue.isEmpty) return null;
    if (previous) {
      if (_cursor > 0) return _trail[--_cursor];
      return current ?? queue.first;
    }
    if (_priority.isNotEmpty) {
      final id = _priority.removeAt(0);
      _remaining.remove(id);
      _record(id);
      return id;
    }
    if (_cursor + 1 < _trail.length) return _trail[++_cursor];
    if (_remaining.isEmpty) {
      _remaining.addAll(queue.toSet().toList()..shuffle(_random));
      if (_remaining.length > 1 && _remaining.first == current) {
        final first = _remaining[0];
        _remaining[0] = _remaining[1];
        _remaining[1] = first;
      }
      if (_remaining.isEmpty) _remaining.add(queue.first);
    }
    final id = _remaining.removeAt(0);
    _record(id);
    return id;
  }

  void arrive(String id) {
    _remaining.remove(id);
    if (_cursor < 0 || _trail[_cursor] != id) _record(id);
  }

  void failed(String id, String? actual) {
    if (_cursor == _trail.length - 1 &&
        _cursor >= 0 &&
        _trail[_cursor] == id &&
        id != actual) {
      _trail.removeLast();
    }
    _cursor = actual == null ? -1 : _trail.lastIndexOf(actual);
  }

  void _record(String id) {
    if (_cursor + 1 < _trail.length) {
      _trail.removeRange(_cursor + 1, _trail.length);
    }
    _trail.add(id);
    if (_trail.length > 2048) _trail.removeRange(0, _trail.length - 2048);
    _cursor = _trail.length - 1;
  }
}
