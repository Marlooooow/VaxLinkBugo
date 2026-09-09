import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/vaccination_reminder.dart';
import '../models/reminder_follow_up.dart';
import '../models/appointment_slot_offer.dart';
import '../services/session_context.dart';
import '../utils/user_facing_error.dart';
import '../theme/status_colors.dart';
import '../repositories/child_repository.dart';
import '../repositories/appointment_repository.dart';
import '../repositories/reminder_repository.dart';
import '../repositories/repository_registry.dart';
import '../widgets/app_loading.dart';
import '../widgets/worker_app_bar_actions.dart';
import '../widgets/guardian_app_bar_actions.dart';
import 'child_profile_screen.dart';
import 'appointment_form_screen.dart';
import 'earlier_appointment_offers_screen.dart';

class VaccinationRemindersScreen extends StatefulWidget {
  final String? guardianId;
  final bool healthWorkerMode;
  final ReminderRepository? repository;
  final String? childId;
  final VaccinationReminderStatus? initialFilter;

  const VaccinationRemindersScreen.guardian({
    super.key,
    required this.guardianId,
    this.repository,
    this.childId,
    this.initialFilter,
  }) : healthWorkerMode = false;

  const VaccinationRemindersScreen.healthWorker({
    super.key,
    this.repository,
    this.childId,
    this.initialFilter,
  }) : guardianId = null,
       healthWorkerMode = true;

  @override
  State<VaccinationRemindersScreen> createState() =>
      _VaccinationRemindersScreenState();
}

class _VaccinationRemindersScreenState
    extends State<VaccinationRemindersScreen> {
  late final ReminderRepository _repository;
  final ChildRepository _childRepository =
      RepositoryRegistry.instance.childRepository;
  final AppointmentRepository _appointmentRepository =
      RepositoryRegistry.instance.appointmentRepository;
  late Future<List<VaccinationReminder>> _reminders;
  Future<ReminderSummary>? _facilitySummary;
  Future<List<AppointmentSlotOffer>>? _slotOffers;
  VaccinationReminderStatus? _filter;
  final Set<String> _selectedIds = {};
  bool _batchSaving = false;
  final Set<String> _locallyReadIds = {};
  int _guardianVisibleChildLimit = 10;
  int _facilityOffset = 0;
  bool _hasMoreFacilityReminders = false;
  bool _loadingMoreFacilityReminders = false;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? RepositoryRegistry.instance.reminderRepository;
    _filter = widget.initialFilter;
    _reload();
  }

  void _reload() {
    final guardianId = widget.guardianId;
    if (!widget.healthWorkerMode && guardianId != null) {
      _guardianVisibleChildLimit = 10;
      _reminders = () async {
        await _repository.syncGuardianReminders(guardianId);
        return _repository.getGuardianReminders(guardianId);
      }();
      _slotOffers = _appointmentRepository.getGuardianSlotOffers(guardianId);
      return;
    }
    _facilityOffset = 0;
    _reminders = _loadInitialFacilityPage();
    _facilitySummary = _repository.getFacilityFollowUpSummary();
    if (!widget.healthWorkerMode) {
      _slotOffers = _appointmentRepository.getGuardianSlotOffers(
        widget.guardianId!,
      );
    }
  }

  void _setFilter(VaccinationReminderStatus? status) {
    setState(() {
      _filter = status;
      _guardianVisibleChildLimit = 10;
      _selectedIds.clear();
    });
  }

  Future<List<VaccinationReminder>> _loadInitialFacilityPage() async {
    final page = await _repository.getFacilityFollowUpsPage();
    _facilityOffset = page.nextOffset;
    _hasMoreFacilityReminders = page.hasMore;
    return page.items;
  }

  Future<void> _loadMoreFacilityReminders() async {
    if (!widget.healthWorkerMode ||
        !_hasMoreFacilityReminders ||
        _loadingMoreFacilityReminders) {
      return;
    }
    setState(() => _loadingMoreFacilityReminders = true);
    try {
      final current = await _reminders;
      final page = await _repository.getFacilityFollowUpsPage(
        offset: _facilityOffset,
      );
      if (!mounted) return;
      setState(() {
        _reminders = Future.value([...current, ...page.items]);
        _facilityOffset = page.nextOffset;
        _hasMoreFacilityReminders = page.hasMore;
        _loadingMoreFacilityReminders = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingMoreFacilityReminders = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('More reminders could not be loaded: $error')),
      );
    }
  }

  Future<void> _markRead(VaccinationReminder reminder) async {
    if (reminder.isRead || _locallyReadIds.contains(reminder.id)) return;
    await _repository.markAsRead(reminder.id);
    if (mounted) {
      setState(() => _locallyReadIds.add(reminder.id));
    }
  }

  Future<void> _openChildDue(VaccinationReminder reminder) async {
    await _repository.markAsRead(reminder.id);
    final child = await _childRepository.findChildByIdentifier(
      reminder.childId,
    );
    if (!mounted) return;
    if (child == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The linked child record was not found.')),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChildProfileScreen(
          child: child,
          highlightedVaccineId: reminder.vaccineId,
          highlightedDoseNumber: reminder.doseNumber,
        ),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _performBatchAction(_BatchChoice choice) async {
    if (_selectedIds.isEmpty) return;
    if (choice == _BatchChoice.printList) {
      final exported = await _exportSelectedFollowUpList();
      if (!exported) return;
    }
    final live = RepositoryRegistry.instance.environment.isLive;
    final (action, outcome, message, notes, assignee) = switch (choice) {
      _BatchChoice.mockSms => (
        live ? ReminderFollowUpAction.sms : ReminderFollowUpAction.mockSms,
        live
            ? ReminderFollowUpOutcome.providerAccepted
            : ReminderFollowUpOutcome.reminderSent,
        live ? 'SMS delivery requests accepted' : 'Mock SMS reminders sent',
        live
            ? 'SMS delivery requested.'
            : 'Mock SMS reminder queued for delivery.',
        null,
      ),
      _BatchChoice.assignToMe => (
        ReminderFollowUpAction.assign,
        ReminderFollowUpOutcome.assigned,
        'Follow-ups assigned',
        'Assigned from the health-worker follow-up queue.',
        SessionContext.userId,
      ),
      _BatchChoice.printList => (
        ReminderFollowUpAction.printedList,
        ReminderFollowUpOutcome.printed,
        'Follow-up list exported',
        'Included in the generated follow-up PDF or CSV.',
        null,
      ),
      _BatchChoice.noAnswer => (
        ReminderFollowUpAction.phoneCall,
        ReminderFollowUpOutcome.noAnswer,
        'No-answer outcomes recorded',
        'Guardian did not answer the contact attempt.',
        null,
      ),
      _BatchChoice.visitScheduled => (
        ReminderFollowUpAction.phoneCall,
        ReminderFollowUpOutcome.visitScheduled,
        'Scheduled-visit outcomes recorded',
        'Guardian confirmed a follow-up visit.',
        null,
      ),
      _BatchChoice.homeVisit => (
        ReminderFollowUpAction.homeVisit,
        ReminderFollowUpOutcome.homeVisitRequired,
        'Home-visit follow-ups recorded',
        'Case requires barangay home-visit follow-up.',
        SessionContext.userId,
      ),
    };
    final records = await _repository.performBatchAction(
      ReminderBatchActionRequest(
        reminderIds: _selectedIds.toList(growable: false),
        action: action,
        outcome: outcome,
        assignedToUserId: assignee,
        notes: notes,
        performedByUserId: SessionContext.userId,
      ),
    );
    if (!mounted) return;
    final count = records.length;
    setState(() {
      // Keep the selection so another independent action can be applied.
      _reload();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$message for $count reminder${count == 1 ? '' : 's'}.'),
      ),
    );
  }

  Future<bool> _exportSelectedFollowUpList() async {
    final all = await _reminders;
    final selected =
        all
            .where((item) => _selectedIds.contains(item.id))
            .toList(growable: false)
          ..sort((left, right) {
            final child = left.childName.compareTo(right.childName);
            return child != 0 ? child : left.dueDate.compareTo(right.dueDate);
          });
    if (selected.isEmpty || !mounted) return false;
    final format = await showDialog<_FollowUpExportFormat>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Export follow-up list'),
        content: Text(
          '${selected.length} selected vaccine reminder${selected.length == 1 ? '' : 's'} will be included.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.pop(dialogContext, _FollowUpExportFormat.csv),
            icon: const Icon(Icons.table_view_outlined),
            label: const Text('CSV'),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.pop(dialogContext, _FollowUpExportFormat.pdf),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF'),
          ),
        ],
      ),
    );
    if (format == null) return false;
    final fileStem =
        'vaccination_follow_up_${DateTime.now().toIso8601String().split('T').first}';
    if (format == _FollowUpExportFormat.pdf) {
      return Printing.layoutPdf(
        name: '$fileStem.pdf',
        onLayout: (_) => _buildFollowUpPdf(selected),
      );
    }
    final rows = <List<String>>[
      [
        'Reminder ID',
        'Guardian ID',
        'Guardian',
        'Mobile number',
        'Child',
        'Vaccine',
        'Dose',
        'Status',
        'Due date',
      ],
      for (final reminder in selected)
        [
          reminder.reminderCode,
          reminder.guardianCode ?? reminder.guardianId,
          reminder.guardianName ?? 'Not recorded',
          reminder.guardianPhone ?? 'Not provided',
          reminder.childName,
          reminder.vaccineName,
          reminder.doseNumber.toString(),
          _statusLabel(reminder.status),
          _date(reminder.dueDate),
        ],
    ];
    final csv = rows.map((row) => row.map(_csvCell).join(',')).join('\r\n');
    await SharePlus.instance.share(
      ShareParams(
        title: 'Vaccination Follow-up List',
        files: [
          XFile.fromData(
            Uint8List.fromList(utf8.encode('\uFEFF$csv')),
            mimeType: 'text/csv',
          ),
        ],
        fileNameOverrides: ['$fileStem.csv'],
      ),
    );
    return true;
  }

  Future<Uint8List> _buildFollowUpPdf(
    List<VaccinationReminder> reminders,
  ) async {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Vaccination Follow-up List',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Generated ${_dateTime(DateTime.now())} • ${reminders.length} vaccine reminders',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 10),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: const [
              'Guardian',
              'Guardian ID',
              'Mobile',
              'Child',
              'Vaccine / Dose',
              'Status',
              'Due date',
            ],
            data: reminders
                .map(
                  (reminder) => [
                    reminder.guardianName ?? 'Not recorded',
                    reminder.guardianCode ?? reminder.guardianId,
                    reminder.guardianPhone ?? 'Not provided',
                    reminder.childName,
                    '${reminder.vaccineName} Dose ${reminder.doseNumber}',
                    _statusLabel(reminder.status),
                    _date(reminder.dueDate),
                  ],
                )
                .toList(growable: false),
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.blueGrey800,
            ),
            cellStyle: const pw.TextStyle(fontSize: 7.5),
            cellPadding: const pw.EdgeInsets.all(4),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
          ),
        ],
      ),
    );
    return document.save();
  }

  static String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';

  Future<void> _chooseBatchAction() async {
    if (_batchSaving || _selectedIds.isEmpty) return;
    final choice = await Navigator.push<_BatchChoice>(
      context,
      MaterialPageRoute(
        builder: (sheetContext) => Scaffold(
          appBar: AppBar(title: const Text('Follow-up actions')),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 768),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '${_selectedIds.length} reminders selected. Choose an action to review before applying it.',
                        key: const ValueKey('batch-action-selection-summary'),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView(
                        key: const ValueKey('batch-action-options'),
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          const ListTile(
                            title: Text(
                              'Communication and assignment',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              'Perform these independently. Your selection stays available for another action.',
                            ),
                          ),
                          _BatchActionTile(
                            icon: Icons.sms_outlined,
                            title:
                                RepositoryRegistry.instance.environment.isLive
                                ? 'Send SMS reminders'
                                : 'Send mock SMS reminder',
                            onTap: () => Navigator.pop(
                              sheetContext,
                              _BatchChoice.mockSms,
                            ),
                          ),
                          _BatchActionTile(
                            icon: Icons.assignment_ind_outlined,
                            title: 'Assign to me',
                            onTap: () => Navigator.pop(
                              sheetContext,
                              _BatchChoice.assignToMe,
                            ),
                          ),
                          _BatchActionTile(
                            icon: Icons.print_outlined,
                            title: 'Export follow-up list',
                            onTap: () => Navigator.pop(
                              sheetContext,
                              _BatchChoice.printList,
                            ),
                          ),
                          const Divider(indent: 16, endIndent: 16),
                          const ListTile(
                            title: Text(
                              'Record a follow-up outcome',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              'Choose only the outcome that applies to every selected reminder after contact or review.',
                            ),
                          ),
                          _BatchActionTile(
                            icon: Icons.phone_missed_outlined,
                            title: 'Record no answer',
                            onTap: () => Navigator.pop(
                              sheetContext,
                              _BatchChoice.noAnswer,
                            ),
                          ),
                          _BatchActionTile(
                            icon: Icons.event_available_outlined,
                            title: 'Record visit scheduled',
                            onTap: () => Navigator.pop(
                              sheetContext,
                              _BatchChoice.visitScheduled,
                            ),
                          ),
                          _BatchActionTile(
                            icon: Icons.home_work_outlined,
                            title: 'Mark for home visit',
                            onTap: () => Navigator.pop(
                              sheetContext,
                              _BatchChoice.homeVisit,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: TextButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              child: const Text('Cancel'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final live = RepositoryRegistry.instance.environment.isLive;
    final title = switch (choice) {
      _BatchChoice.mockSms =>
        live ? 'Send SMS reminders' : 'Send mock SMS reminders',
      _BatchChoice.assignToMe => 'Assign follow-ups to me',
      _BatchChoice.printList => 'Export follow-up list',
      _BatchChoice.noAnswer => 'Record no answer',
      _BatchChoice.visitScheduled => 'Record visit scheduled',
      _BatchChoice.homeVisit => 'Mark for home visit',
    };
    final explanation = switch (choice) {
      _BatchChoice.mockSms =>
        live
            ? 'The selected vaccine reminders will be grouped into one SMS per guardian and child. Each message includes the child, vaccines, doses, statuses, and due dates. Acceptance confirms that the delivery request was submitted, not that it reached the phone. Select at most 20 vaccine reminders at a time.'
            : 'This simulates SMS delivery. No actual messages will be sent.',
      _BatchChoice.printList =>
        'Generate a PDF for printing or a CSV file from the selected database-backed reminders.',
      _BatchChoice.visitScheduled =>
        'Only record this if a visit has already been confirmed. This does not create or reschedule an appointment.',
      _BatchChoice.noAnswer =>
        'Only record this for guardians you attempted to contact without an answer.',
      _BatchChoice.homeVisit =>
        'Record that these follow-ups need a home visit. This does not book a visit date.',
      _BatchChoice.assignToMe =>
        'Assign these follow-ups to your signed-in account.',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(
            'Apply to ${_selectedIds.length} selected vaccine reminders?\n\n$explanation\n\nA separate follow-up history entry will be saved for each selected vaccine reminder for audit purposes.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm action'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _batchSaving) return;
    setState(() => _batchSaving = true);
    try {
      await _performBatchAction(choice);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.message(
              error,
              fallback:
                  'The action could not be confirmed. Check follow-up history before trying again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _batchSaving = false);
    }
  }

  Future<void> _scheduleAppointment(VaccinationReminder reminder) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentFormScreen.schedule(
          repository: _appointmentRepository,
          reminder: reminder,
        ),
      ),
    );
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appointment or waitlist entry saved.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.healthWorkerMode ? 'Follow-up Reminders' : 'Reminders',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: widget.healthWorkerMode
          ? const [WorkerAppBarActions()]
          : const [GuardianAppBarActions(showNotifications: false)],
    ),
    body: FutureBuilder<List<VaccinationReminder>>(
      future: _reminders,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoadingView(
            title: 'Loading reminders',
            message: 'Checking due, overdue, and upcoming vaccinations.',
          );
        }
        if (snapshot.hasError) {
          return _ErrorState(
            message: UserFacingError.message(
              snapshot.error!,
              fallback: 'The reminders could not be loaded. Please try again.',
            ),
            onRetry: () => setState(_reload),
          );
        }
        final reminders = (snapshot.data ?? const <VaccinationReminder>[])
            .where(
              (item) =>
                  (widget.childId == null || item.childId == widget.childId) &&
                  _isInActionableReminderWindow(item),
            )
            .toList();
        final visible = _filter == null
            ? reminders
            : reminders.where((item) => item.status == _filter).toList();
        final visibleGroups = _groupRemindersByChild(visible);
        final displayedGroups = widget.healthWorkerMode
            ? visibleGroups
            : visibleGroups
                  .take(_guardianVisibleChildLimit)
                  .toList(growable: false);
        final displayed = displayedGroups
            .expand((group) => group.reminders)
            .toList(growable: false);
        final hasMoreGuardianReminders =
            !widget.healthWorkerMode &&
            displayedGroups.length < visibleGroups.length;
        return Column(
          children: [
            if (widget.healthWorkerMode &&
                (visible.isNotEmpty || _selectedIds.isNotEmpty))
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                child: _BatchSelectionBar(
                  selectedCount: _selectedIds.length,
                  allSelected:
                      displayed.isNotEmpty &&
                      displayed.every((item) => _selectedIds.contains(item.id)),
                  onSelectAll: () => setState(() {
                    if (_batchSaving) return;
                    final ids = displayed.map((item) => item.id).toSet();
                    if (ids.every(_selectedIds.contains)) {
                      _selectedIds.removeAll(ids);
                    } else {
                      _selectedIds.addAll(ids);
                    }
                  }),
                  onAction: _selectedIds.isEmpty || _batchSaving
                      ? null
                      : _chooseBatchAction,
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => setState(_reload),
                child: ListView(
                  key: const PageStorageKey('vaccination-reminders-list'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
                  children: [
                    _ReminderIntro(healthWorkerMode: widget.healthWorkerMode),
                    if (widget.childId != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Showing reminders for ${reminders.isEmpty ? 'the selected child' : reminders.first.childName}.',
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (widget.healthWorkerMode)
                      FutureBuilder<ReminderSummary>(
                        future: _facilitySummary,
                        builder: (context, summarySnapshot) {
                          if (summarySnapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const LinearProgressIndicator();
                          }
                          if (summarySnapshot.hasError ||
                              !summarySnapshot.hasData) {
                            return _SummaryUnavailable(
                              onRetry: () => setState(() {
                                _facilitySummary = _repository
                                    .getFacilityFollowUpSummary();
                              }),
                            );
                          }
                          return _Summary(
                            summary: summarySnapshot.data!,
                            selectedStatus: _filter,
                            onSelected: _setFilter,
                          );
                        },
                      )
                    else
                      _Summary(
                        summary: ReminderSummary.fromItems(reminders),
                        selectedStatus: _filter,
                        onSelected: _setFilter,
                      ),
                    const SizedBox(height: 14),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('All'),
                            selected: _filter == null,
                            onSelected: (_) => _setFilter(null),
                          ),
                          const SizedBox(width: 8),
                          for (final status in _availableFilters(
                            reminders,
                          )) ...[
                            ChoiceChip(
                              label: Text(_statusLabel(status)),
                              selected: _filter == status,
                              onSelected: (_) => _setFilter(status),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (widget.healthWorkerMode && displayed.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'The New badge marks an unread reminder. Tap the arrow to review its details.',
                                style: TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!widget.healthWorkerMode &&
                        (_filter == null ||
                            _filter == VaccinationReminderStatus.upcoming))
                      FutureBuilder<List<AppointmentSlotOffer>>(
                        future: _slotOffers,
                        builder: (context, offerSnapshot) {
                          final offers = (offerSnapshot.data ?? const [])
                              .where(
                                (item) =>
                                    item.status ==
                                        AppointmentSlotOfferStatus.pending &&
                                    (widget.childId == null ||
                                        item.childId == widget.childId),
                              )
                              .toList(growable: false);
                          return Column(
                            children: [
                              for (final offer in offers)
                                _SlotOfferCard(
                                  offer: offer,
                                  onOpen: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            EarlierAppointmentOffersScreen(
                                              healthWorkerMode: false,
                                              guardianId: widget.guardianId,
                                              initialOfferId: offer.id,
                                              repository:
                                                  _appointmentRepository,
                                            ),
                                      ),
                                    );
                                    if (mounted) setState(_reload);
                                  },
                                ),
                            ],
                          );
                        },
                      ),
                    if (visible.isEmpty)
                      _EmptyState(healthWorkerMode: widget.healthWorkerMode)
                    else if (widget.healthWorkerMode)
                      ...displayedGroups.map(
                        (group) => _ChildReminderGroupCard(
                          group: group,
                          selected: group.reminders.every(
                            (item) => _selectedIds.contains(item.id),
                          ),
                          isRead: (item) =>
                              !item.hasUnreadNotification ||
                              _locallyReadIds.contains(item.id),
                          onSelected: (selected) => setState(() {
                            final ids = group.reminders
                                .map((item) => item.id)
                                .toSet();
                            if (selected) {
                              _selectedIds.addAll(ids);
                            } else {
                              _selectedIds.removeAll(ids);
                            }
                          }),
                          onOpen: _markRead,
                          historyLoader: (item) =>
                              _repository.getFollowUpHistory(item.id),
                          onSchedule: _scheduleAppointment,
                        ),
                      )
                    else
                      ...displayedGroups.map(
                        (group) => _GuardianChildReminderGroupCard(
                          group: group,
                          isRead: (item) =>
                              !item.hasUnreadNotification ||
                              _locallyReadIds.contains(item.id),
                          onOpen: _markRead,
                          onViewChild: () =>
                              _openChildDue(group.reminders.first),
                        ),
                      ),
                    if (widget.healthWorkerMode && _hasMoreFacilityReminders)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: OutlinedButton.icon(
                          onPressed: _loadingMoreFacilityReminders
                              ? null
                              : _loadMoreFacilityReminders,
                          icon: const Icon(Icons.expand_more_rounded),
                          label: Text(
                            _loadingMoreFacilityReminders
                                ? 'Loading…'
                                : 'Load 10 more',
                          ),
                        ),
                      ),
                    if (!widget.healthWorkerMode && hasMoreGuardianReminders)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              setState(() => _guardianVisibleChildLimit += 10),
                          icon: const Icon(Icons.expand_more_rounded),
                          label: const Text('Load 10 more'),
                        ),
                      ),
                    if (((widget.healthWorkerMode &&
                                !_hasMoreFacilityReminders) ||
                            (!widget.healthWorkerMode &&
                                !hasMoreGuardianReminders)) &&
                        displayed.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle_outline_rounded,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'All reminders loaded',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  List<VaccinationReminderStatus> _availableFilters(
    List<VaccinationReminder> reminders,
  ) => VaccinationReminderStatus.values
      .where(
        (status) =>
            status == _filter || reminders.any((item) => item.status == status),
      )
      .toList(growable: false);
}

class _ReminderIntro extends StatelessWidget {
  final bool healthWorkerMode;

  const _ReminderIntro({required this.healthWorkerMode});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          healthWorkerMode
              ? Icons.notification_important_outlined
              : Icons.notifications_active_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                healthWorkerMode
                    ? 'Children needing follow-up'
                    : 'Vaccination schedule reminders',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              Text(
                healthWorkerMode
                    ? 'Database reminder records are grouped into one card per child. Summary totals count vaccine doses.'
                    : 'Reminders are grouped into one card per child, with every applicable PNIP vaccine dose listed inside.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SlotOfferCard extends StatelessWidget {
  final AppointmentSlotOffer offer;
  final VoidCallback onOpen;
  const _SlotOfferCard({required this.offer, required this.onOpen});
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.all(16),
      leading: const Icon(Icons.event_available_outlined),
      title: Text(
        offer.childName,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${offer.vaccineName} • Earlier appointment available\nReview the offered time and response deadline',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onOpen,
    ),
  );
}

class _SummaryUnavailable extends StatelessWidget {
  final VoidCallback onRetry;

  const _SummaryUnavailable({required this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      children: [
        Icon(
          Icons.info_outline_rounded,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text('Total reminder counts are temporarily unavailable.'),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

class _Summary extends StatelessWidget {
  final ReminderSummary summary;
  final VaccinationReminderStatus? selectedStatus;
  final ValueChanged<VaccinationReminderStatus> onSelected;

  const _Summary({
    required this.summary,
    required this.selectedStatus,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryItem(
            '${summary.dueToday}',
            'Due today',
            StatusColors.due,
            selected: selectedStatus == VaccinationReminderStatus.dueToday,
            onTap: () => onSelected(VaccinationReminderStatus.dueToday),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryItem(
            '${summary.overdue}',
            'Overdue',
            StatusColors.overdue,
            selected: selectedStatus == VaccinationReminderStatus.overdue,
            onTap: () => onSelected(VaccinationReminderStatus.overdue),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryItem(
            '${summary.upcoming}',
            'Upcoming',
            StatusColors.upcoming,
            selected: selectedStatus == VaccinationReminderStatus.upcoming,
            onTap: () => onSelected(VaccinationReminderStatus.upcoming),
          ),
        ),
      ],
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _SummaryItem(
    this.value,
    this.label,
    this.color, {
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '$label reminders: $value',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
          decoration: BoxDecoration(
            color: color.withValues(alpha: selected ? 0.12 : 0.07),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: color.withValues(alpha: selected ? 0.5 : 0.18),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                child: Text(label, style: const TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ChildReminderGroup {
  final String childId;
  final String childName;
  final List<VaccinationReminder> reminders;

  const _ChildReminderGroup({
    required this.childId,
    required this.childName,
    required this.reminders,
  });
}

List<_ChildReminderGroup> _groupRemindersByChild(
  List<VaccinationReminder> reminders,
) {
  final grouped = <String, List<VaccinationReminder>>{};
  for (final reminder in reminders) {
    grouped.putIfAbsent(reminder.childId, () => []).add(reminder);
  }
  return grouped.entries
      .map(
        (entry) => _ChildReminderGroup(
          childId: entry.key,
          childName: entry.value.first.childName,
          reminders: List.unmodifiable(entry.value),
        ),
      )
      .toList(growable: false);
}

bool _isInActionableReminderWindow(VaccinationReminder reminder) {
  if (reminder.status != VaccinationReminderStatus.overdue &&
      reminder.status != VaccinationReminderStatus.dueToday &&
      reminder.status != VaccinationReminderStatus.upcoming) {
    return false;
  }
  final today = DateTime.now();
  final todayOnly = DateTime(today.year, today.month, today.day);
  final lastUpcomingDate = todayOnly.add(const Duration(days: 30));
  final dueDate = DateTime(
    reminder.dueDate.year,
    reminder.dueDate.month,
    reminder.dueDate.day,
  );
  return !dueDate.isAfter(lastUpcomingDate);
}

class _ChildReminderGroupCard extends StatelessWidget {
  final _ChildReminderGroup group;
  final bool selected;
  final bool Function(VaccinationReminder reminder) isRead;
  final ValueChanged<bool> onSelected;
  final ValueChanged<VaccinationReminder> onOpen;
  final Future<List<ReminderFollowUpRecord>> Function(
    VaccinationReminder reminder,
  )
  historyLoader;
  final ValueChanged<VaccinationReminder> onSchedule;

  const _ChildReminderGroupCard({
    required this.group,
    required this.selected,
    required this.isRead,
    required this.onSelected,
    required this.onOpen,
    required this.historyLoader,
    required this.onSchedule,
  });

  @override
  Widget build(BuildContext context) {
    int count(VaccinationReminderStatus status) =>
        group.reminders.where((item) => item.status == status).length;
    final overdue = count(VaccinationReminderStatus.overdue);
    final due = count(VaccinationReminderStatus.dueToday);
    final upcoming = count(VaccinationReminderStatus.upcoming);
    final unread = group.reminders.any((item) => !isRead(item));
    final color = overdue > 0
        ? StatusColors.overdue
        : due > 0
        ? StatusColors.due
        : StatusColors.upcoming;

    return Card(
      margin: const EdgeInsets.only(bottom: 11),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('child-reminders-${group.childId}'),
        maintainState: true,
        onExpansionChanged: (expanded) {
          if (!expanded) return;
          for (final reminder in group.reminders.where(
            (item) => !isRead(item),
          )) {
            onOpen(reminder);
          }
        },
        leading: Checkbox(
          value: selected,
          onChanged: (value) => onSelected(value ?? false),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                group.childName,
                style: TextStyle(
                  fontWeight: unread ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ),
            if (unread) const _NewBadge(),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            '${group.reminders.length} vaccine reminder(s)'
            '${overdue > 0 ? ' • $overdue overdue' : ''}'
            '${due > 0 ? ' • $due due today' : ''}'
            '${upcoming > 0 ? ' • $upcoming upcoming' : ''}',
            style: TextStyle(color: color),
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          const Divider(),
          for (final reminder in group.reminders)
            ExpansionTile(
              key: PageStorageKey('group-dose-${reminder.id}'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 12),
              onExpansionChanged: (expanded) {
                if (expanded && !isRead(reminder)) onOpen(reminder);
              },
              leading: Icon(
                _statusIcon(reminder.status),
                color: _statusColor(reminder.status),
              ),
              title: Text(
                '${reminder.vaccineName} Dose ${reminder.doseNumber}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${_statusLabel(reminder.status)} • ${_date(reminder.dueDate)}',
              ),
              children: [
                _Detail('PNIP due date', _date(reminder.dueDate)),
                _Detail('Status', _statusLabel(reminder.status)),
                _Detail('Channel', _channelLabel(reminder.channel)),
                _Detail('Reminder ID', reminder.reminderCode),
                const SizedBox(height: 8),
                _FollowUpHistory(loader: () => historyLoader(reminder)),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => onSchedule(reminder),
                    icon: const Icon(Icons.edit_calendar_outlined),
                    label: const Text('Schedule / Waitlist'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _GuardianChildReminderGroupCard extends StatelessWidget {
  final _ChildReminderGroup group;
  final bool Function(VaccinationReminder reminder) isRead;
  final ValueChanged<VaccinationReminder> onOpen;
  final VoidCallback onViewChild;

  const _GuardianChildReminderGroupCard({
    required this.group,
    required this.isRead,
    required this.onOpen,
    required this.onViewChild,
  });

  @override
  Widget build(BuildContext context) {
    int count(VaccinationReminderStatus status) =>
        group.reminders.where((item) => item.status == status).length;
    final overdue = count(VaccinationReminderStatus.overdue);
    final due = count(VaccinationReminderStatus.dueToday);
    final upcoming = count(VaccinationReminderStatus.upcoming);
    final unread = group.reminders.any((item) => !isRead(item));
    final color = overdue > 0
        ? StatusColors.overdue
        : due > 0
        ? StatusColors.due
        : StatusColors.upcoming;

    return Card(
      margin: const EdgeInsets.only(bottom: 11),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('guardian-child-reminders-${group.childId}'),
        maintainState: true,
        onExpansionChanged: (expanded) {
          if (!expanded) return;
          for (final reminder in group.reminders.where(
            (item) => !isRead(item),
          )) {
            onOpen(reminder);
          }
        },
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.10),
          child: Icon(Icons.vaccines_outlined, color: color),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                group.childName,
                style: TextStyle(
                  fontWeight: unread ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ),
            if (unread) const _NewBadge(),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            '${group.reminders.length} vaccine reminder(s)'
            '${overdue > 0 ? ' • $overdue overdue' : ''}'
            '${due > 0 ? ' • $due due today' : ''}'
            '${upcoming > 0 ? ' • $upcoming upcoming' : ''}',
            style: TextStyle(color: color),
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          const Divider(),
          for (final reminder in group.reminders)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _statusIcon(reminder.status),
                color: _statusColor(reminder.status),
              ),
              title: Text(
                '${reminder.vaccineName} Dose ${reminder.doseNumber}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${_statusLabel(reminder.status)} • ${_date(reminder.dueDate)}',
              ),
              onTap: onViewChild,
            ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onViewChild,
              icon: const Icon(Icons.child_care_outlined),
              label: const Text('View vaccination schedule'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  final VaccinationReminder reminder;
  final bool isRead;
  final bool healthWorkerMode;
  final VoidCallback onOpen;
  final VoidCallback? onViewChild;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final Future<List<ReminderFollowUpRecord>> Function()? historyLoader;
  final VoidCallback? onSchedule;

  const _ReminderCard({
    required this.reminder,
    required this.isRead,
    required this.healthWorkerMode,
    required this.onOpen,
    this.onViewChild,
    required this.selected,
    this.onSelected,
    this.historyLoader,
    this.onSchedule,
  });

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(reminder.status);
    if (!healthWorkerMode) {
      return Card(
        margin: const EdgeInsets.only(bottom: 11),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onViewChild,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.10),
            child: Icon(_statusIcon(reminder.status), color: color),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  reminder.childName,
                  style: TextStyle(
                    fontWeight: isRead ? FontWeight.w700 : FontWeight.w900,
                  ),
                ),
              ),
              if (!isRead) const _NewBadge(),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              '${reminder.vaccineName} Dose ${reminder.doseNumber}\n'
              '${_statusLabel(reminder.status)} • ${_date(reminder.dueDate)}',
            ),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 11),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey<String>('reminder-${reminder.id}'),
        maintainState: true,
        onExpansionChanged: (expanded) {
          if (expanded) onOpen();
        },
        leading: Checkbox(
          value: selected,
          onChanged: (value) => onSelected?.call(value ?? false),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                reminder.childName,
                style: TextStyle(
                  fontWeight: isRead ? FontWeight.w700 : FontWeight.w900,
                ),
              ),
            ),
            if (!isRead) const _NewBadge(),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${reminder.vaccineName} Dose ${reminder.doseNumber}\n'
            '${_statusLabel(reminder.status)} • ${_date(reminder.dueDate)}',
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Divider(),
          _Detail('Child ID', reminder.childId),
          _Detail(
            'Vaccine',
            '${reminder.vaccineName} Dose ${reminder.doseNumber}',
          ),
          _Detail('PNIP due date', _date(reminder.dueDate)),
          _Detail('Status', _statusLabel(reminder.status)),
          _Detail('Channel', _channelLabel(reminder.channel)),
          _Detail('Reminder ID', reminder.reminderCode),
          if (healthWorkerMode) ...[
            const SizedBox(height: 10),
            _FollowUpHistory(loader: historyLoader!),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onSchedule,
                icon: const Icon(Icons.edit_calendar_outlined),
                label: const Text('Schedule / Waitlist'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFFE8F1FC),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      'New',
      style: const TextStyle(
        color: Color(0xFF185A9D),
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _FollowUpHistory extends StatelessWidget {
  final Future<List<ReminderFollowUpRecord>> Function() loader;

  const _FollowUpHistory({required this.loader});

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<ReminderFollowUpRecord>>(
    future: loader(),
    builder: (context, snapshot) {
      final records = snapshot.data ?? const [];
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const LinearProgressIndicator();
      }
      if (records.isEmpty) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'No follow-up attempt recorded yet. Select this reminder and use Batch action.',
            style: TextStyle(fontSize: 12.5),
          ),
        );
      }
      final latest = records.first;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Latest follow-up',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(_outcomeLabel(latest.outcome)),
            Text(
              '${_dateTime(latest.performedAt)} • ${latest.followUpCode}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11.5,
              ),
            ),
            if (records.length > 1)
              Text(
                '${records.length} attempts recorded',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11.5,
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _BatchSelectionBar extends StatelessWidget {
  final int selectedCount;
  final bool allSelected;
  final VoidCallback onSelectAll;
  final VoidCallback? onAction;

  const _BatchSelectionBar({
    required this.selectedCount,
    required this.allSelected,
    required this.onSelectAll,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final selection = Row(
          children: [
            Checkbox(value: allSelected, onChanged: (_) => onSelectAll()),
            Expanded(
              child: Text(
                selectedCount == 0
                    ? 'Select visible reminders'
                    : '$selectedCount selected',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
        final action = FilledButton.icon(
          onPressed: onAction,
          icon: const Icon(Icons.playlist_add_check_rounded, size: 19),
          label: const Text('Batch action'),
        );
        if (constraints.maxWidth < 340 ||
            MediaQuery.textScalerOf(context).scale(14) > 20) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [selection, const SizedBox(height: 8), action],
          );
        }
        return Row(
          children: [
            Expanded(child: selection),
            const SizedBox(width: 8),
            action,
          ],
        );
      },
    ),
  );
}

class _BatchActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _BatchActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
    title: Text(title),
    onTap: onTap,
  );
}

enum _BatchChoice {
  mockSms,
  assignToMe,
  printList,
  noAnswer,
  visitScheduled,
  homeVisit,
}

enum _FollowUpExportFormat { pdf, csv }

class _Detail extends StatelessWidget {
  final String label;
  final String value;

  const _Detail(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 105,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final bool healthWorkerMode;

  const _EmptyState({required this.healthWorkerMode});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    alignment: Alignment.center,
    child: Column(
      children: [
        Icon(
          Icons.notifications_none_rounded,
          size: 42,
          color: Colors.grey.shade400,
        ),
        const SizedBox(height: 10),
        Text(
          healthWorkerMode
              ? 'No children currently need follow-up.'
              : 'No reminders in this category.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 42),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

String _statusLabel(VaccinationReminderStatus status) => switch (status) {
  VaccinationReminderStatus.upcoming => 'Upcoming',
  VaccinationReminderStatus.dueToday => 'Due today',
  VaccinationReminderStatus.overdue => 'Overdue',
  VaccinationReminderStatus.completed => 'Completed',
  VaccinationReminderStatus.dismissed => 'Dismissed',
};

Color _statusColor(VaccinationReminderStatus status) => switch (status) {
  VaccinationReminderStatus.upcoming => StatusColors.upcoming,
  VaccinationReminderStatus.dueToday => StatusColors.due,
  VaccinationReminderStatus.overdue => StatusColors.overdue,
  VaccinationReminderStatus.completed => StatusColors.completed,
  VaccinationReminderStatus.dismissed => Colors.grey,
};

IconData _statusIcon(VaccinationReminderStatus status) => switch (status) {
  VaccinationReminderStatus.upcoming => Icons.event_outlined,
  VaccinationReminderStatus.dueToday => Icons.today_outlined,
  VaccinationReminderStatus.overdue => Icons.notification_important_outlined,
  VaccinationReminderStatus.completed => Icons.check_circle_outline,
  VaccinationReminderStatus.dismissed => Icons.notifications_off_outlined,
};

String _channelLabel(VaccinationReminderChannel channel) => switch (channel) {
  VaccinationReminderChannel.inApp => 'In-app notification',
  VaccinationReminderChannel.sms => 'SMS',
  VaccinationReminderChannel.email => 'Email',
  VaccinationReminderChannel.printedFollowUp => 'Printed follow-up list',
};

String _outcomeLabel(ReminderFollowUpOutcome outcome) => switch (outcome) {
  ReminderFollowUpOutcome.reminderSent => 'Mock reminder sent',
  ReminderFollowUpOutcome.providerAccepted => 'SMS request accepted',
  ReminderFollowUpOutcome.deliveryFailed => 'SMS delivery failed or uncertain',
  ReminderFollowUpOutcome.assigned => 'Assigned to a health worker',
  ReminderFollowUpOutcome.contacted => 'Guardian contacted',
  ReminderFollowUpOutcome.noAnswer => 'No answer',
  ReminderFollowUpOutcome.invalidContact => 'Invalid contact information',
  ReminderFollowUpOutcome.visitScheduled => 'Follow-up visit scheduled',
  ReminderFollowUpOutcome.declined => 'Guardian declined',
  ReminderFollowUpOutcome.homeVisitRequired => 'Home visit required',
  ReminderFollowUpOutcome.printed => 'Included in printed follow-up list',
};

String _date(DateTime value) =>
    '${value.month.toString().padLeft(2, '0')}/'
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.year}';

String _dateTime(DateTime value) =>
    '${_date(value)} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';
