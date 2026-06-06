import 'package:card_manager/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('main menu smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const CardManagerApp());

    expect(find.text('Gestion Carte Etudiant'), findsOneWidget);
    expect(find.text('Classer'), findsOneWidget);
    expect(find.text('Nettoyer les doublons'), findsOneWidget);
    expect(find.text('Dupliquer une carte'), findsOneWidget);
  });
}
