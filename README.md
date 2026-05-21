# HAWAS

HAWAS (Hierarchical Autonomous Wallet Agent System) is an internal-only, single-tenant autonomous Web3 operating system for governed EVM transaction execution.

The repository is organized around the product source of truth in `projects/kiro/dosc/PRD.md` and the active testnet variant in `projects/kiro/hawas-testnet/`.

## Current launch track

- Phase 0: vision and threat model scaffolded.
- Phase 1: monorepo workspace scaffolded with pnpm, uv, and Turborepo.
- Phase 2: HAWAS folder structure scaffolded for backend, web, admin, shared UI, typed contract, docs, and infra.

## Quick start

```bash
pnpm install
pnpm check
cd projects/kiro/hawas-testnet/apps/backend
uv run pytest
```

