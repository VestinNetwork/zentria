from __future__ import annotations

from datetime import datetime
from uuid import UUID, uuid4

import pyotp
from fastapi.testclient import TestClient

from hawas.auth.router import get_auth_repository
from hawas.auth.security import decode_jwt, hash_password
from hawas.auth.service import AuthUser
from hawas.config import get_settings
from hawas.main import app


class FakeAuthRepository:
    def __init__(self) -> None:
        self.operator = AuthUser(
            id=uuid4(),
            email="operator@hawas.local",
            password_hash=hash_password("test-password-123"),
            is_active=True,
            roles={"user"},
        )
        self.admin_secret = pyotp.random_base32()
        self.admin = AuthUser(
            id=uuid4(),
            email="admin@hawas.local",
            password_hash=hash_password("test-password-123"),
            is_active=True,
            roles={"admin"},
            mfa_enabled=True,
            totp_secret=self.admin_secret,
        )
        self.users = {self.operator.email: self.operator, self.admin.email: self.admin}
        self.refresh_tokens: dict[UUID, tuple[UUID, datetime, bool]] = {}

    async def get_user_by_email(self, email: str) -> AuthUser | None:
        return self.users.get(email)

    async def get_user_by_id(self, user_id: UUID) -> AuthUser | None:
        return next((user for user in self.users.values() if user.id == user_id), None)

    async def store_refresh_token(self, *, user_id: UUID, jti: UUID, expires_at: datetime) -> None:
        self.refresh_tokens[jti] = (user_id, expires_at, False)

    async def rotate_refresh_token(self, *, old_jti: UUID, new_jti: UUID, user_id: UUID, expires_at: datetime) -> bool:
        stored = self.refresh_tokens.get(old_jti)
        if stored is None or stored[0] != user_id or stored[2]:
            return False
        self.refresh_tokens[old_jti] = (stored[0], stored[1], True)
        self.refresh_tokens[new_jti] = (user_id, expires_at, False)
        return True


def make_client(repository: FakeAuthRepository) -> TestClient:
    async def override_repository() -> FakeAuthRepository:
        return repository

    app.dependency_overrides[get_auth_repository] = override_repository
    return TestClient(app)


def test_login_issues_access_refresh_tokens_and_hawas_cookies() -> None:
    repository = FakeAuthRepository()
    client = make_client(repository)

    response = client.post(
        "/api/v1/auth/login",
        json={"email": "operator@hawas.local", "password": "test-password-123"},
    )

    assert response.status_code == 200
    body = response.json()
    payload = decode_jwt(settings=get_settings(), token=body["access_token"], expected_type="access")
    assert payload["email"] == "operator@hawas.local"
    assert body["roles"] == ["user"]
    assert "wallets:read" in body["permissions"]
    assert "hawas_at" in response.cookies
    assert "hawas_rt" in response.cookies


def test_login_rejects_invalid_password_with_error_envelope() -> None:
    client = make_client(FakeAuthRepository())

    response = client.post(
        "/api/v1/auth/login",
        json={"email": "operator@hawas.local", "password": "wrong"},
    )

    assert response.status_code == 401
    assert response.json()["code"] == "invalid_credentials"


def test_admin_login_requires_valid_totp_after_mfa_enrollment() -> None:
    repository = FakeAuthRepository()
    client = make_client(repository)

    missing = client.post(
        "/api/v1/auth/login",
        json={"email": "admin@hawas.local", "password": "test-password-123"},
    )
    assert missing.status_code == 401
    assert missing.json()["code"] == "mfa_required"

    code = pyotp.TOTP(repository.admin_secret).now()
    accepted = client.post(
        "/api/v1/auth/login",
        json={"email": "admin@hawas.local", "password": "test-password-123", "totp_code": code},
    )
    assert accepted.status_code == 200
    assert accepted.json()["roles"] == ["admin"]
    assert "admin:policies" in accepted.json()["permissions"]


def test_refresh_rotates_refresh_token_and_rejects_reuse() -> None:
    repository = FakeAuthRepository()
    client = make_client(repository)
    login = client.post(
        "/api/v1/auth/login",
        json={"email": "operator@hawas.local", "password": "test-password-123"},
    )
    refresh_token = login.json()["refresh_token"]

    refreshed = client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})
    reused = client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})

    assert refreshed.status_code == 200
    assert refreshed.json()["refresh_token"] != refresh_token
    assert reused.status_code == 401
    assert reused.json()["code"] == "refresh_token_reused"
