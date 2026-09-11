import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_auth_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/login_screen.dart';
import 'package:qr_code_based_pediatric_vaccination/theme/app_theme.dart';

void main() {
  testWidgets('login reports invalid credentials clearly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: LoginScreen(authRepository: MockAuthRepository()),
      ),
    );
    expect(find.text('Welcome back!'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'invalid');
    await tester.enterText(find.byType(TextField).last, 'invalid');
    final signIn = find.widgetWithText(FilledButton, 'Sign in');
    await tester.ensureVisible(signIn);
    await tester.tap(signIn);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'We could not verify those login details. '
        'Please check your Login ID and enter your password again.',
      ),
      findsOneWidget,
    );
    var passwordField = tester.widget<TextField>(find.byType(TextField).last);
    expect(passwordField.controller?.text, isEmpty);
    expect(passwordField.focusNode?.hasFocus, isTrue);

    await tester.enterText(find.byType(TextField).last, 'replacement');
    passwordField = tester.widget<TextField>(find.byType(TextField).last);
    expect(passwordField.controller?.text, 'replacement');
    expect(tester.takeException(), isNull);
  });
}
