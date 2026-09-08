import 'package:flutter/material.dart';

import '../models/qr_scan_result.dart';
import 'vaccination_assessment_screen.dart';
import 'qr_scan_screen.dart';

class QrScanResultScreen extends StatelessWidget {
  final QrScanResult result;

  const QrScanResultScreen({super.key, required this.result});

  void _assessVaccination(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VaccinationAssessmentScreen(child: result.child),
      ),
    );
  }

  void _scanAnotherChild(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final primary = colorScheme.primary;
    final secondary = colorScheme.secondary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Child Identified',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 30),
          child: Column(
            children: [
              // ----------------------------------------------------------
              // CHILD IDENTIFICATION CARD
              // ----------------------------------------------------------
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 26),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: primary.withValues(alpha: 0.10)),
                ),
                child: Column(
                  children: [
                    // Child icon
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.child_care_rounded,
                        size: 52,
                        color: primary,
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Child name
                    Text(
                      result.child.fullName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 6),

                    // Child ID
                    Text(
                      'Child ID: ${result.child.id}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // ----------------------------------------------------------
              // CHILD INFORMATION
              // ----------------------------------------------------------
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: primary.withValues(alpha: 0.10)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.badge_outlined, color: primary),
                        const SizedBox(width: 10),
                        const Text(
                          'Child Information',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    _InfoRow(
                      label: 'Date of birth',
                      value: _formatDate(result.child.birthDate),
                    ),

                    const SizedBox(height: 16),

                    _InfoRow(label: 'Sex', value: result.child.sex),

                    const SizedBox(height: 16),

                    _InfoRow(
                      label: 'QR identifier',
                      value: result.child.qrIdentifier,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // ----------------------------------------------------------
              // NEXT STEP
              // ----------------------------------------------------------
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: primary.withValues(alpha: 0.10)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.arrow_forward_rounded, color: secondary),
                        const SizedBox(width: 10),
                        const Text(
                          'Next Step',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // Information message
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, color: secondary),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'The QR code identifies the child. '
                              'Review the vaccination history and '
                              'applicable schedule before recording '
                              'a vaccination.',
                              style: TextStyle(fontSize: 13, height: 1.45),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // ----------------------------------------------------
                    // ASSESS VACCINATION BUTTON
                    // ----------------------------------------------------
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _assessVaccination(context);
                        },
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text(
                          'Assess Vaccination',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // ----------------------------------------------------------
              // SCAN TIME
              // ----------------------------------------------------------
              Text(
                'Scanned at ${_formatDateTime(result.scannedAt)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 22),

              // ----------------------------------------------------------
              // SCAN ANOTHER CHILD
              // ----------------------------------------------------------
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () {
                    _scanAnotherChild(context);
                  },
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Scan Another Child'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

    return '${months[date.month - 1]} '
        '${date.day}, '
        '${date.year}';
  }

  String _formatDateTime(DateTime dateTime) {
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

    final hour = dateTime.hour == 0
        ? 12
        : dateTime.hour > 12
        ? dateTime.hour - 12
        : dateTime.hour;

    final minute = dateTime.minute.toString().padLeft(2, '0');

    final period = dateTime.hour >= 12 ? 'PM' : 'AM';

    return '${months[dateTime.month - 1]} '
        '${dateTime.day}, '
        '${dateTime.year} • '
        '$hour:$minute $period';
  }
}

// --------------------------------------------------------------------------
// INFORMATION ROW
// --------------------------------------------------------------------------

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 20),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
