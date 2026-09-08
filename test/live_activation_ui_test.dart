import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_code_based_pediatric_vaccination/models/app_user.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_invitation.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/auth_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/guardian_activation_screen.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/login_screen.dart';
import 'package:qr_code_based_pediatric_vaccination/widgets/guardian_activation_code_dialog.dart';
import 'package:qr_code_based_pediatric_vaccination/theme/app_theme.dart';

class _LiveAuth extends Fake implements AuthRepository {
  int calls = 0;
  @override
  Future<GuardianActivationResult> activateGuardianInvitation({
    required String activationCode,
  }) async {
    calls++;
    throw FunctionException(
      status: 409,
      details: {'error': 'That username is already in use.'},
    );
  }
}

void main() {
  testWidgets(
    'live sign-in does not show prototype credentials or a simulated-auth caption',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: LoginScreen(authRepository: _LiveAuth()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Prototype Demo'), findsNothing);
      expect(find.text('Prototype authentication is simulated'), findsNothing);
      await tester.ensureVisible(
        find.text('Sign in with your registered account'),
      );
      expect(find.text('Sign in with your registered account'), findsOneWidget);
    },
  );

  testWidgets(
    'live activation rejects a short mock code without contacting the server',
    (tester) async {
      final auth = _LiveAuth();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: GuardianActivationScreen(authRepository: auth),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Use Elena Dela Cruz invitation'), findsNothing);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'ACT-000101');
      await tester.enterText(fields.at(1), 'guardian.valid');
      await tester.enterText(fields.at(2), 'password123');
      await tester.enterText(fields.at(3), 'password123');
      await tester.ensureVisible(find.text('Activate Online Access'));
      await tester.tap(find.text('Activate Online Access'));
      await tester.pumpAndSettle();
      expect(auth.calls, 0);
      expect(
        find.text(
          'Enter the complete activation code provided by your health center.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('live activation accepts pasted codes with spacing separators', (
    tester,
  ) async {
    final auth = _LiveAuth();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: GuardianActivationScreen(authRepository: auth),
      ),
    );
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(
      fields.at(0),
      'ACT-0123 4567 89AB CDEF 0123 4567 89AB CDEF',
    );
    await tester.enterText(fields.at(1), 'guardian.valid');
    await tester.enterText(fields.at(2), 'password123');
    await tester.enterText(fields.at(3), 'password123');
    await tester.ensureVisible(find.text('Activate Online Access'));
    await tester.tap(find.text('Activate Online Access'));
    await tester.pumpAndSettle();
    expect(auth.calls, 1);
    expect(
      find.text('That username is already in use. Choose another username.'),
      findsOneWidget,
    );
    expect(find.textContaining('Bad state'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'visible paste action extracts a code copied with surrounding text',
    (tester) async {
      final auth = _LiveAuth();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          return {
            'text':
                'Guardian activation code: ACT-0123 4567 89AB CDEF 0123 4567 89AB CDEF',
          };
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: GuardianActivationScreen(authRepository: auth),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Paste activation code'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextFormField>(
        find.byType(TextFormField).first,
      );
      expect(field.controller!.text, 'ACT-0123456789ABCDEF0123456789ABCDEF');
    },
  );

  testWidgets(
    'live activation shows a server username conflict inline without Bad state',
    (tester) async {
      final auth = _LiveAuth();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: GuardianActivationScreen(authRepository: auth),
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(
        fields.at(0),
        'ACT-0123456789ABCDEF0123456789ABCDEF',
      );
      await tester.enterText(fields.at(1), 'guardian.valid');
      await tester.enterText(fields.at(2), 'password123');
      await tester.enterText(fields.at(3), 'password123');
      await tester.ensureVisible(find.text('Activate Online Access'));
      await tester.tap(find.text('Activate Online Access'));
      await tester.pumpAndSettle();
      expect(auth.calls, 1);
      expect(
        find.text('That username is already in use. Choose another username.'),
        findsOneWidget,
      );
      expect(find.textContaining('Bad state'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'one-time activation dialog fits a narrow phone with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final invitation = GuardianInvitation(
        id: 'test',
        invitationCode: 'ACT-0123456789ABCDEF0123456789ABCDEF',
        guardianId: 'guardian',
        channel: GuardianInvitationChannel.printedSlip,
        destination: 'Hand to guardian',
        maskedDestination: 'Hand to guardian',
        status: GuardianInvitationStatus.pendingDelivery,
        createdAt: DateTime(2026),
        deliveredAt: null,
        acceptedAt: null,
        expiresAt: DateTime(2099, 1, 8),
        createdByUserId: 'worker',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showGuardianActivationCodeDialog(context, invitation),
                child: const Text('Issue'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Issue'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Copy for guardian'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
