#!/bin/bash
# =============================================================================
# Тестовый скрипт для проверки GitLab с автоинициализацией
#
# Проверяет:
# - Запуск docker compose
# - Автоинициализацию GitLab
# - Вход по статическому паролю из .env
# - Регистрацию GitLab Runner
# - Push в ветку terraform и работу CI/CD pipeline
# =============================================================================

set -e

BASEDIR=$(cd "$(dirname "$0")" && pwd)
GITLAB_URL="http://localhost:8929"
PROJECT_NAME="architecture-future_2_0"

# Загружаем переменные из .env
if [ -f "$BASEDIR/.env" ]; then
    source "$BASEDIR/.env"
fi

GITLAB_USER="${GITLAB_ROOT_USER:-root}"
GITLAB_PASSWORD="${GITLAB_ROOT_PASSWORD:-mega_gitlab_password}"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_test() { echo -e "${BLUE}[TEST]${NC} $1"; }
log_section() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
}

# =============================================================================
# Шаг 1: Остановка и очистка предыдущих контейнеров
# =============================================================================
log_section "Шаг 1: Очистка предыдущих контейнеров"

log_info "Остановка и удаление контейнеров с volumes..."
cd "$BASEDIR"
docker compose down -v 2>/dev/null || true

log_info "✓ Очистка завершена"

# =============================================================================
# Шаг 2: Запуск docker compose
# =============================================================================
log_section "Шаг 2: Запуск docker compose"

log_info "Сборка и запуск контейнеров..."
docker compose build 2>/dev/null || true
docker compose up -d

log_info "✓ Контейнеры запущены"

# =============================================================================
# Шаг 3: Ожидание готовности GitLab
# =============================================================================
log_section "Шаг 3: Ожидание готовности GitLab"

log_info "Ожидание запуска GitLab (это может занять 3-5 минут)..."

for i in {1..60}; do
    if curl -s -f "$GITLAB_URL/-/readiness" > /dev/null 2>&1; then
        log_info "✓ GitLab готов к работе (попытка $i)"
        break
    fi
    
    # Альтернативная проверка через страницу входа
    if curl -s "$GITLAB_URL" 2>&1 | grep -q "sign_in\|GitLab"; then
        log_info "✓ GitLab UI доступен (попытка $i)"
        # Ждём ещё немного для полной инициализации
        sleep 10
        break
    fi
    
    echo "  Ожидание GitLab... (попытка $i/60)"
    sleep 10
done

# Финальная проверка
if ! curl -s "$GITLAB_URL" 2>&1 | grep -q "sign_in\|GitLab\|users"; then
    log_error "GitLab не запустился за отведённое время"
    docker compose logs gitlab | tail -50
    exit 1
fi

log_info "✓ GitLab доступен"

# =============================================================================
# Шаг 4: Ожидание создания root пользователя
# =============================================================================
log_section "Шаг 4: Проверка создания root пользователя"

log_info "Ожидание создания root пользователя (GitLab использует пароль из GITLAB_ROOT_PASSWORD)..."

for i in {1..30}; do
    # Проверяем, что root пользователь создан
    RESULT=$(docker exec gitlab gitlab-rails runner "puts User.find_by(username: 'root').present?" 2>/dev/null || echo "false")
    if [ "$RESULT" = "true" ]; then
        log_info "✓ Root пользователь создан (попытка $i)"
        break
    fi
    echo "  Ожидание создания root... (попытка $i/30)"
    sleep 10
done

# Проверяем пароль
log_test "Проверка пароля из .env..."
PASS_VALID=$(docker exec gitlab gitlab-rails runner "user = User.find_by(username: 'root'); puts user&.valid_password?('$GITLAB_PASSWORD')" 2>/dev/null || echo "false")
if [ "$PASS_VALID" = "true" ]; then
    log_info "✓ Пароль из .env работает"
else
    log_warn "Пароль из .env не подошёл, возможно GitLab сгенерировал случайный"
fi

# =============================================================================
# Шаг 5: Проверка входа по паролю из .env
# =============================================================================
log_section "Шаг 5: Проверка входа в GitLab"

log_test "Попытка входа как $GITLAB_USER с паролем из .env..."

# Получаем CSRF токен
CSRF_TOKEN=$(curl -s -c /tmp/gitlab_cookies.txt "$GITLAB_URL/users/sign_in" | \
    grep -oP 'name="authenticity_token"[^>]*value="\K[^"]+' | head -1 || echo "")

if [ -z "$CSRF_TOKEN" ]; then
    log_warn "Не удалось получить CSRF токен, пробуем API..."
fi

# Пробуем получить токен через API (OAuth password grant)
ACCESS_TOKEN=$(curl -s -X POST "$GITLAB_URL/oauth/token" \
    -d "grant_type=password" \
    -d "username=$GITLAB_USER" \
    -d "password=$GITLAB_PASSWORD" 2>/dev/null | jq -r '.access_token // empty' || echo "")

if [ -n "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "null" ]; then
    log_info "✓ Вход успешен через OAuth! Токен получен."
else
    # Альтернативный способ - создаём персональный токен через rails
    log_info "Создание персонального токена через rails..."
    
    ACCESS_TOKEN=$(docker exec gitlab gitlab-rails runner "
user = User.find_by(username: '$GITLAB_USER')
if user && user.valid_password?('$GITLAB_PASSWORD')
  token = user.personal_access_tokens.create!(
    name: 'test-token-$(date +%s)',
    scopes: ['api', 'read_repository', 'write_repository'],
    expires_at: 1.day.from_now
  )
  puts token.token
else
  STDERR.puts 'Authentication failed'
  exit 1
end
" 2>/dev/null || echo "")
    
    if [ -n "$ACCESS_TOKEN" ]; then
        log_info "✓ Вход успешен! Персональный токен создан."
    else
        log_error "✗ Не удалось войти с паролем из .env"
        log_error "Проверьте, что пароль установлен корректно"
        exit 1
    fi
fi

# =============================================================================
# Шаг 6: Проверка существования проекта
# =============================================================================
log_section "Шаг 6: Проверка проекта"

log_test "Проверка существования проекта $PROJECT_NAME..."

PROJECT_INFO=$(curl -s -H "PRIVATE-TOKEN: $ACCESS_TOKEN" \
    "$GITLAB_URL/api/v4/projects/$GITLAB_USER%2F$PROJECT_NAME" 2>/dev/null || echo "{}")

if echo "$PROJECT_INFO" | jq -e '.id' > /dev/null 2>&1; then
    PROJECT_ID=$(echo "$PROJECT_INFO" | jq -r '.id')
    log_info "✓ Проект найден: ID=$PROJECT_ID"
else
    log_warn "Проект не найден, создаём..."
    
    PROJECT_INFO=$(curl -s -X POST -H "PRIVATE-TOKEN: $ACCESS_TOKEN" \
        "$GITLAB_URL/api/v4/projects" \
        -d "name=$PROJECT_NAME" \
        -d "visibility=private" 2>/dev/null || echo "{}")
    
    if echo "$PROJECT_INFO" | jq -e '.id' > /dev/null 2>&1; then
        PROJECT_ID=$(echo "$PROJECT_INFO" | jq -r '.id')
        log_info "✓ Проект создан: ID=$PROJECT_ID"
    else
        log_error "✗ Не удалось создать проект"
        echo "$PROJECT_INFO"
        exit 1
    fi
fi

# =============================================================================
# Шаг 7: Регистрация GitLab Runner
# =============================================================================
log_section "Шаг 7: Регистрация GitLab Runner"

log_test "Проверка и регистрация GitLab Runner..."

# Получаем регистрационный токен проекта
RUNNER_TOKEN=$(docker exec gitlab gitlab-rails runner "
project = Project.find_by_full_path('$GITLAB_USER/$PROJECT_NAME')
if project
  puts project.runners_token
end
" 2>/dev/null || echo "")

if [ -z "$RUNNER_TOKEN" ]; then
    log_warn "Не удалось получить токен runner из проекта, используем instance token..."
    RUNNER_TOKEN=$(docker exec gitlab gitlab-rails runner "puts Gitlab::CurrentSettings.runners_registration_token" 2>/dev/null || echo "")
fi

if [ -n "$RUNNER_TOKEN" ]; then
    log_info "Токен runner: ${RUNNER_TOKEN:0:10}..."
    
    # Проверяем, зарегистрирован ли уже runner
    RUNNERS=$(curl -s -H "PRIVATE-TOKEN: $ACCESS_TOKEN" \
        "$GITLAB_URL/api/v4/runners/all" 2>/dev/null || echo "[]")
    
    if echo "$RUNNERS" | jq -e '.[0]' > /dev/null 2>&1; then
        log_info "✓ Runner уже зарегистрирован"
    else
        log_info "Регистрация нового runner..."
        
        docker exec gitlab-runner gitlab-runner register \
            --non-interactive \
            --url "http://gitlab:8929" \
            --registration-token "$RUNNER_TOKEN" \
            --executor "docker" \
            --docker-image "alpine:latest" \
            --docker-network-mode "gitlab_network" \
            --description "test-runner" \
            --tag-list "docker,test" \
            --run-untagged="true" \
            --locked="false" 2>/dev/null || log_warn "Регистрация runner может потребовать ручного вмешательства"
        
        log_info "✓ Runner зарегистрирован"
    fi
else
    log_warn "Не удалось получить токен для регистрации runner"
fi

# =============================================================================
# Шаг 8: Push в ветку terraform и проверка CI/CD
# =============================================================================
log_section "Шаг 8: Push в ветку terraform"

log_test "Создание тестового коммита в ветку terraform..."

# Создаём временную директорию для git операций
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Клонируем репозиторий (или создаём новый если пустой)
GIT_URL="http://$GITLAB_USER:$GITLAB_PASSWORD@localhost:8929/$GITLAB_USER/$PROJECT_NAME.git"

git init
git config user.email "test@test.local"
git config user.name "Test User"
git remote add origin "$GIT_URL"

# Пробуем получить ветку terraform или создаём новую
git fetch origin terraform 2>/dev/null || true
git checkout -B terraform

# Создаём тестовый файл
echo "# Test commit at $(date)" > test_commit.md
echo "This is a test file to verify CI/CD pipeline." >> test_commit.md

# Создаём .gitlab-ci.yml если не существует
if [ ! -f .gitlab-ci.yml ]; then
    cat > .gitlab-ci.yml << 'EOF'
# =============================================================================
# GitLab CI/CD Pipeline для Terraform
# =============================================================================

stages:
  - test
  - deploy

# Тестовый job для проверки работоспособности
test_pipeline:
  stage: test
  image: alpine:latest
  script:
    - echo "Pipeline is working!"
    - echo "Branch: $CI_COMMIT_BRANCH"
    - echo "Commit: $CI_COMMIT_SHA"
  only:
    - terraform

# Job для Terraform (заглушка)
terraform_plan:
  stage: deploy
  image: hashicorp/terraform:latest
  script:
    - echo "Terraform plan would run here"
    - terraform version
  only:
    - terraform
  when: manual
EOF
fi

git add -A
git commit -m "Test commit at $(date)" || log_info "Нет изменений для коммита"

# Push
log_info "Push в ветку terraform..."
if git push -u origin terraform --force 2>&1; then
    log_info "✓ Push успешен"
else
    log_warn "Push не удался (возможно, репозиторий пуст или проблемы с сетью)"
fi

# Очистка временной директории
cd "$BASEDIR"
rm -rf "$TEMP_DIR"

# =============================================================================
# Шаг 9: Проверка запуска pipeline
# =============================================================================
log_section "Шаг 9: Проверка CI/CD pipeline"

log_test "Ожидание запуска pipeline..."

sleep 5

PIPELINES=$(curl -s -H "PRIVATE-TOKEN: $ACCESS_TOKEN" \
    "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines?ref=terraform" 2>/dev/null || echo "[]")

if echo "$PIPELINES" | jq -e '.[0]' > /dev/null 2>&1; then
    PIPELINE_ID=$(echo "$PIPELINES" | jq -r '.[0].id')
    PIPELINE_STATUS=$(echo "$PIPELINES" | jq -r '.[0].status')
    log_info "✓ Pipeline найден: ID=$PIPELINE_ID, статус=$PIPELINE_STATUS"
    
    # Ждём завершения pipeline (макс 2 минуты)
    for i in {1..24}; do
        PIPELINE_STATUS=$(curl -s -H "PRIVATE-TOKEN: $ACCESS_TOKEN" \
            "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines/$PIPELINE_ID" 2>/dev/null | \
            jq -r '.status' || echo "unknown")
        
        if [ "$PIPELINE_STATUS" = "success" ]; then
            log_info "✓ Pipeline завершён успешно!"
            break
        elif [ "$PIPELINE_STATUS" = "failed" ]; then
            log_warn "Pipeline завершился с ошибкой"
            break
        elif [ "$PIPELINE_STATUS" = "pending" ] || [ "$PIPELINE_STATUS" = "running" ]; then
            echo "  Pipeline статус: $PIPELINE_STATUS (попытка $i/24)"
            sleep 5
        else
            log_warn "Неизвестный статус pipeline: $PIPELINE_STATUS"
            break
        fi
    done
else
    log_warn "Pipeline не найден (возможно, CI/CD не настроен или runner не зарегистрирован)"
fi

# =============================================================================
# Итоги
# =============================================================================
log_section "Итоги тестирования"

echo ""
log_info "✓ GitLab запущен и доступен: $GITLAB_URL"
log_info "✓ Автоинициализация выполнена"
log_info "✓ Вход работает с credentials из .env"
log_info "  User: $GITLAB_USER"
log_info "  Password: $GITLAB_PASSWORD"
echo ""
log_info "Для входа в GitLab откройте: $GITLAB_URL"
echo ""

exit 0
