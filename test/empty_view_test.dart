import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';

void main() {
  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets(
      'short empty viewport keeps its action reachable scale=$scale',
      (tester) async {
        var activated = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: tingyuTheme('bili'),
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: SizedBox(
                  width: 320,
                  height: 156,
                  child: EmptyView(
                    '还没有歌曲',
                    '搜索喜欢的音乐，或登录账号导入收藏夹。',
                    child: TextButton(
                      onPressed: () => activated = true,
                      child: const Text('登录账号'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('登录账号'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('登录账号'));
        expect(activated, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
