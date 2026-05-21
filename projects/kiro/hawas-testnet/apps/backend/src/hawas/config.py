from __future__ import annotations

from functools import lru_cache
from os import environ

from pydantic import BaseModel


class Settings(BaseModel):
    environment: str = environ.get("HAWAS_ENV", "local")
    database_url: str = environ.get("DATABASE_URL", "postgresql+asyncpg://hawas:hawas@localhost:5433/hawas")
    jwt_secret: str = environ.get("HAWAS_JWT_SECRET", "dev-only-change-before-prod-32-bytes-min")
    jwt_issuer: str = environ.get("HAWAS_JWT_ISSUER", "hawas-testnet")
    access_token_minutes: int = int(environ.get("HAWAS_ACCESS_TOKEN_MINUTES", "15"))
    refresh_token_days: int = int(environ.get("HAWAS_REFRESH_TOKEN_DAYS", "7"))
    mfa_fernet_key: str | None = environ.get("HAWAS_MFA_FERNET_KEY")

    def assert_safe(self) -> None:
        if self.environment == "production" and self.jwt_secret == "dev-only-change-before-prod-32-bytes-min":
            raise RuntimeError("HAWAS_JWT_SECRET must be set in production")


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    settings.assert_safe()
    return settings
