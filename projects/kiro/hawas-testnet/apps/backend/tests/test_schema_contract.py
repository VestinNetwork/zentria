from pathlib import Path

from hawas.db.models import Base


MIGRATION_FILE = Path(__file__).resolve().parents[1] / "migrations" / "versions" / "0001_baseline.py"


def test_phase_4_metadata_declares_prd_canonical_tables() -> None:
    assert set(Base.metadata.tables) == {
        "users",
        "roles",
        "user_roles",
        "wallets",
        "intents",
        "plans",
        "policies",
        "risk_rules",
        "approvals",
        "audit_events",
    }


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
