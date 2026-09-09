import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:ui' as ui;

import '../models/child/child_profile.dart';
import '../models/referral.dart';
import '../repositories/repository_registry.dart';
import 'child_profile_screen.dart';
import 'referral_group_details_screen.dart';
import 'referral_history_screen.dart';

String _verificationToken(List<Referral> referrals) {
  final token = referrals.first.verificationToken?.trim() ?? '';
  if (token.isEmpty) {
    throw StateError(
      'This referral no longer contains its one-time QR verification token. '
      'Generate a new referral before printing or sharing a QR code.',
    );
  }
  return token;
}

class ReferralQrScreen extends StatefulWidget {
  final List<Referral> referrals;
  final ChildProfile child;

  const ReferralQrScreen({
    super.key,
    required this.referrals,
    required this.child,
  });

  @override
  State<ReferralQrScreen> createState() => _ReferralQrScreenState();
}

class _ReferralQrScreenState extends State<ReferralQrScreen> {
  final _printViewKey = GlobalKey<_PrintableReferralViewState>();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _QrDisplayView(
          referrals: widget.referrals,
          childProfile: widget.child,
          onPrint: () {
            _printViewKey.currentState?._printReferral();
          },
        ),
        Offstage(
          offstage: true,
          child: _PrintableReferralView(
            key: _printViewKey,
            referrals: widget.referrals,
            onBack: () {},
          ),
        ),
      ],
    );
  }
}

// ==========================================================================
// QR DISPLAY VIEW
// ==========================================================================

class _QrDisplayView extends StatelessWidget {
  final List<Referral> referrals;
  final ChildProfile childProfile;
  final VoidCallback onPrint;

  const _QrDisplayView({
    required this.referrals,
    required this.childProfile,
    required this.onPrint,
  });

  String _buildQrData() {
    final groupId = referrals.first.referralGroupId;
    final data = {
      'type': 'vaccination_referral',
      'version': 1,
      'referral_group_id': groupId,
      'referral_group_code': referrals.first.referralGroupCode,
      'verification_token': _verificationToken(referrals),
    };

    return jsonEncode(data);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    if (referrals.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Referral QR',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: const Center(child: Text('No referral information available.')),
      );
    }

    if ((referrals.first.verificationToken?.trim() ?? '').isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Referral QR',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'The secure QR token is available only when the referral is '
              'created. Generate a new referral to display or print its QR code.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final child = referrals.first;

    final vaccineNames = referrals
        .map(
          (referral) => '${referral.vaccineName} Dose ${referral.doseNumber}',
        )
        .join(', ');

    final referralIds = referrals
        .map((referral) => referral.referralId)
        .join(', ');

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'View Referral QR',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          child: Column(
            children: [
              const SizedBox(height: 10),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      color: Colors.green,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Referral created successfully',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                'Vaccination Referral',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),

              const SizedBox(height: 7),

              Text(
                referrals.length == 1
                    ? 'Present this QR code to the receiving health facility.'
                    : 'This QR code contains the referral information for all unavailable vaccines.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 28),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    QrImageView(
                      data: _buildQrData(),
                      version: QrVersions.auto,
                      size: 230,
                      backgroundColor: Colors.white,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      referrals.length == 1
                          ? referrals.first.referralId
                          : '${referrals.length} Vaccine Referrals',
                      style: TextStyle(
                        color: primary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              _InfoCard(
                title: 'Child',
                value: child.childName,
                icon: Icons.child_care_rounded,
                primary: primary,
              ),

              const SizedBox(height: 10),

              _VaccineListCard(referrals: referrals, primary: primary),

              const SizedBox(height: 10),

              _InfoCard(
                title: 'Originating Facility',
                value: child.originatingFacility,
                icon: Icons.local_hospital_outlined,
                primary: primary,
              ),

              const SizedBox(height: 10),

              _InfoCard(
                title: 'Referral ID(s)',
                value: referralIds,
                icon: Icons.confirmation_number_outlined,
                primary: primary,
              ),

              const SizedBox(height: 24),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        referrals.length == 1
                            ? 'This QR identifies the vaccination referral for $vaccineNames. The receiving facility can use the referral information to verify the requested vaccine.'
                            : 'This QR contains the referral information for $vaccineNames. The receiving facility can use the QR to verify the requested vaccines.',
                        style: const TextStyle(fontSize: 12.5, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: onPrint,
                  icon: const Icon(Icons.print_rounded),
                  label: const Text('Print referral'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReferralGroupDetailsScreen(
                        referrals: referrals,
                        repository:
                            RepositoryRegistry.instance.referralRepository,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('View referral details'),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReferralHistoryScreen(
                            repository:
                                RepositoryRegistry.instance.referralRepository,
                          ),
                        ),
                      ),
                      child: const Text('Referral history'),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChildProfileScreen(
                            child: childProfile,
                            initialSection: ChildProfileSection.upcoming,
                            repository: RepositoryRegistry
                                .instance
                                .vaccinationRepository,
                          ),
                        ),
                      ),
                      child: const Text('Child profile'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================================================
// PRINTABLE REFERRAL VIEW
// ==========================================================================

class _PrintableReferralView extends StatefulWidget {
  final List<Referral> referrals;
  final VoidCallback onBack;

  const _PrintableReferralView({
    super.key,
    required this.referrals,
    required this.onBack,
  });

  @override
  State<_PrintableReferralView> createState() => _PrintableReferralViewState();
}

class _PrintableReferralViewState extends State<_PrintableReferralView> {
  String _buildQrData() {
    final groupId = widget.referrals.first.referralGroupId;
    final data = {
      'type': 'vaccination_referral',
      'version': 1,
      'referral_group_id': groupId,
      'referral_group_code': widget.referrals.first.referralGroupCode,
      'verification_token': _verificationToken(widget.referrals),
    };

    return jsonEncode(data);
  }

  String _formatDate(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${months[date.month - 1]} '
        '${date.day}, '
        '${date.year}';
  }

  Future<void> _printReferral() async {
    if (widget.referrals.isEmpty) {
      return;
    }

    try {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async {
          return _buildPdf();
        },
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to print referral: $e')));
    }
  }

  Future<Uint8List> _buildPdf() async {
    final pdf = pw.Document();

    final child = widget.referrals.first;

    final vaccineNames = widget.referrals
        .map(
          (referral) => '${referral.vaccineName} Dose ${referral.doseNumber}',
        )
        .join(', ');

    final referralIds = widget.referrals
        .map((referral) => referral.referralId)
        .join(', ');

    final qrImage = await _buildQrImage();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // HEADER
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'VACCINATION REFERRAL',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      'Date Issued: ${_formatDate(child.createdAt)}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 10),
              pw.Divider(),
              pw.SizedBox(height: 8),

              _pdfSectionTitle('CHILD INFORMATION'),

              pw.SizedBox(height: 10),

              _pdfField('Child Name', child.childName),

              pw.SizedBox(height: 7),

              _pdfField('Child ID', child.childId),

              pw.SizedBox(height: 10),
              pw.Divider(),
              pw.SizedBox(height: 8),

              _pdfSectionTitle('REFERRAL INFORMATION'),

              pw.SizedBox(height: 10),

              _pdfField('Referral ID', referralIds),

              pw.SizedBox(height: 7),

              _pdfField('Vaccine', vaccineNames),

              pw.SizedBox(height: 7),

              _pdfField('Originating Facility', child.originatingFacility),

              pw.SizedBox(height: 10),

              // QR
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey400),
                      ),
                      child: pw.Image(qrImage, width: 115, height: 115),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Scan to verify referral',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 10),
              pw.Divider(),
              pw.SizedBox(height: 8),

              _pdfSectionTitle('EXTERNAL VACCINATION CONFIRMATION'),

              pw.SizedBox(height: 12),

              _pdfBlankField('Vaccine Administered', ''),

              pw.SizedBox(height: 8),

              _pdfBlankField(
                'Date Administered',
                '',
                guideText: 'MM / DD / YYYY',
              ),

              pw.SizedBox(height: 8),

              _pdfBlankField('Administering Facility', ''),

              pw.SizedBox(height: 8),

              _pdfBlankField('Health Worker Name', ''),

              pw.SizedBox(height: 14),

              pw.SizedBox(
                height: 78,
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: _pdfSignatureField('Health Worker Signature'),
                    ),
                    pw.SizedBox(width: 25),
                    pw.Expanded(child: _pdfStampField()),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  Future<pw.MemoryImage> _buildQrImage() async {
    final painter = QrPainter(
      data: _buildQrData(),
      version: QrVersions.auto,
      gapless: true,
    );

    final imageData = await painter.toImageData(
      600,
      format: ui.ImageByteFormat.png,
    );

    if (imageData == null) {
      throw Exception('Unable to generate QR code image.');
    }

    return pw.MemoryImage(imageData.buffer.asUint8List());
  }

  pw.Widget _pdfSectionTitle(String title) {
    return pw.Text(
      title,
      style: pw.TextStyle(
        fontSize: 11,
        fontWeight: pw.FontWeight.bold,
        letterSpacing: 1,
      ),
    );
  }

  pw.Widget _pdfField(String label, String value) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 125,
          child: pw.Text(
            '$label:',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey700,
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    );
  }

  pw.Widget _pdfBlankField(String label, String value, {String? guideText}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '$label:',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey700,
          ),
        ),
        if (guideText != null) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            guideText,
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
        ],
        pw.SizedBox(height: 5),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.only(bottom: 5),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey600)),
          ),
          child: pw.Text(
            value.isEmpty ? ' ' : value,
            style: const pw.TextStyle(fontSize: 10),
          ),
        ),
      ],
    );
  }

  pw.Widget _pdfSignatureField(String label) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '$label:',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey700,
          ),
        ),
        pw.SizedBox(height: 35),
        pw.Container(
          width: double.infinity,
          height: 1,
          color: PdfColors.grey600,
        ),
      ],
    );
  }

  pw.Widget _pdfStampField() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Facility Stamp:',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey700,
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Container(
          height: 55,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
          ),
          child: pw.Center(
            child: pw.Text(
              'Facility Stamp',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.referrals.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Printable Referral',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: Center(
          child: ElevatedButton(
            onPressed: widget.onBack,
            child: const Text('Go Back'),
          ),
        ),
      );
    }

    final child = widget.referrals.first;

    final vaccineNames = widget.referrals
        .map(
          (referral) => '${referral.vaccineName} Dose ${referral.doseNumber}',
        )
        .join(', ');

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Printable Referral',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: widget.onBack,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ================================================================
            // PREVIEW
            // ================================================================
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // HEADER
                  Center(
                    child: Column(
                      children: [
                        const Text(
                          'VACCINATION REFERRAL',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Date Issued: ${_formatDate(child.createdAt)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 18),

                  const _PrintSectionTitle('CHILD INFORMATION'),

                  const SizedBox(height: 12),

                  _PrintField(label: 'Child Name', value: child.childName),

                  const SizedBox(height: 8),

                  _PrintField(label: 'Child ID', value: child.childId),

                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 18),

                  const _PrintSectionTitle('REFERRAL INFORMATION'),

                  const SizedBox(height: 12),

                  _PrintField(
                    label: 'Referral ID',
                    value: widget.referrals.length == 1
                        ? widget.referrals.first.referralId
                        : widget.referrals.map((r) => r.referralId).join(', '),
                  ),

                  const SizedBox(height: 8),

                  _PrintField(label: 'Vaccine', value: vaccineNames),

                  const SizedBox(height: 8),

                  _PrintField(
                    label: 'Originating Facility',
                    value: child.originatingFacility,
                  ),

                  const SizedBox(height: 20),

                  // QR CODE
                  Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: QrImageView(
                            data: _buildQrData(),
                            version: QrVersions.auto,
                            size: 180,
                            backgroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Scan to verify referral',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 20),

                  const _PrintSectionTitle('EXTERNAL VACCINATION CONFIRMATION'),

                  const SizedBox(height: 14),

                  _PrintTextField(label: 'Vaccine Administered'),

                  const SizedBox(height: 12),

                  _PrintTextField(
                    label: 'Date Administered',
                    helperText: 'MM / DD / YYYY',
                  ),

                  const SizedBox(height: 12),

                  _PrintTextField(label: 'Administering Facility'),

                  const SizedBox(height: 12),

                  _PrintTextField(label: 'Health Worker Name'),

                  const SizedBox(height: 24),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _SignatureBox(title: 'Health Worker Signature'),
                      ),
                      const SizedBox(width: 20),
                      Expanded(child: _StampBox(title: 'Facility Stamp')),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ================================================================
            // ACTIONS
            // ================================================================
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: widget.onBack,
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Close'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _printReferral,
                      icon: const Icon(Icons.print_rounded),
                      label: const Text('Print / Save'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================================================
// PRINT SECTION TITLE
// ==========================================================================

class _PrintSectionTitle extends StatelessWidget {
  final String title;

  const _PrintSectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
      ),
    );
  }
}

// ==========================================================================
// PRINT FIELD
// ==========================================================================

class _PrintField extends StatelessWidget {
  final String label;
  final String value;

  const _PrintField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 125,
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

// ==========================================================================
// PRINT TEXT FIELD
// ==========================================================================

class _PrintTextField extends StatelessWidget {
  final String label;
  final String? helperText;

  const _PrintTextField({required this.label, this.helperText});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 2),
          Text(
            helperText!,
            style: TextStyle(
              fontSize: 9,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          height: 48,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ],
    );
  }
}

// ==========================================================================
// SIGNATURE BOX
// ==========================================================================

class _SignatureBox extends StatelessWidget {
  final String title;

  const _SignatureBox({required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 40),
        Container(
          height: 1,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

// ==========================================================================
// FACILITY STAMP BOX
// ==========================================================================

class _StampBox extends StatelessWidget {
  final String title;

  const _StampBox({required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 70,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              'Facility Stamp',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade400,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ==========================================================================
// VACCINE LIST
// ==========================================================================

class _VaccineListCard extends StatelessWidget {
  final List<Referral> referrals;
  final Color primary;

  const _VaccineListCard({required this.referrals, required this.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.vaccines_outlined, color: primary),
              ),
              const SizedBox(width: 13),
              const Text(
                'Unavailable Vaccines',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...referrals.map(
            (referral) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 18,
                    color: Colors.red.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      referral.vaccineName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    'Unavailable',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================================================
// INFORMATION CARD
// ==========================================================================

class _InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color primary;

  const _InfoCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: primary),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
