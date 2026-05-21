from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import jwt
import pyotp
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError
from cryptography.fernet import Fernet, InvalidToken

from hawas.config import Settings


password_hasher = PasswordHasher()


def hash_password(password: str) -> str:
    return password_hasher.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return password_hasher.verify(password_hash, password)
    except VerifyMismatchError:
        return False


def verify_totp(secret: str, code: str) -> bool:
    return pyotp.TOTP(secret).verify(code, valid_window=1)


def encrypt_mfa_secret(secret: str, fernet_key: str) -> bytes:
    return Fernet(fernet_key.encode()).encrypt(secret.encode())


def decrypt_mfa_secret(ciphertext: bytes, fernet_key: str) -> str:
    try:
        return Fernet(fernet_key.encode()).decrypt(ciphertext).decode()
    except InvalidToken as exc:
        raise ValueError("Invalid MFA secret ciphertext") from exc


def issue_jwt(
    *,
    settings: Settings,
    subject: UUID,
    email: str,
    roles: set[str],
    permissions: set[str],
    token_type: str,
    lifetime: timedelta,
    jti: UUID | None = None,
) -> tuple[str, UUID, datetime]:
    now = datetime.now(UTC)
    token_jti = jti or uuid4()
    expires_at = now + lifetime
    payload = {
        "iss": settings.jwt_issuer,
        "sub": str(subject),
        "email": email,
        "roles": sorted(roles),
        "permissions": sorted(permissions),
        "type": token_type,
        "jti": str(token_jti),
        "iat": int(now.timestamp()),
        "exp": int(expires_at.timestamp()),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256"), token_jti, expires_at


def decode_jwt(*, settings: Settings, token: str, expected_type: str) -> dict[str, object]:
    payload = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"], issuer=settings.jwt_issuer)
    if payload.get("type") != expected_type:
        raise jwt.InvalidTokenError("Unexpected token type")
    return payload
