import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/models/app_user.dart';
import 'package:qr_code_based_pediatric_vaccination/services/session_context.dart';
import 'package:qr_code_based_pediatric_vaccination/theme/app_theme.dart';
import 'package:qr_code_based_pediatric_vaccination/utils/user_facing_error.dart';

void main() {
  tearDown(SessionContext.clear);

  test('record attribution uses the active user and clears on logout', () {
    expect(() => SessionContext.userId, throwsStateError);
    SessionContext.setUser(
      const AppUser(
        id: 'worker-test',
        fullName: 'Test worker',
        role: UserRole.healthWorker,
        active: true,
      ),
    );
    expect(SessionContext.userId, 'worker-test');
    SessionContext.clear();
    expect(() => SessionContext.userId, throwsStateError);
  });

  test('technical errors are not exposed to users', () {
    expect(
      UserFacingError.message(
        StateError('The adjustment exceeds the available stock.'),
      ),
      'The quantity is greater than the available usable stock.',
    );
    expect(
      UserFacingError.message(Exception('private database details')),
      'Something went wrong. Please try again.',
    );
  });

  testWidgets('dialog actions fit a narrow phone with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: AlertDialog(
            title: const Text('Review visit'),
            content: const Text('Check these details before saving.'),
            actions: [
              TextButton(onPressed: () {}, child: const Text('Back to edit')),
              FilledButton(
                onPressed: () {},
                child: const Text('Confirm and save'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
