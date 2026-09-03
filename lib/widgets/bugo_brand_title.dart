import 'package:flutter/material.dart';

import 'app_logo.dart';

class BugoBrandTitle extends StatelessWidget {
  const BugoBrandTitle({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const AppLogo(size: 38, showLabel: false),
      const SizedBox(width: 10),
      const Flexible(
        child: Text(
          'Bugo Sangguniang Barangay',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 17,
            height: 1.05,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ],
  );
}
