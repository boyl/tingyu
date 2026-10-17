import 'dart:io';
import 'dart:convert';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data?['playingIndicator'] == null) return;
    await File(
      'artifacts/acceptance/playing-indicator.json',
    ).writeAsString(jsonEncode(data!['playingIndicator']));
  },
  onScreenshot:
      (String name, List<int> bytes, [Map<String, Object?>? args]) async {
        final directory = Directory('artifacts/acceptance/screenshots');
        await directory.create(recursive: true);
        await File('${directory.path}/$name.png').writeAsBytes(bytes);
        return bytes.isNotEmpty;
      },
);
