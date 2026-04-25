# ResourceUpdateServer

Swift/Vapor server for static resource manifest delivery.

## Run

```bash
swift run
```

Optional environment:

- `CI_PUBLISH_TOKEN` (required)
- `ARTIFACT_BACKEND` = `local` | `s3` (default: `local`)
- `S3_BUCKET` (required when `ARTIFACT_BACKEND=s3`)
- `S3_REGION` (default: `us-east-1`)
- `S3_ENDPOINT` (optional; use for MinIO/S3-compatible)
- `S3_ACCESS_KEY_ID` (required when `ARTIFACT_BACKEND=s3`)
- `S3_SECRET_ACCESS_KEY` (required when `ARTIFACT_BACKEND=s3`)
- `S3_PATH_STYLE` = `true` | `false` (default: `true`)

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

### 1) GET latest manifest

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

### 2) GET manifest by version

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

### 3) POST publish manifest

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

### 4) GET patch

`GET /v1/patch/:appId/from/:fromVersion/to/:toVersion`

Response `200 OK`:

```json
{
  "appId": "demoapp",
  "fromVersion": "1.0.0",
  "toVersion": "1.1.0",
  "generatedAt": "2026-04-20T15:35:00Z",
  "operations": [
    { "op": "remove", "path": "config/main.json", "hash": null, "size": null },
    { "op": "add", "path": "fonts/regular.ttf", "hash": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd", "size": 300 },
    { "op": "replace", "path": "images/a.png", "hash": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc", "size": 101 }
  ]
}
```

Response headers:
- `Content-Type: application/json`
- `Content-Disposition: attachment; filename="<from>-<to>.patch.json"`
- `X-Patch-SHA256: <sha256>`

Returns `404 Not Found` when `fromVersion` or `toVersion` manifest does not exist.

### 5) POST resource upload

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

### 6) GET resource by hash

`GET /v1/resource/:appId/hash/:hash`

Response: raw binary (`application/octet-stream`) with headers:
- `X-Resource-Hash`
- `X-Resource-Size`

### 7) GET patch meta

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
    { "path": "images/a.png", "fromHash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "toHash": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc", "size": 101 }
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
