#!/bin/bash
# =============================================================================
# Тестовый скрипт для проверки Terraform-модуля LXC-контейнеров
#
# Использование: ./test_terraform_module.sh [OPTIONS]
#
# Опции:
#   -e, --env ENV          Окружение: dev, stage, prod (по умолчанию: dev)
#   --skip-cleanup         Пропустить удаление существующих контейнеров
#   --skip-terraform       Пропустить запуск Terraform (только проверка)
#   -h, --help             Показать справку
# =============================================================================

set -e

BASEDIR=$(cd "$(dirname "$0")" && pwd)
TERRAFORM_DIR="$BASEDIR/terraform/vm_module"
ENVS_DIR="$BASEDIR/terraform/envs"

# === Параметры по умолчанию ===
ENV="dev"
SKIP_CLEANUP=false
SKIP_TERRAFORM=false

# === Пути ===
PRIVATE_KEY="$BASEDIR/vm_access_key"
NODE_IPS_FILE="$BASEDIR/.node_ips"

# === Цвета для вывода ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# === Парсинг аргументов командной строки ===
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--env)
            ENV="$2"
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
        -h|--help)
            echo "Использование: $0 [OPTIONS]"
            echo ""
            echo "Опции:"
            echo "  -e, --env ENV          Окружение: dev, stage, prod (по умолчанию: dev)"
            echo "  --skip-cleanup         Пропустить удаление существующих контейнеров"
            echo "  --skip-terraform       Пропустить запуск Terraform (только проверка)"
            echo "  -h, --help             Показать справку"
            exit 0
            ;;
        *)
            echo "Неизвестный параметр: $1"
            exit 1
            ;;
    esac
done

# === Проверка окружения ===
if [[ ! "$ENV" =~ ^(dev|stage|prod)$ ]]; then
    log_error "Неверное окружение: $ENV. Допустимые значения: dev, stage, prod"
    exit 1
fi

TFVARS_FILE="$ENVS_DIR/${ENV}.tfvars"
if [ ! -f "$TFVARS_FILE" ]; then
    log_error "Файл переменных не найден: $TFVARS_FILE"
    exit 1
fi

log_section "Тестирование Terraform-модуля LXC"
log_info "Окружение: $ENV"
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
ALL_NODES_OK=true

echo "$NODE_IPS" | while read -r IP; do
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
        ALL_NODES_OK=false
    fi
done

# Проверяем результат (нужно перепроверить, т.к. while в подоболочке)
for IP in $NODE_IPS; do
    [ -z "$IP" ] && continue
    if ! ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
           -o ConnectTimeout=5 root@"$IP" "exit 0" 2>/dev/null; then
        log_error "Нода $IP недоступна по SSH"
        exit 1
    fi
done

log_info "✓ Все Proxmox-ноды доступны"

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
    
    cd "$TERRAFORM_DIR"
    
    # Инициализация Terraform
    log_info "Инициализация Terraform..."
    terraform init -upgrade
    
    # Планирование
    log_info "Планирование изменений..."
    terraform plan -var-file="$TFVARS_FILE" -out=tfplan
    
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
log_section "Шаг 5: Проверка SSH-доступа к LXC-контейнерам"

# Получаем IP-адреса контейнеров
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
    
    # Пробуем подключиться через Proxmox-ноду (проброс SSH)
    # Alpine LXC может не иметь SSH по умолчанию, проверяем через pct exec
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
    echo "Terraform-модуль работает корректно для окружения: $ENV"
    exit 0
else
    log_error "✗ Некоторые проверки не пройдены"
    exit 1
fi
