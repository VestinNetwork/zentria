import os
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from hawas.db.models import Base


BACKEND_ROOT = Path(__file__).resolve().parents[1]
MIGRATION_FILE = BACKEND_ROOT / "migrations" / "versions" / "0001_baseline.py"


def test_phase_4_metadata_declares_prd_canonical_tables() -> None:
    assert set(Base.metadata.tables) == {
        "users",
        "roles",
        "user_roles",
        "user_mfa_settings",
        "refresh_tokens",
        "wallets",
        "intents",
        "plans",
        "policies",
        "risk_rules",
        "approvals",
        "audit_events",
    }


def test_phase_5_auth_metadata_declares_mfa_and_refresh_storage() -> None:
    mfa = Base.metadata.tables["user_mfa_settings"]
    refresh_tokens = Base.metadata.tables["refresh_tokens"]

    assert {"user_id", "totp_secret_ciphertext", "is_enabled"}.issubset(mfa.c.keys())
    assert {"jti", "user_id", "expires_at", "revoked_at"}.issubset(refresh_tokens.c.keys())


def test_phase_4_intents_keep_extensible_payload_and_idempotency_key() -> None:
    intents = Base.metadata.tables["intents"]

    assert {"type", "chain", "status", "payload", "submitted_by", "idempotency_key"}.issubset(intents.c.keys())
    assert intents.c.idempotency_key.unique is True
    assert intents.c.payload.type.__class__.__name__ == "JSONB"


def test_phase_4_audit_events_are_hash_chained_and_append_only() -> None:
    audit_events = Base.metadata.tables["audit_events"]
    migration = MIGRATION_FILE.read_text()

    assert {"prev_hash", "hash", "payload", "kind", "actor_type"}.issubset(audit_events.c.keys())
    assert "BEFORE UPDATE OR DELETE ON audit_events" in migration
    assert "RAISE EXCEPTION 'audit_events are append-only'" in migration


def test_phase_4_required_indexes_match_prd_read_paths() -> None:
    indexes = {
        index.name
        for table in Base.metadata.tables.values()
        for index in table.indexes
    }

    assert {
        "idx_intents_status_created_at",
        "idx_audit_events_intent_id_created_at",
        "idx_approvals_status_created_at",
        "idx_wallets_tier_chain",
    }.issubset(indexes)


def test_phase_4_migration_has_reversible_upgrade_and_downgrade() -> None:
    migration = MIGRATION_FILE.read_text()

    assert "def upgrade() -> None:" in migration
    assert "def downgrade() -> None:" in migration
    assert migration.count("op.create_table(") == 10
    assert migration.count("op.drop_table(") == 10


@pytest.mark.integration
def test_phase_4_alembic_round_trip_against_postgres() -> None:
    database_url = os.environ.get("HAWAS_TEST_DATABASE_URL")
    if not database_url:
        pytest.skip("Set HAWAS_TEST_DATABASE_URL to an empty disposable Postgres database")

    config = Config(str(BACKEND_ROOT / "alembic.ini"))
    config.set_main_option("sqlalchemy.url", database_url)

    command.upgrade(config, "head")
    command.downgrade(config, "base")
    command.upgrade(config, "head")
