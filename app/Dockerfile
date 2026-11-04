# syntax=docker/dockerfile:1

# ---- Stage 1: base (runtime deps only) -------------------------------------
FROM python:3.13-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /usr/src/app
# Pull in the latest Debian security fixes so Trivy's OS-package findings stay low.
RUN apt-get update \
 && apt-get -y --no-install-recommends upgrade \
 && rm -rf /var/lib/apt/lists/*
COPY requirements.txt ./
RUN pip install -r requirements.txt
COPY app.py instrumentation.py ./

# ---- Stage 2: test (pytest runs during the build; failure stops the pipeline)
FROM base AS test
COPY requirements-dev.txt test_app.py ./
RUN pip install -r requirements-dev.txt && pytest -q test_app.py

# ---- Stage 3: production (no test tooling, non-root, unprivileged port) -----
FROM base AS production
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} PORT=8080
RUN useradd --system --uid 10001 --no-create-home appuser
USER 10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request,os;urllib.request.urlopen('http://127.0.0.1:%s/health'%os.environ.get('PORT','8080'),timeout=2)" || exit 1
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--worker-tmp-dir", "/dev/shm", "--access-logfile", "-", "app:app"]
