import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_code_based_pediatric_vaccination/config/app_environment.dart';
import 'package:qr_code_based_pediatric_vaccination/models/app_user.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/repository_registry.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/app_shell.dart';
import 'package:qr_code_based_pediatric_vaccination/theme/app_theme.dart';
import 'package:qr_code_based_pediatric_vaccination/theme/theme_controller.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ThemeController.mode.value = ThemeMode.light;
  });
  for (final guardian in [true, false]) {
    testWidgets(
      '${guardian ? 'Guardian' : 'Worker'} fixed tabs and dark mode',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final registry = RepositoryRegistry.create(
          const AppEnvironment(
            dataMode: AppDataMode.mock,
            supabaseUrl: '',
            supabaseAnonKey: '',
          ),
        );
        await tester.pumpWidget(
          ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeController.mode,
            builder: (_, mode, child) => MaterialApp(
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: mode,
              home: AppShell(
                user: AppUser(
                  id: guardian ? 'USR-G-001' : 'USR-H-001',
                  fullName: guardian ? 'Maria Santos' : 'Nurse Maria Reyes',
                  role: guardian ? UserRole.guardian : UserRole.healthWorker,
                  active: true,
                ),
                authRepository: registry.authRepository,
              ),
            ),
          ),
        );
        Future<void> settle() async {
          for (var i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 500));
          }
        }

        Future<void> tab(String name) async {
          await tester.tap(
            find.descendant(
              of: find.byType(NavigationBar),
              matching: find.text(name),
            ),
          );
          await settle();
        }

        await settle();
        expect(find.text('Vaccination Statistics'), findsOneWidget);
        expect(find.text('All services'), findsNothing);
        if (!guardian) {
          final scanner = find.byKey(const Key('worker-qr-scan-action'));
          expect(scanner, findsOneWidget);
          expect(scanner.hitTestable(), findsOneWidget);
          await tester.tap(scanner);
          await tester.pumpAndSettle();
          expect(find.text('Scan Child QR'), findsWidgets);
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(scanner.hitTestable(), findsOneWidget);
        }
        await tab('Services');
        expect(find.text('All services'), findsOneWidget);
        await tester.tap(find.byTooltip('Switch to dark theme'));
        await tester.pumpAndSettle();
        expect(ThemeController.mode.value, ThemeMode.dark);
        expect(
          Theme.of(tester.element(find.byType(NavigationBar))).brightness,
          Brightness.dark,
        );
        await tab(guardian ? 'Children' : 'Families');
        expect(find.byType(NavigationBar), findsOneWidget);
        await tab('Appointments');
        expect(find.byType(NavigationBar), findsOneWidget);
        await tab('Home');
        expect(find.text('Vaccination Statistics'), findsOneWidget);
        await tester.tap(find.byTooltip('Switch to light theme'));
        await tester.pumpAndSettle();
        expect(ThemeController.mode.value, ThemeMode.light);
        expect(
          Theme.of(tester.element(find.byType(NavigationBar))).brightness,
          Brightness.light,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final brightness in Brightness.values) {
    testWidgets('Theme toggle works from device $brightness', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      ThemeController.mode.value = ThemeMode.system;
      await tester.pumpWidget(
        ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeController.mode,
          builder: (_, mode, child) => MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: mode,
            home: Scaffold(appBar: AppBar(actions: const [ThemeModeButton()])),
          ),
        ),
      );
      final nextMode = brightness == Brightness.dark
          ? ThemeMode.light
          : ThemeMode.dark;
      expect(find.byType(PopupMenuButton<ThemeMode>), findsNothing);
      await tester.tap(find.byTooltip('Switch to ${nextMode.name} theme'));
      await tester.pumpAndSettle();
      expect(ThemeController.mode.value, nextMode);
      expect(
        (await SharedPreferences.getInstance()).getString('appearance_mode'),
        nextMode.name,
      );
      expect(tester.takeException(), isNull);
    });
  }
  test('Appearance preference restores after restart', () async {
    await ThemeController.setMode(ThemeMode.dark);
    ThemeController.mode.value = ThemeMode.light;
    await ThemeController.initialize();
    expect(ThemeController.mode.value, ThemeMode.dark);
  });
}
