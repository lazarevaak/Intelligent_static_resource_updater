# GitLab CI/CD

В репозитории добавлен минимальный pipeline для четырёх задач:

- запуск тестов серверной части;
- запуск тестов SDK;
- валидация и публикация статических ресурсов через `publish-local`.
- явная генерация patch-артефактов как отдельный job.

## Jobs

- `server_tests`:
  запускает `swift test` в `server/ResourceUpdateServer`
- `sdk_tests`:
  запускает `swift test` в `sdk/ResourceUpdater`
- `resource_validate`:
  проверяет директорию ресурсов и собирает manifest через `swift run ResourceUpdateServer validate`
- `publish_resources`:
  публикует ресурсы и manifest через `swift run ResourceUpdateServer publish-local`
- `publish_patches`:
  принудительно генерирует patch-артефакты между уже опубликованной версией и указанными предыдущими версиями

## Required variables

Для `resource_validate`:

- `STATIC_RESOURCES_DIR`:
  путь до директории со статическими ресурсами относительно корня репозитория
- `RESOURCE_APP_ID`:
  идентификатор приложения

Для `publish_resources`:

- `STATIC_RESOURCES_DIR`
- `RESOURCE_APP_ID`
- `RESOURCE_UPDATE_BASE_URL`:
  публичный base URL сервера обновлений, например `https://updates.example.com/`
- `CI_PUBLISH_TOKEN`:
  токен публикации, совпадающий с конфигурацией сервера

Для `publish_patches`:

- `RESOURCE_APP_ID`
- `RESOURCE_UPDATE_BASE_URL`
- `PATCH_FROM_VERSIONS`:
  список исходных версий через запятую, например `1.0.0,1.0.1`

Опциональные переменные:

- `RESOURCE_VERSION`:
  версия публикуемого набора ресурсов; если не задана, используется `CI_COMMIT_TAG`, иначе `CI_COMMIT_SHORT_SHA`
- `MIN_SDK_VERSION`:
  минимальная версия SDK в manifest, по умолчанию `1.0`

## Example

Если ресурсы лежат в `mobile-resources/`, то можно задать:

```text
STATIC_RESOURCES_DIR=mobile-resources
RESOURCE_APP_ID=demoapp
RESOURCE_UPDATE_BASE_URL=https://updates.example.com/
CI_PUBLISH_TOKEN=***
MIN_SDK_VERSION=1.0
PATCH_FROM_VERSIONS=1.0.0,1.0.1
```

## Notes

- `publish_resources` запускается вручную только для default branch и tag pipeline.
- `publish_patches` запускается отдельно после `publish_resources` и подходит для явной демонстрации формирования patch в CI/CD.
- Если `STATIC_RESOURCES_DIR` не задана, job `resource_validate` завершается сообщением о пропуске.
- Для фактической публикации сервер обновлений должен быть уже развернут и доступен по `RESOURCE_UPDATE_BASE_URL`.
- Job `publish_patches` вызывает публичные endpoints `patch meta` и `patch`, тем самым принудительно создавая patch-артефакты на сервере для указанных версий.
