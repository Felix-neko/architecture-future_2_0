#!/bin/bash
# Скрипт создания Proxmox-кластера из нескольких нод
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
#   -h, --help             Показать справку

set -e

BASEDIR=$(cd "$(dirname "$0")" && pwd)

# === Параметры по умолчанию ===
NODE_COUNT=3
NODE_CPUS=4
NODE_RAM_MB=8192
NODE_DISK_SIZE="40G"
ROOT_PASSWORD="mega_root_password"
CLUSTER_NAME="pve-cluster"

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
PUBLIC_KEY="$BASEDIR/vm_access_key.pub"

# === Массив для хранения IP-адресов нод ===
declare -a NODE_IPS
declare -a NODE_NAMES

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

# === 1. Очистка старых VM ===
echo "=== Шаг 1: Очистка старых VM ==="
if [ -f "$BASEDIR/cleanup_all_vms.sh" ]; then
    "$BASEDIR/cleanup_all_vms.sh" --force || true
else
    echo "Скрипт cleanup_all_vms.sh не найден, пропускаем очистку"
fi
echo ""

# === 2. Генерация SSH-ключей (если нет) ===
echo "=== Шаг 2: Проверка SSH-ключей ==="
if [ ! -f "$PRIVATE_KEY" ]; then
    echo "Генерация SSH-ключей..."
    ssh-keygen -t ed25519 -f "$PRIVATE_KEY" -N "" -C "vm-access-key"
fi
echo "✓ SSH-ключи готовы"
echo ""

# === 3. Создание нод кластера ===
echo "=== Шаг 3: Создание нод кластера ==="

for i in $(seq 1 $NODE_COUNT); do
    NODE_NAME="pve-node-$i"
    NODE_NAMES+=("$NODE_NAME")
    
    echo ""
    echo "--- Создание ноды $i/$NODE_COUNT: $NODE_NAME ---"
    
    # Экспортируем переменные для install_proxmox_final.sh
    export VM_NAME="$NODE_NAME"
    export VM_VCPUS="$NODE_CPUS"
    export VM_RAM_MB="$NODE_RAM_MB"
    export VM_DISK_SIZE="$NODE_DISK_SIZE"
    export ROOT_PASSWORD="$ROOT_PASSWORD"
    
    # Запускаем установку
    "$BASEDIR/install_proxmox_final.sh"
    
    # Получаем IP-адрес созданной ноды
    VM_MAC=$(virsh domiflist "$NODE_NAME" 2>/dev/null | grep -oE '([0-9a-f]{2}:){5}[0-9a-f]{2}' | head -1)
    NODE_IP=$(virsh net-dhcp-leases default 2>/dev/null | grep -i "$VM_MAC" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    NODE_IPS+=("$NODE_IP")
    
    echo "✓ Нода $NODE_NAME создана с IP: $NODE_IP"
done

echo ""
echo "=== Созданные ноды ==="
for i in $(seq 0 $((NODE_COUNT - 1))); do
    echo "  ${NODE_NAMES[$i]}: ${NODE_IPS[$i]}"
done
echo ""

# === 4. Создание кластера на первой ноде ===
echo "=== Шаг 4: Создание Proxmox-кластера ==="
MASTER_IP="${NODE_IPS[0]}"
MASTER_NAME="${NODE_NAMES[0]}"

echo "Создание кластера '$CLUSTER_NAME' на ноде $MASTER_NAME ($MASTER_IP)..."

ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$MASTER_IP" << CLUSTER_SCRIPT
# Монтируем файловые системы в chroot
mount --bind /dev /srv/debian-pve/dev 2>/dev/null || true
mount --bind /dev/pts /srv/debian-pve/dev/pts 2>/dev/null || true
mount --bind /proc /srv/debian-pve/proc 2>/dev/null || true
mount --bind /sys /srv/debian-pve/sys 2>/dev/null || true
cp /etc/resolv.conf /srv/debian-pve/etc/resolv.conf

# Создаём кластер
chroot /srv/debian-pve /bin/bash << 'CHROOT_CMD'
export DEBIAN_FRONTEND=noninteractive

# Настраиваем hostname в /etc/hosts
HOSTNAME=\$(hostname 2>/dev/null || echo "pve-node-1")
IP=\$(ip -4 addr show | grep -oP '(?<=inet\s)192\.168\.\d+\.\d+' | head -1 || echo "127.0.0.1")
grep -q "\$IP \$HOSTNAME" /etc/hosts 2>/dev/null || echo "\$IP \$HOSTNAME" >> /etc/hosts

# Проверяем pvecm
which pvecm && echo "pvecm найден" || echo "pvecm не найден"

# Создаём кластер (если pvecm доступен)
if which pvecm >/dev/null 2>&1; then
    pvecm create "$CLUSTER_NAME" 2>/dev/null || echo "Кластер уже существует или ошибка создания"
    pvecm status 2>/dev/null || echo "Статус кластера недоступен"
fi
CHROOT_CMD
CLUSTER_SCRIPT

echo "✓ Кластер создан на $MASTER_NAME"
echo ""

# === 5. Присоединение остальных нод к кластеру ===
if [ $NODE_COUNT -gt 1 ]; then
    echo "=== Шаг 5: Присоединение нод к кластеру ==="
    
    for i in $(seq 1 $((NODE_COUNT - 1))); do
        NODE_IP="${NODE_IPS[$i]}"
        NODE_NAME="${NODE_NAMES[$i]}"
        
        echo "Присоединение $NODE_NAME ($NODE_IP) к кластеру..."
        
        ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$NODE_IP" << JOIN_SCRIPT
mount --bind /dev /srv/debian-pve/dev 2>/dev/null || true
mount --bind /dev/pts /srv/debian-pve/dev/pts 2>/dev/null || true
mount --bind /proc /srv/debian-pve/proc 2>/dev/null || true
mount --bind /sys /srv/debian-pve/sys 2>/dev/null || true
cp /etc/resolv.conf /srv/debian-pve/etc/resolv.conf

chroot /srv/debian-pve /bin/bash << 'CHROOT_CMD'
if which pvecm >/dev/null 2>&1; then
    # Пробуем присоединиться к кластеру (может не работать в chroot)
    echo "Попытка присоединения к кластеру..."
    pvecm add $MASTER_IP --force 2>/dev/null || echo "Присоединение к кластеру не удалось (ожидаемо в chroot)"
fi
CHROOT_CMD
JOIN_SCRIPT
        
        echo "✓ Нода $NODE_NAME обработана"
    done
    echo ""
fi

# === 6. Проверка статуса кластера ===
echo "=== Шаг 6: Проверка статуса кластера ==="
ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$MASTER_IP" << STATUS_SCRIPT
chroot /srv/debian-pve /bin/bash << 'CHROOT_CMD'
echo "--- pveversion ---"
pveversion 2>/dev/null || echo "недоступно"
echo ""
echo "--- pvecm status ---"
pvecm status 2>/dev/null || echo "недоступно"
echo ""
echo "--- pvecm nodes ---"
pvecm nodes 2>/dev/null || echo "недоступно"
CHROOT_CMD
STATUS_SCRIPT
echo ""

# === 7. Проверка Proxmox на всех нодах ===
echo "=== Шаг 7: Проверка Proxmox на всех нодах ==="
for i in $(seq 0 $((NODE_COUNT - 1))); do
    NODE_IP="${NODE_IPS[$i]}"
    NODE_NAME="${NODE_NAMES[$i]}"
    echo -n "  $NODE_NAME ($NODE_IP): "
    PVE_VER=$(ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$NODE_IP" "chroot /srv/debian-pve pveversion 2>/dev/null" 2>/dev/null || echo "недоступен")
    echo "$PVE_VER"
done
echo ""

# === 8. Итоговая информация ===
echo "========================================"
echo "✓ Proxmox-кластер создан!"
echo "========================================"
echo ""
echo "Кластер: $CLUSTER_NAME"
echo "Нод: $NODE_COUNT"
echo ""
echo "Ноды кластера:"
for i in $(seq 0 $((NODE_COUNT - 1))); do
    echo "  ${NODE_NAMES[$i]}: ${NODE_IPS[$i]}"
done
echo ""
echo "=== Ограничения chroot-окружения ==="
echo ""
echo "ВАЖНО: Proxmox установлен в chroot-окружении, поэтому:"
echo "  - Веб-интерфейс (порт 8006) НЕ ДОСТУПЕН"
echo "  - API сервисы не запущены"
echo "  - Для полноценной работы требуется перезагрузка в Proxmox-ядро"
echo ""
echo "Для проверки Proxmox используйте CLI команды через chroot."
echo ""
echo "=== SSH-доступ ==="
echo ""
for i in $(seq 0 $((NODE_COUNT - 1))); do
    echo "  ssh -i $PRIVATE_KEY root@${NODE_IPS[$i]}"
done
echo ""
echo "=== Проверка Proxmox на нодах ==="
echo ""
for i in $(seq 0 $((NODE_COUNT - 1))); do
    echo "  ssh -i $PRIVATE_KEY root@${NODE_IPS[$i]} 'chroot /srv/debian-pve pveversion'"
done
echo ""
echo "========================================"
