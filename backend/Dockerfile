FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

WORKDIR /app

COPY --from=ghcr.io/astral-sh/uv:0.11.21 /uv /uvx /bin/
COPY backend/pyproject.toml backend/uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

COPY backend/app ./app
COPY backend/migrations ./migrations
COPY backend/alembic.ini ./alembic.ini
COPY backend/pyproject.toml ./pyproject.toml
RUN uv sync --frozen --no-dev

RUN addgroup --system muto \
    && adduser --system --ingroup muto muto \
    && mkdir -p /var/lib/muto/images \
    && chown -R muto:muto /var/lib/muto/images
USER muto

EXPOSE 8000

CMD [".venv/bin/uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
