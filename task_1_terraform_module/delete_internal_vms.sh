#!/bin/bash
# Скрипт удаления всех LXC-контейнеров внутри Proxmox-кластера
#
# Использование: ./delete_internal_vms.sh [OPTIONS]
#
# Опции:
#   --master-ip IP         IP мастер-ноды кластера (по умолчанию: автоопределение)
#   --force                Удалить без подтверждения
#   -h, --help             Показать справку

set -e

BASEDIR=$(cd "$(dirname "$0")" && pwd)

# === Параметры по умолчанию ===
MASTER_IP=""
FORCE=false

# === Пути ===
PRIVATE_KEY="$BASEDIR/vm_access_key"

# === Парсинг аргументов командной строки ===
while [[ $# -gt 0 ]]; do
    case $1 in
        --master-ip)
            MASTER_IP="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            echo "Использование: $0 [OPTIONS]"
            echo ""
            echo "Опции:"
            echo "  --master-ip IP         IP мастер-ноды кластера (по умолчанию: автоопределение)"
            echo "  --force                Удалить без подтверждения"
            echo "  -h, --help             Показать справку"
            exit 0
            ;;
        *)
            echo "Неизвестный параметр: $1"
            exit 1
            ;;
    esac
done

# === Функция получения IP по имени VM через virsh + arp ===
get_vm_ip_by_name() {
    local vm_name="$1"
    local ip=""
    
    # Проверяем, существует ли VM
    if ! virsh list --name 2>/dev/null | grep -q "^${vm_name}$"; then
        return 1
    fi
    
    # Получаем MAC-адрес VM
    local mac=$(virsh domiflist "$vm_name" 2>/dev/null | tail -n +3 | head -1 | awk '{print $5}')
    if [ -z "$mac" ]; then
        return 1
    fi
    
    # Ищем IP по MAC в arp-таблице
    ip=$(arp -an 2>/dev/null | grep -i "$mac" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    if [ -z "$ip" ]; then
        # Пробуем ip neigh
        ip=$(ip neigh show 2>/dev/null | grep -i "$mac" | awk '{print $1}' | head -1)
    fi
    
    echo "$ip"
}

# === Автоопределение IP мастер-ноды ===
if [ -z "$MASTER_IP" ]; then
    echo "Определение IP мастер-ноды (pve-node-1)..."
    
    # 1. Сначала пробуем прочитать из файла .node_ips (первая строка - мастер-нода)
    if [ -f "$BASEDIR/.node_ips" ]; then
        MASTER_IP=$(head -1 "$BASEDIR/.node_ips")
        if [ -n "$MASTER_IP" ]; then
            echo "  IP из .node_ips: $MASTER_IP"
        fi
    fi
    
    # 2. Если не нашли в файле, пробуем virsh domifaddr
    if [ -z "$MASTER_IP" ]; then
        MASTER_IP=$(virsh domifaddr pve-node-1 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
        if [ -n "$MASTER_IP" ]; then
            echo "  IP через virsh domifaddr: $MASTER_IP"
        fi
    fi
    
    # 3. Пробуем virsh net-dhcp-leases
    if [ -z "$MASTER_IP" ]; then
        MASTER_IP=$(virsh net-dhcp-leases default 2>/dev/null | grep -i pve-node-1 | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
        if [ -n "$MASTER_IP" ]; then
            echo "  IP через virsh net-dhcp-leases: $MASTER_IP"
        fi
    fi
    
    # 4. Fallback: ищем pve-ноды через virsh и получаем IP через arp
    if [ -z "$MASTER_IP" ]; then
        echo "  Поиск pve-нод через virsh + arp..."
        # Проверяем наличие pve-node-1
        if virsh list --name 2>/dev/null | grep -q "pve-node-1"; then
            MASTER_IP=$(get_vm_ip_by_name "pve-node-1")
            if [ -n "$MASTER_IP" ]; then
                echo "  IP через virsh + arp: $MASTER_IP"
            fi
        fi
    fi
    
    if [ -z "$MASTER_IP" ]; then
        echo "✗ Не удалось определить IP мастер-ноды pve-node-1"
        echo "  Укажите IP вручную через --master-ip"
        exit 1
    fi
fi

echo "========================================"
echo "Удаление LXC-контейнеров в Proxmox"
echo "========================================"
echo "  Мастер-нода: $MASTER_IP"
echo "========================================"
echo ""

# === Проверка доступности мастер-ноды ===
echo "Проверка доступности мастер-ноды..."
if ! ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@"$MASTER_IP" "exit 0" 2>/dev/null; then
    echo "✗ Мастер-нода $MASTER_IP недоступна по SSH"
    exit 1
fi
echo "✓ Мастер-нода доступна"
echo ""

# === Получение списка контейнеров ===
echo "=== Текущие LXC-контейнеры ==="
CONTAINERS=$(ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$MASTER_IP" \
    "pct list 2>/dev/null | tail -n +2 | awk '{print \$1}'" 2>/dev/null || true)

if [ -z "$CONTAINERS" ]; then
    echo "Контейнеры не найдены"
    exit 0
fi

echo "Найдены контейнеры:"
ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$MASTER_IP" \
    "pct list" 2>/dev/null
echo ""

# === Подтверждение удаления ===
if [ "$FORCE" != "true" ]; then
    echo "Удалить все контейнеры? (y/N)"
    read -r CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo "Отменено"
        exit 0
    fi
fi

# === Удаление контейнеров ===
echo "=== Удаление LXC-контейнеров ==="

for VMID in $CONTAINERS; do
    echo "Удаление контейнера VMID=$VMID..."
    ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$MASTER_IP" \
        "pct stop $VMID 2>/dev/null || true; pct destroy $VMID --force 2>/dev/null" && \
        echo "✓ Контейнер $VMID удалён" || echo "⚠ Ошибка удаления контейнера $VMID"
done

echo ""

# === Проверка результата ===
echo "=== Оставшиеся контейнеры ==="
ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$MASTER_IP" \
    "pct list" 2>/dev/null || echo "Контейнеров нет"

echo ""
echo "========================================"
echo "✓ Удаление LXC-контейнеров завершено"
echo "========================================"
