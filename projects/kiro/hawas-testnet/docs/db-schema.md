# HAWAS testnet database schema

Phase 4 establishes the canonical MVP schema from the PRD:

- `users`, `roles`, `user_roles`
- `wallets`
- `intents`
- `plans`
- `policies`
- `risk_rules`
- `approvals`
- `audit_events`

The source of truth is the SQLAlchemy metadata in `apps/backend/src/hawas/db/models.py` plus Alembic revision `0001_baseline`.

## Read-path indexes

- `idx_intents_status_created_at`
- `idx_audit_events_intent_id_created_at`
- `idx_approvals_status_created_at`
- `idx_wallets_tier_chain`

## Audit immutability

`audit_events` contains `prev_hash` and `hash` columns for hash-chain verification. The baseline migration installs a PostgreSQL trigger that raises before any `UPDATE` or `DELETE` against `audit_events`.

## Migration lifecycle

```bash
cd projects/kiro/hawas-testnet/apps/backend
uv run alembic upgrade head
uv run alembic downgrade base
uv run alembic upgrade head
```

The automated integration test uses a disposable PostgreSQL database:

```bash
HAWAS_TEST_DATABASE_URL=postgresql+asyncpg://hawas:hawas@localhost:5433/hawas_test \
  uv run pytest -m integration tests/test_schema_contract.py
```
