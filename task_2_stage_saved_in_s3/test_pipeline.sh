#!/bin/bash
# =============================================================================
# Тестовый скрипт для проверки GitLab CI/CD pipeline
#
# Выполняет:
# 1. Запуск pipeline через GitLab REST API (без коммитов в git)
# 2. Ожидание завершения pipeline с мониторингом логов
# 3. Проверка статуса всех jobs
# 4. Вывод логов упавших jobs
# =============================================================================

set -e

BASEDIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$BASEDIR/.." && pwd)
GITLAB_URL="http://localhost:8929"
PROJECT_ID="1"  # ID проекта в GitLab
BRANCH="terraform"  # ветка для запуска pipeline

# Имя pipeline (отображается в GitLab UI)
PIPELINE_NAME="Terraform Infrastructure Test - $(date +%Y-%m-%d_%H:%M:%S)"

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
# Шаг 1: Получение токена API
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
# Шаг 2: Запуск pipeline через REST API
# =============================================================================
log_section "Шаг 2: Запуск pipeline через REST API"

log_info "Ветка: $BRANCH"
log_info "Pipeline name: $PIPELINE_NAME"

# Запускаем pipeline с переменной для имени
# Переменная CI_PIPELINE_NAME отображается в UI GitLab
RESPONSE=$(curl -s -X POST \
    -H "PRIVATE-TOKEN: $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"ref\": \"$BRANCH\",
        \"variables\": [
            {\"key\": \"PIPELINE_NAME\", \"value\": \"$PIPELINE_NAME\"},
            {\"key\": \"TRIGGERED_BY\", \"value\": \"test_pipeline.sh\"}
        ]
    }" \
    "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipeline")

PIPELINE_ID=$(echo "$RESPONSE" | jq -r '.id')
PIPELINE_WEB_URL=$(echo "$RESPONSE" | jq -r '.web_url')

if [ -z "$PIPELINE_ID" ] || [ "$PIPELINE_ID" = "null" ]; then
    log_error "Не удалось запустить pipeline"
    echo "Response: $RESPONSE"
    exit 1
fi

log_info "Pipeline запущен!"
log_info "  ID: $PIPELINE_ID"
log_info "  URL: $PIPELINE_WEB_URL"

# =============================================================================
# Шаг 3: Ожидание завершения pipeline с мониторингом
# =============================================================================
log_section "Шаг 3: Ожидание завершения pipeline"

MAX_WAIT=600  # 10 минут максимум
WAIT_COUNT=0
CHECK_INTERVAL=5
LAST_JOB_STATUS=""

while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    # Получаем статус pipeline
    PIPELINE_INFO=$(curl -s -H "PRIVATE-TOKEN: $ACCESS_TOKEN" \
        "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines/$PIPELINE_ID")
    STATUS=$(echo "$PIPELINE_INFO" | jq -r '.status')
    
    # Проверяем завершение
    if [ "$STATUS" = "success" ] || [ "$STATUS" = "failed" ] || [ "$STATUS" = "canceled" ]; then
        break
    fi
    
    # Получаем текущие jobs для отображения прогресса
    JOBS=$(curl -s -H "PRIVATE-TOKEN: $ACCESS_TOKEN" \
        "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines/$PIPELINE_ID/jobs")
    
    # Находим running job
    RUNNING_JOB=$(echo "$JOBS" | jq -r '.[] | select(.status == "running") | .name' | head -1)
    CURRENT_JOB_STATUS=$(echo "$JOBS" | jq -r '.[] | "\(.name):\(.status)"' | tr '\n' ' ')
    
    # Выводим прогресс только если статус изменился
    if [ "$CURRENT_JOB_STATUS" != "$LAST_JOB_STATUS" ]; then
        echo ""
        log_info "Pipeline status: $STATUS (${WAIT_COUNT}s)"
        echo "$JOBS" | jq -r '.[] | "  - \(.name): \(.status)"'
        LAST_JOB_STATUS="$CURRENT_JOB_STATUS"
        
        # Если есть running job, показываем последние строки лога
        if [ -n "$RUNNING_JOB" ]; then
            RUNNING_JOB_ID=$(echo "$JOBS" | jq -r ".[] | select(.name == \"$RUNNING_JOB\") | .id")
            if [ -n "$RUNNING_JOB_ID" ] && [ "$RUNNING_JOB_ID" != "null" ]; then
                echo ""
                echo "  --- Последние строки лога job '$RUNNING_JOB': ---"
                curl -s -H "PRIVATE-TOKEN: $ACCESS_TOKEN" \
                    "$GITLAB_URL/api/v4/projects/$PROJECT_ID/jobs/$RUNNING_JOB_ID/trace" 2>/dev/null | tail -10 | sed 's/^/  | /'
            fi
        fi
    else
        # Короткий вывод без изменений
        printf "."
    fi
    
    sleep $CHECK_INTERVAL
    WAIT_COUNT=$((WAIT_COUNT + CHECK_INTERVAL))
done

echo ""

if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
    log_error "Timeout: pipeline не завершился за ${MAX_WAIT}s"
fi

# =============================================================================
# Шаг 4: Результаты pipeline
# =============================================================================
log_section "Шаг 4: Результаты pipeline"

PIPELINE_INFO=$(curl -s -H "PRIVATE-TOKEN: $ACCESS_TOKEN" \
    "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines/$PIPELINE_ID")

FINAL_STATUS=$(echo "$PIPELINE_INFO" | jq -r '.status')
DURATION=$(echo "$PIPELINE_INFO" | jq -r '.duration // "N/A"')

log_info "Статус: $FINAL_STATUS"
log_info "Длительность: ${DURATION}s"
log_info "URL: $PIPELINE_WEB_URL"

# Выводим статус всех jobs
echo ""
log_info "Статус jobs:"
JOBS=$(curl -s -H "PRIVATE-TOKEN: $ACCESS_TOKEN" \
    "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines/$PIPELINE_ID/jobs")

echo "$JOBS" | jq -r '.[] | "  - \(.name): \(.status) (stage: \(.stage))"'

# Выводим логи упавших jobs
FAILED_JOBS=$(echo "$JOBS" | jq -r '.[] | select(.status == "failed") | .id')

for JOB_ID in $FAILED_JOBS; do
    JOB_NAME=$(echo "$JOBS" | jq -r ".[] | select(.id == $JOB_ID) | .name")
    log_section "Логи упавшего job: $JOB_NAME"
    curl -s -H "PRIVATE-TOKEN: $ACCESS_TOKEN" \
        "$GITLAB_URL/api/v4/projects/$PROJECT_ID/jobs/$JOB_ID/trace" | tail -100
done

# =============================================================================
# Шаг 5: Проверка вывода IP-адресов LXC и SSH-подключения
# =============================================================================
log_section "Шаг 5: Проверка LXC IP и SSH-подключения"

LXC_INFO_CHECK_PASSED=true
SSH_CHECK_PASSED=true
LXC_IPS_FOUND=""

# Получаем логи job show_lxc_info
SHOW_LXC_JOB_ID=$(echo "$JOBS" | jq -r '.[] | select(.name == "show_lxc_info") | .id')

if [ -n "$SHOW_LXC_JOB_ID" ] && [ "$SHOW_LXC_JOB_ID" != "null" ]; then
    log_info "Получаем логи job show_lxc_info (ID: $SHOW_LXC_JOB_ID)"
    
    SHOW_LXC_LOG=$(curl -s -H "PRIVATE-TOKEN: $ACCESS_TOKEN" \
        "$GITLAB_URL/api/v4/projects/$PROJECT_ID/jobs/$SHOW_LXC_JOB_ID/trace")
    
    # Проверяем наличие маркеров секции IP
    if echo "$SHOW_LXC_LOG" | grep -q "=== LXC_IPS_START ==="; then
        log_info "✓ Найден маркер LXC_IPS_START"
    else
        log_error "✗ Не найден маркер LXC_IPS_START"
        LXC_INFO_CHECK_PASSED=false
    fi
    
    if echo "$SHOW_LXC_LOG" | grep -q "=== LXC_IPS_END ==="; then
        log_info "✓ Найден маркер LXC_IPS_END"
    else
        log_error "✗ Не найден маркер LXC_IPS_END"
        LXC_INFO_CHECK_PASSED=false
    fi
    
    # Проверяем наличие инструкций SSH
    if echo "$SHOW_LXC_LOG" | grep -q "ssh -i task_1_terraform_module/vm_access_key"; then
        log_info "✓ Найдены инструкции SSH-подключения"
    else
        log_error "✗ Не найдены инструкции SSH-подключения"
        LXC_INFO_CHECK_PASSED=false
    fi
    
    # Извлекаем IP-адреса из логов
    LXC_IPS_FOUND=$(echo "$SHOW_LXC_LOG" | grep "LXC_IP:" | sed 's/.*LXC_IP: //' | tr -d ' ')
    
    if [ -n "$LXC_IPS_FOUND" ]; then
        log_info "✓ Найдены IP-адреса LXC:"
        for IP in $LXC_IPS_FOUND; do
            echo "    - $IP"
        done
    else
        log_warn "⊕ IP-адреса LXC не найдены (возможно, контейнеры ещё не созданы)"
    fi
    
    # Проверяем SSH-подключение к каждому LXC
    SSH_KEY="$REPO_ROOT/task_1_terraform_module/vm_access_key"
    
    if [ -n "$LXC_IPS_FOUND" ] && [ -f "$SSH_KEY" ]; then
        log_info "Проверяем SSH-подключение к LXC-контейнерам..."
        chmod 600 "$SSH_KEY"
        
        for IP in $LXC_IPS_FOUND; do
            echo ""
            log_info "Проверка SSH к $IP..."
            
            # Проверяем подключение с таймаутом 10 секунд
            if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes \
                root@"$IP" "echo 'SSH_TEST_SUCCESS'" 2>/dev/null | grep -q "SSH_TEST_SUCCESS"; then
                log_info "✓ SSH-подключение к $IP успешно"
            else
                log_error "✗ Не удалось подключиться по SSH к $IP"
                SSH_CHECK_PASSED=false
            fi
        done
    elif [ -z "$LXC_IPS_FOUND" ]; then
        log_warn "Пропускаем проверку SSH: нет IP-адресов LXC"
    elif [ ! -f "$SSH_KEY" ]; then
        log_error "✗ SSH-ключ не найден: $SSH_KEY"
        SSH_CHECK_PASSED=false
    fi
else
    log_warn "Не найден job show_lxc_info"
    LXC_INFO_CHECK_PASSED=false
fi

# =============================================================================
# Итог
# =============================================================================
log_section "Итог"

EXIT_CODE=0

if [ "$FINAL_STATUS" != "success" ]; then
    log_error "✗ Pipeline завершился с ошибками"
    log_error "  Статус: $FINAL_STATUS"
    log_error "  URL: $PIPELINE_WEB_URL"
    EXIT_CODE=1
fi

if [ "$LXC_INFO_CHECK_PASSED" = "false" ]; then
    log_error "✗ Проверка вывода LXC info не пройдена"
    EXIT_CODE=1
else
    log_info "✓ Проверка вывода LXC info пройдена"
fi

if [ "$SSH_CHECK_PASSED" = "false" ]; then
    log_error "✗ Проверка SSH-подключения не пройдена"
    EXIT_CODE=1
else
    log_info "✓ Проверка SSH-подключения пройдена"
fi

if [ $EXIT_CODE -eq 0 ]; then
    log_info "✓ Pipeline успешно завершён!"
    log_info "  Имя: $PIPELINE_NAME"
    log_info "  ID: $PIPELINE_ID"
    
    if [ -n "$LXC_IPS_FOUND" ]; then
        echo ""
        log_info "LXC-контейнеры доступны по SSH:"
        for IP in $LXC_IPS_FOUND; do
            echo "  ssh -i task_1_terraform_module/vm_access_key root@$IP"
        done
    fi
fi

exit $EXIT_CODE
