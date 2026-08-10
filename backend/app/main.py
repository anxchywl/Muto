from __future__ import annotations

import re
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager
from uuid import uuid4

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from starlette.exceptions import HTTPException as StarletteHttpException
from starlette.responses import Response

from app.api.errors import (
    error_response,
    handle_app_error,
    handle_http_error,
    handle_unexpected_error,
    handle_validation_error,
)
from app.api.router import router
from app.config import AppEnvironment, Settings, get_settings
from app.domain.errors import AppError
from app.infrastructure.auth import create_principal_resolver
from app.infrastructure.db import Database
from app.infrastructure.storage import create_image_storage

REQUEST_ID_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
BODY_METHODS = {"POST", "PUT", "PATCH", "DELETE"}


def create_app(settings: Settings | None = None) -> FastAPI:
    active_settings = settings or get_settings()

    @asynccontextmanager
    async def lifespan(application: FastAPI) -> AsyncIterator[None]:
        database = Database(active_settings.database_url)
        application.state.database = database
        application.state.principal_resolver = create_principal_resolver(
            active_settings
        )
        application.state.image_storage = create_image_storage(active_settings)
        yield
        await database.close()

    application = FastAPI(
        title="Muto API",
        version="0.1.0",
        docs_url="/documentation" if active_settings.api_docs_enabled else None,
        redoc_url=None,
        openapi_url=("/openapi.json" if active_settings.api_docs_enabled else None),
        lifespan=lifespan,
    )
    application.state.settings = active_settings
    application.add_middleware(
        CORSMiddleware,
        allow_origins=active_settings.cors_allowed_origins,
        allow_credentials=False,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=[
            "Authorization",
            "Content-Type",
            "Idempotency-Key",
            "If-Match",
            "X-Request-ID",
        ],
        expose_headers=[
            "ETag",
            "Idempotent-Replayed",
            "Retry-After",
            "X-Request-ID",
        ],
    )

    @application.middleware("http")
    async def request_context(
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        supplied = request.headers.get("X-Request-ID", "")
        request_id = (
            supplied if REQUEST_ID_PATTERN.fullmatch(supplied) else str(uuid4())
        )
        request.state.request_id = request_id

        if request.method in BODY_METHODS:
            body_limit = active_settings.request_body_max_bytes
            if (
                request.method == "PUT"
                and request.url.path.startswith("/api/v1/image-uploads/")
                and request.url.path.endswith("/content")
            ):
                body_limit = 5 * 1024 * 1024
            content_length = request.headers.get("Content-Length")
            if content_length is not None and content_length.isdigit():
                if int(content_length) > body_limit:
                    too_large_response = error_response(
                        request,
                        status_code=413,
                        code="request_body_too_large",
                        message="The request body is too large.",
                    )
                    too_large_response.headers["X-Request-ID"] = request_id
                    return too_large_response
            chunks: list[bytes] = []
            received = 0
            async for chunk in request.stream():
                received += len(chunk)
                if received > body_limit:
                    too_large_response = error_response(
                        request,
                        status_code=413,
                        code="request_body_too_large",
                        message="The request body is too large.",
                    )
                    too_large_response.headers["X-Request-ID"] = request_id
                    return too_large_response
                chunks.append(chunk)
            request._body = b"".join(chunks)  # noqa: SLF001

        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "no-referrer"
        if request.url.path.startswith("/api/") and not request.url.path.startswith(
            "/api/v1/images/"
        ):
            response.headers["Cache-Control"] = "private, no-store"
        if active_settings.environment == AppEnvironment.production:
            response.headers["Strict-Transport-Security"] = (
                "max-age=31536000; includeSubDomains"
            )
        return response

    application.add_exception_handler(AppError, handle_app_error)  # type: ignore[arg-type]
    application.add_exception_handler(
        RequestValidationError,
        handle_validation_error,  # type: ignore[arg-type]
    )
    application.add_exception_handler(
        StarletteHttpException,
        handle_http_error,  # type: ignore[arg-type]
    )
    application.add_exception_handler(Exception, handle_unexpected_error)
    application.include_router(router)
    return application


app = create_app()
