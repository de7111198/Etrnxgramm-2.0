import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:etrnxgram/main.dart';

void main() {
  testWidgets('main sections render and navigation switches to gifts',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MainScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Etrnxgram'), findsOneWidget);
    expect(find.text('Чатов пока нет'), findsOneWidget);

    await tester.tap(find.text('Подарки'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Подключи сервер'), findsOneWidget);

    await tester.tap(find.text('Контакты'));
    await tester.pumpAndSettle();
    expect(find.text('Пока нет пользователей'), findsOneWidget);
  });

  testWidgets('shows backend setup instead of fake login when unconfigured',
      (tester) async {
    await tester.pumpWidget(const EtrnxgramApp());

    expect(find.text('Сервер ещё не настроен'), findsOneWidget);
    expect(find.text('Вход в Etrnxgram'), findsNothing);
  });
}
