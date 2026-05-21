# PHASE 4 — Database

## What shipped

- Alembic baseline migration `0001_baseline`.
- SQLAlchemy 2 metadata for the PRD canonical MVP tables.
- PostgreSQL `pgcrypto` bootstrap for UUID generation.
- Hash-chain columns on `audit_events`.
- DB-level append-only trigger that rejects `UPDATE` and `DELETE` on `audit_events`.
- Required read-path indexes for intents, approvals, wallets, and audit events.
- Schema contract tests covering table inventory, JSONB payload extensibility, idempotency uniqueness, indexes, and migration reversibility shape.

## Round-trip coverage

The backend test suite imports the database metadata and validates it against the PRD contract. A real Postgres migration round trip is documented in `docs/db-schema.md` and becomes CI-enforced once the Phase 22 pipeline exists.

## Honest scope

This phase creates schema and migration contracts only. No repository layer, seed data, auth flows, wallet APIs, policy evaluation, audit writer, or hash-chain verification service is implemented yet.
