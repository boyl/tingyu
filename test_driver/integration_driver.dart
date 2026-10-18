import 'dart:io';
import 'dart:convert';
import 'package:integration_test/integration_test_driver_extended.dart';

/// Native screenshots are processed after the test, so use a synchronous
/// localhost bridge to trigger the Android screenshot while audio is playing.
Future<void> main() async {
  final adb = File(
    '../.toolchains/android-sdk/platform-tools/adb',
  ).absolute.path;
  final device = Platform.environment['TINGYU_ACCEPTANCE_DEVICE'];
  HttpServer? bridge;
  const devicePort = '47935';
  Future<ProcessResult> adbRun(List<String> args) =>
      Process.run(adb, ['-s', device!, ...args]);
  if (device == 'emulator-5558') {
    final identity = await adbRun(['emu', 'avd', 'name']);
    if (!identity.stdout.toString().startsWith('tingyu-regression')) {
      throw StateError(
        'System screenshot probe requires isolated tingyu-regression',
      );
    }
    bridge = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final reverse = await adbRun([
      'reverse',
      'tcp:$devicePort',
      'tcp:${bridge.port}',
    ]);
    if (reverse.exitCode != 0) {
      throw StateError('Screenshot bridge unavailable');
    }
    bridge.listen((request) async {
      if (request.method != 'POST' ||
          request.uri.path != '/system-screenshot') {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        final result = await adbRun([
          'shell',
          'input',
          'keyevent',
          'KEYCODE_SYSRQ',
        ]);
        request.response.statusCode = result.exitCode == 0
            ? HttpStatus.ok
            : HttpStatus.internalServerError;
      }
      await request.response.close();
    });
  }
  await integrationDriver(
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      if (data?['playingIndicator'] != null) {
        await File(
          'artifacts/acceptance/playing-indicator.json',
        ).writeAsString(jsonEncode(data!['playingIndicator']));
      }
      if (bridge != null) {
        await adbRun(['reverse', '--remove', 'tcp:$devicePort']);
        await bridge!.close(force: true);
      }
    },
    onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? args]) async {
          final directory = Directory('artifacts/acceptance/screenshots');
          await directory.create(recursive: true);
          await File('${directory.path}/$name.png').writeAsBytes(bytes);
          return bytes.isNotEmpty;
        },
  );
}
