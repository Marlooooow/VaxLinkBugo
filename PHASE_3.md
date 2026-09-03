# Phase 3 — Health Worker QR Identification

Flow: Health Worker Home → Scan Child QR → Simulated Scan → Child Identified → Child information retrieved.

The QR is an identifier only. It does not determine a vaccination schedule, record a vaccination, or create a referral. Those decisions happen in later phases.

Mock QR scanning is isolated behind `QrRepository` so a real camera/QR implementation can replace it later.

Demo child: Sofia Santos / CH-001 / QR-CH-001.
