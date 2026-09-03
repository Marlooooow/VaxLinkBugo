import '../repositories/repository_registry.dart';
import 'package:flutter/material.dart';

import '../models/child_profile.dart';
import '../models/referral.dart';
import '../models/vaccine_inventory.dart';
import '../repositories/referral_repository.dart';
import 'referral_qr_screen.dart';

class ReferralScreen extends StatefulWidget {
  final ChildProfile child;
  final List<VaccineInventory> unavailableVaccines;

  const ReferralScreen({
    super.key,
    required this.child,
    required this.unavailableVaccines,
  });

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  final ReferralRepository _repository =
      RepositoryRegistry.instance.referralRepository;

  bool _isGenerating = false;

  List<Referral> _referrals = [];

  Future<void> _generateReferrals() async {
    if (_isGenerating || widget.unavailableVaccines.isEmpty) {
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    try {
      final referrals = await _repository.createReferralGroup(
        child: widget.child,
        vaccines: widget.unavailableVaccines,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _referrals = referrals;
        _isGenerating = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isGenerating = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to generate referral: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final primary = colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'QR Referral',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.qr_code_2_rounded, color: primary, size: 32),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Referral Required',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'The following vaccine(s) are '
                            'currently unavailable at '
                            'Barangay Bugo Health Center.',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // Child
              const Text(
                'Child',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),

              const SizedBox(height: 10),

              _InfoCard(
                icon: Icons.child_care_rounded,
                title: widget.child.fullName,
                subtitle: 'Child ID: ${widget.child.id}',
                primary: primary,
              ),

              const SizedBox(height: 22),

              const Text(
                'Unavailable Vaccines',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),

              const SizedBox(height: 10),

              ...widget.unavailableVaccines.map(
                (vaccine) => Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(17),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 45,
                        height: 45,
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          Icons.vaccines_outlined,
                          color: Colors.red.shade700,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Text(
                          vaccine.vaccineName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
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

              const SizedBox(height: 14),

              if (_referrals.isNotEmpty)
                _buildGeneratedReferrals(primary)
              else
                _buildGenerateSection(primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGenerateSection(Color primary) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'A referral QR will contain the '
                  'referral information needed by '
                  'the receiving health facility.',
                  style: TextStyle(fontSize: 12.5, height: 1.4),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton.icon(
            onPressed: _isGenerating ? null : _generateReferrals,
            icon: _isGenerating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.qr_code_2_rounded),
            label: Text(
              _isGenerating ? 'Generating...' : 'Generate QR Referral',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGeneratedReferrals(Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Referral generated successfully.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        const Text(
          'Referral Details',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),

        const SizedBox(height: 10),

        ..._referrals.map(
          (referral) => _ReferralCard(referral: referral, primary: primary),
        ),

        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          height: 54,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReferralQrScreen(referrals: _referrals),
                ),
              );
            },
            icon: const Icon(Icons.qr_code_2_rounded),
            label: const Text('View Referral QR'),
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color primary;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
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

class _ReferralCard extends StatelessWidget {
  final Referral referral;
  final Color primary;

  const _ReferralCard({required this.referral, required this.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  referral.vaccineName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Pending',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Text(
            'Referral ID',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 3),

          Text(
            referral.referralId,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),

          const SizedBox(height: 10),

          Text(
            'From: ${referral.originatingFacility}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
