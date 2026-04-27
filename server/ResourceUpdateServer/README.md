# ResourceUpdateServer

Swift/Vapor server for static resource manifest delivery.

## Run

```bash
swift run
```

Docker:

```bash
docker build -t resource-update-server .
docker run --rm \
  -p 8080:8080 \
  -e CI_PUBLISH_TOKEN=dev-ci-token \
  -e SIGNING_ACTIVE_KEY_ID=main \
  -e SIGNING_KEYS_JSON='[{"keyId":"main","privateKeyBase64":"<base64-private-key>","createdAt":"2026-04-26T00:00:00Z"}]' \
  resource-update-server
```

Docker Compose:

```bash
cp compose.yml compose.local.yml
# подставь реальный privateKeyBase64 вместо REPLACE_WITH_BASE64_PRIVATE_KEY
docker compose -f compose.local.yml up --build
```

После запуска:
- API: `http://127.0.0.1:8081`
- Swagger UI: `http://127.0.0.1:8081/docs`
- OpenAPI: `http://127.0.0.1:8081/openapi.yaml`

Для Docker Compose host-порт можно переопределить:

```bash
HOST_PORT=8080 docker compose -f compose.local.yml up --build
```

HTTPS via reverse proxy (Caddy with internal CA for local/stage use):

```bash
docker compose -f compose.https.yml up --build
```

После запуска HTTPS доступен на:
- API: `https://127.0.0.1:8443`
- Swagger UI: `https://127.0.0.1:8443/docs`
- OpenAPI: `https://127.0.0.1:8443/openapi.yaml`

Для `curl` в локальной среде с internal CA:

```bash
curl -k https://127.0.0.1:8443/openapi.yaml
```

Local CLI modes (without CI pipeline):

```bash
swift run ResourceUpdateServer publish-local \
  --base-url http://127.0.0.1:8080/ \
  --app-id demoapp \
  --version 1.2.0 \
  --resources-dir ./SampleResources \
  --token dev-ci-token
```

`publish-local` does:
- recursively scans `--resources-dir`;
- computes `sha256` + file size for each resource;
- uploads resources via `POST /v1/resource/:appId/upload`;
- publishes manifest via `POST /v1/manifest/:appId/version/:version`;
- prints summary (uploaded/skipped/manifest status).

Dry run (build manifest locally, no uploads):

```bash
swift run ResourceUpdateServer dry-run \
  --app-id demoapp \
  --version 1.2.0 \
  --resources-dir ./SampleResources \
  --json
```

Validation only:

```bash
swift run ResourceUpdateServer validate \
  --app-id demoapp \
  --version 1.2.0 \
  --resources-dir ./SampleResources
```

Cleanup old versions/resources (local storage):

```bash
swift run ResourceUpdateServer cleanup \
  --app-id demoapp \
  --keep-last 3 \
  --public-dir ./Public
```

Background cleanup scheduler:
- runs inside the public server process
- periodically applies the same retention policy as CLI `cleanup`
- keeps latest `N` versions, removes obsolete patch artifacts and unused resource binaries

Secure transport:
- public deployment must terminate TLS before the Vapor app;
- local/stage HTTPS can be started with `compose.https.yml` and `deploy/Caddyfile`;
- production ingress/reverse proxy may be Nginx, Caddy, Traefik or cloud LB, but client traffic to the public API must use HTTPS.

Optional flags:
- `--min-sdk-version` (default: `1.0`)
- `--request-id` (default: random UUID)
- `--token` (if omitted, reads `CI_PUBLISH_TOKEN`)

Optional environment:

- `CI_PUBLISH_TOKEN` (required)
- `ARTIFACT_BACKEND` = `local` | `s3` (default: `local`)
- `S3_BUCKET` (required when `ARTIFACT_BACKEND=s3`)
- `S3_REGION` (default: `us-east-1`)
- `S3_ENDPOINT` (optional; use for MinIO/S3-compatible)
- `S3_ACCESS_KEY_ID` (required when `ARTIFACT_BACKEND=s3`)
- `S3_SECRET_ACCESS_KEY` (required when `ARTIFACT_BACKEND=s3`)
- `S3_PATH_STYLE` = `true` | `false` (default: `true`)
- `SIGNING_KEYS_JSON` (preferred, required for multi-key mode): JSON array:
  - `[{ "keyId": "...", "privateKeyBase64": "...", "createdAt": "2026-04-25T00:00:00Z" }]`
- `SIGNING_ACTIVE_KEY_ID` (required when `SIGNING_KEYS_JSON` is set)
- Backward-compatible single-key mode:
  - `SIGNING_PRIVATE_KEY_BASE64` (Ed25519 private key raw 32 bytes in base64)
  - `SIGNING_KEY_ID` (optional, default: `main`)
- `METRICS_TOKEN` (optional, required to enable secured metrics access by token)
- `METRICS_ALLOWLIST` (optional, comma-separated client IP allowlist for metrics, e.g. `127.0.0.1,::1,10.0.0.5`)
- `METRICS_BIND_HOST` (optional, default: `127.0.0.1`, used together with `METRICS_PORT`)
- `METRICS_PORT` (optional; if set, metrics endpoints are moved to a dedicated listener and hidden from the public app)
- `RATE_LIMIT_BACKEND` = `memory` | `shared-file` (default: `memory`)
- `RATE_LIMIT_UPDATES_PER_MINUTE` (optional, default: `60`, set `0` to disable)
- `RATE_LIMIT_PATCH_PER_MINUTE` (optional, default: `20`, set `0` to disable)
- `RATE_LIMIT_SHARED_DIR` (optional; used by `shared-file` backend, defaults to `Public/rate-limit-store`)
- `CLEANUP_INTERVAL_SECONDS` (optional; if set to `> 0`, enables periodic background cleanup)
- `CLEANUP_KEEP_LAST` (optional, default: `3`)
- `CLEANUP_APP_IDS` (optional, comma-separated app ids; if omitted, cleanup scans all apps under `Public/manifests`)

## Test

```bash
swift test
```

Optional S3 integration test (for MinIO/AWS):

```bash
RUN_S3_INTEGRATION=true \
S3_BUCKET=resource-updater-test \
S3_REGION=us-east-1 \
S3_ENDPOINT=http://localhost:9000 \
S3_ACCESS_KEY_ID=minioadmin \
S3_SECRET_ACCESS_KEY=minioadmin \
S3_PATH_STYLE=true \
swift test
```

## API v1

Base path: `/v1`

Swagger/OpenAPI:
- `GET /openapi.yaml` — статическая OpenAPI 3.0.3 спецификация
- `GET /docs` — Swagger UI поверх `openapi.yaml`
- `GET /docs` использует `swagger-ui-dist` с CDN, сама спецификация лежит локально в `Public/openapi.yaml`

### 1) GET signing keys

`GET /v1/keys`

Response `200 OK`:

```json
[
  {
    "keyId": "k-2026-04",
    "alg": "ed25519",
    "publicKeyBase64": "...",
    "createdAt": "2026-04-25T00:00:00Z",
    "active": true
  }
]
```

`GET /v1/keys/:keyId` returns one key or `404`.

### 2) GET latest manifest

`GET /v1/manifest/:appId/latest`

Response `200 OK`:

```json
{
  "schemaVersion": 1,
  "minSdkVersion": "1.0",
  "version": "1.1.0",
  "generatedAt": "2026-04-20T15:30:00Z",
  "resources": [
    { "path": "images/a.png", "hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "size": 100 }
  ]
}
```

### 3) GET manifest by version

`GET /v1/manifest/:appId/version/:version`

Response `200 OK`:

```json
{
  "schemaVersion": 1,
  "minSdkVersion": "1.0",
  "version": "1.0.0",
  "generatedAt": "2026-04-20T15:00:00Z",
  "resources": [
    { "path": "images/a.png", "hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "size": 100 }
  ]
}
```

Response headers for manifest integrity/authenticity:
- `X-Manifest-SHA256: <sha256>`
- `X-Signature: <base64-ed25519-signature>`
- `X-Signature-Alg: ed25519`
- `X-Signature-Key-Id: <key-id>`

### 4) GET update decision

`GET /v1/updates/:appId?fromVersion=<version>&sdkVersion=<sdk>`

Response `200 OK`:

```json
{
  "decision": "patch",
  "appId": "demoapp",
  "fromVersion": "1.0.0",
  "latestVersion": "1.1.0",
  "sdkVersion": "2.1",
  "reason": "patch-available",
  "manifest": {
    "url": "/v1/manifest/demoapp/version/1.1.0",
    "sha256": "....",
    "signature": "....",
    "signatureAlgorithm": "ed25519",
    "signatureKeyId": "main",
    "size": 512
  },
  "patch": {
    "url": "/v1/patch/demoapp/from/1.0.0/to/1.1.0",
    "sha256": "....",
    "signature": "....",
    "signatureAlgorithm": "ed25519",
    "signatureKeyId": "main",
    "size": 928
  }
}
```

Response headers for decision integrity/authenticity:
- `X-Updates-SHA256: <sha256>`
- `X-Updates-Signature: <base64-ed25519-signature>`
- `X-Updates-Signature-Alg: ed25519`
- `X-Updates-Signature-Key-Id: <key-id>`

Decisions:
- `no-update`: `fromVersion` already equals latest.
- `manifest-only`: patch is not applicable (missing params / sdk too old / patch unavailable).
- `patch`: patch can be applied.

SDK validation for `/v1/updates`:
- verify `sha256(rawBody)` equals `X-Updates-SHA256`;
- verify signature in `X-Updates-Signature` for raw body using public key from `/v1/keys`;
- trust `decision/reason/url` only after signature verification.

Cache headers and conditional GET:
- `GET /v1/manifest/:appId/latest`: `Cache-Control: public, max-age=30, must-revalidate`
- `GET /v1/updates/:appId`: `Cache-Control: public, max-age=15, must-revalidate`
- `GET /v1/manifest/:appId/version/:version`: `Cache-Control: public, max-age=31536000, immutable`
- `GET /v1/patch/:appId/from/:fromVersion/to/:toVersion`: `Cache-Control: public, max-age=31536000, immutable`
- all endpoints above return `ETag`, support `If-None-Match`, and may return `304 Not Modified`.

Rate limiting:
- `GET /v1/updates/:appId` is limited per `clientIP + appId`
- `GET /v1/patch/:appId/from/:fromVersion/to/:toVersion` is limited per `clientIP + appId + fromVersion + toVersion`
- exceed limit => `429 Too Many Requests`
- response includes `Retry-After`
- error body stays in the standard JSON envelope format
- backend is configurable:
  - `memory`: per-process in-memory counters
  - `shared-file`: counters shared through filesystem-backed store for multiple server processes on the same host/shared volume

### 5) GET API metrics

`GET /v1/metrics`

By default this route is served from the main application listener.

If `METRICS_PORT` is set:
- `/metrics` and `/v1/metrics` are removed from the public listener
- a dedicated metrics-only listener is started on `METRICS_BIND_HOST:METRICS_PORT`
- only metrics routes are exposed there

Requires metrics access:
- `X-Metrics-Token: <token>` or `Authorization: Bearer <token>` when `METRICS_TOKEN` is set
- client IP must be in `METRICS_ALLOWLIST` when allowlist is set

Response `200 OK`:

```json
{
  "generatedAt": "2026-04-25T20:00:00Z",
  "endpoints": [
    {
      "endpoint": "updates",
      "totalRequests": 42,
      "status2xx": 40,
      "status4xx": 0,
      "status5xx": 0,
      "status304": 8,
      "notModifiedRatio": 0.1904761905,
      "averageResponseBytes": 512.8,
      "latencyMs": { "p50": 1.2, "p95": 3.8, "p99": 5.1 }
    }
  ]
}
```

Metrics are aggregated separately for `updates`, `manifest`, `patch`.
If metrics protection is not configured, metrics endpoints return `404 Not Found`.

Prometheus export:

`GET /metrics`

Response `200 OK` with `Content-Type: text/plain; version=0.0.4; charset=utf-8`

Requires the same metrics access rules as `/v1/metrics`.

Example:

```text
# HELP resource_update_api_requests_total Total API requests by endpoint group and status class.
# TYPE resource_update_api_requests_total counter
resource_update_api_requests_total{endpoint="manifest",status_class="2xx"} 10
resource_update_api_requests_304_total{endpoint="manifest"} 3
resource_update_api_not_modified_ratio{endpoint="manifest"} 0.3
resource_update_api_response_bytes_avg{endpoint="manifest"} 245.4
# TYPE resource_update_api_latency_ms histogram
resource_update_api_latency_ms_bucket{endpoint="manifest",le="1"} 4
resource_update_api_latency_ms_bucket{endpoint="manifest",le="5"} 10
resource_update_api_latency_ms_bucket{endpoint="manifest",le="+Inf"} 10
resource_update_api_latency_ms_sum{endpoint="manifest"} 18.4
resource_update_api_latency_ms_count{endpoint="manifest"} 10
# TYPE resource_update_api_response_bytes histogram
resource_update_api_response_bytes_bucket{endpoint="manifest",le="1024"} 10
resource_update_api_response_bytes_bucket{endpoint="manifest",le="+Inf"} 10
resource_update_api_response_bytes_sum{endpoint="manifest"} 2454
resource_update_api_response_bytes_count{endpoint="manifest"} 10
```

### 6) POST publish manifest

`POST /v1/manifest/:appId/version/:version`

Requires CI auth token:
- `X-CI-Token: <token>` or
- `Authorization: Bearer <token>`

Requires idempotency key:
- `X-Request-Id: <uuid>`

Request body:

```json
{
  "schemaVersion": 1,
  "minSdkVersion": "1.0",
  "version": "1.1.0",
  "generatedAt": "2026-04-20T15:30:00Z",
  "resources": [
    { "path": "images/a.png", "hash": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc", "size": 101 },
    { "path": "fonts/regular.ttf", "hash": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd", "size": 300 }
  ]
}
```

Responses:
- `201 Created` when saved
- `200 OK` for idempotent retry with same `X-Request-Id` and same payload
- `409 Conflict` if same `X-Request-Id` was reused with different payload
- `400 Bad Request` for validation errors
- `401 Unauthorized` for missing/invalid CI token

### 7) POST patch artifact upload

`POST /v1/patch/:appId/from/:fromVersion/to/:toVersion/upload`

Requires CI auth token:
- `X-CI-Token: <token>` or
- `Authorization: Bearer <token>`

Requires idempotency key:
- `X-Request-Id: <uuid>`

Headers:
- `X-Patch-SHA256` (sha256 hex, 64 chars)
- `X-Patch-Size` (optional, bytes)

Body: raw bytes of patch artifact (`application/json` or `application/octet-stream`).

Responses:
- `201 Created` when uploaded
- `200 OK` for idempotent retry with same `X-Request-Id` and same payload hash
- `409 Conflict` if same `X-Request-Id` was reused with different payload
- `400 Bad Request` for hash/size mismatch
- `404 Not Found` if `fromVersion` or `toVersion` manifest does not exist

### 8) GET patch

`GET /v1/patch/:appId/from/:fromVersion/to/:toVersion`

Response `200 OK`:

```json
{
  "appId": "demoapp",
  "fromVersion": "1.0.0",
  "toVersion": "1.1.0",
  "generatedAt": "2026-04-20T15:35:00Z",
  "operations": [
    { "op": "remove", "path": "config/main.json", "hash": null, "size": null, "dataBase64": null, "delta": null },
    { "op": "add", "path": "fonts/regular.ttf", "hash": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd", "size": 300, "dataBase64": "AAECAwQF...", "delta": null },
    {
      "op": "replace",
      "path": "images/a.png",
      "hash": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      "size": 101,
      "dataBase64": null,
      "delta": {
        "algorithm": "splice-v1",
        "baseHash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "baseSize": 100,
        "targetHash": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
        "targetSize": 101,
        "operations": [
          { "offset": 6, "deleteLength": 3, "dataBase64": "R0lG" }
        ]
      }
    }
  ]
}
```

Response headers:
- `Content-Type: application/json`
- `Content-Disposition: attachment; filename="<from>-<to>.patch.json"`
- `X-Patch-SHA256: <sha256>`
- `X-Signature: <base64-ed25519-signature>`
- `X-Signature-Alg: ed25519`
- `X-Signature-Key-Id: <key-id>`

Returns `404 Not Found` when `fromVersion` or `toVersion` manifest does not exist.

SDK apply rules:
- verify `X-Patch-SHA256` against raw response body;
- parse operations in given order;
- execute patch in transaction mode:
  - keep snapshot of current local resources before first operation;
  - do not partially commit final state until all validations pass.
- `remove`: delete local file by `path`;
- `add`: decode `dataBase64`, verify `sha256(data) == hash` and `data.count == size`, then write file by `path`;
- `replace` (`splice-v1`):
  - verify base resource exists and `sha256(base) == delta.baseHash` and `base.count == delta.baseSize`;
  - `delta.operations` may contain one or multiple isolated splice edits;
  - apply each splice operation in reverse order by `offset`:
    - validate `offset >= 0`, `deleteLength >= 0`,
    - validate `offset + deleteLength <= currentData.count`,
    - replace the target range with decoded `dataBase64`;
  - verify final bytes: `sha256(result) == delta.targetHash == hash`,
    `result.count == delta.targetSize == size`;
- if any operation or validation fails, rollback to snapshot and return error.

Performance verification:
- automated smoke tests validate local server timings for `GET /v1/updates` under `300 ms` and 5 MB resource upload/download under `5 s`;
- run them with:

```bash
swift test
```

- these checks validate implementation overhead on a local deployment profile; end-to-end Internet latency still depends on network path, reverse proxy and artifact storage backend.

### 9) POST resource upload

`POST /v1/resource/:appId/upload`

Headers:
- `X-CI-Token` or `Authorization: Bearer`
- `X-Resource-Path` (relative path in app bundle)
- `X-Resource-Hash` (sha256 hex, 64 chars)
- `X-Resource-Size` (optional, bytes)

Request body: raw binary bytes of resource file.

Responses:
- `201 Created` for new resource
- `200 OK` if the same hash already existed
- `400 Bad Request` for hash/size mismatch
- `401 Unauthorized` for invalid publish token

### 10) GET resource by hash

`GET /v1/resource/:appId/hash/:hash`

Response: raw binary (`application/octet-stream`) with headers:
- `X-Resource-Hash`
- `X-Resource-Size`

### 11) GET patch meta

`GET /v1/patch/:appId/from/:fromVersion/to/:toVersion/meta`

Response `200 OK`:

```json
{
  "appId": "demoapp",
  "fromVersion": "1.0.0",
  "toVersion": "1.1.0",
  "generatedAt": "2026-04-20T15:35:00Z",
  "added": [
    { "path": "fonts/regular.ttf", "hash": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd", "size": 300 }
  ],
  "changed": [
    { "path": "images/a.png", "fromHash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "fromSize": 100, "toHash": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc", "size": 101 }
  ],
  "removed": [
    "config/main.json"
  ]
}
```

Returns `404 Not Found` when `fromVersion` or `toVersion` manifest does not exist.

## Error format

All API errors use a single JSON envelope:

```json
{
  "error": {
    "code": "bad_request",
    "message": "resource.hash contains invalid characters",
    "requestId": "A1B2C3D4-..."
  }
}
```

## Publish flow

Publish in server storage is performed as:
1. Upload resource binaries via `POST /v1/resource/:appId/upload`.
2. Validate manifest input, auth token, and idempotency key.
3. Stage manifest and patch document locally (`.pending` files).
4. Upload patch artifact to artifact backend (when previous version exists).
5. Commit manifest and patch document in local storage.
6. Switch `latest` pointer.
7. Save idempotency record.

If any step fails, staged files and uploaded artifacts are rolled back best-effort.

## Artifact storage

- `local`: artifacts are stored under `Public/artifacts/...`.
- `s3`: implemented via Soto S3 client (AWS + S3-compatible endpoints).

Patch serving priority:
1. local patch artifact cache (`Public/manifests/<appId>/patches/...`);
2. artifact backend (`artifacts/apps/<appId>/patches/...` or S3 key);
3. on-the-fly generation from manifests/resources (fallback).
