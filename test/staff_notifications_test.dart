import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/models/app_user.dart';
import 'package:qr_code_based_pediatric_vaccination/models/staff_notification.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/staff_notification_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/repository_registry.dart';
import 'package:qr_code_based_pediatric_vaccination/config/app_environment.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/staff_notifications_screen.dart';
import 'package:qr_code_based_pediatric_vaccination/theme/app_theme.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/child_link_requests_screen.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/vaccination_appointments_screen.dart';

class _Repository implements StaffNotificationRepository {
  StaffNotificationTarget target = StaffNotificationTarget.followUps;
  @override
  final ChangeNotifier changes = ChangeNotifier();
  final read = <String>{};
  bool fail = false;
  @override
  bool isRead(String userId, String id) => read.contains('$userId:$id');
  @override
  Future<void> markRead(String userId, Iterable<String> ids) async {
    if (fail) throw StateError('private failure');
    read.addAll(ids.map((id) => '$userId:$id'));
    changes.notifyListeners();
  }

  @override
  Future<List<StaffNotification>> load() async => [
    StaffNotification(
      id: 'daily',
      title: 'Daily follow-up summary',
      body: '3 doses due today.',
      target: target,
      entityId: target == StaffNotificationTarget.followUps
          ? null
          : 'missing-record',
      createdAt: DateTime(2026, 8, 30),
    ),
  ];

  @override
  Future<StaffNotificationPage> loadPage({
    required String userId,
    bool unreadOnly = false,
    int limit = 20,
    int offset = 0,
  }) async {
    final all = await load();
    final unread = all.where((item) => !isRead(userId, item.id)).toList();
    final visible = unreadOnly ? unread : all;
    final items = visible.skip(offset).take(limit).toList(growable: false);
    return StaffNotificationPage(
      items: items,
      overallCount: all.length,
      totalCount: visible.length,
      unreadCount: unread.length,
      hasMore: offset + items.length < visible.length,
      nextOffset: offset + items.length,
    );
  }

  @override
  Future<int> unreadCount(String userId) async =>
      (await load()).where((item) => !isRead(userId, item.id)).length;

  @override
  Future<String> resetGuardianPassword(String requestId) async => 'guardian123';

  @override
  Future<String> resetGuardianPasswordForGuardian(String guardianId) async => 'guardian123';
}

void main() {
  testWidgets(
    'Request notification opens request directly without extra details page',
    (tester) async {
      final repository = _Repository()
        ..target = StaffNotificationTarget.requests;
      await tester.pumpWidget(
        MaterialApp(
          home: StaffNotificationsScreen(
            repository: repository,
            user: const AppUser(
              id: 'worker',
              fullName: 'Nurse',
              role: UserRole.healthWorker,
              active: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily follow-up summary'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.byType(ChildLinkRequestsScreen), findsOneWidget);
      expect(find.text('Notification details'), findsNothing);
      expect(repository.isRead('worker', 'daily'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  for (final requests in [true, false]) {
    testWidgets('Missing linked record does not show general list: $requests', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: requests
              ? const ChildLinkRequestsScreen(
                  initialRequestId: 'missing-record',
                  healthWorker: AppUser(
                    id: 'worker',
                    fullName: 'Nurse',
                    role: UserRole.healthWorker,
                    active: true,
                  ),
                )
              : const VaccinationAppointmentsScreen.healthWorker(
                  initialAppointmentId: 'missing-record',
                ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(
        find.text(
          requests
              ? 'This request is no longer pending or is unavailable.'
              : 'This appointment is no longer available.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Bell clears when inbox marks all read and returns', (
    tester,
  ) async {
    final repository = _Repository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              StaffNotificationBell(
                repository: repository,
                user: const AppUser(
                  id: 'worker',
                  fullName: 'Nurse',
                  role: UserRole.healthWorker,
                  active: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Notifications (1 unread)'), findsOneWidget);
    await tester.tap(find.byTooltip('Notifications (1 unread)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark all as read'));
    await tester.pumpAndSettle();
    expect(find.text('Unread (0)'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Notifications (0 unread)'), findsOneWidget);
    final badge = tester.widget<Badge>(find.byType(Badge));
    expect(badge.isLabelVisible, isFalse);
    expect(tester.takeException(), isNull);
  });
  test(
    'Backend payload preserves arbitrary insight IDs without name matching',
    () {
      final payload = <String, dynamic>{
        'id': 'future-notification',
        'title': 'A newly generated advisory',
        'body': 'Future database content',
        'target': 'insights',
        'entity_id': 'future-insight-uuid',
        'created_at': '2027-01-01T00:00:00Z',
      };
      final item = StaffNotification.fromJson(payload);
      expect(item.entityId, 'future-insight-uuid');
      expect(StaffNotification.fromJson(item.toJson()).entityId, item.entityId);
      expect(
        () => StaffNotification.fromJson({...payload, 'entity_id': null}),
        throwsFormatException,
      );
      expect(
        () => StaffNotification.fromJson({
          ...payload,
          'target': 'arbitrary-route',
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'Connected alerts are deduplicated and read receipts are per worker',
    () async {
      final registry = RepositoryRegistry.create(
        const AppEnvironment(
          dataMode: AppDataMode.mock,
          supabaseUrl: '',
          supabaseAnonKey: '',
        ),
      );
      final repository = MockStaffNotificationRepository(registry);
      final first = await repository.load();
      expect(first, isNotEmpty);
      expect(first.map((n) => n.id).toSet().length, first.length);
      expect(
        first
            .where((n) => n.target == StaffNotificationTarget.followUps)
            .length,
        1,
      );
      await repository.markRead(
        'notification-test-worker',
        first.map((n) => n.id),
      );
      final next = await repository.load();
      expect(next.map((n) => n.id).toSet(), first.map((n) => n.id).toSet());
      expect(
        next.every((n) => repository.isRead('notification-test-worker', n.id)),
        isTrue,
      );
      expect(next.any((n) => repository.isRead('other-worker', n.id)), isFalse);
    },
  );

  for (final fails in [false, true]) {
    testWidgets('Small-screen inbox mark all read, failure=$fails', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository()..fail = fails;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: StaffNotificationsScreen(
            repository: repository,
            user: const AppUser(
              id: 'worker',
              fullName: 'Nurse',
              role: UserRole.healthWorker,
              active: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark all as read'));
      await tester.pumpAndSettle();
      expect(find.text(fails ? 'Unread (1)' : 'Unread (0)'), findsOneWidget);
      if (fails) {
        expect(
          find.text('Could not mark notifications as read. Please try again.'),
          findsOneWidget,
        );
      } else {
        await tester.tap(find.text('Unread (0)'));
        await tester.pumpAndSettle();
        expect(
          find.text('You’re all caught up. No unread notifications.'),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}
