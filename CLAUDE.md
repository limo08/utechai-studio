# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

MOVO Community Edition: a self-hosted enterprise Agent platform built on the DeepSeek Harness (DSH). It is a monorepo containing two Vue 3 SPAs, three FastAPI services, an out-of-process Node.js DSH Runtime Host, a document-parsing Celery worker, and Docker Compose deployment tooling.

Legacy `askai`/`ASKAI_` names are deliberately retained in environment variables, module paths, and internal headers. `MOVO_*` variables are newer aliases in many places; when touching config, check both spellings.

## Commands

### Local development (source mode)

Prerequisites: Python 3.10+ (CI exercises 3.10 and 3.11), Node 22.19+ (or 24+) for the runtime host, `pnpm`, Redis running locally, and system tools used by `dev.sh` (`lsof`).

```bash
./dev.sh          # user-web :3000, chat-api :8000, admin-web :3100, admin-api :8100, document-api :8200, Celery worker
./dev_dsh.sh      # additionally starts the pinned DSH Runtime Host on :8101, then runs ./dev.sh
./dev_dsh.sh --desktop
```

`dev.sh` creates `services/chat-api/venv` and `services/document-parser/.venv`, installs requirements on demand, and generates shared internal-service credentials via `scripts/dev/internal_service_auth.sh`. API docs are at `/docs` on each FastAPI port.

Vite dev servers proxy `/api` and `/askai-api` to chat-api (`8000`), and `/portal-api`, `/knowledge-api`, `/admin-api`, `/sso` to admin-api (`8100`).

### Docker / deployment

The `./movo` launcher is the operator entry point and uses prebuilt images by default:

```bash
./movo up                 # pull images, start stack, wait for health
./movo up --build         # build local images via docker-compose.build.yml
./movo build              # build without starting
./movo status
./movo logs chat-api
./movo restart
./movo update             # pull newer images and run additive DB migrations
./movo fix                # repair sequence conflicts during upgrade
./movo backup /path/on/large/disk
./movo down               # stop and keep data
./movo down -v            # destructive: delete volumes after confirmation
./movo --mirror cn up     # use the China ACR mirror for MOVO and infra images
```

First-run setup is at `http://localhost:3000/admin/setup`. The gateway is the only published port (`MOVO_PORT`, default 3000) and routes by path: `/` → user-web, `/admin/` → admin-web, `/admin-api/` → admin-api:8100, `/api/` and `/askai-api/` → chat-api:8000.

### Repository guards (match CI in `.github/workflows/runtime-guard.yml`)

```bash
python3 scripts/check_open_source_hygiene.py
python -m compileall -q services/chat-api/app services/chat-api/scripts services/admin-api/app services/document-parser/app
python scripts/check_web_runtime_baseline.py
python -m unittest scripts/release/test_web_runtime_baseline.py
python services/chat-api/scripts/check_dsh_legacy_runtime_boundary.py
python services/chat-api/scripts/check_dsh_native_code_boundary.py
python services/chat-api/scripts/check_dsh_supply_chain.py
python services/chat-api/scripts/check_dsh_upgrade_contract.py
node scripts/check_web_i18n_keys.cjs
```

### Backend tests

Each service is tested with `PYTHONPATH` set to that service directory, from the repo root. The chat-api suite requires a **real MongoDB**; it fails rather than skips when the server is unreachable.

```bash
docker run -d --name movo-test-mongo -p 27017:27017 mongo:6.0.20
pip install -r services/chat-api/requirements.txt pytest

# whole suite / a directory / one file / one test
PYTHONPATH=services/chat-api python -m pytest services/chat-api/tests -q
PYTHONPATH=services/chat-api python -m pytest services/chat-api/tests/services -q
PYTHONPATH=services/chat-api python -m pytest services/chat-api/tests/services/test_skill_sharing.py -q
PYTHONPATH=services/chat-api python -m pytest services/chat-api/tests/services/test_skill_sharing.py::test_name -q

# admin-api and document-parser use the same pattern
PYTHONPATH=services/admin-api python -m pytest services/admin-api/tests/test_model_groups.py -q
PYTHONPATH=services/document-parser python -m pytest services/document-parser/tests/test_retrieval_scope.py -q
```

`MOVO_TEST_MONGODB_URI` overrides the test Mongo URI (default `mongodb://localhost:27017`). Each test gets an isolated `movo_test_<uuid>` database that is dropped afterward; see `services/chat-api/tests/conftest.py` for the motor event-loop rules.

### DSH Runtime Host tests

```bash
cd services/chat-api/dsh/runtime-host
pnpm install --frozen-lockfile
pnpm test                                        # node --test tests/*.test.mjs
node --test tests/model-profile.test.mjs         # single file
```

### Frontend tests/builds

Frontend unit tests are plain TypeScript modules bundled with `esbuild` and run with Node — there is no Vitest/Jest.

```bash
cd apps/user-web
npm ci
npm run typecheck
npm run build
npm run test:session-live        # one of many test:* scripts in package.json

# arbitrary single test file
npx esbuild tests/evidence-source-groups.test.ts --bundle --platform=node --format=esm --outfile=/tmp/t.mjs && node /tmp/t.mjs

cd apps/admin-web
npm ci --legacy-peer-deps
npm run build                    # includes vue-tsc --noEmit
npm run typecheck
```

### End-to-end QA

Playwright specs live in `qa/`. They need a running deployment and an evidence directory:

```bash
cd qa && npm ci
MOVO_QA_BASE_URL=http://localhost:3000 EVIDENCE_ROOT=/tmp/movo-evidence npx playwright test
MOVO_QA_BASE_URL=http://localhost:3000 EVIDENCE_ROOT=/tmp/movo-evidence npx playwright test --config release-smoke.config.ts
```

## Architecture

### Agent execution boundary (the most important design constraint)

`services/chat-api` is the system of record and policy plane; the Node DSH Runtime Host (`services/chat-api/dsh/runtime-host`) is the agent execution plane.

- `app/dsh_runtime/` implements `AgentKernelContract` (sessions, turns, cancellation, event mapping) and talks over HTTP to the runtime host. `host_manager.py` can also spawn the host as a local subprocess; in Compose it runs as a separate service on `:8101`.
- The runtime host runs the pinned DeepSeek Harness packages (planning, agent loop, session persistence, subagents, skills). It must **not** call model providers directly. Model requests and tool calls loop back to chat-api through signed internal endpoints: `/internal/dsh/model/generate` and `/internal/dsh/tools`, authenticated with `DSH_MODEL_GATEWAY_SIGNING_SECRET` / `DSH_RUNTIME_HOST_TOKEN`.
- chat-api owns authentication, tenancy, model access, quota, tool/skill/plugin policy, approval/governance, evidence persistence, and file delivery. `app/dsh_runtime/profile/` compiles a per-tenant runtime profile (models, tools, skills, plugins, search availability) that the host consumes.
- Enterprise features exposed to the agent are adapters under `app/enterprise_capabilities/` (knowledge, research, content generation, spreadsheets, presentations, browser, artifacts, delivery). Keep provider/model logic and policy in Python and the agent loop in Node.
- Chat turn events are persisted and projected through `app/dsh_runtime/events/`, `session_live`, and `session_snapshots` for live streaming and reconnect.

The DSH version is pinned in `services/chat-api/dsh/versions.lock`, `compatibility-matrix.yaml`, `sbom.cdx.json`, and `runtime-host/pnpm-lock.yaml`. Guard scripts reject mixed DSH release trains, legacy-runtime leakage, native-code boundary violations, and supply-chain drift. Do not hand-bump these; use the `services/chat-api/scripts/dsh_upgrade` tooling and keep the guards green.

### Backend services

- **chat-api** (`services/chat-api`, FastAPI, `:8000`): conversation, session, task, skill, plugin, DSH, knowledge-source, scheduled-task, quota, file, and internal gateway endpoints. Routes are mounted under `/api`, with internal model/tool gateways mounted outside that prefix. Runtime dependencies are canonical in `requirements.txt`; `pyproject.toml` is metadata only.
- **admin-api** (`services/admin-api`, FastAPI, `:8100`): control plane for setup, organizations, users, roles, models and model groups, knowledge, skills, tools, external search, audit, quotas, and traffic allocation. It shares the Mongo database with chat-api but uses its own collection/repository boundary. Env vars use the `ASKAI_ADMIN_` prefix. Startup creates indexes and bootstraps admin/directory records.
- **document-parser** (`services/document-parser`, FastAPI + Celery, `:8200`): API and worker ship in the same image; `entrypoint.sh` dispatches `api`, `worker`, or `all`. It parses PDF/DOCX/XLSX/PPTX/CSV/Markdown (Docling, LibreOffice, OCR for embedded images), chunks/optimizes text, calls embedding/reranking providers from Model Center, indexes vectors into Weaviate, and serves retrieval with access scoping. Celery tasks use the `document_processing` Redis queue.
- Data stores: MongoDB (database `gragentic`), Redis, Weaviate (anonymous access, no vectorizer module), and local/OSS storage volumes. Compose volumes are prefixed by `MOVO_VOLUME_PREFIX`.

### Secrets and internal authentication

On first `./movo up`, the one-shot `bootstrap` service writes `deployment-secrets/runtime.env`; every service sources it in its entrypoint. This file holds the shared service tokens, `DSH_*` secrets, and `ASKAI_ADMIN_JWT_SECRET`/`MODEL_CONFIG_SECRET`. The admin JWT secret encrypts Model Center provider credentials and must be identical across admin-api, document-api, and the worker or stored API keys become unreadable. Source-mode development reproduces this via `scripts/dev/internal_service_auth.sh` and persists the generated secret under `.movo-dev/`.

### Product extension seams

Community vs. commercial behavior is injected, not branched inline:

- Backend: `app/product/extensions.py` in chat-api and admin-api expose feature flags, routers, startup hooks, and access-policy hooks. A distribution can load its own module through `MOVO_PRODUCT_EXTENSION_MODULE` / `MOVO_ADMIN_PRODUCT_EXTENSION_MODULE`.
- Frontend: Vite aliases `@movo-product-extension` (user-web) and `@movo-admin-product-extension` (admin-web) default to each app's `src/product/community.ts` and are overridden by `MOVO_PRODUCT_UI_EXTENSION` / `MOVO_ADMIN_PRODUCT_UI_EXTENSION`.
- Keep these seams intact and preserve MOVO branding/copyright in the included frontends; the license requires it.

### Database migrations

Migrations are additive and live in `services/chat-api/app/migrations/`. They run inside the chat-api image:

```bash
cd services/chat-api && python -m app.migrations
```

`./movo update` runs `python -m app.migrations` (currently the additive session-sharing index migration) before replacing a running chat-api. `./movo fix` instead invokes `python -m app.migrations.sequence_repair` to resolve sequence conflicts. Application startup also ensures service-specific indexes, especially in admin-api.

### Frontend structure notes

- `apps/user-web`: Vue 3 + Vite + naive-ui, Tailwind, no vue-router or Pinia — a single-shell workspace driven by composables (`src/composables/`) and platform adapters (`src/platform/`, web vs. Electron/desktop).
- `apps/admin-web`: Vue 3 + Vite + naive-ui with vue-router and Pinia; built with base path `/admin/` and mounted by the gateway below `/admin/`.
- Locale keys are shared/checked by `scripts/check_web_i18n_keys.cjs`; a removed/renamed key will fail CI.

## Contribution constraints

- Run the hygiene script before any PR. It blocks files under `docs/`, `apps/desktop-electron/`, `apps/local-browser-agent/`, `apps/official-website/`, `apps/crm/`, `services/crm-service/`, runtime storage/log paths, and several internal READMEs; it also scans for private deployment URLs, credentials, and secrets.
- Keep changes modular. Do not append unrelated logic to already-large endpoint files or Vue components.
- Document public API, stored-data, environment-variable, deployment-topology, and licensing changes in the PR template.
- Frontend runtime baselines are pinned and checked; avoid dependency or runtime churn without updating the baseline intentionally.
