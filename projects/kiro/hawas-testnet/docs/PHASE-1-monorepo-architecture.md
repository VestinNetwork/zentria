# PHASE 1 — Monorepo architecture

## What shipped

- Root `pnpm-workspace.yaml`.
- Root `turbo.json`.
- Backend `uv` project under `apps/backend`.
- Package workspaces for `apps/web`, `apps/admin`, `packages/ui`, and `packages/types-hawas`.

## Honest scope

The workspace is intentionally minimal. CI, lefthook, generated OpenAPI artifacts, and full dependency hardening land in later phases.

