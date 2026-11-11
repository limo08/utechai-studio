#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=internal_service_auth.sh
source "$SCRIPT_DIR/internal_service_auth.sh"

export ASKAI_ADMIN_JWT_SECRET="test-admin-jwt-secret"
unset ADMIN_BACKEND_SERVICE_TOKEN ASKAI_ADMIN_BACKEND_SERVICE_TOKEN \
    MOVO_DOC_PROCESSING_SERVICE_TOKEN ASKAI_ADMIN_DOCUMENT_PROCESSING_SERVICE_TOKEN \
    DOCUMENT_PROCESSING_SERVICE_TOKEN MOVO_DOC_PROCESSING_ADMIN_JWT_SECRET \
    MODEL_CONFIG_SECRET
movo_prepare_internal_service_auth
test -n "$ADMIN_BACKEND_SERVICE_TOKEN"
test "$ADMIN_BACKEND_SERVICE_TOKEN" = "$ASKAI_ADMIN_BACKEND_SERVICE_TOKEN"
test -n "$MOVO_DOC_PROCESSING_SERVICE_TOKEN"
test "$DOCUMENT_PROCESSING_SERVICE_TOKEN" = "$MOVO_DOC_PROCESSING_SERVICE_TOKEN"
test "$ASKAI_ADMIN_DOCUMENT_PROCESSING_SERVICE_TOKEN" = "$MOVO_DOC_PROCESSING_SERVICE_TOKEN"
test "$MOVO_DOC_PROCESSING_ADMIN_JWT_SECRET" = "$ASKAI_ADMIN_JWT_SECRET"
test "$MODEL_CONFIG_SECRET" = "$ASKAI_ADMIN_JWT_SECRET"

ADMIN_BACKEND_SERVICE_TOKEN="canonical-token"
ASKAI_ADMIN_BACKEND_SERVICE_TOKEN="stale-alias"
movo_prepare_internal_service_auth
test "$ADMIN_BACKEND_SERVICE_TOKEN" = "canonical-token"
test "$ASKAI_ADMIN_BACKEND_SERVICE_TOKEN" = "canonical-token"

unset ADMIN_BACKEND_SERVICE_TOKEN
ASKAI_ADMIN_BACKEND_SERVICE_TOKEN="legacy-token"
movo_prepare_internal_service_auth
test "$ADMIN_BACKEND_SERVICE_TOKEN" = "legacy-token"
test "$ASKAI_ADMIN_BACKEND_SERVICE_TOKEN" = "legacy-token"

ASKAI_ADMIN_JWT_SECRET="canonical-jwt-secret"
MOVO_DOC_PROCESSING_ADMIN_JWT_SECRET="stale-jwt-secret"
MODEL_CONFIG_SECRET="stale-model-secret"
movo_prepare_internal_service_auth
test "$ASKAI_ADMIN_JWT_SECRET" = "canonical-jwt-secret"
test "$MOVO_DOC_PROCESSING_ADMIN_JWT_SECRET" = "canonical-jwt-secret"
test "$MODEL_CONFIG_SECRET" = "canonical-jwt-secret"

echo "internal service auth checks passed"
