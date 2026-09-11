import 'package:flutter/material.dart';

import 'app_logo.dart';

class BugoBrandTitle extends StatelessWidget {
  const BugoBrandTitle({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final availableWidth = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      final compact = availableWidth < 230;

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppLogo(size: compact ? 30 : 34, showLabel: false),
          SizedBox(width: compact ? 6 : 8),
          Flexible(
            child: Text(
              'Barangay Bugo',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                fontSize: compact ? 14 : 16,
                height: 1.1,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      );
    },
  );
}
