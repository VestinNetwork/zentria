from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Protocol
from uuid import UUID

from fastapi import HTTPException, status
from jwt import InvalidTokenError
from pydantic import BaseModel

from hawas.auth.rbac import permissions_for_roles
from hawas.auth.security import decode_jwt, issue_jwt, verify_password, verify_totp
from hawas.config import Settings


@dataclass(frozen=True)
class AuthUser:
    id: UUID
    email: str
    password_hash: str
    is_active: bool
    roles: set[str]
    mfa_enabled: bool = False
    totp_secret: str | None = None


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    roles: list[str]
    permissions: list[str]


class AuthRepository(Protocol):
    async def get_user_by_email(self, email: str) -> AuthUser | None: ...

    async def get_user_by_id(self, user_id: UUID) -> AuthUser | None: ...

    async def store_refresh_token(self, *, user_id: UUID, jti: UUID, expires_at: datetime) -> None: ...

    async def rotate_refresh_token(self, *, old_jti: UUID, new_jti: UUID, user_id: UUID, expires_at: datetime) -> bool: ...


class AuthService:
    def __init__(self, *, repository: AuthRepository, settings: Settings) -> None:
        self.repository = repository
        self.settings = settings

    async def login(self, *, email: str, password: str, totp_code: str | None) -> TokenPair:
        user = await self.repository.get_user_by_email(email.lower())
        if user is None or not user.is_active or not verify_password(password, user.password_hash):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail={"code": "invalid_credentials"})

        if self._requires_mfa(user):
            if not totp_code or not user.totp_secret or not verify_totp(user.totp_secret, totp_code):
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail={"code": "mfa_required"})

        return await self._issue_pair(user)

    async def refresh(self, *, refresh_token: str) -> TokenPair:
        try:
            payload = decode_jwt(settings=self.settings, token=refresh_token, expected_type="refresh")
            user_id = UUID(str(payload["sub"]))
            old_jti = UUID(str(payload["jti"]))
        except (InvalidTokenError, KeyError, ValueError) as exc:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail={"code": "invalid_refresh_token"}) from exc

        user = await self.repository.get_user_by_id(user_id)
        if user is None or not user.is_active:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail={"code": "invalid_refresh_token"})

        roles = user.roles
        permissions = permissions_for_roles(roles)
        refresh_token_new, new_jti, refresh_expires_at = issue_jwt(
            settings=self.settings,
            subject=user.id,
            email=user.email,
            roles=roles,
            permissions=permissions,
            token_type="refresh",
            lifetime=timedelta(days=self.settings.refresh_token_days),
        )
        rotated = await self.repository.rotate_refresh_token(
            old_jti=old_jti,
            new_jti=new_jti,
            user_id=user.id,
            expires_at=refresh_expires_at,
        )
        if not rotated:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail={"code": "refresh_token_reused"})

        access_token, _, _ = issue_jwt(
            settings=self.settings,
            subject=user.id,
            email=user.email,
            roles=roles,
            permissions=permissions,
            token_type="access",
            lifetime=timedelta(minutes=self.settings.access_token_minutes),
        )
        return TokenPair(
            access_token=access_token,
            refresh_token=refresh_token_new,
            expires_in=self.settings.access_token_minutes * 60,
            roles=sorted(roles),
            permissions=sorted(permissions),
        )

    async def _issue_pair(self, user: AuthUser) -> TokenPair:
        roles = user.roles
        permissions = permissions_for_roles(roles)
        access_token, _, _ = issue_jwt(
            settings=self.settings,
            subject=user.id,
            email=user.email,
            roles=roles,
            permissions=permissions,
            token_type="access",
            lifetime=timedelta(minutes=self.settings.access_token_minutes),
        )
        refresh_token, refresh_jti, refresh_expires_at = issue_jwt(
            settings=self.settings,
            subject=user.id,
            email=user.email,
            roles=roles,
            permissions=permissions,
            token_type="refresh",
            lifetime=timedelta(days=self.settings.refresh_token_days),
        )
        await self.repository.store_refresh_token(user_id=user.id, jti=refresh_jti, expires_at=refresh_expires_at)
        return TokenPair(
            access_token=access_token,
            refresh_token=refresh_token,
            expires_in=self.settings.access_token_minutes * 60,
            roles=sorted(roles),
            permissions=sorted(permissions),
        )

    def _requires_mfa(self, user: AuthUser) -> bool:
        return "admin" in user.roles and user.mfa_enabled


def is_unexpired(expires_at: datetime) -> bool:
    return expires_at > datetime.now(UTC)
