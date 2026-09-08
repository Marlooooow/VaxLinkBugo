import 'dart:async';

import 'package:flutter/material.dart';

import '../models/person_name.dart';
import '../models/staff_member.dart';
import '../repositories/repository_registry.dart';
import '../repositories/staff_repository.dart';
import '../utils/user_facing_error.dart';
import '../widgets/app_loading.dart';

class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  static const _pageSize = 20;
  late final StaffRepository _repository =
      RepositoryRegistry.instance.staffRepository;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<StaffMember> _staff = [];
  Object? _error;
  int _totalCount = 0;
  int _nextOffset = 0;
  int _requestVersion = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _loadFirstPage);
    setState(() {});
  }

  Future<void> _loadFirstPage() async {
    final version = ++_requestVersion;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _staff = [];
      _totalCount = 0;
      _nextOffset = 0;
      _hasMore = false;
    });
    try {
      final page = await _repository.getStaffMembersPage(
        query: _searchController.text,
        limit: _pageSize,
      );
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _staff = page.items;
        _totalCount = page.totalCount;
        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadNextPage() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final version = _requestVersion;
    setState(() => _loadingMore = true);
    try {
      final page = await _repository.getStaffMembersPage(
        query: _searchController.text,
        limit: _pageSize,
        offset: _nextOffset,
      );
      if (!mounted || version != _requestVersion) return;
      setState(() {
        final ids = _staff.map((item) => item.id).toSet();
        _staff.addAll(page.items.where((item) => ids.add(item.id)));
        _totalCount = page.totalCount;
        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _error = error;
        _loadingMore = false;
      });
    }
  }

  Future<void> _addStaff() async {
    final result = await showModalBottomSheet<StaffInvitationResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _StaffRegistrationSheet(repository: _repository),
    );
    if (result == null || !mounted) return;
    await _loadFirstPage();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.mark_email_read_rounded, size: 42),
        title: const Text('Staff invitation created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${result.staff.fullName} was added as ${result.staff.typeLabel}.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            const Text('One-time activation code'),
            const SizedBox(height: 6),
            SelectableText(
              result.activationCode,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Give this code privately to the staff member. The code is not stored in plain text.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _openStaff(StaffMember staff) async {
    final canChange = staff.status != StaffAccessStatus.invitationPending;
    final next = staff.status == StaffAccessStatus.active
        ? StaffAccessStatus.disabled
        : StaffAccessStatus.active;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              staff.fullName,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text('${staff.staffCode} • ${staff.typeLabel}'),
            Text('Status: ${staff.statusLabel}'),
            if (staff.phone != null) Text('Mobile: ${staff.phone}'),
            if (staff.email != null) Text('Email: ${staff.email}'),
            if (staff.licenseNumber != null)
              Text('License: ${staff.licenseNumber}'),
            const SizedBox(height: 18),
            if (canChange)
              FilledButton.icon(
                onPressed: () => Navigator.pop(sheetContext, true),
                icon: Icon(
                  next == StaffAccessStatus.disabled
                      ? Icons.person_off_outlined
                      : Icons.person_outline_rounded,
                ),
                label: Text(
                  next == StaffAccessStatus.disabled
                      ? 'Disable account'
                      : 'Reactivate account',
                ),
              )
            else
              const Text(
                'The staff member must activate the invitation before account status can be changed.',
              ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await runWithAppLoading(
        context,
        title: next == StaffAccessStatus.disabled
            ? 'Disabling account'
            : 'Reactivating account',
        message: 'Updating staff access and recording the audit entry.',
        operation: () => _repository.setStaffStatus(staff.id, next),
      );
      if (!mounted) return;
      await _loadFirstPage();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next == StaffAccessStatus.disabled
                ? 'Staff account disabled.'
                : 'Staff account reactivated.',
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
              fallback: 'Staff account status could not be updated.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Staff Management',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _addStaff,
      icon: const Icon(Icons.person_add_alt_1_rounded),
      label: const Text('Add staff'),
    ),
    body: _loading
        ? const AppLoadingView(
            title: 'Loading staff',
            message: 'Checking staff records and activation status.',
          )
        : _error != null && _staff.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Staff records could not be loaded.'),
                  TextButton(
                    onPressed: _loadFirstPage,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
            children: [
              Text(
                'Only administrators can add staff. Every invitation and activation is recorded in the facility audit trail.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                onChanged: (_) => _onSearchChanged(),
                decoration: InputDecoration(
                  hintText: 'Search staff name, ID, phone, or email',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            _loadFirstPage();
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Text('Showing ${_staff.length} of $_totalCount staff member(s)'),
              const SizedBox(height: 8),
              if (_staff.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No staff members have been added yet.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                for (final staff in _staff)
                  Card(
                    child: ListTile(
                      onTap: () => _openStaff(staff),
                      leading: const CircleAvatar(
                        child: Icon(Icons.medical_services_outlined),
                      ),
                      title: Text(
                        staff.fullName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${staff.staffCode} • ${staff.typeLabel}\n${staff.statusLabel}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right_rounded),
                    ),
                  ),
              if (_hasMore)
                OutlinedButton.icon(
                  onPressed: _loadingMore ? null : _loadNextPage,
                  icon: _loadingMore
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more_rounded),
                  label: Text(_loadingMore ? 'Loading…' : 'Load 20 more'),
                )
              else if (_staff.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'All matching staff members are displayed.',
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
  );
}

class _StaffRegistrationSheet extends StatefulWidget {
  final StaffRepository repository;
  const _StaffRegistrationSheet({required this.repository});

  @override
  State<_StaffRegistrationSheet> createState() =>
      _StaffRegistrationSheetState();
}

class _StaffRegistrationSheetState extends State<_StaffRegistrationSheet> {
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _middle = TextEditingController();
  final _last = TextEditingController();
  final _suffix = TextEditingController();
  final _license = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  StaffType _type = StaffType.nurse;
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in [
      _first,
      _middle,
      _last,
      _suffix,
      _license,
      _phone,
      _email,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final result = await widget.repository.registerStaff(
        StaffRegistrationRequest(
          name: PersonName(
            firstName: _first.text,
            middleName: _middle.text,
            lastName: _last.text,
            suffix: _suffix.text,
          ),
          staffType: _type,
          licenseNumber: _license.text,
          phone: _phone.text,
          email: _email.text,
        ),
      );
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.message(
              error,
              fallback: 'The staff invitation could not be created.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      16,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Form(
      key: _formKey,
      child: ListView(
        shrinkWrap: true,
        children: [
          const Text(
            'Add nurse or health worker',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _nameField(_first, 'First name', true)),
              const SizedBox(width: 10),
              Expanded(child: _nameField(_last, 'Last name', true)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _nameField(_middle, 'Middle name/initial', false),
              ),
              const SizedBox(width: 10),
              SizedBox(width: 100, child: _nameField(_suffix, 'Suffix', false)),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<StaffType>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Staff type'),
            items: StaffType.values
                .map(
                  (type) =>
                      DropdownMenuItem(value: type, child: Text(type.label)),
                )
                .toList(),
            onChanged: (value) => setState(() => _type = value!),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _license,
            decoration: const InputDecoration(
              labelText: 'License number (optional)',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone (optional)'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email (optional)'),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: const Icon(Icons.mark_email_read_outlined),
            label: Text(_saving ? 'Creating invitation…' : 'Create invitation'),
          ),
        ],
      ),
    ),
  );

  TextFormField _nameField(
    TextEditingController controller,
    String label,
    bool required,
  ) => TextFormField(
    controller: controller,
    textCapitalization: TextCapitalization.words,
    decoration: InputDecoration(labelText: label),
    validator: required
        ? (value) => value == null || value.trim().isEmpty ? 'Required' : null
        : null,
  );
}
