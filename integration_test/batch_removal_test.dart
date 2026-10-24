import 'package:integration_test/integration_test.dart';
import '../test/batch_removal_ui_test.dart' as scenarios;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  scenarios.batchRemovalTests(includeMac: false, nativeSize: true);
}
