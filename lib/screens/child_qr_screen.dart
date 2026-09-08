import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/child/child_profile.dart';

class ChildQrScreen extends StatefulWidget {
  final ChildProfile child;

  const ChildQrScreen({super.key, required this.child});

  @override
  State<ChildQrScreen> createState() => _ChildQrScreenState();
}

class _ChildQrScreenState extends State<ChildQrScreen> {
  bool _printing = false;

  String get _payload => jsonEncode({
    'type': 'child_identity',
    'version': 1,
    'child_id': widget.child.id,
    'qr_identifier': widget.child.qrIdentifier,
  });

  String _date(DateTime value) =>
      '${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}/${value.year}';

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => pw.Center(
          child: pw.Container(
            width: 330,
            padding: const pw.EdgeInsets.all(26),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey500),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(
                  'CHILD VACCINATION QR',
                  style: pw.TextStyle(
                    fontSize: 17,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text('Barangay Bugo Health Center'),
                pw.SizedBox(height: 22),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: _payload,
                  width: 190,
                  height: 190,
                ),
                pw.SizedBox(height: 18),
                pw.Text(
                  widget.child.fullName,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 7),
                pw.Text('Child ID: ${widget.child.id}'),
                pw.Text('Birth date: ${_date(widget.child.birthDate)}'),
                pw.SizedBox(height: 18),
                pw.Divider(),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Present this card at the health center. Scanning identifies the child but does not record a vaccination.',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return document.save();
  }

  Future<void> _print() async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      await Printing.layoutPdf(
        name: 'Child_QR_${widget.child.id}.pdf',
        onLayout: _buildPdf,
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Child QR',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE1E8F0)),
            ),
            child: Column(
              children: [
                const Text(
                  'CHILD VACCINATION QR',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(
                  'Barangay Bugo Health Center',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFD9E1EA)),
                  ),
                  child: QrImageView(
                    data: _payload,
                    size: 220,
                    version: QrVersions.auto,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  widget.child.fullName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  'Child ID: ${widget.child.id}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text('Birth date: ${_date(widget.child.birthDate)}'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('Identification only'),
            subtitle: Text(
              'Scanning retrieves the child record. It does not automatically record a vaccination.',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _printing ? null : _print,
            icon: _printing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_rounded),
            label: Text(_printing ? 'Preparing...' : 'Print / Save Child QR'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    ),
  );
}
