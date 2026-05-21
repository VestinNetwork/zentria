# HAWAS launch roadmap

## Current phase gate

The repository started empty. The first launch increment establishes phases 0-2 and a minimal fullstack health round trip.

## Next execution order

1. Phase 3: Docker Compose stack with Traefik, Postgres, Redis, backend, web, admin, and observability placeholders. (scaffolded)
2. Phase 4: Alembic schema for users, roles, wallets, intents, approvals, audit events, and immutability triggers.
3. Phase 5: Auth, RBAC, JWT cookies, refresh rotation, and MFA enrollment/login.
4. Phase 6: Wallet tier model and list/detail APIs.
5. Phase 7-12: signer, chain, execution, policy, risk, and simulation gates before any transaction can broadcast.
6. Phase 13-16: planner, memory, queues, monitoring, and alerting.
7. Phase 17-18: operator and admin product surfaces.
8. Phase 19-24: test matrix, security hardening, load, CI/CD, production infra, and launch sign-off.
