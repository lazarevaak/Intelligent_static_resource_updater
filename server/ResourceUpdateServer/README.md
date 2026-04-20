# ResourceUpdateServer

Swift/Vapor server for static resource manifest delivery.

## Run

```bash
swift run
```

## Test

```bash
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

### 4) GET patch meta

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
