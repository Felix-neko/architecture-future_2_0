#!/bin/bash
# Скрипт создания LXC-контейнеров внутри Proxmox-кластера
#
# Использование: ./create_internal_vms.sh [OPTIONS]
#
# Опции:
#   -n, --count NUM        Количество контейнеров (по умолчанию: 1)
#   -c, --cpus NUM         Количество CPU на контейнер (по умолчанию: 2)
#   -m, --memory MB        Объём памяти на контейнер в MB (по умолчанию: 8192)
#   -d, --disk GB          Размер диска на контейнер в GB (по умолчанию: 10)
#   --start-id NUM         Начальный VMID (по умолчанию: 100)
#   --template NAME        Шаблон контейнера (по умолчанию: alpine-3.19-default_20240207_amd64.tar.xz)
#   --master-ip IP         IP мастер-ноды кластера (по умолчанию: автоопределение)
#   -h, --help             Показать справку

set -e

BASEDIR=$(cd "$(dirname "$0")" && pwd)

# === Параметры по умолчанию ===
CONTAINER_COUNT=1
CONTAINER_CPUS=2
CONTAINER_RAM_MB=8192
CONTAINER_DISK_GB=10
START_VMID=100
TEMPLATE="alpine-3.22-default_20250617_amd64.tar.xz"
MASTER_IP=""

# === Пути ===
PRIVATE_KEY="$BASEDIR/vm_access_key"

# === Парсинг аргументов командной строки ===
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--count)
            CONTAINER_COUNT="$2"
            shift 2
            ;;
        -c|--cpus)
            CONTAINER_CPUS="$2"
            shift 2
            ;;
        -m|--memory)
            CONTAINER_RAM_MB="$2"
            shift 2
            ;;
        -d|--disk)
            CONTAINER_DISK_GB="$2"
            shift 2
            ;;
        --start-id)
            START_VMID="$2"
            shift 2
            ;;
        --template)
            TEMPLATE="$2"
            shift 2
            ;;
        --master-ip)
            MASTER_IP="$2"
            shift 2
            ;;
        -h|--help)
            echo "Использование: $0 [OPTIONS]"
            echo ""
            echo "Опции:"
            echo "  -n, --count NUM        Количество контейнеров (по умолчанию: 1)"
            echo "  -c, --cpus NUM         Количество CPU на контейнер (по умолчанию: 2)"
            echo "  -m, --memory MB        Объём памяти на контейнер в MB (по умолчанию: 8192)"
            echo "  -d, --disk GB          Размер диска на контейнер в GB (по умолчанию: 10)"
            echo "  --start-id NUM         Начальный VMID (по умолчанию: 100)"
            echo "  --template NAME        Шаблон контейнера (по умолчанию: alpine-3.19-...)"
            echo "  --master-ip IP         IP мастер-ноды кластера (по умолчанию: автоопределение)"
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
echo "Создание LXC-контейнеров в Proxmox"
echo "========================================"
echo "  Мастер-нода: $MASTER_IP"
echo "  Контейнеров: $CONTAINER_COUNT"
echo "  CPU/контейнер: $CONTAINER_CPUS"
echo "  RAM/контейнер: $CONTAINER_RAM_MB MB"
echo "  Disk/контейнер: $CONTAINER_DISK_GB GB"
echo "  Шаблон: $TEMPLATE"
echo "  Начальный VMID: $START_VMID"
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

# === Скачивание шаблона (если нет) ===
echo "Проверка наличия шаблона контейнера..."
ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$MASTER_IP" << EOF
if ! pveam list local | grep -q "$TEMPLATE"; then
    echo "Скачивание шаблона $TEMPLATE..."
    pveam update
    pveam download local $TEMPLATE
else
    echo "✓ Шаблон уже скачан"
fi
EOF
echo ""

# === Создание контейнеров ===
echo "=== Создание LXC-контейнеров ==="

for i in $(seq 1 $CONTAINER_COUNT); do
    VMID=$((START_VMID + i - 1))
    CT_NAME="lxc-container-$VMID"
    
    echo ""
    echo "--- Создание контейнера $i/$CONTAINER_COUNT: $CT_NAME (VMID: $VMID) ---"
    
    ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$MASTER_IP" << EOF
# Удаляем старый контейнер если есть
pct destroy $VMID --force 2>/dev/null || true

# Создаём контейнер
pct create $VMID local:vztmpl/$TEMPLATE \
    --hostname $CT_NAME \
    --memory $CONTAINER_RAM_MB \
    --cores $CONTAINER_CPUS \
    --rootfs local-lvm:$CONTAINER_DISK_GB \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --unprivileged 1 \
    --start 1

echo "✓ Контейнер $CT_NAME создан и запущен"
EOF
done

echo ""

# === Вывод списка созданных контейнеров ===
echo "=== Список созданных контейнеров ==="
ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$MASTER_IP" \
    "pct list"

echo ""
echo "========================================"
echo "✓ Создано $CONTAINER_COUNT LXC-контейнеров"
echo "========================================"
echo ""
echo "Управление контейнерами:"
echo "  Список: ssh -i $PRIVATE_KEY root@$MASTER_IP 'pct list'"
echo "  Консоль: ssh -i $PRIVATE_KEY root@$MASTER_IP 'pct enter <VMID>'"
echo "  Стоп: ssh -i $PRIVATE_KEY root@$MASTER_IP 'pct stop <VMID>'"
echo "  Удаление: ./delete_internal_vms.sh"
echo "========================================"
