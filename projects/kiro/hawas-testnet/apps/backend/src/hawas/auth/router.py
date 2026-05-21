from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Cookie, Depends, Response
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from hawas.auth.repository import SqlAlchemyAuthRepository
from hawas.auth.service import AuthRepository, AuthService, TokenPair
from hawas.config import Settings, get_settings
from hawas.db.session import get_session


router = APIRouter(prefix="/api/v1/auth", tags=["auth"])


class LoginRequest(BaseModel):
    email: str
    password: str
    totp_code: str | None = None


class RefreshRequest(BaseModel):
    refresh_token: str | None = None


async def get_auth_repository(
    session: Annotated[AsyncSession, Depends(get_session)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> AuthRepository:
    return SqlAlchemyAuthRepository(session=session, settings=settings)


def get_auth_service(
    repository: Annotated[AuthRepository, Depends(get_auth_repository)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> AuthService:
    return AuthService(repository=repository, settings=settings)


@router.post("/login", response_model=TokenPair)
async def login(
    request: LoginRequest,
    response: Response,
    service: Annotated[AuthService, Depends(get_auth_service)],
) -> TokenPair:
    token_pair = await service.login(email=request.email, password=request.password, totp_code=request.totp_code)
    response.set_cookie("hawas_at", token_pair.access_token, httponly=True, samesite="lax", secure=False)
    response.set_cookie("hawas_rt", token_pair.refresh_token, httponly=True, samesite="lax", secure=False)
    return token_pair


@router.post("/refresh", response_model=TokenPair)
async def refresh(
    request: RefreshRequest,
    response: Response,
    service: Annotated[AuthService, Depends(get_auth_service)],
    hawas_rt: Annotated[str | None, Cookie()] = None,
) -> TokenPair:
    refresh_token = request.refresh_token or hawas_rt
    if refresh_token is None:
        from fastapi import HTTPException, status

        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail={"code": "missing_refresh_token"})
    token_pair = await service.refresh(refresh_token=refresh_token)
    response.set_cookie("hawas_at", token_pair.access_token, httponly=True, samesite="lax", secure=False)
    response.set_cookie("hawas_rt", token_pair.refresh_token, httponly=True, samesite="lax", secure=False)
    return token_pair
