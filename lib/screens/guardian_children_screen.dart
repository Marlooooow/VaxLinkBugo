import '../repositories/repository_registry.dart';
import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/child_profile.dart';
import '../models/child_link_request.dart';
import '../repositories/auth_repository.dart';
import '../repositories/child_repository.dart';
import 'child_profile_screen.dart';
import 'login_screen.dart';
import 'guardian_child_request_screen.dart';
import '../models/pnip_schedule_entry.dart';
import '../widgets/vaccination_progress_bar.dart';
import '../widgets/app_loading.dart';
import '../utils/user_facing_error.dart';
import '../services/session_context.dart';
import '../widgets/guardian_app_bar_actions.dart';
import '../widgets/bugo_brand_title.dart';

class GuardianChildrenScreen extends StatefulWidget {
  final AppUser user;
  final AuthRepository authRepository;

  const GuardianChildrenScreen({
    super.key,
    required this.user,
    required this.authRepository,
  });

  @override
  State<GuardianChildrenScreen> createState() => _GuardianChildrenScreenState();
}

class _GuardianChildrenScreenState extends State<GuardianChildrenScreen> {
  final ChildRepository _childRepository =
      RepositoryRegistry.instance.childRepository;

  List<ChildProfile> _children = [];
  List<ChildLinkRequest> _requests = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _childRepository.getChildrenForGuardian(widget.user.id),
        _childRepository.getGuardianChildLinkRequests(widget.user.id),
      ]);
      final children = results[0] as List<ChildProfile>;
      final requests = results[1] as List<ChildLinkRequest>;

      if (!mounted) return;

      setState(() {
        _children = children;
        _requests = requests;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Unable to load your child records.';
      });
    }
  }

  Future<void> _requestChild() async {
    final result = await Navigator.push<ChildLinkRequest>(
      context,
      MaterialPageRoute(
        builder: (_) => GuardianChildRequestScreen(
          guardianUserId: widget.user.id,
          repository: _childRepository,
        ),
      ),
    );
    if (result == null || !mounted) return;
    await _loadChildren();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Child request submitted for verification.'),
      ),
    );
  }

  Future<void> _logout() async {
    try {
      await runWithAppLoading(
        context,
        title: 'Signing you out',
        message: 'Closing your secure session safely.',
        operation: widget.authRepository.logout,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.message(
              error,
              fallback: 'Sign-out could not be completed. Please try again.',
            ),
          ),
        ),
      );
      return;
    }
    SessionContext.clear();

    if (!mounted) return;

    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(authRepository: widget.authRepository),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final green = Theme.of(context).colorScheme.secondary;
    final ownChildren = _children
        .where((child) => child.isParentRelationship)
        .toList();
    final childrenUnderCare = _children
        .where((child) => !child.isParentRelationship)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const BugoBrandTitle(),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadChildren,
            icon: const Icon(Icons.refresh_rounded),
          ),
          GuardianAppBarActions(
            user: widget.user,
            authRepository: widget.authRepository,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadChildren,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Guardian account',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.user.fullName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: primary.withValues(alpha: 0.10)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.family_restroom_rounded,
                          color: primary,
                        ),
                      ),
                      const SizedBox(width: 13),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Child records',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Select a child to view their vaccination information.',
                              style: TextStyle(fontSize: 12.5, height: 1.35),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _requestChild,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Request to Add a Child'),
                  ),
                ),
                if (_requests.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text(
                    'Child requests',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 9),
                  ..._requests.map(
                    (request) => Card(
                      margin: const EdgeInsets.only(bottom: 9),
                      child: ListTile(
                        leading: Icon(
                          request.status == ChildLinkRequestStatus.approved
                              ? Icons.check_circle_outline_rounded
                              : request.status ==
                                    ChildLinkRequestStatus.rejected
                              ? Icons.cancel_outlined
                              : Icons.schedule_rounded,
                        ),
                        title: Text(request.childName),
                        subtitle: Text(
                          request.status == ChildLinkRequestStatus.pending
                              ? 'Waiting for health-worker verification'
                              : request.status ==
                                    ChildLinkRequestStatus.approved
                              ? 'Approved and linked to your account'
                              : 'Not approved${request.reviewNotes?.isNotEmpty == true ? ': ${request.reviewNotes}' : ''}',
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    const Text(
                      'Registered children',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    if (!_loading)
                      Text(
                        '${_children.length}',
                        style: TextStyle(
                          color: green,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const _LoadingCard()
                else if (_error != null)
                  _ErrorCard(message: _error!, onRetry: _loadChildren)
                else if (_children.isEmpty)
                  const _EmptyCard()
                else ...[
                  if (ownChildren.isNotEmpty)
                    _ChildSection(
                      title: 'Your children',
                      subtitle: 'Children linked through a parent relationship',
                      children: ownChildren,
                      primary: primary,
                    ),
                  if (ownChildren.isNotEmpty && childrenUnderCare.isNotEmpty)
                    const SizedBox(height: 10),
                  if (childrenUnderCare.isNotEmpty)
                    _ChildSection(
                      title: 'Children under your care',
                      subtitle:
                          'Children for whom you are an authorized guardian',
                      children: childrenUnderCare,
                      primary: primary,
                    ),
                ],
                const SizedBox(height: 8),
                // Container(
                //   width: double.infinity,
                //   padding: const EdgeInsets.all(15),
                //   decoration: BoxDecoration(
                //     color: Colors.white,
                //     borderRadius: BorderRadius.circular(17),
                //     border: Border.all(color: const Color(0xFFE7EDF4)),
                //   ),
                //   child: Row(
                //     crossAxisAlignment: CrossAxisAlignment.start,
                //     children: [
                //       Icon(
                //         Icons.info_outline_rounded,
                //         size: 19,
                //         color: primary,
                //       ),
                //       const SizedBox(width: 10),
                //       Expanded(
                //         child: Text(
                //           'Phase 2 uses mock child data. The repository is separated so it can later be connected to the actual backend without changing this screen.',
                //           style: TextStyle(
                //             fontSize: 12,
                //             color: Theme.of(context).colorScheme.onSurfaceVariant,
                //             height: 1.4,
                //           ),
                //         ),
                //       ),
                //     ],
                //   ),
                // ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChildSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<ChildProfile> children;
  final Color primary;

  const _ChildSection({
    required this.title,
    required this.subtitle,
    required this.children,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        ...children.map(
          (child) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ChildCard(
              child: child,
              primary: primary,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChildProfileScreen(child: child),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ChildCard extends StatefulWidget {
  final ChildProfile child;
  final Color primary;
  final Future<void> Function() onTap;

  const _ChildCard({
    required this.child,
    required this.primary,
    required this.onTap,
  });

  @override
  State<_ChildCard> createState() => _ChildCardState();
}

class _ChildCardState extends State<_ChildCard> {
  ChildProfile get child => widget.child;
  Color get primary => widget.primary;
  late Future<List<PnipScheduleEntry>> _schedule;

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  void _loadSchedule() {
    _schedule = RepositoryRegistry.instance.vaccinationRepository
        .getVaccinationSchedule(child);
  }

  @override
  void didUpdateWidget(covariant _ChildCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child != child) _loadSchedule();
  }

  Future<void> _openChild() async {
    await widget.onTap();
    if (mounted) setState(_loadSchedule);
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _openChild,
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE7EDF4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.09),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.child_care_rounded,
                      color: primary,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          child.fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Born ${_formatDate(child.birthDate)}',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          runSpacing: 6,
                          children: [
                            Icon(
                              child.sex == 'Female'
                                  ? Icons.female_rounded
                                  : Icons.male_rounded,
                              size: 15,
                              color: primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              child.sex,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Guardian: ${child.relationship}',
                                style: TextStyle(
                                  color: primary,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
              const Divider(height: 24),
              FutureBuilder<List<PnipScheduleEntry>>(
                future: _schedule,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return TextButton(
                      onPressed: () => setState(_loadSchedule),
                      child: const Text('Retry loading vaccination progress'),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Text('Loading vaccination progress…');
                  }
                  return VaccinationProgressBar(schedule: snapshot.data!);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7EDF4)),
      ),
      child: const AppLoadingView(
        title: 'Loading child records',
        message: 'Preparing your children and vaccination progress.',
        padding: EdgeInsets.all(12),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7EDF4)),
      ),
      child: const Column(
        children: [
          Icon(Icons.child_friendly_rounded, size: 40, color: Colors.grey),
          SizedBox(height: 10),
          Text(
            'No child records yet',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 5),
          Text(
            'A registered child will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.red, size: 34),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
