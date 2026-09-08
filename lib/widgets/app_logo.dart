import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final bool showLabel;

  const AppLogo({super.key, this.size = 76, this.showLabel = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isDarkMode = theme.brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: 'Bugo Sangguniang Barangay logo',
          child: SizedBox(
            width: size,
            height: size,
            child: Image.asset(
              'assets/images/bugo_sangguniang_barangay_logo.png',
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
          ),
        ),
        if (showLabel) ...[
          const SizedBox(height: 16),
          Text(
            'BUGO SANGGUNIANG BARANGAY',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDarkMode ? Colors.white : primary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
          Text(
            'PEDIATRIC IMMUNIZATION',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDarkMode ? Colors.white : const Color(0xFF334155),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
            ),
          ),
        ],
      ],
    );
  }
}
