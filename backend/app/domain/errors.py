from __future__ import annotations

from typing import Any


class AppError(Exception):
    def __init__(
        self,
        *,
        status_code: int,
        code: str,
        message: str,
        details: dict[str, Any] | None = None,
        headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.details = details
        self.headers = headers or {}


class UnauthorizedError(AppError):
    def __init__(self, message: str = "Authentication is required.") -> None:
        super().__init__(
            status_code=401, code="authentication_required", message=message
        )


class ForbiddenError(AppError):
    def __init__(self, message: str = "This action is not allowed.") -> None:
        super().__init__(status_code=403, code="action_forbidden", message=message)


class ServiceUnavailableError(AppError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(status_code=503, code=code, message=message)


class NotFoundError(AppError):
    def __init__(
        self,
        code: str = "resource_not_found",
        message: str = "The requested resource was not found.",
    ) -> None:
        super().__init__(status_code=404, code=code, message=message)


class GoneError(AppError):
    def __init__(self) -> None:
        super().__init__(
            status_code=410,
            code="listing_removed",
            message="This listing was taken down.",
        )


class ConflictError(AppError):
    def __init__(
        self, code: str, message: str, details: dict[str, Any] | None = None
    ) -> None:
        super().__init__(status_code=409, code=code, message=message, details=details)


class ValidationError(AppError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(status_code=422, code=code, message=message)


class RateLimitedError(AppError):
    def __init__(self, retry_after_seconds: int) -> None:
        super().__init__(
            status_code=429,
            code="report_rate_limited",
            message="Too many reports were submitted. Try again later.",
            details={"retry_after_seconds": retry_after_seconds},
            headers={"Retry-After": str(retry_after_seconds)},
        )


class ImageUploadRateLimitedError(AppError):
    def __init__(self, retry_after_seconds: int) -> None:
        super().__init__(
            status_code=429,
            code="image_upload_rate_limited",
            message="Too many image uploads were started. Try again later.",
            details={"retry_after_seconds": retry_after_seconds},
            headers={"Retry-After": str(retry_after_seconds)},
        )


class ImageUploadExpiredError(AppError):
    def __init__(self) -> None:
        super().__init__(
            status_code=410,
            code="image_upload_expired",
            message="The staged image has expired.",
        )
