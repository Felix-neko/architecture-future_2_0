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

# === Автоопределение IP мастер-ноды ===
if [ -z "$MASTER_IP" ]; then
    echo "Определение IP мастер-ноды (pve-node-1)..."
    MASTER_IP=$(virsh domifaddr pve-node-1 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
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
