# GitLab CI/CD с автоматическим push в GitHub

Локальный GitLab-сервер с CI/CD пайплайном для:
1. Тестирования при push в ветку `terraform`
2. Автоматического push изменений в GitHub

## Быстрый старт (автоматическая настройка)

```bash
cd task_2_stage_saved_in_s3

# 1. Запуск GitLab
docker compose up -d

# 2. Инициализация (создаёт проект и настраивает GITHUB_TOKEN)
./init-gitlab.sh

# 3. Регистрация Runner
RUNNER_TOKEN=$(docker exec gitlab gitlab-rails runner \
  "puts Gitlab::CurrentSettings.current_application_settings.runners_registration_token" 2>/dev/null)
docker exec gitlab-runner gitlab-runner register \
  --non-interactive \
  --url "http://gitlab:8929" \
  --registration-token "$RUNNER_TOKEN" \
  --executor "docker" \
  --docker-image "alpine:latest" \
  --docker-network-mode "gitlab_network" \
  --docker-privileged

# 4. Настройка clone_url (важно для CI/CD!)
docker exec gitlab-runner sh -c 'sed -i "/executor = \"docker\"/a\\  clone_url = \"http://gitlab:8929\"" /etc/gitlab-runner/config.toml'
docker restart gitlab-runner

# 5. Настройка remote и push
./switch-to-gitlab.sh
git push gitlab terraform
```

## Данные для входа

- **URL**: http://localhost:8929
- **User**: root
- **Password**: выводится скриптом `init-gitlab.sh`

## Скрипты

| Скрипт | Описание |
|--------|----------|
| `init-gitlab.sh` | Автоматически создаёт проект и настраивает GITHUB_TOKEN |
| `switch-to-gitlab.sh` | Добавляет remote `gitlab` в репозиторий |
| `switch-to-github.sh` | Добавляет remote `github` в репозиторий |

## Полная очистка

```bash
docker compose down -v
```

**Важно**: При `docker compose down` все данные удаляются (volumes не сохраняются между перезапусками).

## Ручная настройка (альтернатива)

### Настройка GitHub-токена

Создайте файл `.env`:
```bash
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Токен должен иметь права `repo` для push.

### Получение пароля root

```bash
docker exec gitlab grep 'Password:' /etc/gitlab/initial_root_password
```

### Проверка работы пайплайна

```bash
git checkout terraform
git commit --allow-empty -m "Test CI/CD"
git push gitlab terraform
```

Проверьте в GitLab -> CI/CD -> Pipelines.

---

## Структура CI/CD пайплайна

Пайплайн определён в файле `.gitlab-ci.yml` в корне репозитория:

```yaml
stages:
  - test      # Тестирование
  - deploy    # Push в GitHub

# Hello World тест
hello_world:
  stage: test
  script:
    - echo "Hello World from GitLab CI/CD!"

# Валидация Terraform
terraform_validate:
  stage: test
  script:
    - terraform validate

# Push в GitHub
push_to_github:
  stage: deploy
  script:
    - git push github HEAD:main
```

---

## Полезные команды

### Управление GitLab

```bash
# Просмотр логов
docker compose logs -f gitlab

# Перезапуск GitLab
docker compose restart gitlab

# Остановка всего
docker compose down

# Остановка с удалением volumes (ОСТОРОЖНО: удалит все данные!)
docker compose down -v
```

### Работа с GitLab Runner

```bash
# Просмотр зарегистрированных Runner'ов
docker exec gitlab-runner gitlab-runner list

# Проверка статуса Runner
docker exec gitlab-runner gitlab-runner verify

# Удаление всех Runner'ов
docker exec gitlab-runner gitlab-runner unregister --all-runners
```

### Отладка CI/CD

```bash
# Просмотр логов Runner
docker compose logs -f gitlab-runner

# Проверка переменных CI/CD (в пайплайне)
# Добавьте в .gitlab-ci.yml:
#   script:
#     - env | grep CI_
```

---

## Устранение проблем

### GitLab не запускается

1. Проверьте логи:
   ```bash
   docker compose logs gitlab
   ```

2. Убедитесь, что достаточно ресурсов (минимум 4GB RAM)

3. Подождите 3-5 минут — первый запуск долгий

### Пайплайн не запускается

1. Проверьте, что Runner зарегистрирован:
   ```bash
   docker exec gitlab-runner gitlab-runner list
   ```

2. Проверьте, что Runner активен в GitLab UI (Settings -> CI/CD -> Runners)

3. Убедитесь, что `.gitlab-ci.yml` корректен:
   ```bash
   # В GitLab: CI/CD -> Editor -> Validate
   ```

### Push в GitHub не работает

1. Проверьте GITHUB_TOKEN:
   - Токен добавлен в переменные CI/CD?
   - Токен имеет права `repo`?
   - Токен не истёк?

2. Проверьте URL репозитория в `.gitlab-ci.yml`

### Ошибка "Runner not available"

Runner может быть не подключён к сети GitLab:

```bash
# Проверяем сеть
docker network inspect gitlab_network

# Перезапускаем Runner
docker compose restart gitlab-runner
```

---

## Конфигурация

### Изменение порта GitLab

В `docker-compose.yaml` измените:
```yaml
ports:
  - "НОВЫЙ_ПОРТ:8929"
```

И в `GITLAB_OMNIBUS_CONFIG`:
```ruby
external_url 'http://localhost:НОВЫЙ_ПОРТ'
nginx['listen_port'] = НОВЫЙ_ПОРТ
```

### Добавление HTTPS

Для production-использования рекомендуется добавить HTTPS через reverse proxy (nginx, traefik).

---

## Ссылки

- [GitLab Docker Installation](https://docs.gitlab.com/ee/install/docker.html)
- [GitLab Runner Installation](https://docs.gitlab.com/runner/install/docker.html)
- [GitLab CI/CD Configuration](https://docs.gitlab.com/ee/ci/yaml/)
- [GitHub Personal Access Tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token)
