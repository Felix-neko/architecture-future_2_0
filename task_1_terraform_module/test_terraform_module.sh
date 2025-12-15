#!/bin/bash
# =============================================================================
# Тестовый скрипт для проверки Terraform-модуля LXC-контейнеров
#
# Использование: ./test_terraform_module.sh [OPTIONS]
#
# Опции:
#   -e, --env ENV                 Окружение: dev, stage, prod (по умолчанию: dev)
#   --environment NAME            Отдельное окружение из environments/ (dev-1, dev-2)
#   --skip-cleanup                Пропустить удаление существующих контейнеров
#   --skip-terraform              Пропустить запуск Terraform (только проверка)
#   --test-resource-overflow      Тест ошибки превышения ресурсов на одной ноде
#   --test-cluster-overflow       Тест ошибки превышения общих ресурсов кластера
#   --test-vmid-conflict          Тест уникальности VMID между окружениями
#   -h, --help                    Показать справку
# =============================================================================

set -e

BASEDIR=$(cd "$(dirname "$0")" && pwd)
TERRAFORM_DIR="$BASEDIR/terraform/vm_module"
ENVS_DIR="$BASEDIR/terraform/envs"
ENVIRONMENTS_DIR="$BASEDIR/terraform/environments"

# === Параметры по умолчанию ===
ENV="dev"
ENVIRONMENT=""
SKIP_CLEANUP=false
SKIP_TERRAFORM=false
TEST_RESOURCE_OVERFLOW=false
TEST_CLUSTER_OVERFLOW=false
TEST_VMID_CONFLICT=false

# === Пути ===
PRIVATE_KEY="$BASEDIR/vm_access_key"
NODE_IPS_FILE="$BASEDIR/.node_ips"

# === Цвета для вывода ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# === Функции ===
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
}

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# === Парсинг аргументов командной строки ===
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--env)
            ENV="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --skip-cleanup)
            SKIP_CLEANUP=true
            shift
            ;;
        --skip-terraform)
            SKIP_TERRAFORM=true
            shift
            ;;
        --test-resource-overflow)
            TEST_RESOURCE_OVERFLOW=true
            shift
            ;;
        --test-cluster-overflow)
            TEST_CLUSTER_OVERFLOW=true
            shift
            ;;
        --test-vmid-conflict)
            TEST_VMID_CONFLICT=true
            shift
            ;;
        -h|--help)
            echo "Использование: $0 [OPTIONS]"
            echo ""
            echo "Опции:"
            echo "  -e, --env ENV                 Окружение: dev, stage, prod (по умолчанию: dev)"
            echo "  --environment NAME            Отдельное окружение из environments/ (dev-1, dev-2)"
            echo "  --skip-cleanup                Пропустить удаление существующих контейнеров"
            echo "  --skip-terraform              Пропустить запуск Terraform (только проверка)"
            echo "  --test-resource-overflow      Тест ошибки превышения ресурсов на одной ноде"
            echo "  --test-cluster-overflow       Тест ошибки превышения общих ресурсов кластера"
            echo "  --test-vmid-conflict          Тест уникальности VMID между окружениями"
            echo "  -h, --help                    Показать справку"
            exit 0
            ;;
        *)
            echo "Неизвестный параметр: $1"
            exit 1
            ;;
    esac
done

# === Определяем рабочую директорию ===
if [ -n "$ENVIRONMENT" ]; then
    # Используем отдельное окружение
    WORK_DIR="$ENVIRONMENTS_DIR/$ENVIRONMENT"
    if [ ! -d "$WORK_DIR" ]; then
        log_error "Окружение не найдено: $WORK_DIR"
        exit 1
    fi
    TFVARS_FILE="$WORK_DIR/terraform.tfvars"
    log_info "Используется отдельное окружение: $ENVIRONMENT"
else
    # Используем пресет из envs/
    if [[ ! "$ENV" =~ ^(dev|stage|prod)$ ]]; then
        log_error "Неверное окружение: $ENV. Допустимые значения: dev, stage, prod"
        exit 1
    fi
    WORK_DIR="$TERRAFORM_DIR"
    TFVARS_FILE="$ENVS_DIR/${ENV}.tfvars"
    log_info "Используется пресет окружения: $ENV"
fi

if [ ! -f "$TFVARS_FILE" ]; then
    log_error "Файл переменных не найден: $TFVARS_FILE"
    exit 1
fi

log_section "Тестирование Terraform-модуля LXC"
log_info "Рабочая директория: $WORK_DIR"
log_info "Файл переменных: $TFVARS_FILE"

# =============================================================================
# ШАГ 1: Проверка доступности Proxmox-нод
# =============================================================================
log_section "Шаг 1: Проверка доступности Proxmox-нод"

# Получаем IP-адреса нод
if [ -f "$NODE_IPS_FILE" ]; then
    log_info "Читаем IP-адреса из $NODE_IPS_FILE"
    NODE_IPS=$(cat "$NODE_IPS_FILE" | grep -v '^$')
else
    log_info "Файл .node_ips не найден, определяем IP через virsh..."
    NODE_IPS=""
    for i in 1 2 3; do
        IP=$(virsh domifaddr "pve-node-$i" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)
        if [ -n "$IP" ]; then
            NODE_IPS="$NODE_IPS$IP"$'\n'
        fi
    done
    NODE_IPS=$(echo "$NODE_IPS" | grep -v '^$')
    
    # Сохраняем в файл для Terraform
    if [ -n "$NODE_IPS" ]; then
        echo "$NODE_IPS" > "$NODE_IPS_FILE"
        log_info "IP-адреса сохранены в $NODE_IPS_FILE"
    fi
fi

if [ -z "$NODE_IPS" ]; then
    log_error "Не найдены IP-адреса Proxmox-нод"
    log_error "Убедитесь, что виртуалки pve-node-* запущены или создайте файл .node_ips"
    exit 1
fi

log_info "Найдены Proxmox-ноды:"
echo "$NODE_IPS" | while read -r IP; do
    [ -n "$IP" ] && echo "  - $IP"
done

# Проверяем доступность каждой ноды
MASTER_IP=$(echo "$NODE_IPS" | head -1)

for IP in $NODE_IPS; do
    [ -z "$IP" ] && continue
    echo -n "  Проверка $IP... "
    
    # Проверка SSH-доступа с несколькими попытками
    SSH_OK=false
    for attempt in {1..3}; do
        if ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
               -o ConnectTimeout=5 root@"$IP" "exit 0" 2>/dev/null; then
            SSH_OK=true
            break
        fi
        sleep 1
    done
    
    if [ "$SSH_OK" = true ]; then
        echo -e "${GREEN}✓ SSH OK${NC}"
    else
        echo -e "${RED}✗ SSH FAIL${NC}"
        log_error "Нода $IP недоступна по SSH"
        exit 1
    fi
done

log_info "✓ Все Proxmox-ноды доступны"

# =============================================================================
# СПЕЦИАЛЬНЫЕ ТЕСТЫ: Проверка ресурсов
# =============================================================================

if [ "$TEST_RESOURCE_OVERFLOW" = true ]; then
    log_section "ТЕСТ: Превышение ресурсов на одной ноде"
    
    log_test "Создаём конфигурацию с превышением памяти на одной ноде..."
    
    # Создаём временный tfvars с огромным требованием памяти
    TEMP_TFVARS=$(mktemp)
    cat > "$TEMP_TFVARS" << EOF
# Тестовая конфигурация: превышение ресурсов на одной ноде
lxc_count = 1
lxc_cpus = 2
lxc_memory_mb = 99999  # 99 ГБ - точно не поместится на одну ноду
lxc_disk_gb = 10
lxc_name_prefix = "test-overflow"
start_vmid = 999
ip_start_offset = 199
enable_resource_check = true
EOF
    
    cd "$TERRAFORM_DIR"
    terraform init -upgrade > /dev/null 2>&1
    
    log_test "Запускаем terraform plan с превышением ресурсов..."
    if terraform plan -var-file="$TEMP_TFVARS" -out=tfplan 2>&1 | grep -q "Недостаточно ресурсов\|error\|Error"; then
        log_info "✓ ТЕСТ ПРОЙДЕН: Terraform корректно отклонил конфигурацию с превышением ресурсов"
        rm -f "$TEMP_TFVARS" tfplan
        exit 0
    else
        # Проверяем, есть ли ошибка размещения в output
        if terraform output placement_error 2>/dev/null | grep -q "Недостаточно"; then
            log_info "✓ ТЕСТ ПРОЙДЕН: Ошибка размещения обнаружена"
            rm -f "$TEMP_TFVARS" tfplan
            exit 0
        fi
        log_error "✗ ТЕСТ НЕ ПРОЙДЕН: Terraform не отклонил конфигурацию с превышением ресурсов"
        rm -f "$TEMP_TFVARS" tfplan
        exit 1
    fi
fi

if [ "$TEST_CLUSTER_OVERFLOW" = true ]; then
    log_section "ТЕСТ: Превышение общих ресурсов кластера"
    
    log_test "Создаём конфигурацию с превышением общих ресурсов..."
    
    # Создаём временный tfvars с множеством контейнеров
    TEMP_TFVARS=$(mktemp)
    cat > "$TEMP_TFVARS" << EOF
# Тестовая конфигурация: превышение общих ресурсов кластера
lxc_count = 100  # 100 контейнеров
lxc_cpus = 4
lxc_memory_mb = 8192  # 8 ГБ каждый = 800 ГБ всего
lxc_disk_gb = 50
lxc_name_prefix = "test-cluster-overflow"
start_vmid = 900
ip_start_offset = 180
enable_resource_check = true
EOF
    
    cd "$TERRAFORM_DIR"
    terraform init -upgrade > /dev/null 2>&1
    
    log_test "Запускаем terraform plan с превышением общих ресурсов..."
    if terraform plan -var-file="$TEMP_TFVARS" -out=tfplan 2>&1 | grep -q "Недостаточно ресурсов\|error\|Error"; then
        log_info "✓ ТЕСТ ПРОЙДЕН: Terraform корректно отклонил конфигурацию с превышением общих ресурсов"
        rm -f "$TEMP_TFVARS" tfplan
        exit 0
    else
        if terraform output placement_error 2>/dev/null | grep -q "Недостаточно"; then
            log_info "✓ ТЕСТ ПРОЙДЕН: Ошибка размещения обнаружена"
            rm -f "$TEMP_TFVARS" tfplan
            exit 0
        fi
        log_error "✗ ТЕСТ НЕ ПРОЙДЕН: Terraform не отклонил конфигурацию с превышением общих ресурсов"
        rm -f "$TEMP_TFVARS" tfplan
        exit 1
    fi
fi

if [ "$TEST_VMID_CONFLICT" = true ]; then
    log_section "ТЕСТ: Уникальность VMID между окружениями"
    
    log_test "Проверяем, что VMID в dev-1 и dev-2 не пересекаются..."
    
    DEV1_VMID=$(grep "start_vmid" "$ENVIRONMENTS_DIR/dev-1/terraform.tfvars" 2>/dev/null | grep -oE '[0-9]+' || echo "100")
    DEV2_VMID=$(grep "start_vmid" "$ENVIRONMENTS_DIR/dev-2/terraform.tfvars" 2>/dev/null | grep -oE '[0-9]+' || echo "110")
    
    log_test "dev-1 start_vmid: $DEV1_VMID"
    log_test "dev-2 start_vmid: $DEV2_VMID"
    
    if [ "$DEV1_VMID" != "$DEV2_VMID" ]; then
        log_info "✓ ТЕСТ ПРОЙДЕН: VMID в окружениях dev-1 и dev-2 различаются"
        
        # Дополнительно проверяем IP-смещения
        DEV1_IP=$(grep "ip_start_offset" "$ENVIRONMENTS_DIR/dev-1/terraform.tfvars" 2>/dev/null | grep -oE '[0-9]+' || echo "100")
        DEV2_IP=$(grep "ip_start_offset" "$ENVIRONMENTS_DIR/dev-2/terraform.tfvars" 2>/dev/null | grep -oE '[0-9]+' || echo "110")
        
        log_test "dev-1 ip_start_offset: $DEV1_IP"
        log_test "dev-2 ip_start_offset: $DEV2_IP"
        
        if [ "$DEV1_IP" != "$DEV2_IP" ]; then
            log_info "✓ ТЕСТ ПРОЙДЕН: IP-смещения в окружениях различаются"
            exit 0
        else
            log_error "✗ ТЕСТ НЕ ПРОЙДЕН: IP-смещения в окружениях одинаковые"
            exit 1
        fi
    else
        log_error "✗ ТЕСТ НЕ ПРОЙДЕН: VMID в окружениях dev-1 и dev-2 одинаковые"
        exit 1
    fi
fi

# =============================================================================
# ШАГ 2: Удаление существующих LXC-контейнеров
# =============================================================================
if [ "$SKIP_CLEANUP" = false ]; then
    log_section "Шаг 2: Удаление существующих LXC-контейнеров"
    
    if [ -f "$BASEDIR/delete_internal_vms.sh" ]; then
        log_info "Запуск delete_internal_vms.sh --force"
        "$BASEDIR/delete_internal_vms.sh" --force --master-ip "$MASTER_IP" || true
    else
        log_warn "Скрипт delete_internal_vms.sh не найден, пропускаем очистку"
    fi
else
    log_info "Пропуск очистки (--skip-cleanup)"
fi

# =============================================================================
# ШАГ 3: Запуск Terraform
# =============================================================================
if [ "$SKIP_TERRAFORM" = false ]; then
    log_section "Шаг 3: Запуск Terraform"
    
    # Проверяем наличие Terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform не установлен"
        exit 1
    fi
    
    log_info "Версия Terraform: $(terraform version -json | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1)"
    
    cd "$WORK_DIR"
    
    # Инициализация Terraform
    log_info "Инициализация Terraform..."
    terraform init -upgrade
    
    # Планирование
    log_info "Планирование изменений..."
    if [ -n "$ENVIRONMENT" ]; then
        # Для отдельных окружений используем terraform.tfvars автоматически
        terraform plan -out=tfplan
    else
        terraform plan -var-file="$TFVARS_FILE" -out=tfplan
    fi
    
    # Применение
    log_info "Применение изменений..."
    terraform apply -auto-approve tfplan
    
    # Получение выходных данных
    log_info "Получение IP-адресов созданных контейнеров..."
    LXC_IPS=$(terraform output -json lxc_ips 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")
    
    if [ -z "$LXC_IPS" ]; then
        log_warn "Не удалось получить IP-адреса из Terraform output"
    else
        log_info "Созданные контейнеры:"
        echo "$LXC_IPS" | while read -r IP; do
            [ -n "$IP" ] && echo "  - $IP"
        done
    fi
    
    # Проверяем файл с IP-адресами
    LXC_IPS_FILE=$(terraform output -raw lxc_ips_file 2>/dev/null || echo "")
    if [ -n "$LXC_IPS_FILE" ] && [ -f "$LXC_IPS_FILE" ]; then
        log_info "✓ Файл с IP-адресами создан: $LXC_IPS_FILE"
        log_info "Содержимое:"
        cat "$LXC_IPS_FILE" | while read -r IP; do
            echo "  - $IP"
        done
    fi
    
    # Показываем назначения нод
    log_info "Назначения контейнеров на ноды:"
    terraform output -json node_assignments 2>/dev/null | jq -r '.[]' 2>/dev/null | while read -r NODE; do
        [ -n "$NODE" ] && echo "  - $NODE"
    done
    
    cd "$BASEDIR"
else
    log_info "Пропуск Terraform (--skip-terraform)"
fi

# =============================================================================
# ШАГ 4: Проверка созданных LXC-контейнеров
# =============================================================================
log_section "Шаг 4: Проверка созданных LXC-контейнеров"

# Получаем список контейнеров через Proxmox API
log_info "Получение списка контейнеров с мастер-ноды..."
CONTAINERS_INFO=$(ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    root@"$MASTER_IP" "pct list" 2>/dev/null || echo "")

if [ -z "$CONTAINERS_INFO" ] || [ "$(echo "$CONTAINERS_INFO" | wc -l)" -le 1 ]; then
    log_error "Контейнеры не найдены на мастер-ноде"
    exit 1
fi

echo "$CONTAINERS_INFO"

# Получаем ожидаемые параметры из tfvars
EXPECTED_COUNT=$(grep -E "^lxc_count\s*=" "$TFVARS_FILE" | sed 's/.*=\s*//' | tr -d ' ')
EXPECTED_CPUS=$(grep -E "^lxc_cpus\s*=" "$TFVARS_FILE" | sed 's/.*=\s*//' | tr -d ' ')
EXPECTED_RAM_MB=$(grep -E "^lxc_memory_mb\s*=" "$TFVARS_FILE" | sed 's/.*=\s*//' | tr -d ' ')

log_info "Ожидаемые параметры:"
echo "  - Количество контейнеров: $EXPECTED_COUNT"
echo "  - CPU на контейнер: $EXPECTED_CPUS"
echo "  - RAM на контейнер: $EXPECTED_RAM_MB MB"

# Проверяем количество контейнеров
ACTUAL_COUNT=$(echo "$CONTAINERS_INFO" | tail -n +2 | wc -l)
log_info "Фактическое количество контейнеров: $ACTUAL_COUNT"

if [ "$ACTUAL_COUNT" -lt "$EXPECTED_COUNT" ]; then
    log_error "Создано меньше контейнеров, чем ожидалось: $ACTUAL_COUNT < $EXPECTED_COUNT"
    exit 1
fi

# Проверяем ресурсы каждого контейнера
log_info "Проверка ресурсов контейнеров..."
VMIDS=$(echo "$CONTAINERS_INFO" | tail -n +2 | awk '{print $1}')

ALL_CHECKS_PASSED=true
for VMID in $VMIDS; do
    echo -n "  Контейнер $VMID: "
    
    # Получаем конфигурацию контейнера
    CONFIG=$(ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        root@"$MASTER_IP" "pct config $VMID" 2>/dev/null || echo "")
    
    if [ -z "$CONFIG" ]; then
        echo -e "${RED}✗ Не удалось получить конфигурацию${NC}"
        ALL_CHECKS_PASSED=false
        continue
    fi
    
    # Проверяем CPU
    ACTUAL_CPUS=$(echo "$CONFIG" | grep -E "^cores:" | awk '{print $2}')
    # Проверяем RAM
    ACTUAL_RAM=$(echo "$CONFIG" | grep -E "^memory:" | awk '{print $2}')
    
    CPU_OK=false
    RAM_OK=false
    
    if [ "$ACTUAL_CPUS" = "$EXPECTED_CPUS" ]; then
        CPU_OK=true
    fi
    
    if [ "$ACTUAL_RAM" = "$EXPECTED_RAM_MB" ]; then
        RAM_OK=true
    fi
    
    if [ "$CPU_OK" = true ] && [ "$RAM_OK" = true ]; then
        echo -e "${GREEN}✓ CPU=$ACTUAL_CPUS, RAM=${ACTUAL_RAM}MB${NC}"
    else
        echo -e "${RED}✗ CPU=$ACTUAL_CPUS (ожидалось $EXPECTED_CPUS), RAM=$ACTUAL_RAM (ожидалось $EXPECTED_RAM_MB)${NC}"
        ALL_CHECKS_PASSED=false
    fi
done

# =============================================================================
# ШАГ 5: Проверка SSH-доступа к контейнерам
# =============================================================================
log_section "Шаг 5: Проверка доступа к LXC-контейнерам"

for VMID in $VMIDS; do
    CONFIG=$(ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        root@"$MASTER_IP" "pct config $VMID" 2>/dev/null || echo "")
    
    # Извлекаем IP из конфигурации net0
    NET_CONFIG=$(echo "$CONFIG" | grep -E "^net0:" | head -1)
    CONTAINER_IP=$(echo "$NET_CONFIG" | grep -oE 'ip=[0-9.]+' | cut -d= -f2)
    
    if [ -z "$CONTAINER_IP" ]; then
        log_warn "Не удалось определить IP для контейнера $VMID"
        continue
    fi
    
    echo -n "  Контейнер $VMID ($CONTAINER_IP): "
    
    # Проверяем через pct exec
    if ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
           root@"$MASTER_IP" "pct exec $VMID -- echo 'OK'" 2>/dev/null | grep -q "OK"; then
        echo -e "${GREEN}✓ pct exec работает${NC}"
    else
        echo -e "${YELLOW}⚠ pct exec не работает (контейнер может быть не запущен)${NC}"
    fi
done

# =============================================================================
# Итоги
# =============================================================================
log_section "Итоги тестирования"

if [ "$ALL_CHECKS_PASSED" = true ]; then
    log_info "✓ Все проверки пройдены успешно!"
    echo ""
    if [ -n "$ENVIRONMENT" ]; then
        echo "Terraform-модуль работает корректно для окружения: $ENVIRONMENT"
    else
        echo "Terraform-модуль работает корректно для окружения: $ENV"
    fi
    exit 0
else
    log_error "✗ Некоторые проверки не пройдены"
    exit 1
fi
