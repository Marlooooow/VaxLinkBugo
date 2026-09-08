import '../repositories/repository_registry.dart';
import 'package:flutter/material.dart';
import '../models/appointment_slot_offer.dart';
import '../repositories/appointment_repository.dart';
import '../services/session_context.dart';
import '../utils/user_facing_error.dart';
import '../widgets/offer_timing_panel.dart';
import '../widgets/app_loading.dart';
import '../widgets/guardian_app_bar_actions.dart';
import '../widgets/worker_app_bar_actions.dart';

class EarlierAppointmentOffersScreen extends StatefulWidget {
  final String? guardianId;
  final bool healthWorkerMode;
  final String? initialOfferId;
  final AppointmentRepository? repository;
  const EarlierAppointmentOffersScreen({
    super.key,
    this.guardianId,
    required this.healthWorkerMode,
    this.initialOfferId,
    this.repository,
  });
  @override
  State<EarlierAppointmentOffersScreen> createState() =>
      _EarlierAppointmentOffersScreenState();
}

class _EarlierAppointmentOffersScreenState
    extends State<EarlierAppointmentOffersScreen> {
  late final AppointmentRepository _repository;
  late Future<List<AppointmentSlotOffer>> _offers;
  final List<AppointmentSlotOffer> _loadedOffers = [];
  final Set<String> _responding = {};
  AppointmentSlotOfferStatus? _filter = AppointmentSlotOfferStatus.pending;
  String? _focusedId;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _nextOffset = 0;
  int _totalCount = 0;
  int _pendingCount = 0;
  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? RepositoryRegistry.instance.appointmentRepository;
    _focusedId = widget.initialOfferId;
    _reload();
  }

  void _reload() {
    _offers = widget.healthWorkerMode
        ? _loadOfferPage(reset: true)
        : _repository.getGuardianSlotOffers(widget.guardianId!);
  }

  Future<List<AppointmentSlotOffer>> _loadOfferPage({
    required bool reset,
  }) async {
    final page = await _repository.getFacilitySlotOffersPage(
      status: _focusedId == null ? _filter : null,
      initialOfferId: _focusedId,
      limit: 20,
      offset: reset ? 0 : _nextOffset,
    );
    if (reset) _loadedOffers.clear();
    final ids = _loadedOffers.map((offer) => offer.id).toSet();
    _loadedOffers.addAll(page.items.where((offer) => ids.add(offer.id)));
    _hasMore = page.hasMore;
    _nextOffset = page.nextOffset;
    _totalCount = page.totalCount;
    _pendingCount = page.pendingCount;
    return List.unmodifiable(_loadedOffers);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || !widget.healthWorkerMode) return;
    setState(() => _loadingMore = true);
    try {
      final offers = await _loadOfferPage(reset: false);
      if (mounted) setState(() => _offers = Future.value(offers));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _refresh() async {
    setState(_reload);
    try {
      await _offers;
    } catch (_) {
      /* Error and retry rendered below. */
    }
  }

  Future<void> _respondToOffer(AppointmentSlotOffer offer, bool accept) async {
    if (_responding.contains(offer.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          widget.healthWorkerMode
              ? 'Record guardian response'
              : 'Confirm appointment choice',
        ),
        content: Text(
          widget.healthWorkerMode
              ? 'Record this only after contacting the guardian. ${accept ? "They accepted the earlier appointment." : "They chose to keep the current appointment."}'
              : accept
              ? 'Accept the earlier date and time? Your current slot will be released only after confirmation.'
              : 'Keep your current appointment? The earlier slot will be offered to the next eligible child.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _responding.contains(offer.id)) return;
    setState(() => _responding.add(offer.id));
    try {
      await _repository.respondToSlotOffer(
        offer.id,
        accept,
        widget.guardianId ?? SessionContext.userId,
        responseChannel: widget.healthWorkerMode
            ? 'staff_recorded'
            : 'guardian_online',
      );
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'Earlier appointment accepted.'
                : 'Original appointment retained.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.message(
              error,
              fallback:
                  'The appointment could not be updated. Please try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _responding.remove(offer.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Earlier appointment offers'),
      actions: [
        IconButton(
          tooltip: 'Refresh offers',
          onPressed: _responding.isEmpty ? _refresh : null,
          icon: const Icon(Icons.refresh),
        ),
        if (widget.healthWorkerMode)
          const WorkerAppBarActions()
        else
          const GuardianAppBarActions(),
      ],
    ),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 768),
          child: FutureBuilder<List<AppointmentSlotOffer>>(
            future: _offers,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const AppLoadingView(
                  title: 'Loading appointment offers',
                  message: 'Checking available earlier schedules.',
                );
              }
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Offers could not be loaded.'),
                      TextButton(
                        onPressed: _refresh,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                );
              }
              final all = snapshot.data ?? <AppointmentSlotOffer>[];
              final visible =
                  all
                      .where(
                        (o) => _focusedId != null
                            ? o.id == _focusedId
                            : _filter == null || o.status == _filter,
                      )
                      .toList()
                    ..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
              final pending = widget.healthWorkerMode
                  ? _pendingCount
                  : all
                        .where(
                          (o) => o.status == AppointmentSlotOfferStatus.pending,
                        )
                        .length;
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    if (_focusedId == null) ...[
                      Text(
                        '$pending awaiting response',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Current appointments stay unchanged until an earlier offer is accepted.',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final status in <AppointmentSlotOfferStatus?>[
                            null,
                            ...AppointmentSlotOfferStatus.values,
                          ])
                            ChoiceChip(
                              label: Text(
                                status == null ? 'All' : _status(status),
                              ),
                              selected: _filter == status,
                              onSelected: (_) {
                                setState(() => _filter = status);
                                if (widget.healthWorkerMode) _refresh();
                              },
                            ),
                        ],
                      ),
                    ] else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () {
                            setState(() {
                              _focusedId = null;
                              _filter = null;
                            });
                            _refresh();
                          },
                          child: const Text('View all offers'),
                        ),
                      ),
                    if (widget.healthWorkerMode)
                      ExpansionTile(
                        title: const Text('How automatic offers work'),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
                        children: const [
                          Text(
                            'Prototype: weekdays 9 AM–12 PM, 15-minute slots. Priority first, then eligible waiting-list entry time. Expiry is processed on refresh. Holds are provisional; clinical assessment is still required. Record an offline response only after contacting the guardian.',
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _focusedId != null
                              ? 'This offer is no longer available.'
                              : 'No offers in this category.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    for (final offer in visible)
                      Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ExpansionTile(
                          key: PageStorageKey('offer-${offer.id}'),
                          initiallyExpanded: _focusedId == offer.id,
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            16,
                          ),
                          title: Text(
                            offer.childName,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                '${offer.vaccineName} • Dose ${offer.doseNumber}',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _when(context, offer.offeredAppointmentDate),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: _color(
                                    offer.status,
                                  ).withValues(alpha: .09),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  _status(offer.status),
                                  style: TextStyle(
                                    color: _color(offer.status),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (offer.status ==
                                  AppointmentSlotOfferStatus.pending)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    'Respond by ${_when(context, offer.expiresAt)}',
                                  ),
                                ),
                            ],
                          ),
                          children: [
                            const Divider(),
                            OfferTimingPanel(offer: offer),
                            const SizedBox(height: 12),
                            Text(
                              'Offer ID: ${offer.offerCode}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (offer.status ==
                                AppointmentSlotOfferStatus.pending) ...[
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _responding.contains(offer.id)
                                      ? null
                                      : () => _respondToOffer(offer, true),
                                  icon: const Icon(Icons.event_available),
                                  label: Text(
                                    _responding.contains(offer.id)
                                        ? 'Saving…'
                                        : widget.healthWorkerMode
                                        ? 'Record guardian acceptance'
                                        : 'Accept earlier appointment',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: _responding.contains(offer.id)
                                      ? null
                                      : () => _respondToOffer(offer, false),
                                  child: Text(
                                    widget.healthWorkerMode
                                        ? 'Record guardian decline'
                                        : 'Keep current appointment',
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    if (widget.healthWorkerMode && visible.isNotEmpty) ...[
                      Text(
                        'Showing ${visible.length} of $_totalCount offers',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      if (_loadingMore)
                        const Center(child: CircularProgressIndicator())
                      else if (_hasMore)
                        OutlinedButton.icon(
                          onPressed: _loadMore,
                          icon: const Icon(Icons.expand_more_rounded),
                          label: const Text('Load 20 more'),
                        )
                      else
                        const Center(child: Text('All offers are loaded.')),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

String _status(AppointmentSlotOfferStatus status) => switch (status) {
  AppointmentSlotOfferStatus.pending => 'Awaiting response',
  AppointmentSlotOfferStatus.accepted => 'Accepted',
  AppointmentSlotOfferStatus.declined => 'Declined',
  AppointmentSlotOfferStatus.expired => 'Expired',
};
Color _color(AppointmentSlotOfferStatus status) => switch (status) {
  AppointmentSlotOfferStatus.pending => const Color(0xFF945400),
  AppointmentSlotOfferStatus.accepted => const Color(0xFF237A3B),
  _ => const Color(0xFF526174),
};
String _when(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final format = MaterialLocalizations.of(context);
  return '${format.formatMediumDate(local)} • ${format.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}
