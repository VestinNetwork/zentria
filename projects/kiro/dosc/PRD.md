# HAWAS Product Requirements Document

Status: Active. This file is the product source of truth for HAWAS variants under `projects/kiro/`.

The launch target is the HAWAS PRD supplied by the architecture council on 2026-05-21. Implementation work must preserve these binding invariants:

1. AI may plan but must never sign, bypass policy, bypass risk, bypass simulation, or directly control treasury wallets.
2. Default deny: with no active policies loaded, intents are rejected.
3. Audit events are append-only, hash-chained, and protected by database triggers.
4. Treasury signing requires human approval logically through policy and structurally before broadcast.
5. Every transaction flow runs validation, policy, risk, simulation, execution, and post-execution monitoring.
6. Mutating APIs require idempotency keys and replay to the original outcome.
7. `hawas/` and `hawas-testnet/` are the same product; the testnet variant leads active development.

## Mandatory launch phases

The project launches only after phases 0 through 24 pass their exit criteria: merged code, docs, honest scope, wf-mem updates, and at least one round-trip test per phase.

| # | Phase | Required output |
| - | ----- | --------------- |
| 0 | Vision + threat model | Product scope, threat model, success criteria |
| 1 | Monorepo architecture | pnpm, uv, Turborepo workspaces |
| 2 | Folder structure | `apps/`, `packages/`, `infra/`, docs |
| 3 | Infrastructure | Compose, ports, Traefik routes |
| 4 | Database | Alembic schema, ER diagram |
| 5 | Auth + RBAC | JWT, roles, MFA |
| 6 | Wallet engine | HD derivation, tier model, wallet APIs |
| 7 | Secure signing | Local encrypted signer and signer interface |
| 8 | Chain abstraction | EVM chain client registry |
| 9 | Transaction execution | Executor, broadcaster, watcher |
| 10 | Policy engine | DSL evaluator, deny-by-default, admin CRUD |
| 11 | Risk engine | Scorer registry and weighted aggregation |
| 12 | Simulation | `eth_call` wrapper and revert mapping |
| 13 | AI orchestration | LangGraph plan DAG and tools |
| 14 | Agent memory | Thread persistence and LRU |
| 15 | Scheduler + queue | Celery, beat, retries, idempotency |
| 16 | Monitoring + observability | Prometheus, Grafana, Loki, OTel, Alertmanager |
| 17 | Frontend web | Login, wallets, intents, approvals, audit |
| 18 | Admin frontend | Policies, risk rules, agents, health |
| 19 | Testing | pytest, Playwright, Hypothesis, factories |
| 20 | Security hardening | Headers, secret rotation, checklist |
| 21 | Load testing | k6/Locust scenarios and capacity report |
| 22 | Deployment pipeline | GitHub Actions, Trivy, cosign, Helm |
| 23 | Production infrastructure | K8s, Vault, HA Postgres |
| 24 | Launch checklist | Engineering, security, ops, treasury sign-off |

## Active implementation path

The current repository starts from an empty baseline, so work begins with phases 0-2 as a launch scaffold before any domain subsystem is added.

