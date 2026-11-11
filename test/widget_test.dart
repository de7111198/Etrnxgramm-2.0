import 'package:flutter_test/flutter_test.dart';
import 'package:etrnxgram/main.dart';

void main() {
  testWidgets('Etrnxgram opens and switches between main sections',
      (tester) async {
    await tester.pumpWidget(const EtrnxgramApp());

    expect(find.text('Etrnxgram'), findsOneWidget);
    expect(find.text('Чатов пока нет'), findsOneWidget);

    await tester.tap(find.text('Подарки'));
    await tester.pumpAndSettle();
    expect(find.text('Коллекция подарков пока не подключена к серверу.'),
        findsOneWidget);

    await tester.tap(find.text('Профиль'));
    await tester.pumpAndSettle();
    expect(find.text('Etrnx User'), findsOneWidget);
    expect(find.text('Редактировать профиль'), findsOneWidget);
  });
}
