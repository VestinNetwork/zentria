# PHASE 3 — Infrastructure

## What shipped

- Docker Compose local topology for the 14 PRD services: Traefik, Postgres, Redis, backend, `worker-plan`, `worker-execute`, `scheduler-beat`, web, admin, OTel collector, Prometheus, Grafana, Loki, and Alertmanager.
- Two-network boundary:
  - `hawas-edge` for Traefik and routable HTTP services.
  - `hawas-internal` for DB, Redis, workers, telemetry, and service-to-service traffic.
- Traefik routes:
  - `hawas.localhost` → operator web.
  - `admin.hawas.localhost` → admin web.
  - `api.hawas.localhost` or `/api` → FastAPI backend.
  - `grafana.hawas.localhost` and `prometheus.hawas.localhost` for local observability.
- Local development ports:
  - web `3000`
  - admin `3100`
  - backend `8000`
  - Postgres `5433→5432`
  - Redis `6380→6379`
  - Grafana `3001`
  - Prometheus `9090`
  - Traefik dashboard `8082`
- Container build files for backend, web, and admin.
- Minimal Prometheus, Alertmanager, and OTel collector configuration.

## Round-trip coverage

Phase 3 adds infrastructure contract tests that assert the Compose file exposes the required services, ports, network boundary, and Traefik routes. The existing backend health test continues to prove the first API contract round trip.

## Honest scope

The Celery workers are placeholder long-running processes until Phase 15 adds the real Celery app and queues. Metrics scraping is wired, but `/metrics` is implemented in Phase 16. Production Kubernetes, Vault, HA Postgres, CI image signing, and hardened secrets are later phase gates.
