#!/bin/bash
# Скрипт создания Proxmox-кластера из нескольких нод
# Использует create_proxmox_nodes.sh и join_proxmox_nodes_in_cluster.sh
#
# Использование: ./create_proxmox_cluster.sh [OPTIONS]
#
# Опции:
#   -n, --nodes NUM        Количество нод в кластере (по умолчанию: 3)
#   -c, --cpus NUM         Количество CPU на ноду (по умолчанию: 4)
#   -m, --memory MB        Объём памяти на ноду в MB (по умолчанию: 8192)
#   -d, --disk SIZE        Размер диска на ноду (по умолчанию: 40G)
#   -p, --password PASS    Пароль root (по умолчанию: mega_root_password)
#   --cluster-name NAME    Имя кластера (по умолчанию: pve-cluster)
#   --skip-nodes           Пропустить создание нод (использовать существующие)
#   --skip-cluster         Пропустить объединение в кластер
#   -h, --help             Показать справку

set -e

BASEDIR=$(cd "$(dirname "$0")" && pwd)

# === Параметры по умолчанию ===
NODE_COUNT=3
NODE_CPUS=5
NODE_RAM_MB=16384
NODE_DISK_SIZE="80G"
ROOT_PASSWORD="mega_root_password"
CLUSTER_NAME="pve-cluster"
SKIP_NODES=false
SKIP_CLUSTER=false

# === Пути ===
PRIVATE_KEY="$BASEDIR/vm_access_key"

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
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --skip-nodes)
            SKIP_NODES=true
            shift
            ;;
        --skip-cluster)
            SKIP_CLUSTER=true
            shift
            ;;
        -h|--help)
            echo "Использование: $0 [OPTIONS]"
            echo ""
            echo "Опции:"
            echo "  -n, --nodes NUM        Количество нод в кластере (по умолчанию: 3)"
            echo "  -c, --cpus NUM         Количество CPU на ноду (по умолчанию: 4)"
            echo "  -m, --memory MB        Объём памяти на ноду в MB (по умолчанию: 8192)"
            echo "  -d, --disk SIZE        Размер диска на ноду (по умолчанию: 40G)"
            echo "  -p, --password PASS    Пароль root (по умолчанию: mega_root_password)"
            echo "  --cluster-name NAME    Имя кластера (по умолчанию: pve-cluster)"
            echo "  --skip-nodes           Пропустить создание нод (использовать существующие)"
            echo "  --skip-cluster         Пропустить объединение в кластер"
            echo "  -h, --help             Показать справку"
            exit 0
            ;;
        *)
            echo "Неизвестный параметр: $1"
            exit 1
            ;;
    esac
done

echo "========================================"
echo "Создание Proxmox-кластера"
echo "========================================"
echo "  Кластер:    $CLUSTER_NAME"
echo "  Нод:        $NODE_COUNT"
echo "  CPU/нода:   $NODE_CPUS"
echo "  RAM/нода:   $NODE_RAM_MB MB"
echo "  Disk/нода:  $NODE_DISK_SIZE"
echo "  Пароль:     $ROOT_PASSWORD"
echo "========================================"
echo ""

# === 1. Создание нод ===
if [ "$SKIP_NODES" = false ]; then
    echo "=== Этап 1: Создание Proxmox-нод ==="
    "$BASEDIR/create_proxmox_nodes.sh" \
        -n "$NODE_COUNT" \
        -c "$NODE_CPUS" \
        -m "$NODE_RAM_MB" \
        -d "$NODE_DISK_SIZE" \
        -p "$ROOT_PASSWORD"
    echo ""
else
    echo "=== Этап 1: Пропуск создания нод (--skip-nodes) ==="
    echo ""
fi

# === 2. Объединение в кластер ===
if [ "$SKIP_CLUSTER" = false ]; then
    echo "=== Этап 2: Объединение нод в кластер ==="
    "$BASEDIR/join_proxmox_nodes_in_cluster.sh" \
        --cluster-name "$CLUSTER_NAME" \
        --test-lxc
    echo ""
else
    echo "=== Этап 2: Пропуск объединения в кластер (--skip-cluster) ==="
    echo ""
fi

# === 3. Проверка и вывод информации о файлах нод ===
NODE_IPS_FILE="$BASEDIR/.node_ips"
NODE_NAMES_FILE="$BASEDIR/.node_names"

echo "=== Файлы с информацией о нодах ==="
if [ -f "$NODE_IPS_FILE" ] && [ -f "$NODE_NAMES_FILE" ]; then
    echo "✓ $NODE_IPS_FILE:"
    cat "$NODE_IPS_FILE" | while read ip; do echo "    $ip"; done
    echo ""
    echo "✓ $NODE_NAMES_FILE:"
    cat "$NODE_NAMES_FILE" | while read name; do echo "    $name"; done
else
    echo "⚠ Файлы .node_ips или .node_names не найдены"
fi
echo ""

# === 4. Проверка количества нод в Proxmox-кластере ===
echo "=== Проверка количества нод в кластере ==="

# Получаем IP первой ноды для проверки
FIRST_NODE_IP=$(head -1 "$NODE_IPS_FILE" 2>/dev/null)

if [ -n "$FIRST_NODE_IP" ]; then
    # Получаем количество нод в кластере через pvecm nodes
    CLUSTER_NODES=$(ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        root@"$FIRST_NODE_IP" "pvecm nodes 2>/dev/null | grep -c '^\s*[0-9]'" 2>/dev/null || echo "0")
    
    echo "Нод в кластере Proxmox: $CLUSTER_NODES"
    echo "Ожидаемое количество:   $NODE_COUNT"
    
    if [ "$CLUSTER_NODES" -eq "$NODE_COUNT" ]; then
        echo "✓ Все $NODE_COUNT нод успешно объединены в кластер!"
    else
        echo "⚠ ВНИМАНИЕ: В кластере $CLUSTER_NODES нод вместо ожидаемых $NODE_COUNT"
        echo ""
        echo "Статус кластера:"
        ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no root@"$FIRST_NODE_IP" "pvecm status" 2>/dev/null || true
        echo ""
        echo "Список нод:"
        ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no root@"$FIRST_NODE_IP" "pvecm nodes" 2>/dev/null || true
        
        if [ "$CLUSTER_NODES" -lt "$NODE_COUNT" ]; then
            echo ""
            echo "✗ Кластер не полностью сформирован!"
            exit 1
        fi
    fi
else
    echo "⚠ Не удалось получить IP первой ноды для проверки"
fi
echo ""

echo "========================================"
echo "✓ Proxmox-кластер '$CLUSTER_NAME' готов!"
echo "========================================"
echo ""
echo "Для использования в terraform-модуле:"
echo "  Файл IP-адресов:  $NODE_IPS_FILE"
echo "  Файл имён нод:    $NODE_NAMES_FILE"
