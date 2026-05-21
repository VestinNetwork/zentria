# PHASE 5 — Auth + RBAC

## What shipped

- Auth module under `hawas.auth`.
- Argon2id password hashing and verification.
- JWT access and refresh token issuing with issuer, subject, role, permission, type, expiry, and JTI claims.
- Refresh-token rotation with reuse rejection.
- Role-to-permission mapping for `user`, `approver`, and `admin`.
- Admin MFA enforcement after enrollment using TOTP.
- Encrypted MFA secret storage column via `user_mfa_settings.totp_secret_ciphertext`.
- Refresh-token persistence table via migration `0002_auth_sessions_mfa`.
- `POST /api/v1/auth/login` and `POST /api/v1/auth/refresh`.
- httpOnly cookie setting for `hawas_at` and `hawas_rt`.
- Operator and admin `/login` page scaffolds.

## Round-trip coverage

Backend tests cover successful login, invalid password error envelope, admin MFA rejection/acceptance, refresh rotation, and token reuse rejection. Schema tests cover MFA and refresh-token storage. The Alembic integration test continues to run `upgrade head → downgrade base → upgrade head` against disposable Postgres when `HAWAS_TEST_DATABASE_URL` is set.

## Honest scope

MFA enrollment, refresh-cookie security hardening for production, seed CLI, auth middleware for protected routes, frontend form submission, and full session-aware navigation land in later phase work. The login pages are static contract surfaces in this phase.
