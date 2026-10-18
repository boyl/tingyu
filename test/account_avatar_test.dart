import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';

void main() {
  testWidgets('anonymous and malformed avatars use the local fallback', (
    tester,
  ) async {
    for (final profile in <Map<String, dynamic>?>[
      null,
      {'face': ''},
      {'face': 'file:///private/avatar.png'},
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: tingyuTheme('sunrise'),
          home: Scaffold(body: AccountAvatar(profile: profile)),
        ),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
      expect(find.byType(ClipOval), findsOneWidget);
    }
  });
  testWidgets('Bilibili avatar uses the authenticated profile image', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: tingyuTheme('sunrise'),
        home: const Scaffold(
          body: AccountAvatar(
            profile: {'face': '//i0.hdslb.com/bfs/face/avatar.jpg'},
          ),
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as NetworkImage).url,
      'https://i0.hdslb.com/bfs/face/avatar.jpg',
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
