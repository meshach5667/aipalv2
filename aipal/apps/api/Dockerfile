# Production Dockerfile for AiPal API Backend
FROM python:3.12-slim

WORKDIR /app

# Install sqlite3 CLI and system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    sqlite3 \
    curl \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt gunicorn uvicorn

# Copy application files
COPY . .

# Ensure instance directory exists for SQLite WAL DB
RUN mkdir -p instance

EXPOSE 8102

ENV DATABASE_URL="sqlite+aiosqlite:///./instance/app.db"
ENV DATABASE_PATH="./instance/app.db"

CMD ["gunicorn", "-c", "gunicorn.conf.py", "app.main:app"]
