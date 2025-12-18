#!/bin/bash
# Скрипт создания набора Proxmox-нод (без объединения в кластер)
#
# Использование: ./create_proxmox_nodes.sh [OPTIONS]
#
# Опции:
#   -n, --nodes NUM        Количество нод (по умолчанию: 3)
#   -c, --cpus NUM         Количество CPU на ноду (по умолчанию: 4)
#   -m, --memory MB        Объём памяти на ноду в MB (по умолчанию: 8192)
#   -d, --disk SIZE        Размер диска на ноду (по умолчанию: 40G)
#   -p, --password PASS    Пароль root (по умолчанию: mega_root_password)
#   --no-cleanup           Не удалять старые VM перед созданием
#   -h, --help             Показать справку

set -e

BASEDIR=$(cd "$(dirname "$0")" && pwd)

# === Параметры по умолчанию ===
NODE_COUNT=3
NODE_CPUS=4
NODE_RAM_MB=8192
NODE_DISK_SIZE="40G"
ROOT_PASSWORD="mega_root_password"
DO_CLEANUP=true

# === Парсинг аргументов командной строки ===
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--nodes)
            NODE_COUNT="$2"
            shift 2
            ;;
        -c|--cpus)
            NODE_CPUS="$2"
            shift 2
            ;;
        -m|--memory)
            NODE_RAM_MB="$2"
            shift 2
            ;;
        -d|--disk)
            NODE_DISK_SIZE="$2"
            shift 2
            ;;
        -p|--password)
            ROOT_PASSWORD="$2"
            shift 2
            ;;
        --no-cleanup)
            DO_CLEANUP=false
            shift
            ;;
        -h|--help)
            echo "Использование: $0 [OPTIONS]"
            echo ""
            echo "Опции:"
            echo "  -n, --nodes NUM        Количество нод (по умолчанию: 3)"
            echo "  -c, --cpus NUM         Количество CPU на ноду (по умолчанию: 4)"
            echo "  -m, --memory MB        Объём памяти на ноду в MB (по умолчанию: 8192)"
            echo "  -d, --disk SIZE        Размер диска на ноду (по умолчанию: 40G)"
            echo "  -p, --password PASS    Пароль root (по умолчанию: mega_root_password)"
            echo "  --no-cleanup           Не удалять старые VM перед созданием"
            echo "  -h, --help             Показать справку"
            exit 0
            ;;
        *)
            echo "Неизвестный параметр: $1"
            exit 1
            ;;
    esac
done

# === Пути ===
PRIVATE_KEY="$BASEDIR/vm_access_key"

# === Массивы для хранения данных нод ===
declare -a NODE_IPS
declare -a NODE_NAMES

echo "========================================"
echo "Создание Proxmox-нод"
echo "========================================"
echo "  Нод:        $NODE_COUNT"
echo "  CPU/нода:   $NODE_CPUS"
echo "  RAM/нода:   $NODE_RAM_MB MB"
echo "  Disk/нода:  $NODE_DISK_SIZE"
echo "  Пароль:     $ROOT_PASSWORD"
echo "========================================"
echo ""

# === 1. Очистка старых VM (опционально) ===
if [ "$DO_CLEANUP" = true ]; then
    echo "=== Шаг 1: Очистка старых VM ==="
    "$BASEDIR/cleanup_all_vms.sh" --force || true
    echo ""
fi

# === 2. Создание нод ===
echo "=== Шаг 2: Создание Proxmox-нод ==="

for i in $(seq 1 $NODE_COUNT); do
    NODE_NAME="pve-node-$i"
    NODE_NAMES+=("$NODE_NAME")
    
    echo ""
    echo "--- Создание ноды $i/$NODE_COUNT: $NODE_NAME ---"
    
    # Экспортируем переменные для install_proxmox_iso.sh
    export VM_NAME="$NODE_NAME"
    export VM_VCPUS="$NODE_CPUS"
    export VM_RAM_MB="$NODE_RAM_MB"
    export VM_DISK_SIZE="$NODE_DISK_SIZE"
    export ROOT_PASSWORD="$ROOT_PASSWORD"
    # ISO пересоздаётся с уникальным hostname для каждой VM
    
    # Запускаем установку Proxmox из ISO
    "$BASEDIR/install_proxmox_iso.sh"
    
    # Получаем IP-адрес созданной ноды
    NODE_IP=$(virsh domifaddr "$NODE_NAME" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    NODE_IPS+=("$NODE_IP")
    
    echo "✓ Нода $NODE_NAME создана с IP: $NODE_IP"
done

echo ""

# === 3. Проверка веб-интерфейса на всех нодах ===
echo "=== Шаг 3: Проверка веб-интерфейса ==="
ALL_OK=true
for i in $(seq 0 $((NODE_COUNT - 1))); do
    NODE_IP="${NODE_IPS[$i]}"
    NODE_NAME="${NODE_NAMES[$i]}"
    
    if curl -sk --connect-timeout 5 "https://$NODE_IP:8006" >/dev/null 2>&1; then
        echo "✓ $NODE_NAME ($NODE_IP): веб-интерфейс доступен"
    else
        echo "✗ $NODE_NAME ($NODE_IP): веб-интерфейс недоступен"
        ALL_OK=false
    fi
done
echo ""

# === 4. Итоговая информация ===
echo "========================================"
if [ "$ALL_OK" = true ]; then
    echo "✓ Все $NODE_COUNT Proxmox-нод созданы успешно!"
else
    echo "⚠ Некоторые ноды имеют проблемы"
fi
echo "========================================"
echo ""
echo "Созданные ноды:"
for i in $(seq 0 $((NODE_COUNT - 1))); do
    echo "  ${NODE_NAMES[$i]}: https://${NODE_IPS[$i]}:8006"
done
echo ""
echo "Подключение по SSH:"
echo "  ssh -i $PRIVATE_KEY root@<IP>"
echo ""
echo "Логин в веб-интерфейс:"
echo "  Пользователь: root"
echo "  Пароль: $ROOT_PASSWORD"
echo ""
echo "Для объединения нод в кластер запустите:"
echo "  ./join_proxmox_cluster.sh"
echo "========================================"

# Сохраняем информацию о нодах для join_proxmox_cluster.sh и terraform-модуля
# Формат: по одному значению на строку (совместимо с terraform)
printf '%s\n' "${NODE_IPS[@]}" > "$BASEDIR/.node_ips"
printf '%s\n' "${NODE_NAMES[@]}" > "$BASEDIR/.node_names"
echo "Сохранены файлы: $BASEDIR/.node_ips, $BASEDIR/.node_names"
