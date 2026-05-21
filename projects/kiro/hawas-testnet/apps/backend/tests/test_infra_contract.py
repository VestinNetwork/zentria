from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[3]
COMPOSE_FILE = ROOT / "infra" / "compose" / "docker-compose.yml"


def test_phase_3_compose_declares_required_local_services() -> None:
    compose = yaml.safe_load(COMPOSE_FILE.read_text())

    assert set(compose["services"]) == {
        "traefik",
        "postgres",
        "redis",
        "backend",
        "worker-plan",
        "worker-execute",
        "scheduler-beat",
        "web",
        "admin",
        "otel-collector",
        "prometheus",
        "grafana",
        "loki",
        "alertmanager",
    }


def test_phase_3_compose_pins_ports_and_network_boundaries() -> None:
    compose = yaml.safe_load(COMPOSE_FILE.read_text())

    assert compose["services"]["postgres"]["ports"] == ["5433:5432"]
    assert compose["services"]["redis"]["ports"] == ["6380:6379"]
    assert compose["services"]["backend"]["ports"] == ["8000:8000"]
    assert compose["services"]["web"]["ports"] == ["3000:3000"]
    assert compose["services"]["admin"]["ports"] == ["3100:3100"]
    assert compose["services"]["grafana"]["ports"] == ["3001:3000"]
    assert compose["networks"]["hawas-internal"]["internal"] is True


def test_phase_3_traefik_routes_core_surfaces() -> None:
    compose = yaml.safe_load(COMPOSE_FILE.read_text())

    assert "PathPrefix(`/api`)" in compose["services"]["backend"]["labels"]["traefik.http.routers.hawas-api.rule"]
    assert compose["services"]["web"]["labels"]["traefik.http.routers.hawas-web.rule"] == "Host(`hawas.localhost`)"
    assert compose["services"]["admin"]["labels"]["traefik.http.routers.hawas-admin.rule"] == "Host(`admin.hawas.localhost`)"
