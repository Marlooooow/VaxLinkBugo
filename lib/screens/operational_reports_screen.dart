import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/child/child_profile.dart';
import '../models/operational_report.dart';
import '../repositories/child_repository.dart';
import '../repositories/operational_report_repository.dart';
import '../repositories/repository_registry.dart';
import '../utils/user_facing_error.dart';
import '../widgets/app_loading.dart';
import '../widgets/worker_app_bar_actions.dart';

class OperationalReportsScreen extends StatefulWidget {
  final OperationalReportRepository? repository;
  final ChildRepository? childRepository;

  const OperationalReportsScreen({
    super.key,
    this.repository,
    this.childRepository,
  });

  @override
  State<OperationalReportsScreen> createState() =>
      _OperationalReportsScreenState();
}

class _OperationalReportsScreenState extends State<OperationalReportsScreen> {
  late final OperationalReportRepository _repository;
  late final ChildRepository _childRepository;
  late DateTimeRange _period;
  OperationalReportType _type = OperationalReportType.followUps;
  OperationalReport? _report;
  ChildProfile? _selectedChild;
  bool _loading = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ??
        RepositoryRegistry.instance.operationalReportRepository;
    _childRepository =
        widget.childRepository ?? RepositoryRegistry.instance.childRepository;
    final today = _day(DateTime.now());
    _period = DateTimeRange(
      start: DateTime(today.year, today.month),
      end: today,
    );
  }

  Future<void> _choosePeriod() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 366)),
      initialDateRange: _period,
      helpText: 'Select report period',
    );
    if (selected == null || !mounted) return;
    if (selected.duration.inDays > 366) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a period of 366 days or less.')),
      );
      return;
    }
    setState(() {
      _period = selected;
      _report = null;
    });
  }

  Future<void> _generate() async {
    if (_loading) return;
    if (_type == OperationalReportType.childVaccinationRecord &&
        _selectedChild == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a child first.')));
      return;
    }
    setState(() {
      _loading = true;
      _report = null;
    });
    try {
      final report = await _repository.generate(
        type: _type,
        fromDate: _period.start,
        toDate: _period.end,
        childId: _selectedChild?.id,
      );
      if (mounted) setState(() => _report = report);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.message(
              error,
              fallback: 'The report could not be generated. Please try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseChild() async {
    final selected = await showDialog<ChildProfile>(
      context: context,
      builder: (_) => _ChildReportPicker(repository: _childRepository),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedChild = selected;
      _report = null;
    });
  }

  Future<Uint8List> _buildPdf(OperationalReport report, PdfPageFormat _) async {
    final document = pw.Document();
    final pageFormat = report.columns.length > 9
        ? PdfPageFormat.a3.landscape
        : report.columns.length > 6
        ? PdfPageFormat.a4.landscape
        : PdfPageFormat.a4;
    document.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              report.title,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 3),
            pw.Text(report.facilityName),
            pw.Text(
              'Period: ${_date(report.fromDate)} to ${_date(report.toDate)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 10),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Generated ${_dateTime(report.generatedAt)} • Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ),
        build: (_) => [
          if (report.rows.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 20),
              child: pw.Text('No records found for this report.'),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: report.columns.map((column) => column.label).toList(),
              data: report.rows
                  .map(
                    (row) => report.columns
                        .map((column) => _value(row[column.key]))
                        .toList(),
                  )
                  .toList(),
              headerStyle: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blueGrey800,
              ),
              cellStyle: const pw.TextStyle(fontSize: 7),
              cellPadding: const pw.EdgeInsets.all(4),
              border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
            ),
        ],
      ),
    );
    return document.save();
  }

  Future<void> _printPdf() async {
    final report = _report;
    if (report == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      await Printing.layoutPdf(
        name: '${_fileStem(report)}.pdf',
        onLayout: (format) => _buildPdf(report, format),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportCsv() async {
    final report = _report;
    if (report == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      final rows = <List<String>>[
        report.columns.map((column) => column.label).toList(),
        ...report.rows.map(
          (row) =>
              report.columns.map((column) => _value(row[column.key])).toList(),
        ),
      ];
      final csv = rows.map((row) => row.map(_csvCell).join(',')).join('\r\n');
      await SharePlus.instance.share(
        ShareParams(
          title: report.title,
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode('\uFEFF$csv')),
              mimeType: 'text/csv',
            ),
          ],
          fileNameOverrides: ['${_fileStem(report)}.csv'],
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Operational Reports',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: const [WorkerAppBarActions()],
    ),
    body: _loading
        ? const AppLoadingView(
            title: 'Generating report',
            message: 'Retrieving and summarizing live facility records.',
          )
        : RefreshIndicator(
            onRefresh: _generate,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
              children: [
                _ReportIntro(type: _type),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _reportChoice(
                      OperationalReportType.followUps,
                      'Follow-ups',
                      Icons.notification_important_outlined,
                    ),
                    _reportChoice(
                      OperationalReportType.vaccinationAccomplishment,
                      'Vaccinations',
                      Icons.vaccines_outlined,
                    ),
                    _reportChoice(
                      OperationalReportType.inventory,
                      'Inventory',
                      Icons.inventory_2_outlined,
                    ),
                    _reportChoice(
                      OperationalReportType.outreachSessions,
                      'Outreach',
                      Icons.groups_2_outlined,
                    ),
                    _reportChoice(
                      OperationalReportType.childVaccinationRecord,
                      'Child record',
                      Icons.child_care_outlined,
                    ),
                    _reportChoice(
                      OperationalReportType.inventoryTransactions,
                      'Stock transactions',
                      Icons.receipt_long_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_type == OperationalReportType.childVaccinationRecord) ...[
                  OutlinedButton.icon(
                    onPressed: _chooseChild,
                    icon: const Icon(Icons.person_search_outlined),
                    label: Text(
                      _selectedChild == null
                          ? 'Select child'
                          : _selectedChild!.fullName,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (_type != OperationalReportType.childVaccinationRecord)
                  OutlinedButton.icon(
                    onPressed: _choosePeriod,
                    icon: const Icon(Icons.date_range_outlined),
                    label: Text(
                      '${_date(_period.start)} – ${_date(_period.end)}',
                    ),
                  )
                else
                  Text(
                    'The child report includes the complete recorded vaccination history.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                if (_type == OperationalReportType.followUps) ...[
                  const SizedBox(height: 8),
                  Text(
                    'The end date is the report’s “as of” date. All unresolved overdue doses through that date are included.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _generate,
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('Generate report'),
                ),
                if (_report case final report?) ...[
                  const SizedBox(height: 22),
                  _ReportPreview(report: report),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _exporting ? null : _exportCsv,
                          icon: const Icon(Icons.table_view_outlined),
                          label: const Text('Export CSV'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _exporting ? null : _printPdf,
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('Print / Save PDF'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
  );

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  Widget _reportChoice(
    OperationalReportType value,
    String label,
    IconData icon,
  ) => ChoiceChip(
    avatar: Icon(icon, size: 18),
    label: Text(label),
    selected: _type == value,
    onSelected: (_) => setState(() {
      _type = value;
      _report = null;
    }),
  );

  static String _date(DateTime value) =>
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.day.toString().padLeft(2, '0')}/${value.year}';

  static String _dateTime(DateTime value) =>
      '${_date(value.toLocal())} '
      '${value.toLocal().hour.toString().padLeft(2, '0')}:'
      '${value.toLocal().minute.toString().padLeft(2, '0')}';

  static String _value(Object? value) => value?.toString() ?? '';

  static String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';

  static String _fileStem(OperationalReport report) =>
      '${report.type.name}_${report.toDate.year}'
      '${report.toDate.month.toString().padLeft(2, '0')}'
      '${report.toDate.day.toString().padLeft(2, '0')}';
}

class _ReportIntro extends StatelessWidget {
  final OperationalReportType type;

  const _ReportIntro({required this.type});

  @override
  Widget build(BuildContext context) {
    final description = switch (type) {
      OperationalReportType.followUps =>
        'One row per child, with all due-today and overdue vaccine doses grouped together.',
      OperationalReportType.vaccinationAccomplishment =>
        'Administered doses summarized by vaccine, dose number, and record source.',
      OperationalReportType.inventory =>
        'Current usable stock with low-stock, expiry, and period wastage indicators.',
      OperationalReportType.outreachSessions =>
        'Outreach sessions with vaccination coverage, batch allocation, and dose reconciliation details.',
      OperationalReportType.childVaccinationRecord =>
        'A selected child’s database-recorded vaccination history for verification or printing.',
      OperationalReportType.inventoryTransactions =>
        'A dated audit trail of received, adjusted, administered, and wasted vaccine stock.',
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.description_outlined),
          const SizedBox(width: 12),
          Expanded(child: Text(description)),
        ],
      ),
    );
  }
}

class _ReportPreview extends StatelessWidget {
  final OperationalReport report;

  const _ReportPreview({required this.report});

  @override
  Widget build(BuildContext context) {
    final previewRows = report.rows.take(50).toList(growable: false);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              report.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text('${report.facilityName} • ${report.rows.length} row(s)'),
            const SizedBox(height: 14),
            if (report.rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('No records found for this report.')),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: report.columns
                      .map((column) => DataColumn(label: Text(column.label)))
                      .toList(),
                  rows: previewRows
                      .map(
                        (row) => DataRow(
                          cells: report.columns
                              .map(
                                (column) => DataCell(
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 260,
                                    ),
                                    child: Text(
                                      _OperationalReportsScreenState._value(
                                        row[column.key],
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      )
                      .toList(),
                ),
              ),
            if (report.rows.length > previewRows.length) ...[
              const SizedBox(height: 8),
              Text(
                'Previewing the first 50 rows. PDF and CSV include all rows.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChildReportPicker extends StatefulWidget {
  final ChildRepository repository;

  const _ChildReportPicker({required this.repository});

  @override
  State<_ChildReportPicker> createState() => _ChildReportPickerState();
}

class _ChildReportPickerState extends State<_ChildReportPicker> {
  final _searchController = TextEditingController();
  late Future<RegisteredFamilyPage> _families;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search() {
    setState(() {
      _families = widget.repository.getHealthWorkerRegisteredFamiliesPage(
        search: _searchController.text,
        pageSize: 50,
      );
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Select child'),
    content: SizedBox(
      width: 520,
      height: 480,
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Child name or Child ID',
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: _search,
                icon: const Icon(Icons.search_rounded),
              ),
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<RegisteredFamilyPage>(
              future: _families,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Children could not be loaded.'),
                        TextButton(
                          onPressed: _search,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                final families = snapshot.data?.items ?? const [];
                final choices = [
                  for (final summary in families)
                    for (final child in summary.family.children)
                      (
                        child: child,
                        guardian: summary.family.guardian.fullName,
                      ),
                ];
                if (choices.isEmpty) {
                  return const Center(
                    child: Text('No matching children found.'),
                  );
                }
                return ListView.separated(
                  itemCount: choices.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final choice = choices[index];
                    return ListTile(
                      leading: const Icon(Icons.child_care_outlined),
                      title: Text(choice.child.fullName),
                      subtitle: Text(
                        '${choice.child.qrIdentifier}\nGuardian: ${choice.guardian}',
                      ),
                      isThreeLine: true,
                      onTap: () => Navigator.pop(context, choice.child),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}
