# HAWAS context

This file captures the stack constitution referenced by the PRD.

## Required tech stack

- Monorepo: pnpm, uv, Turborepo, lefthook.
- Backend: Python 3.12, FastAPI, SQLAlchemy 2 async, Pydantic v2, Postgres 16, Redis 7.
- Blockchain: web3.py backend, viem frontend, EVM-only at MVP.
- Queue: Celery with Redis broker.
- Frontend: Next.js 15 App Router, Tailwind, `@hawas/ui`, TanStack Query, Zustand, react-hook-form, Zod.
- Contracts: OpenAPI generated to `packages/types-hawas`.
- Security: JWT, Argon2id, TOTP MFA, RBAC, ed25519 internal calls, pluggable signer.
- CI/CD: GitHub Actions, Trivy, gitleaks, bandit, Cosign, Helm.

