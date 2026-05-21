# PHASE 0 — Vision + threat model

## What shipped

- PRD anchor in `projects/kiro/dosc/PRD.md`.
- Testnet variant directory at `projects/kiro/hawas-testnet/`.
- Initial security invariants for AI, signing, policy, treasury, audit, and idempotency.

## Threat model baseline

| Threat | Control |
| ------ | ------- |
| AI attempts to sign or broadcast directly | Signer and executor are separate modules; future import-linter contracts enforce access. |
| No policies are configured | Policy phase must deny by default. |
| Audit tampering | Future database migration adds append-only trigger and hash-chain verification. |
| Replay of mutating request | Idempotency keys are mandatory for state-changing endpoints. |

## Honest scope

No production subsystem is complete in this phase. This is the launch scaffold and source-of-truth alignment only.

