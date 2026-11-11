#!/bin/bash

set -e

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
USER_WEB_DIR="$ROOT_DIR/apps/user-web"
CHAT_API_DIR="$ROOT_DIR/services/chat-api"
ADMIN_WEB_DIR="$ROOT_DIR/apps/admin-web"
ADMIN_API_DIR="$ROOT_DIR/services/admin-api"
DOCUMENT_PARSER_DIR="$ROOT_DIR/services/document-parser"
BACKEND_PORT="${BACKEND_PORT:-8000}"
FRONTEND_PORT="${FRONTEND_PORT:-3000}"
ADMIN_API_PORT="${ADMIN_API_PORT:-8100}"
ADMIN_WEB_PORT="${ADMIN_WEB_PORT:-3100}"
DOC_PROCESSING_PORT="${DOC_PROCESSING_PORT:-8200}"
ASKAI_REDIS_URL="${ASKAI_REDIS_URL:-redis://127.0.0.1:6379/0}"
MONGODB_URI="${MONGODB_URI:-mongodb://127.0.0.1:27017}"
MONGODB_DB="${MONGODB_DB:-gragentic}"
# Source mode runs the services on the host, so Dockerized Mongo/Redis/
# Weaviate must publish their ports to 127.0.0.1. Export both the chat-api
# names and the prefixed names used by admin-api and document-parser.
export MONGODB_URI MONGODB_DB
export ASKAI_ADMIN_MONGODB_URI="${ASKAI_ADMIN_MONGODB_URI:-$MONGODB_URI}"
export ASKAI_ADMIN_MONGODB_DB="${ASKAI_ADMIN_MONGODB_DB:-$MONGODB_DB}"
export MOVO_DOC_PROCESSING_MONGODB_URI="${MOVO_DOC_PROCESSING_MONGODB_URI:-$MONGODB_URI}"
export MOVO_DOC_PROCESSING_MONGODB_DB="${MOVO_DOC_PROCESSING_MONGODB_DB:-$MONGODB_DB}"
BACKEND_PYTHON_BIN=""
DOC_PROCESSING_PYTHON_BIN=""

# Source-mode development only needs a Python 3 interpreter to create venvs.
# Prefer python3 because many Linux distributions no longer provide `python`.
PYTHON_BIN="${PYTHON_BIN:-}"
if [ -z "$PYTHON_BIN" ]; then
    if command -v python3 >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python3)"
    elif command -v python >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python)"
    else
        echo "Python 3 is required to create the service virtual environments." >&2
        exit 1
    fi
fi

# One credential must be shared by admin-api and chat-api in local source mode.
# shellcheck source=scripts/dev/internal_service_auth.sh
source "$ROOT_DIR/scripts/dev/internal_service_auth.sh"

kill_port() {
    local port="$1"
    local pids
    pids="$(lsof -ti tcp:"$port" 2>/dev/null || true)"
    if [ -n "$pids" ]; then
        echo "Releasing port :$port ..."
        kill $pids 2>/dev/null || true
        sleep 1
        pids="$(lsof -ti tcp:"$port" 2>/dev/null || true)"
        if [ -n "$pids" ]; then
            kill -9 $pids 2>/dev/null || true
        fi
    fi
}

cleanup_ports() {
    kill_port "$BACKEND_PORT"
    kill_port "$FRONTEND_PORT"
    kill_port "$ADMIN_API_PORT"
    kill_port "$ADMIN_WEB_PORT"
    kill_port "$DOC_PROCESSING_PORT"
}

ensure_redis() {
    # redis-cli is optional. Redis commonly runs in Docker in source mode, so
    # probe the Redis protocol over TCP when the CLI is not installed.
    if command -v redis-cli >/dev/null 2>&1; then
        if redis-cli -u "$ASKAI_REDIS_URL" ping >/dev/null 2>&1; then
            return 0
        fi
    elif ASKAI_REDIS_URL="$ASKAI_REDIS_URL" "$PYTHON_BIN" - <<'PY' >/dev/null 2>&1
import os
import socket
import sys
from urllib.parse import urlparse

url = urlparse(os.environ.get("ASKAI_REDIS_URL", "redis://127.0.0.1:6379/0"))
host = url.hostname or "127.0.0.1"
port = url.port or 6379

try:
    with socket.create_connection((host, port), timeout=3) as sock:
        sock.sendall(b"*1\r\n$4\r\nPING\r\n")
        response = sock.recv(64)
except OSError:
    sys.exit(1)

if not response.startswith(b"+PONG"):
    sys.exit(1)
PY
    then
        return 0
    fi

    echo "Redis is not available at $ASKAI_REDIS_URL" >&2
    echo "Start Redis locally, or publish the Docker port (for example -p 6379:6379)." >&2
    exit 1
}

cleanup() {
    echo ""
    echo "Stopping services..."
    kill $(jobs -p) 2>/dev/null || true
    cleanup_ports
    exit
}

trap cleanup SIGINT SIGTERM

ensure_backend_venv() {
    cd "$CHAT_API_DIR"
    : > backend.log
    if [ -d "venv" ]; then
        source venv/bin/activate
    else
        "$PYTHON_BIN" -m venv venv
        source venv/bin/activate
    fi
    export PATH="$(pwd)/venv/bin:$PATH"
    export PYTHONUTF8=1
    export PYTHONIOENCODING=utf-8
    # Do not force en_US.UTF-8: minimal Linux images often only ship C.UTF-8,
    # and bash prints a warning for every missing locale. Python already runs
    # in UTF-8 mode via PYTHONUTF8 above.
    if [ -z "${LC_ALL:-}" ]; then
        if locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; then
            export LC_ALL=en_US.UTF-8
        elif locale -a 2>/dev/null | grep -qiE '^C\.utf-?8$'; then
            export LC_ALL=C.UTF-8
        fi
    fi
    export LANG="${LANG:-${LC_ALL:-C}}"
    export ASKAI_ADMIN_APP_ENV="${ASKAI_ADMIN_APP_ENV:-development}"
    export ASKAI_ADMIN_DOCUMENT_PROCESSING_BASE_URL="${ASKAI_ADMIN_DOCUMENT_PROCESSING_BASE_URL:-http://127.0.0.1:$DOC_PROCESSING_PORT}"
    export ASKAI_ADMIN_ADMIN_API_PUBLIC_BASE_URL="${ASKAI_ADMIN_ADMIN_API_PUBLIC_BASE_URL:-http://127.0.0.1:$ADMIN_API_PORT}"
    export ASKAI_DOC_PROCESSING_REDIS_URL="${ASKAI_DOC_PROCESSING_REDIS_URL:-$ASKAI_REDIS_URL}"
    BACKEND_PYTHON_BIN="$(pwd)/venv/bin/python"
    if ! "$BACKEND_PYTHON_BIN" -c "import fastapi, uvicorn, motor, pymongo" >/dev/null 2>&1; then
        echo "Installing chat-api dependencies..."
        "$BACKEND_PYTHON_BIN" -m pip install -r requirements.txt
    fi
    cd "$ROOT_DIR"
}

ensure_document_processing_venv() {
    cd "$DOCUMENT_PARSER_DIR"
    if [ -d ".venv" ]; then
        :
    else
        "$BACKEND_PYTHON_BIN" -m venv .venv
    fi
    DOC_PROCESSING_PYTHON_BIN="$(pwd)/.venv/bin/python"
    if ! "$DOC_PROCESSING_PYTHON_BIN" -c "import celery, fastapi, oss2, pymongo, pydantic_settings, redis, uvicorn" >/dev/null 2>&1; then
        "$DOC_PROCESSING_PYTHON_BIN" -m pip install -r requirements.txt
    fi
    cd "$ROOT_DIR"
}

start_runtime_backend() {
    echo "Starting Backend on :$BACKEND_PORT ..."
    cd "$CHAT_API_DIR"
    PYTHONPATH="$(pwd)" "$BACKEND_PYTHON_BIN" -m uvicorn app.main:app --reload --reload-dir app --port "$BACKEND_PORT" \
        --timeout-graceful-shutdown "${BACKEND_GRACEFUL_SHUTDOWN_SECONDS:-5}" \
        --reload-exclude "backend.log" \
        --reload-exclude "static/*" \
        --reload-exclude "*.pyc" \
        --reload-exclude "__pycache__/*" &
    cd "$ROOT_DIR"
}

start_frontend() {
    echo "Starting Frontend on :$FRONTEND_PORT ..."
    cd "$USER_WEB_DIR"
    npm run dev &
    cd "$ROOT_DIR"
}

start_admin_api() {
    echo "Starting Admin API on :$ADMIN_API_PORT ..."
    cd "$ADMIN_API_DIR"
    PYTHONPATH="$(pwd)" "$BACKEND_PYTHON_BIN" -m uvicorn app.main:app --reload --reload-dir app --port "$ADMIN_API_PORT" &
    cd "$ROOT_DIR"
}

start_document_processing_service() {
    echo "Starting Document Processing Service on :$DOC_PROCESSING_PORT ..."
    cd "$DOCUMENT_PARSER_DIR"
    PYTHONPATH="$(pwd)" "$DOC_PROCESSING_PYTHON_BIN" -m uvicorn app.main:app --reload --reload-dir app --port "$DOC_PROCESSING_PORT" &
    cd "$ROOT_DIR"
}

start_document_worker() {
    echo "Starting Document Worker ..."
    cd "$DOCUMENT_PARSER_DIR"
    PYTHONPATH="$(pwd)" "$DOC_PROCESSING_PYTHON_BIN" -m celery -A app.workers.celery_app:celery_app worker \
        --loglevel=info \
        --queues="${ASKAI_DOC_PROCESSING_CELERY_QUEUE:-document_processing}" &
    cd "$ROOT_DIR"
}

start_admin_web() {
    echo "Starting Admin Web on :$ADMIN_WEB_PORT ..."
    cd "$ADMIN_WEB_DIR"
    npm run dev &
    cd "$ROOT_DIR"
}

echo "Starting AskAI Platform..."
movo_prepare_internal_service_auth "$ROOT_DIR"
cleanup_ports
ensure_backend_venv
ensure_document_processing_venv
ensure_redis
echo "Using Backend Python: $BACKEND_PYTHON_BIN"
echo "Using Doc Processing Python: $DOC_PROCESSING_PYTHON_BIN"

start_runtime_backend
start_frontend
start_admin_api
start_document_processing_service
start_document_worker
start_admin_web

echo ""
echo "Services are starting up!"
echo "  - Frontend:    http://localhost:$FRONTEND_PORT"
echo "  - Backend:     http://localhost:$BACKEND_PORT/docs"
echo "  - Admin Web:   http://localhost:$ADMIN_WEB_PORT"
echo "  - Admin API:   http://localhost:$ADMIN_API_PORT/docs"
echo "  - Doc Process: http://localhost:$DOC_PROCESSING_PORT/docs"
echo "  - Redis:       $ASKAI_REDIS_URL"
echo ""
echo "Press Ctrl+C to stop all services."

wait
