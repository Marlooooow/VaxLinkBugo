# Phase 2 — Guardian Child Records

This phase adds the first real guardian journey:

1. Guardian signs in.
2. Guardian selects **Manage Children**.
3. The app loads mock child records through `ChildRepository`.
4. Guardian sees the registered child.
5. Guardian taps the child.
6. The app opens the child's profile.
7. The profile shows basic information and the QR identifier.
8. Vaccination history/scheduling is intentionally reserved for later phases.

## Backend-ready structure

The UI depends on `ChildRepository`, not directly on mock data.

Current implementation:
- `MockChildRepository`

Later implementation can replace it with a real repository connected to the backend without changing the main UI flow.

## Demo account

Username: `guardian`
Password: `guardian123`

## Scope

This phase does NOT:
- scan a QR code;
- administer a vaccine;
- create a vaccination schedule;
- generate a referral;
- connect to a real backend.

Those belong to later phases.
