# GitLab с CI/CD и интеграцией с GitHub

Этот проект разворачивает локальный GitLab-сервер с CI/CD пайплайном, который:
1. Запускает тесты при push в ветку `terraform`
2. Автоматически делает push изменений в GitHub

## Быстрый старт

### 1. Подготовка

Убедитесь, что установлены:
- Docker
- Docker Compose

### 2. Настройка GitHub-токена

Отредактируйте файл `.env`:

```bash
# Токен GitHub для push в репозиторий
# Получить: GitHub -> Settings -> Developer settings -> Personal access tokens
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**Важно:** Токен должен иметь права `repo` для push в репозиторий.

### 3. Запуск GitLab

```bash
cd task_2_stage_saved_in_s3

# Сборка (если есть Dockerfile)
docker compose build

# Запуск
docker compose up -d

# Ожидание запуска GitLab (может занять 3-5 минут)
for i in {1..60}; do
  if curl -s -f http://localhost:8929/-/health > /dev/null 2>&1; then
    echo "✓ GitLab готов к работе (попытка $i)"
    break
  fi
  echo "Ожидание GitLab... (попытка $i/60)"
  sleep 5
done
```

### 4. Первоначальная настройка GitLab

#### Получение пароля root:

```bash
docker exec gitlab grep 'Password:' /etc/gitlab/initial_root_password
```

пароль root: pD4j5iSfgmqnn+oFM/ZNGIsHjk9fZVuy2BcKSIDeW/o=

#### Вход в GitLab:

1. Откройте http://localhost:8929
2. Войдите как `root` с паролем из предыдущего шага
3. **Сразу смените пароль!** (GitLab попросит это сделать)

### 5. Создание проекта в GitLab

1. Нажмите **"New project"** -> **"Create blank project"**
2. Название: `architecture-future_2_0`
3. Visibility: Private
4. **Не** инициализируйте README

### 6. Push существующего репозитория в GitLab

```bash
cd /home/felix/Projects/yandex_swa_pro/architecture-future_2_0

# Добавляем GitLab как remote
git remote add gitlab http://localhost:8929/root/architecture-future_2_0.git

# Push всех веток
git push gitlab --all

# Push ветки terraform (если нужно создать)
git checkout -b terraform
git push gitlab terraform
```

### 7. Настройка GitHub-токена в GitLab CI/CD

1. Откройте проект в GitLab
2. Перейдите в **Settings** -> **CI/CD** -> **Variables**
3. Нажмите **"Add variable"**:
   - Key: `GITHUB_TOKEN`
   - Value: ваш GitHub Personal Access Token
   - Type: Variable
   - Flags: ✓ Mask variable (скрыть в логах)

### 8. Регистрация GitLab Runner

```bash
# Получаем registration token из GitLab:
# Settings -> CI/CD -> Runners -> "New project runner" или используем существующий токен

# Регистрируем Runner
docker exec -it gitlab-runner gitlab-runner register \
  --non-interactive \
  --url "http://gitlab:8929" \
  --registration-token "YOUR_REGISTRATION_TOKEN" \
  --executor "docker" \
  --docker-image "alpine:latest" \
  --description "docker-runner" \
  --docker-network-mode "gitlab_network"
```

**Альтернатива (через UI):**
1. GitLab -> Settings -> CI/CD -> Runners
2. Скопируйте registration token
3. Выполните команду выше с этим токеном

### 9. Проверка работы пайплайна

```bash
# Создаём коммит в ветке terraform
git checkout terraform
echo "# Test commit $(date)" >> test.md
git add test.md
git commit -m "Test CI/CD pipeline"
git push gitlab terraform
```

Перейдите в GitLab -> CI/CD -> Pipelines и убедитесь, что пайплайн запустился.

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
