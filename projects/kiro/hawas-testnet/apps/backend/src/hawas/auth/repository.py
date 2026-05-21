from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import Select, insert, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from hawas.auth.security import decrypt_mfa_secret
from hawas.auth.service import AuthUser
from hawas.config import Settings
from hawas.db.models import RefreshToken, Role, User, UserMfaSetting, UserRole


class SqlAlchemyAuthRepository:
    def __init__(self, *, session: AsyncSession, settings: Settings) -> None:
        self.session = session
        self.settings = settings

    async def get_user_by_email(self, email: str) -> AuthUser | None:
        return await self._fetch_user(select(User).where(User.email == email))

    async def get_user_by_id(self, user_id: UUID) -> AuthUser | None:
        return await self._fetch_user(select(User).where(User.id == user_id))

    async def store_refresh_token(self, *, user_id: UUID, jti: UUID, expires_at: datetime) -> None:
        await self.session.execute(insert(RefreshToken).values(jti=jti, user_id=user_id, expires_at=expires_at))
        await self.session.commit()

    async def rotate_refresh_token(self, *, old_jti: UUID, new_jti: UUID, user_id: UUID, expires_at: datetime) -> bool:
        result = await self.session.execute(
            update(RefreshToken)
            .where(RefreshToken.jti == old_jti, RefreshToken.user_id == user_id, RefreshToken.revoked_at.is_(None))
            .values(revoked_at=datetime.now(UTC))
        )
        if result.rowcount != 1:
            await self.session.rollback()
            return False
        await self.session.execute(insert(RefreshToken).values(jti=new_jti, user_id=user_id, expires_at=expires_at))
        await self.session.commit()
        return True

    async def _fetch_user(self, statement: Select[tuple[User]]) -> AuthUser | None:
        user = (await self.session.execute(statement)).scalar_one_or_none()
        if user is None:
            return None

        role_rows = await self.session.execute(
            select(Role.name).join(UserRole, UserRole.role_id == Role.id).where(UserRole.user_id == user.id)
        )
        roles = set(role_rows.scalars().all())

        mfa = (
            await self.session.execute(select(UserMfaSetting).where(UserMfaSetting.user_id == user.id, UserMfaSetting.is_enabled.is_(True)))
        ).scalar_one_or_none()
        totp_secret = None
        if mfa and self.settings.mfa_fernet_key:
            totp_secret = decrypt_mfa_secret(mfa.totp_secret_ciphertext, self.settings.mfa_fernet_key)

        return AuthUser(
            id=user.id,
            email=user.email,
            password_hash=user.password_hash,
            is_active=user.is_active,
            roles=roles,
            mfa_enabled=mfa is not None,
            totp_secret=totp_secret,
        )
