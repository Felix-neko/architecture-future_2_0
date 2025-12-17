#!/bin/bash
# =============================================================================
# Тестовый скрипт для проверки GitLab CI/CD pipeline
#
# Выполняет:
# 1. Push .gitlab-ci.yml и terraform конфигураций в ветку terraform
# 2. Ожидание завершения pipeline
# 3. Проверка статуса всех jobs
# 4. Вывод логов упавших jobs
# =============================================================================

set -e

BASEDIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$BASEDIR/.." && pwd)
GITLAB_URL="http://localhost:8929"
PROJECT_PATH="root/architecture-future_2_0"
TF_ENVIRONMENTS_DIR="$REPO_ROOT/task_1_terraform_module/terraform/environments"
CI_YAML_FILE="$BASEDIR/gitlab-ci-terraform.yml"

# Загружаем переменные из .env
if [ -f "$BASEDIR/.env" ]; then
    source "$BASEDIR/.env"
fi

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
}

# =============================================================================
# Проверка наличия файлов
# =============================================================================
log_section "Шаг 0: Проверка наличия файлов"

if [ ! -f "$CI_YAML_FILE" ]; then
    log_error "Файл $CI_YAML_FILE не найден"
    exit 1
fi
log_info "CI YAML: $CI_YAML_FILE"

if [ ! -d "$TF_ENVIRONMENTS_DIR" ]; then
    log_error "Директория $TF_ENVIRONMENTS_DIR не найдена"
    exit 1
fi
log_info "Terraform environments: $TF_ENVIRONMENTS_DIR"
ls -la "$TF_ENVIRONMENTS_DIR"

# =============================================================================
# Получение токена API
# =============================================================================
log_section "Шаг 1: Получение API токена"

ACCESS_TOKEN=$(docker exec gitlab gitlab-rails runner "
user = User.find_by(username: 'root')
token = user.personal_access_tokens.create!(
  name: 'pipeline-test-$(date +%s)',
  scopes: ['api', 'read_repository', 'write_repository'],
  expires_at: 1.day.from_now
)
puts token.token
" 2>/dev/null)

if [ -z "$ACCESS_TOKEN" ]; then
    log_error "Не удалось получить токен"
    exit 1
fi
log_info "Токен получен: ${ACCESS_TOKEN:0:15}..."

# =============================================================================
# Push .gitlab-ci.yml и terraform конфигураций
# =============================================================================
log_section "Шаг 2: Push в GitLab"

TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

git init
git config user.email "test@test.local"
git config user.name "Pipeline Test"

git remote add origin "http://root:${GITLAB_ROOT_PASSWORD}@localhost:8929/${PROJECT_PATH}.git"
git fetch origin terraform 2>/dev/null || true
git checkout -B terraform origin/terraform 2>/dev/null || git checkout -B terraform

# Копируем .gitlab-ci.yml из внешнего файла
log_info "Копирование $CI_YAML_FILE"
cp "$CI_YAML_FILE" .gitlab-ci.yml

# Копируем реальные terraform конфигурации
log_info "Копирование terraform конфигураций из $TF_ENVIRONMENTS_DIR"
mkdir -p task_1_terraform_module/terraform
cp -r "$REPO_ROOT/task_1_terraform_module/terraform/vm_module" task_1_terraform_module/terraform/
cp -r "$REPO_ROOT/task_1_terraform_module/terraform/environments" task_1_terraform_module/terraform/
cp -r "$REPO_ROOT/task_1_terraform_module/terraform/presets" task_1_terraform_module/terraform/ 2>/dev/null || true

# Удаляем .terraform директории (провайдеры большие, не нужны в git)
find task_1_terraform_module -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
find task_1_terraform_module -name ".terraform.lock.hcl" -type f -delete 2>/dev/null || true

# Копируем скрипты из vm_module (check_node_resources.sh и др.)
log_info "Копирование скриптов vm_module"
if [ -d "$REPO_ROOT/task_1_terraform_module/terraform/vm_module/scripts" ]; then
    cp -r "$REPO_ROOT/task_1_terraform_module/terraform/vm_module/scripts" task_1_terraform_module/terraform/vm_module/
    chmod +x task_1_terraform_module/terraform/vm_module/scripts/*.sh 2>/dev/null || true
    ls -la task_1_terraform_module/terraform/vm_module/scripts/
fi

log_info "Структура terraform:"
find task_1_terraform_module -type f -name "*.tf" | head -10

# Копируем .node_ips файл (IP адреса Proxmox нод)
log_info "Копирование .node_ips"
if [ -f "$REPO_ROOT/task_1_terraform_module/.node_ips" ]; then
    cp "$REPO_ROOT/task_1_terraform_module/.node_ips" task_1_terraform_module/
    echo "  Содержимое .node_ips:"
    cat task_1_terraform_module/.node_ips
else
    log_error ".node_ips не найден в $REPO_ROOT/task_1_terraform_module/"
    exit 1
fi

# Явно копируем terraform.tfstate файлы (они могли быть в .gitignore)
log_info "Копирование terraform.tfstate файлов"
for ENV in dev-1 dev-2; do
    SRC="$REPO_ROOT/task_1_terraform_module/terraform/environments/$ENV/terraform.tfstate"
    DST="task_1_terraform_module/terraform/environments/$ENV/terraform.tfstate"
    if [ -f "$SRC" ]; then
        cp "$SRC" "$DST"
        RESOURCES=$(jq -r '.resources | length' "$DST" 2>/dev/null || echo "?")
        echo "  $ENV: $RESOURCES resources"
    else
        echo "  $ENV: нет tfstate"
    fi
done

# Копируем скрипты для CI
log_info "Копирование скриптов CI"
mkdir -p task_2_stage_saved_in_s3/scripts
cp "$BASEDIR/scripts/verify_state.sh" task_2_stage_saved_in_s3/scripts/

# Принудительно добавляем файлы из .gitignore
git add -A
git add -f task_1_terraform_module/.node_ips 2>/dev/null || true
git add -f task_1_terraform_module/terraform/environments/*/terraform.tfstate 2>/dev/null || true

git commit -m "Fix CI/CD pipeline: add state and node_ips" --allow-empty

log_info "Pushing to GitLab..."
git push origin terraform --force 2>&1

cd "$BASEDIR"
rm -rf "$TEMP_DIR"

log_info "✓ Push успешен"

# =============================================================================
# Ожидание создания и завершения pipeline
# =============================================================================
log_section "Шаг 3: Ожидание завершения pipeline"

sleep 5

# Получаем ID последнего pipeline
PIPELINE_ID=$(curl -s -H "PRIVATE-TOKEN: $ACCESS_TOKEN" \
    "$GITLAB_URL/api/v4/projects/1/pipelines?ref=terraform&per_page=1" | jq -r '.[0].id')

if [ -z "$PIPELINE_ID" ] || [ "$PIPELINE_ID" = "null" ]; then
    log_error "Pipeline не найден"
    exit 1
fi

log_info "Pipeline ID: $PIPELINE_ID"

# Ждём завершения pipeline (увеличенный timeout для terraform_plan и verify_state)
MAX_WAIT=300
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    STATUS=$(curl -s -H "PRIVATE-TOKEN: $ACCESS_TOKEN" \
        "$GITLAB_URL/api/v4/projects/1/pipelines/$PIPELINE_ID" | jq -r '.status')
    
    if [ "$STATUS" = "success" ] || [ "$STATUS" = "failed" ] || [ "$STATUS" = "canceled" ]; then
        break
    fi
    
    echo "  Pipeline status: $STATUS (ожидание $WAIT_COUNT/$MAX_WAIT сек)"
    sleep 5
    WAIT_COUNT=$((WAIT_COUNT + 5))
done

# =============================================================================
# Проверка результатов
# =============================================================================
log_section "Шаг 4: Результаты pipeline"

PIPELINE_INFO=$(curl -s -H "PRIVATE-TOKEN: $ACCESS_TOKEN" \
    "$GITLAB_URL/api/v4/projects/1/pipelines/$PIPELINE_ID")

FINAL_STATUS=$(echo "$PIPELINE_INFO" | jq -r '.status')

if [ "$FINAL_STATUS" = "success" ]; then
    log_info "✓ Pipeline успешно завершён!"
else
    log_warn "Pipeline завершился со статусом: $FINAL_STATUS"
fi

# Выводим статус всех jobs
echo ""
log_info "Статус jobs:"
JOBS=$(curl -s -H "PRIVATE-TOKEN: $ACCESS_TOKEN" \
    "$GITLAB_URL/api/v4/projects/1/pipelines/$PIPELINE_ID/jobs")

echo "$JOBS" | jq -r '.[] | "  - \(.name): \(.status)"'

# Выводим логи упавших jobs
FAILED_JOBS=$(echo "$JOBS" | jq -r '.[] | select(.status == "failed") | .id')

for JOB_ID in $FAILED_JOBS; do
    JOB_NAME=$(echo "$JOBS" | jq -r ".[] | select(.id == $JOB_ID) | .name")
    log_section "Логи упавшего job: $JOB_NAME"
    curl -s -H "PRIVATE-TOKEN: $ACCESS_TOKEN" \
        "$GITLAB_URL/api/v4/projects/1/jobs/$JOB_ID/trace" | tail -50
done

# =============================================================================
# Итог
# =============================================================================
log_section "Итог"

if [ "$FINAL_STATUS" = "success" ]; then
    log_info "✓ Все проверки пройдены успешно!"
    exit 0
else
    log_error "✗ Pipeline завершился с ошибками"
    exit 1
fi
