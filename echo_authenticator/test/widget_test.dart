import 'package:flutter_test/flutter_test.dart';
import 'package:echo_authenticator/main.dart';

void main() {
  testWidgets('EchoAuthenticatorApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const EchoAuthenticatorApp());
    expect(find.byType(EchoAuthenticatorApp), findsOneWidget);
  });
}
