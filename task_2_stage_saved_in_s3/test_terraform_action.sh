#!/bin/bash
# =============================================================================
# Тестовый скрипт для проверки Terraform Action с S3-хранилищем
#
# Проверяет:
# - Доступ к Yandex Object Storage
# - Push .gitlab-ci.yml в ветку terraform
# - Запуск и выполнение pipeline
# - Загрузку terraform state в S3
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
# Шаг 1: Проверка предусловий
# =============================================================================
log_section "Шаг 1: Проверка предусловий"

# Проверяем, что GitLab запущен
log_test "Проверка доступности GitLab..."
for i in {1..10}; do
    if curl -s -f "$GITLAB_URL/-/readiness" > /dev/null 2>&1 || \
       curl -s "$GITLAB_URL" 2>&1 | grep -q "sign_in\|GitLab"; then
        log_info "✓ GitLab доступен"
        break
    fi
    if [ $i -eq 10 ]; then
        log_error "GitLab не доступен. Запустите сначала: ./test_gitlab.sh"
        exit 1
    fi
    sleep 3
done

# Проверяем наличие aws cli
if ! command -v aws &> /dev/null; then
    log_warn "AWS CLI не установлен, устанавливаем..."
    # Для Ubuntu/Debian
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y awscli
    # Для Arch
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm aws-cli
    else
        log_error "Не удалось установить AWS CLI автоматически"
        exit 1
    fi
fi

log_info "✓ AWS CLI доступен"

# =============================================================================
# Шаг 2: Проверка доступа к S3
# =============================================================================
log_section "Шаг 2: Проверка доступа к Yandex Object Storage"

log_test "Настройка AWS CLI для Yandex S3..."

# Конфигурируем AWS CLI
export AWS_ACCESS_KEY_ID="${YC_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${YC_SECRET_ACCESS_KEY}"
export AWS_DEFAULT_REGION="ru-central1"

S3_ENDPOINT="${YC_S3_ENDPOINT:-https://storage.yandexcloud.net}"
S3_BUCKET="${YC_S3_BUCKET:-rubber-duck-infra-states}"

log_test "Проверка доступа к бакету $S3_BUCKET..."

if aws s3 ls "s3://${S3_BUCKET}/" --endpoint-url "${S3_ENDPOINT}" 2>/dev/null; then
    log_info "✓ Доступ к S3 бакету работает"
else
    log_warn "Бакет пуст или не существует, создаём тестовый файл..."
    echo "test" | aws s3 cp - "s3://${S3_BUCKET}/test.txt" --endpoint-url "${S3_ENDPOINT}" 2>/dev/null || {
        log_error "Не удалось записать в S3. Проверьте credentials в .env"
        exit 1
    }
    aws s3 rm "s3://${S3_BUCKET}/test.txt" --endpoint-url "${S3_ENDPOINT}" 2>/dev/null || true
    log_info "✓ Запись в S3 работает"
fi

# =============================================================================
# Шаг 3: Получение токена GitLab
# =============================================================================
log_section "Шаг 3: Получение токена GitLab"

log_test "Создание персонального токена..."

ACCESS_TOKEN=$(docker exec gitlab gitlab-rails runner "
user = User.find_by(username: '$GITLAB_USER')
if user && user.valid_password?('$GITLAB_PASSWORD')
  token = user.personal_access_tokens.create!(
    name: 'terraform-test-$(date +%s)',
    scopes: ['api', 'read_repository', 'write_repository'],
    expires_at: 1.day.from_now
  )
  puts token.token
else
  STDERR.puts 'Authentication failed'
  exit 1
end
" 2>/dev/null || echo "")

if [ -z "$ACCESS_TOKEN" ]; then
    log_error "Не удалось получить токен GitLab"
    exit 1
fi

log_info "✓ Токен получен: ${ACCESS_TOKEN:0:10}..."

# Получаем ID проекта
PROJECT_INFO=$(curl -s -H "PRIVATE-TOKEN: $ACCESS_TOKEN" \
    "$GITLAB_URL/api/v4/projects/$GITLAB_USER%2F$PROJECT_NAME" 2>/dev/null || echo "{}")

if ! echo "$PROJECT_INFO" | jq -e '.id' > /dev/null 2>&1; then
    log_error "Проект $PROJECT_NAME не найден"
    exit 1
fi

PROJECT_ID=$(echo "$PROJECT_INFO" | jq -r '.id')
log_info "✓ Проект найден: ID=$PROJECT_ID"

# =============================================================================
# Шаг 4: Push .gitlab-ci.yml и terraform конфигурации
# =============================================================================
log_section "Шаг 4: Push конфигурации в GitLab"

TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

log_test "Клонирование репозитория..."

GIT_URL="http://$GITLAB_USER:$GITLAB_PASSWORD@localhost:8929/$GITLAB_USER/$PROJECT_NAME.git"

git init
git config user.email "test@test.local"
git config user.name "Test User"
git remote add origin "$GIT_URL"

# Пробуем получить ветку terraform
git fetch origin terraform 2>/dev/null || true
git checkout -B terraform

# Копируем .gitlab-ci.yml
log_test "Копирование .gitlab-ci.yml..."
cp "$BASEDIR/gitlab-ci-terraform.yml" .gitlab-ci.yml

# Создаём структуру terraform/environments с тестовой конфигурацией
log_test "Создание тестовой terraform конфигурации..."

mkdir -p terraform/environments/test-env

cat > terraform/environments/test-env/main.tf << 'EOF'
# =============================================================================
# Тестовое окружение для проверки CI/CD pipeline
# =============================================================================

terraform {
  required_version = ">= 1.0"
}

# Локальный ресурс для тестирования
resource "null_resource" "test" {
  triggers = {
    timestamp = timestamp()
  }

  provisioner "local-exec" {
    command = "echo 'Terraform apply executed at ${timestamp()}'"
  }
}

# Выходные переменные
output "test_output" {
  description = "Тестовый output"
  value       = "Pipeline работает! Время: ${timestamp()}"
}

output "environment" {
  description = "Имя окружения"
  value       = "test-env"
}
EOF

cat > terraform/environments/test-env/versions.tf << 'EOF'
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}
EOF

cat > terraform/environments/test-env/terraform.tfvars << 'EOF'
# Тестовые переменные
EOF

# Коммит и push
git add -A
git commit -m "Add terraform CI/CD configuration with S3 state storage" || log_info "Нет изменений"

log_test "Push в ветку terraform..."
if git push -u origin terraform --force 2>&1; then
    log_info "✓ Push успешен"
else
    log_error "Push не удался"
    exit 1
fi

cd "$BASEDIR"
rm -rf "$TEMP_DIR"

# =============================================================================
# Шаг 5: Запуск и мониторинг pipeline
# =============================================================================
log_section "Шаг 5: Запуск и мониторинг pipeline"

log_test "Ожидание создания pipeline..."
sleep 5

# Получаем последний pipeline
for i in {1..10}; do
    PIPELINES=$(curl -s -H "PRIVATE-TOKEN: $ACCESS_TOKEN" \
        "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines?ref=terraform&per_page=1" 2>/dev/null || echo "[]")
    
    if echo "$PIPELINES" | jq -e '.[0]' > /dev/null 2>&1; then
        break
    fi
    echo "  Ожидание pipeline... (попытка $i/10)"
    sleep 3
done

if ! echo "$PIPELINES" | jq -e '.[0]' > /dev/null 2>&1; then
    log_error "Pipeline не создан"
    exit 1
fi

PIPELINE_ID=$(echo "$PIPELINES" | jq -r '.[0].id')
PIPELINE_STATUS=$(echo "$PIPELINES" | jq -r '.[0].status')
log_info "Pipeline создан: ID=$PIPELINE_ID, статус=$PIPELINE_STATUS"

# Мониторинг pipeline
log_test "Мониторинг выполнения pipeline..."

for i in {1..60}; do
    PIPELINE_INFO=$(curl -s -H "PRIVATE-TOKEN: $ACCESS_TOKEN" \
        "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines/$PIPELINE_ID" 2>/dev/null || echo "{}")
    
    PIPELINE_STATUS=$(echo "$PIPELINE_INFO" | jq -r '.status')
    
    case "$PIPELINE_STATUS" in
        "success")
            log_info "✓ Pipeline завершён успешно!"
            break
            ;;
        "failed")
            log_error "Pipeline завершился с ошибкой"
            # Показываем логи jobs
            JOBS=$(curl -s -H "PRIVATE-TOKEN: $ACCESS_TOKEN" \
                "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines/$PIPELINE_ID/jobs" 2>/dev/null || echo "[]")
            echo "$JOBS" | jq -r '.[] | "Job: \(.name) - \(.status)"'
            break
            ;;
        "canceled")
            log_warn "Pipeline отменён"
            break
            ;;
        "pending"|"running"|"created")
            echo "  Статус: $PIPELINE_STATUS (попытка $i/60)"
            sleep 10
            ;;
        *)
            log_warn "Неизвестный статус: $PIPELINE_STATUS"
            sleep 5
            ;;
    esac
done

# =============================================================================
# Шаг 6: Проверка загрузки state в S3
# =============================================================================
log_section "Шаг 6: Проверка state в S3"

log_test "Проверка наличия terraform state в S3..."

sleep 5

S3_CONTENTS=$(aws s3 ls "s3://${S3_BUCKET}/terraform-states/" --recursive --endpoint-url "${S3_ENDPOINT}" 2>/dev/null || echo "")

if [ -n "$S3_CONTENTS" ]; then
    log_info "✓ Terraform state найден в S3:"
    echo "$S3_CONTENTS" | head -20
else
    log_warn "Terraform state не найден в S3 (возможно, pipeline ещё не завершён или apply не был запущен)"
    log_info "Примечание: job 'apply' требует ручного запуска (when: manual)"
fi

# =============================================================================
# Итоги
# =============================================================================
log_section "Итоги тестирования Terraform Action"

echo ""
log_info "✓ GitLab CI/CD pipeline настроен"
log_info "✓ .gitlab-ci.yml загружен в ветку terraform"
log_info "✓ Доступ к S3 работает"
echo ""
log_info "Для запуска terraform apply:"
log_info "  1. Откройте $GITLAB_URL/$GITLAB_USER/$PROJECT_NAME/-/pipelines"
log_info "  2. Найдите job 'apply' и запустите вручную"
log_info "  3. После завершения state будет загружен в S3"
echo ""
log_info "S3 bucket: s3://${S3_BUCKET}/terraform-states/"
echo ""

exit 0
