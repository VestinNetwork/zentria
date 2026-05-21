# PHASE 2 — Folder structure

## What shipped

- `apps/backend` FastAPI modular-monolith entrypoint.
- `apps/web` operator dashboard shell.
- `apps/admin` admin dashboard shell.
- `packages/ui` shared primitives package.
- `packages/types-hawas` typed API contract seed.
- `infra/compose` local deployment seed.

## Honest scope

Only the first health-check round trip is implemented. Wallet, intent, policy, risk, signing, and execution domains are placeholders for subsequent phases.

