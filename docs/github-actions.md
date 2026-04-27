# GitHub Actions

В репозитории добавлен workflow GitHub Actions для четырёх задач:

- запуск тестов серверной части;
- запуск тестов SDK;
- валидация директории статических ресурсов;
- ручная публикация ресурсов, manifest и patch-артефактов.

## Workflow file

- `.github/workflows/ci.yml`

## Triggers

Workflow запускается для:

- `push`;
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
  вручную публикует ресурсы и manifest через `swift run ResourceUpdateServer publish-local`
- `publish_patches`:
  вручную генерирует patch-артефакты между новой версией и указанными предыдущими версиями

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
- `publish_patches`
- `resource_version`
- `patch_from_versions`

## Example

Repository variables:

```text
STATIC_RESOURCES_DIR=mobile-resources
RESOURCE_APP_ID=demoapp
RESOURCE_UPDATE_BASE_URL=https://updates.example.com/
```

Repository secret:

```text
CI_PUBLISH_TOKEN=***
```

Manual run example:

- `publish_resources = true`
- `publish_patches = true`
- `resource_version = 1.1.0`
- `patch_from_versions = 1.0.0,1.0.1`

## Notes

- На `push` и `pull_request` workflow прогоняет тесты и валидацию.
- Публикация ресурсов не выполняется автоматически на каждый push.
- Публикация делается через `workflow_dispatch`, чтобы управлять релизом вручную.
- `publish_patches` должен запускаться только вместе с `publish_resources` или после него для уже опубликованной версии.
- В server jobs workflow временно патчит транзитивную зависимость `apple/swift-configuration`, чтобы обойти несовместимость сборки в GitHub Actions (`Data.bytes` в `FileProvider.swift`).
