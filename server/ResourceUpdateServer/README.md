# ResourceUpdateServer

Swift/Vapor server for static resource manifest delivery.

## Run

```bash
swift run
```

Optional environment:

- `CI_PUBLISH_TOKEN` (default: `dev-ci-token`)
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
  "version": "1.1.0",
  "generatedAt": "2026-04-20T15:30:00Z",
  "resources": [
    { "path": "images/a.png", "hash": "aaaaaaaa", "size": 100 }
  ]
}
```

### 2) GET manifest by version

`GET /v1/manifest/:appId/version/:version`

Response `200 OK`:

```json
{
  "version": "1.0.0",
  "generatedAt": "2026-04-20T15:00:00Z",
  "resources": [
    { "path": "images/a.png", "hash": "aaaaaaaa", "size": 100 }
  ]
}
```

### 3) POST publish manifest

`POST /v1/manifest/:appId/version/:version`

Requires CI auth token:
- `X-CI-Token: <token>` or
- `Authorization: Bearer <token>`

Request body:

```json
{
  "version": "1.1.0",
  "generatedAt": "2026-04-20T15:30:00Z",
  "resources": [
    { "path": "images/a.png", "hash": "cccccccc", "size": 101 },
    { "path": "fonts/regular.ttf", "hash": "dddddddd", "size": 300 }
  ]
}
```

Responses:
- `201 Created` when saved
- `409 Conflict` if this version already exists
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
    { "op": "add", "path": "fonts/regular.ttf", "hash": "dddddddd", "size": 300 },
    { "op": "replace", "path": "images/a.png", "hash": "cccccccc", "size": 101 }
  ]
}
```

Returns `404 Not Found` when `fromVersion` or `toVersion` manifest does not exist.

### 5) GET patch meta

`GET /v1/patch/:appId/from/:fromVersion/to/:toVersion/meta`

Response `200 OK`:

```json
{
  "appId": "demoapp",
  "fromVersion": "1.0.0",
  "toVersion": "1.1.0",
  "generatedAt": "2026-04-20T15:35:00Z",
  "added": [
    { "path": "fonts/regular.ttf", "hash": "dddddddd", "size": 300 }
  ],
  "changed": [
    { "path": "images/a.png", "fromHash": "aaaaaaaa", "toHash": "cccccccc", "size": 101 }
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
1. Validate input and version constraints.
2. Stage manifest locally (`.pending`).
3. Upload artifacts (manifest + patch-meta + patch document).
4. Commit manifest file.
5. Switch `latest` pointer.

If any step fails, staged files and uploaded artifacts are rolled back best-effort.

## Artifact storage

- `local`: artifacts are stored under `Public/artifacts/...`.
- `s3`: implemented via Soto S3 client (AWS + S3-compatible endpoints).
