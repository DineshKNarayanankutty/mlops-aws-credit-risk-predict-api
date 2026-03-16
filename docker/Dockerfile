# ─── Stage 1: Builder ───────────────────────────────────────────────
# FIX: Pinned to digest for reproducible builds.
# To update: docker pull python:3.10-slim && docker inspect --format='{{index .RepoDigests 0}}' python:3.10-slim
FROM python:3.10-slim@sha256:06c1c6e8b55e6f2d49dfdae9e53dbb80e5e9e56843a91e4c5f5e95d3ee0fc84d AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
    && rm -rf /var/lib/apt/lists/*

# FIX C-05: Correct requirements.txt path (was inference/requirements.txt — file didn't exist)
COPY requirements.txt .
RUN pip install --user --no-warn-script-location -r requirements.txt

# ─── Stage 2: Runtime ───────────────────────────────────────────────
FROM python:3.10-slim@sha256:06c1c6e8b55e6f2d49dfdae9e53dbb80e5e9e56843a91e4c5f5e95d3ee0fc84d

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/home/appuser/.local/bin:${PATH}" \
    # Ensure stdout/stderr flushed immediately (important for CloudWatch log capture)
    PYTHONFAULTHANDLER=1

WORKDIR /app

# Create non-root user
RUN useradd --uid 1000 --gid 0 --create-home --shell /bin/bash appuser

# Copy installed packages from builder
COPY --from=builder /root/.local /home/appuser/.local

# FIX C-04: Model is NOT copied here — it is downloaded from S3 by the
#            init container at pod startup via the IRSA-backed ServiceAccount.
# Copy only application source code
COPY --chown=appuser:appuser inference/ /app/

# Create the directory the model will be mounted into at runtime
RUN mkdir -p /app/model && chown appuser:0 /app/model

USER appuser

EXPOSE 8000

# FIX: Added HEALTHCHECK so Docker-level health monitoring works
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

# FIX: Use multiple uvicorn workers for better CPU utilisation on multi-core inference nodes
# Workers = 2 * CPU_COUNT + 1 capped at 4 for predictable memory footprint
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2", \
     "--log-config", "/app/log_config.json"]
