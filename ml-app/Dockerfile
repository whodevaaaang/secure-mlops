# Stage 1: Build
FROM python:3.10-slim AS builder

WORKDIR /app
COPY requirements-runtime.txt .
RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir --prefix=/install -r requirements-runtime.txt

# Stage 2: Production
FROM python:3.10-slim

# Security: run as non-root user
RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -r mluser \
    && useradd -r -g mluser mluser

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy application code
COPY . .

# Remove packaging tooling that is not needed at runtime.
RUN python -m pip uninstall -y wheel pip setuptools

# Set ownership
RUN chown -R mluser:mluser /app

# Switch to non-root user
USER mluser

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

# Run the API
CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000"]
