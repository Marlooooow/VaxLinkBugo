import 'package:flutter/material.dart';

/// Decorative, responsive welcome artwork; contains no clinical status/data.
class FamilyCareBanner extends StatelessWidget {
  const FamilyCareBanner({super.key});

  @override
  Widget build(BuildContext context) => Container(
    // width: double.infinity,
    // padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
    // decoration: BoxDecoration(
    //   gradient: const LinearGradient(
    //     begin: Alignment.topLeft,
    //     end: Alignment.bottomRight,
    //     colors: [AppTheme.softTeal, Color(0xFFFFF6E8)],
    //   ),
    //   borderRadius: BorderRadius.circular(28),
    //   border: Border.all(color: AppTheme.outline),
    // ),
    // child: Column(
      // children: [
      //   ExcludeSemantics(
      //     child: SizedBox(
      //       width: 180,
      //       height: 100,
      //       child: Stack(
      //         alignment: Alignment.center,
      //         children: [
      //           Container(
      //             width: 112,
      //             height: 96,
      //             decoration: BoxDecoration(
      //               color: Colors.white.withValues(alpha: 0.85),
      //               borderRadius: BorderRadius.circular(42),
      //             ),
      //             child: const Icon(
      //               Icons.family_restroom_rounded,
      //               size: 72,
      //               color: AppTheme.primaryTeal,
      //             ),
      //           ),
      //           const Positioned(
      //             left: 2,
      //             top: 8,
      //             child: Icon(
      //               Icons.favorite_rounded,
      //               size: 25,
      //               color: Color(0xFFC66C6C),
      //             ),
      //           ),
      //           const Positioned(
      //             right: 0,
      //             bottom: 8,
      //             child: CircleAvatar(
      //               radius: 22,
      //               backgroundColor: Colors.white,
      //               child: Icon(
      //                 Icons.health_and_safety_outlined,
      //                 color: AppTheme.healthcareGreen,
      //               ),
      //             ),
      //           ),
      //         ],
      //       ),
      //     ),
      //   ),
      //   const SizedBox(height: 12),
      //   const Text(
      //     'Little steps. Healthy futures.',
      //     textAlign: TextAlign.center,
      //     style: TextStyle(
      //       fontSize: 21,
      //       fontWeight: FontWeight.w800,
      //       color: AppTheme.ink,
      //     ),
      //   ),
      //   const SizedBox(height: 6),
      //   const Text(
      //     'Vaccination care, connected for every family.',
      //     textAlign: TextAlign.center,
      //     style: TextStyle(height: 1.4, color: Color(0xFF4E666C)),
      //   ),
      // ],
    // ),
  );
}
