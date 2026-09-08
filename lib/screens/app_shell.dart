import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../repositories/auth_repository.dart';
import 'guardian_home_screen.dart';
import 'health_worker_home_screen.dart';
import 'guardian_children_screen.dart';
import 'registered_families_screen.dart';
import 'vaccination_appointments_screen.dart';
import 'qr_scan_screen.dart';

/// Each tab owns its route stack, keeping the bottom navigation visible.
class AppShell extends StatefulWidget {
  final AppUser user;
  final AuthRepository authRepository;
  const AppShell({super.key, required this.user, required this.authRepository});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selected = 0;
  int _revision = 0;
  int _familiesRevision = 0;
  Set<String>? _familyGuardianFilter;
  final _visited = <int>{0};
  final _keys = List.generate(4, (_) => GlobalKey<NavigatorState>());
  bool get _guardian => widget.user.role == UserRole.guardian;

  void _selectTab(int index) {
    if (index == _selected) {
      _keys[index].currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() {
      _selected = index;
      _visited.add(index);
      _revision++;
    });
  }

  void _openScanner() {
    _keys[_selected].currentState?.push(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
  }

  int get _workerNavigationIndex => _selected < 2 ? _selected : _selected + 1;

  void _selectWorkerDestination(int index) {
    if (index == 2) {
      _openScanner();
      return;
    }
    final tab = index < 2 ? index : index - 1;
    if (tab == 1 && _familyGuardianFilter != null) {
      setState(() {
        _familyGuardianFilter = null;
        _familiesRevision++;
      });
    }
    _selectTab(tab);
  }

  void _openWorkerFamilies(Set<String>? guardianIds) {
    setState(() {
      _familyGuardianFilter = guardianIds == null
          ? null
          : Set.unmodifiable(guardianIds);
      _familiesRevision++;
      _selected = 1;
      _visited.add(1);
      _revision++;
    });
  }

  Widget _root(int index) => switch (index) {
    1 =>
      _guardian
          ? GuardianChildrenScreen(
              user: widget.user,
              authRepository: widget.authRepository,
            )
          : RegisteredFamiliesScreen(
              key: ValueKey('families-$_familiesRevision'),
              healthWorker: widget.user,
              initialGuardianIds: _familyGuardianFilter,
            ),
    2 =>
      _guardian
          ? VaccinationAppointmentsScreen.guardian(
              guardianId: widget.user.id,
              guardianUser: widget.user,
              guardianAuthRepository: widget.authRepository,
            )
          : const VaccinationAppointmentsScreen.healthWorker(),
    _ =>
      _guardian
          ? GuardianHomeScreen(
              user: widget.user,
              authRepository: widget.authRepository,
              servicesOnly: index == 3,
              revision: _revision,
            )
          : HealthWorkerHomeScreen(
              user: widget.user,
              authRepository: widget.authRepository,
              servicesOnly: index == 3,
              revision: _revision,
              onOpenFamilies: _openWorkerFamilies,
            ),
  };

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _selected == 0,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop &&
          _selected != 0 &&
          !(_keys[_selected].currentState?.canPop() ?? false)) {
        setState(() {
          _selected = 0;
          _revision++;
        });
      }
    },
    child: Scaffold(
      body: IndexedStack(
        index: _selected,
        children: [
          for (var index = 0; index < 4; index++)
            if (!_visited.contains(index))
              const SizedBox.shrink()
            else
              NavigatorPopHandler<Object?>(
                enabled: _selected == index,
                onPopWithResult: (result) =>
                    _keys[index].currentState?.pop(result),
                child: Navigator(
                  key: _keys[index],
                  pages: [
                    MaterialPage(
                      key: ValueKey('tab-$index'),
                      child: _root(index),
                    ),
                  ],
                  onDidRemovePage: (_) {},
                ),
              ),
        ],
      ),
      bottomNavigationBar: _guardian
          ? NavigationBar(
              selectedIndex: _selected,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: _selectTab,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.family_restroom_outlined),
                  label: 'Children',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  label: 'Appointments',
                ),
                NavigationDestination(
                  icon: Icon(Icons.grid_view_rounded),
                  label: 'Services',
                ),
              ],
            )
          : _WorkerNavigationBar(
              selectedIndex: _workerNavigationIndex,
              onDestinationSelected: _selectWorkerDestination,
              onScan: _openScanner,
            ),
    ),
  );
}

/// Keeps the familiar app navigation while making QR lookup the worker's
/// unmistakable primary action. Colors always come from the VaxLink theme.
class _WorkerNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onScan;

  const _WorkerNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 92,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            top: 12,
            child: NavigationBar(
              height: 80,
              selectedIndex: selectedIndex,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: onDestinationSelected,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.family_restroom_outlined),
                  label: 'Families',
                ),
                NavigationDestination(
                  icon: SizedBox(width: 52, height: 42),
                  label: 'Scan',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  label: 'Appointments',
                ),
                NavigationDestination(
                  icon: Icon(Icons.grid_view_rounded),
                  label: 'Services',
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Semantics(
                button: true,
                label: 'Scan Child QR',
                child: Tooltip(
                  message: 'Scan Child QR',
                  child: Material(
                    elevation: 7,
                    shadowColor: colors.primary.withValues(alpha: 0.38),
                    color: colors.primary,
                    shape: CircleBorder(
                      side: BorderSide(color: colors.surface, width: 4),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: const Key('worker-qr-scan-action'),
                      onTap: onScan,
                      customBorder: const CircleBorder(),
                      child: SizedBox.square(
                        dimension: 62,
                        child: Icon(
                          Icons.qr_code_scanner_rounded,
                          size: 31,
                          color: colors.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
