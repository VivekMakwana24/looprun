# Looprun server image, used for both the API and the Celery worker.
# Build context MUST be the repository root (it installs ./engine and ./server):
#   docker build -f server/Dockerfile -t looprun-server .

# ---- build stage: install both packages into a virtualenv ----
FROM python:3.12-slim AS build
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
WORKDIR /src
COPY engine ./engine
COPY server ./server
RUN pip install ./engine ./server

# ---- runtime stage ----
FROM python:3.12-slim AS runtime
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1
RUN groupadd --system --gid 10001 looprun \
 && useradd --system --uid 10001 --gid looprun --home-dir /app --shell /usr/sbin/nologin looprun
COPY --from=build /opt/venv /opt/venv
WORKDIR /app
USER 10001:10001
EXPOSE 8000

# Used by the API container. The worker has no HTTP port; docker-compose replaces this check for it with `celery inspect ping`.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=3).status == 200 else 1)"]

# Default command = API. The worker overrides it (see docker-compose files):
#   celery -A app.worker:celery_app worker -B -s /tmp/celerybeat-schedule --loglevel=info
CMD ["uvicorn", "app.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*"]
