from __future__ import annotations

from collections.abc import Awaitable, Callable
from uuid import uuid4

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from starlette.middleware.base import BaseHTTPMiddleware

from hawas.auth.router import router as auth_router


class HawasError(BaseModel):
    code: str
    message: str
    details: dict[str, object] = {}


class HealthResponse(BaseModel):
    status: str
    service: str
    variant: str


class RequestIdMiddleware(BaseHTTPMiddleware):
    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        request_id = request.headers.get("X-Request-Id", str(uuid4()))
        response = await call_next(request)
        response.headers["X-Request-Id"] = request_id
        return response


def create_app() -> FastAPI:
    app = FastAPI(
        title="HAWAS API",
        version="0.1.0",
        description="Hierarchical Autonomous Wallet Agent System API",
    )
    app.add_middleware(RequestIdMiddleware)
    app.include_router(auth_router)

    @app.exception_handler(RequestValidationError)
    async def validation_exception_handler(
        _request: Request,
        exc: RequestValidationError,
    ) -> JSONResponse:
        return JSONResponse(
            status_code=422,
            content=HawasError(
                code="validation_error",
                message="Request validation failed",
                details={"errors": exc.errors()},
            ).model_dump(),
        )

    @app.exception_handler(HTTPException)
    async def http_exception_handler(_request: Request, exc: HTTPException) -> JSONResponse:
        if isinstance(exc.detail, dict) and "code" in exc.detail:
            code = str(exc.detail["code"])
            message = str(exc.detail.get("message", code.replace("_", " ")))
            details = {key: value for key, value in exc.detail.items() if key not in {"code", "message"}}
        else:
            code = "http_error"
            message = str(exc.detail)
            details = {}
        return JSONResponse(
            status_code=exc.status_code,
            content=HawasError(code=code, message=message, details=details).model_dump(),
            headers=exc.headers,
        )

    error_responses = {422: {"model": HawasError}}

    @app.get("/health", response_model=HealthResponse, responses=error_responses, tags=["system"])
    async def health() -> HealthResponse:
        return HealthResponse(status="ok", service="hawas-backend", variant="testnet")

    @app.get("/api/v1/health", response_model=HealthResponse, responses=error_responses, tags=["system"])
    async def api_health() -> HealthResponse:
        return HealthResponse(status="ok", service="hawas-backend", variant="testnet")

    return app


app = create_app()
