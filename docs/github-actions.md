# GitHub Actions

В репозитории добавлен workflow GitHub Actions для четырёх задач:

- запуск тестов серверной части;
- запуск тестов SDK;
- валидация директории статических ресурсов;
- автоматическая публикация ресурсов и manifest после merge/push в ветку `main`;
- ручная публикация ресурсов и manifest через `workflow_dispatch`.

## Workflow file

- `.github/workflows/ci.yml`

## Triggers

Workflow запускается для:

- `push` в ветку `main`;
- `pull_request`;
- `workflow_dispatch`.

## Jobs

- `server_tests`:
  запускает `swift test` в `server/ResourceUpdateServer`
- `sdk_tests`:
  запускает `swift test` в `sdk/ResourceUpdater`
- `resource_validate`:
  проверяет директорию ресурсов и собирает manifest через `swift run ResourceUpdateServer validate`
- `publish_resources`:
  публикует ресурсы и manifest через `swift run ResourceUpdateServer publish-local` на `push` в `main` или при ручном запуске с `publish_resources = true`

## Repository variables

Нужно задать в `Settings -> Secrets and variables -> Actions -> Variables`:

- `STATIC_RESOURCES_DIR`
- `RESOURCE_APP_ID`
- `RESOURCE_UPDATE_BASE_URL`

## Repository secrets

Нужно задать в `Settings -> Secrets and variables -> Actions -> Secrets`:

- `CI_PUBLISH_TOKEN`

## workflow_dispatch inputs

При ручном запуске workflow можно передать:

- `publish_resources`
- `resource_version`

## Example

Repository variables:

```text
STATIC_RESOURCES_DIR=mobile-resources
RESOURCE_APP_ID=demoapp
RESOURCE_UPDATE_BASE_URL=http://81.26.184.66:8081/
```

Repository secret:

```text
CI_PUBLISH_TOKEN=***
```

Manual run example:

- `publish_resources = true`
- `resource_version = 1.1.0`

## Notes

- На `pull_request` workflow прогоняет тесты и валидацию без публикации на сервер.
- На `push` в ветку `main` workflow после успешных тестов и валидации автоматически публикует ресурсы на сервер.
- При публикации нового manifest сервер сам генерирует patch относительно предыдущей latest-версии.
- Ручная публикация через `workflow_dispatch` сохранена для отладки и повторной публикации с указанным `resource_version`.
- В server jobs workflow временно патчит транзитивную зависимость `apple/swift-configuration`, чтобы обойти несовместимость сборки в GitHub Actions (`Data.bytes` в `FileProvider.swift`).
