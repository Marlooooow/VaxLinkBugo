import 'package:flutter/material.dart';

import 'package:qr_code_based_pediatric_vaccination/models/child/child_profile.dart';
import '../models/vaccine_inventory.dart';
import '../repositories/inventory_repository.dart';
import '../repositories/repository_registry.dart';
import '../utils/number_formatter.dart';
import 'vaccine_administration_screen.dart';
import 'referral_screen.dart';
import '../widgets/app_loading.dart';

class InventoryCheckScreen extends StatefulWidget {
  final ChildProfile child;
  final List<String> vaccineIds;

  const InventoryCheckScreen({
    super.key,
    required this.child,
    required this.vaccineIds,
  });

  @override
  State<InventoryCheckScreen> createState() => _InventoryCheckScreenState();
}

class _InventoryCheckScreenState extends State<InventoryCheckScreen> {
  final InventoryRepository _repository =
      RepositoryRegistry.instance.inventoryRepository;

  bool _isLoading = true;

  List<VaccineInventory> _inventory = [];

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    final results = await _repository.getInventoryForVaccines(
      widget.vaccineIds,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _inventory = results;
      _isLoading = false;
    });
  }

  List<VaccineInventory> get _availableVaccines {
    return _inventory.where((item) => item.isAvailable).toList();
  }

  List<VaccineInventory> get _unavailableVaccines {
    return _inventory.where((item) => item.isUnavailable).toList();
  }

  bool get _allAvailable {
    return _inventory.isNotEmpty && _unavailableVaccines.isEmpty;
  }

  bool get _allUnavailable {
    return _inventory.isNotEmpty && _availableVaccines.isEmpty;
  }

  bool get _mixedAvailability {
    return _availableVaccines.isNotEmpty && _unavailableVaccines.isNotEmpty;
  }

  void _continue() {
    if (_allAvailable) {
      _openAdministration(_availableVaccines);
      return;
    }

    if (_allUnavailable) {
      _openReferral(_unavailableVaccines);
      return;
    }

    if (_mixedAvailability) {
      _showMixedAvailabilityDialog();
    }
  }

  void _openAdministration(
    List<VaccineInventory> vaccines, {
    List<VaccineInventory> unavailableVaccines = const [],
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VaccineAdministrationScreen(
          child: widget.child,
          vaccines: vaccines,
          unavailableVaccines: unavailableVaccines,
        ),
      ),
    );
  }

  void _openReferral(List<VaccineInventory> vaccines) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReferralScreen(child: widget.child, unavailableVaccines: vaccines),
      ),
    );
  }

  void _showMixedAvailabilityDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Mixed Vaccine Availability',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'Some vaccines are available while others '
            'are unavailable.\n\n'
            'Available vaccines can be administered at '
            'this facility. Unavailable vaccines will '
            'require a referral.',
          ),
          actionsAlignment: MainAxisAlignment.end,
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);

                _openAdministration(
                  _availableVaccines,
                  unavailableVaccines: _unavailableVaccines,
                );
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: const Text('Proceed'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final primary = colorScheme.primary;
    final secondary = colorScheme.secondary;

    String buttonText;

    if (_allAvailable) {
      buttonText = 'Proceed to Administration';
    } else if (_allUnavailable) {
      buttonText = 'Create QR Referral';
    } else if (_mixedAvailability) {
      buttonText = 'Proceed with Available Vaccines';
    } else {
      buttonText = 'Continue';
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Vaccine Availability',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const AppLoadingView(
                title: 'Checking vaccine availability',
                message: 'Comparing eligible doses with usable inventory.',
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // CHILD
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: primary.withValues(alpha: 0.10),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: 0.08),
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
                                  widget.child.fullName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Child ID: ${widget.child.id}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 22),

                    const Text(
                      'Inventory Check',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      'The system checks each recommended '
                      'vaccine against the current inventory.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // INVENTORY
                    ..._inventory.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _InventoryCard(
                          inventory: item,
                          primary: primary,
                          secondary: secondary,
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // RESULT
                    _buildResultCard(primary, secondary),

                    const SizedBox(height: 24),

                    // CONTINUE
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: _inventory.isEmpty ? null : _continue,
                        icon: Icon(
                          _allUnavailable
                              ? Icons.qr_code_2_rounded
                              : Icons.arrow_forward_rounded,
                        ),
                        label: Text(buttonText),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildResultCard(Color primary, Color secondary) {
    Color iconColor;
    IconData icon;
    String title;
    String message;

    if (_allAvailable) {
      iconColor = Colors.green.shade700;
      icon = Icons.check_circle_outline;
      title = 'All vaccines available';
      message =
          'All recommended vaccines can be administered '
          'at this facility.';
    } else if (_allUnavailable) {
      iconColor = Colors.red.shade700;
      icon = Icons.error_outline_rounded;
      title = 'Vaccines unavailable';
      message =
          'None of the recommended vaccines are currently '
          'available. A referral is required.';
    } else {
      iconColor = Colors.orange.shade700;
      icon = Icons.warning_amber_rounded;
      title = 'Partial availability';
      message =
          'Some vaccines are available for administration '
          'while others require referral.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: iconColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// INVENTORY CARD
// --------------------------------------------------------------------------

class _InventoryCard extends StatelessWidget {
  final VaccineInventory inventory;
  final Color primary;
  final Color secondary;

  const _InventoryCard({
    required this.inventory,
    required this.primary,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final available = inventory.isAvailable;

    final statusText = available
        ? inventory.isLowStock
              ? 'Low stock'
              : 'Available'
        : 'Unavailable';

    final statusColor = available
        ? inventory.isLowStock
              ? Colors.orange.shade700
              : Colors.green.shade700
        : Colors.red.shade700;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(Icons.vaccines_outlined, color: primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inventory.vaccineName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  available
                      ? '${formatWholeNumber(inventory.availableDoses)} doses available'
                      : 'No doses currently available',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
