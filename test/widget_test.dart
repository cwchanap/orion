import 'package:flutter_test/flutter_test.dart';
import 'package:orion/main.dart';

void main() {
  testWidgets('boots into the Orion tower defense shell', (tester) async {
    await tester.pumpWidget(const OrionApp());
    await tester.pump();

    expect(find.text('Orion'), findsOneWidget);
    expect(find.text('Gold 120'), findsOneWidget);
    expect(find.text('Base 20'), findsOneWidget);
    expect(find.text('Wave 1/5'), findsOneWidget);
    expect(find.text('Start Wave'), findsOneWidget);
  });
}
