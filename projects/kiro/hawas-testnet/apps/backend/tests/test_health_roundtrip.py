from fastapi.testclient import TestClient

from hawas.main import app


def test_health_roundtrip_returns_contract_and_request_id() -> None:
    client = TestClient(app)

    response = client.get("/api/v1/health", headers={"X-Request-Id": "roundtrip-1"})

    assert response.status_code == 200
    assert response.headers["X-Request-Id"] == "roundtrip-1"
    assert response.json() == {
        "status": "ok",
        "service": "hawas-backend",
        "variant": "testnet",
    }


def test_openapi_exposes_hawas_error_contract() -> None:
    client = TestClient(app)

    response = client.get("/openapi.json")

    schemas = response.json()["components"]["schemas"]

    assert "HawasError" in schemas
    assert schemas["HawasError"]["properties"]["code"]["type"] == "string"

