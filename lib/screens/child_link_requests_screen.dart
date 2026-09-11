import 'dart:async';

import '../repositories/repository_registry.dart';
import 'package:flutter/material.dart';

import '../models/app_user.dart';
import 'package:qr_code_based_pediatric_vaccination/models/child/child_link_request.dart';
import '../utils/user_facing_error.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_profile.dart';
import '../repositories/child_repository.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_feedback.dart';
import '../widgets/worker_app_bar_actions.dart';

class ChildLinkRequestsScreen extends StatefulWidget {
  final AppUser healthWorker;
  final String? initialRequestId;
  const ChildLinkRequestsScreen({
    super.key,
    required this.healthWorker,
    this.initialRequestId,
  });

  @override
  State<ChildLinkRequestsScreen> createState() =>
      _ChildLinkRequestsScreenState();
}

class _ChildLinkRequestsScreenState extends State<ChildLinkRequestsScreen> {
  final ChildRepository _repository =
      RepositoryRegistry.instance.childRepository;
  final _searchController = TextEditingController();
  final List<ChildLinkRequest> _loadedRequests = [];
  late Future<List<ChildLinkRequest>> _requests;
  Timer? _searchDebounce;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _nextOffset = 0;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    _nextOffset = 0;
    _hasMore = false;
    _totalCount = 0;
    _requests = _loadPage(reset: true);
  }

  Future<List<ChildLinkRequest>> _loadPage({required bool reset}) async {
    final page = await _repository.getPendingChildLinkRequestsPage(
      query: _searchController.text,
      initialRequestId: widget.initialRequestId,
      limit: 20,
      offset: reset ? 0 : _nextOffset,
    );
    if (reset) _loadedRequests.clear();
    final ids = _loadedRequests.map((item) => item.id).toSet();
    _loadedRequests.addAll(page.items.where((item) => ids.add(item.id)));
    _hasMore = page.hasMore;
    _nextOffset = page.nextOffset;
    _totalCount = page.totalCount;
    return List.unmodifiable(_loadedRequests);
  }

  void _onSearchChanged(String _) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(_reload);
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final items = await _loadPage(reset: false);
      if (mounted) setState(() => _requests = Future.value(items));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _requests;
  }

  Future<bool> _review(ChildLinkRequest request, bool approve) async {
    final notes = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'Approve Child Link' : 'Reject Child Link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${request.childName} will be ${approve ? 'verified and linked to ${request.guardianName}' : 'kept unlinked'}.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: notes,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: approve
                    ? 'Review notes (optional)'
                    : 'Rejection reason',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      notes.dispose();
      return false;
    }
    try {
      await _repository.reviewChildLinkRequest(
        requestId: request.id,
        approve: approve,
        reviewedByUserId: widget.healthWorker.id,
        reviewNotes: notes.text,
      );
      if (!mounted) return false;
      setState(_reload);
      AppFeedback.success(
        context,
        message: approve ? 'Child verified and linked.' : 'Request rejected.',
      );
      return true;
    } catch (error) {
      if (mounted) {
        AppFeedback.failure(
          context,
          message: UserFacingError.message(
            error,
            fallback:
                'The child-link request could not be updated. Please try again.',
          ),
        );
      }
      return false;
    } finally {
      notes.dispose();
    }
  }

  Future<void> _openRequest(ChildLinkRequest request) async {
    final guardian = await _repository.findGuardianById(request.guardianId);
    if (!mounted) return;
    if (guardian == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The guardian record could not be found.'),
        ),
      );
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _ChildLinkRequestDetails(
          request: request,
          guardian: guardian,
          onReview: _review,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.initialRequestId != null) {
      return FutureBuilder<List<ChildLinkRequest>>(
        future: _requests,
        builder: (context, snapshot) {
          final request = snapshot.data
              ?.where((r) => r.id == widget.initialRequestId)
              .firstOrNull;
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              appBar: AppBar(title: const Text('Review request')),
              body: const AppLoadingView(
                title: 'Loading request',
                message: 'Retrieving the child-link information.',
              ),
            );
          }
          if (snapshot.hasError || request == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Review request')),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    snapshot.hasError
                        ? 'The request could not be loaded. Please go back and try again.'
                        : 'This request is no longer pending or is unavailable.',
                  ),
                ),
              ),
            );
          }
          return FutureBuilder<GuardianProfile?>(
            future: _repository.findGuardianById(request.guardianId),
            builder: (context, guardian) {
              if (guardian.connectionState == ConnectionState.waiting) {
                return Scaffold(
                  appBar: AppBar(title: const Text('Review request')),
                  body: const AppLoadingView(
                    title: 'Loading guardian',
                    message: 'Retrieving the linked guardian record.',
                  ),
                );
              }
              if (guardian.hasError || guardian.data == null) {
                return Scaffold(
                  appBar: AppBar(title: const Text('Review request')),
                  body: const Center(
                    child: Text('The guardian record could not be loaded.'),
                  ),
                );
              }
              return _ChildLinkRequestDetails(
                request: request,
                guardian: guardian.data!,
                onReview: _review,
              );
            },
          );
        },
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Child Link Requests',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: const [WorkerAppBarActions()],
      ),
      body: FutureBuilder<List<ChildLinkRequest>>(
        future: _requests,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoadingView(
              title: 'Loading requests',
              message: 'Checking for child-link requests awaiting review.',
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: TextButton.icon(
                onPressed: () => setState(_reload),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Child-link requests could not be loaded'),
              ),
            );
          }
          final requests = snapshot.data ?? const [];
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search child, guardian, or request ID',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              _searchDebounce?.cancel();
                              setState(_reload);
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${requests.length} of $_totalCount pending request(s)',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                if (requests.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Text(
                      'No matching child-link requests are waiting for review.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  for (final request in requests)
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: const CircleAvatar(
                          child: Icon(Icons.child_care_rounded),
                        ),
                        title: Text(
                          request.childName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            '${request.guardianName}\n${request.requestCode} • Pending review',
                          ),
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _openRequest(request),
                      ),
                    ),
                if (_hasMore)
                  OutlinedButton.icon(
                    onPressed: _loadingMore ? null : _loadMore,
                    icon: _loadingMore
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.expand_more_rounded),
                    label: Text(
                      _loadingMore ? 'Loading more…' : 'Load more requests',
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ChildLinkRequestDetails extends StatelessWidget {
  final ChildLinkRequest request;
  final GuardianProfile guardian;
  final Future<bool> Function(ChildLinkRequest, bool) onReview;
  const _ChildLinkRequestDetails({
    required this.request,
    required this.guardian,
    required this.onReview,
  });

  String _date(DateTime value) => '${value.month}/${value.day}/${value.year}';

  Future<void> _review(BuildContext context, bool approve) async {
    final saved = await onReview(request, approve);
    if (saved && context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Review Child Link',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.fact_check_outlined, color: Colors.blue),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Compare these details with the presented birth record and proof of guardianship before deciding.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _DetailsCard(
          title: 'Guardian Information',
          icon: Icons.person_outline_rounded,
          rows: {
            'Full name': guardian.fullName,
            'Sex': guardian.sex,
            'Guardian ID': guardian.guardianCode,
            'Phone': guardian.phoneNumber ?? 'Not provided',
            'Email': guardian.emailAddress ?? 'Not provided',
            'Address': guardian.address,
            'Account access': guardian.accessLabel,
          },
        ),
        const SizedBox(height: 12),
        _DetailsCard(
          title: 'Child Information',
          icon: Icons.child_care_rounded,
          rows: {
            'Full name': request.childName,
            'Birth date': _date(request.birthDate),
            'Sex': request.sex,
            'Relationship': request.relationship,
          },
        ),
        const SizedBox(height: 12),
        _DetailsCard(
          title: 'Request Information',
          icon: Icons.description_outlined,
          rows: {
            'Request ID': request.requestCode,
            'Submitted': _date(request.submittedAt),
            'Status': 'Pending review',
          },
        ),
      ],
    ),
    bottomNavigationBar: Material(
      elevation: 10,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(18, 12, 18, 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _review(context, false),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Reject'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  side: BorderSide(color: Theme.of(context).colorScheme.error),
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _review(context, true),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Approve'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DetailsCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Map<String, String> rows;
  const _DetailsCard({
    required this.title,
    required this.icon,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.blue),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const Divider(height: 26),
          for (final row in rows.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 115,
                    child: Text(
                      row.key,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.value,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
