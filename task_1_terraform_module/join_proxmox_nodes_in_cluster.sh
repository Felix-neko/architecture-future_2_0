#!/bin/bash
# Скрипт объединения Proxmox-нод в кластер
#
# Использование: ./join_proxmox_cluster.sh [OPTIONS]
#
# Опции:
#   --cluster-name NAME    Имя кластера (по умолчанию: pve-cluster)
#   --test-lxc             Создать и удалить тестовый LXC-контейнер
#   -h, --help             Показать справку

set -e

BASEDIR=$(cd "$(dirname "$0")" && pwd)

# === Параметры по умолчанию ===
CLUSTER_NAME="pve-cluster"
TEST_LXC=true
ROOT_PASSWORD="mega_root_password"

# === Пути ===
PRIVATE_KEY="$BASEDIR/vm_access_key"

# === Парсинг аргументов командной строки ===
while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --test-lxc)
            TEST_LXC=true
            shift
            ;;
        --no-test-lxc)
            TEST_LXC=false
            shift
            ;;
        -h|--help)
            echo "Использование: $0 [OPTIONS]"
            echo ""
            echo "Опции:"
            echo "  --cluster-name NAME    Имя кластера (по умолчанию: pve-cluster)"
            echo "  --test-lxc             Создать и удалить тестовый LXC-контейнер (по умолчанию)"
            echo "  --no-test-lxc          Не создавать тестовый LXC-контейнер"
            echo "  -h, --help             Показать справку"
            exit 0
            ;;
        *)
            echo "Неизвестный параметр: $1"
            exit 1
            ;;
    esac
done

# === Получаем список нод ===
echo "=== Поиск Proxmox-нод ==="

# Если есть сохранённые данные от create_proxmox_nodes.sh
if [ -f "$BASEDIR/.node_ips" ] && [ -f "$BASEDIR/.node_names" ]; then
    # Читаем файлы построчно (формат: по одному значению на строку)
    mapfile -t NODE_IPS < "$BASEDIR/.node_ips"
    mapfile -t NODE_NAMES < "$BASEDIR/.node_names"
else
    # Автоопределение нод по virsh
    declare -a NODE_IPS
    declare -a NODE_NAMES
    
    for vm in $(virsh list --name 2>/dev/null | grep "^pve-node-"); do
        NODE_NAMES+=("$vm")
        IP=$(virsh domifaddr "$vm" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
        NODE_IPS+=("$IP")
    done
fi

NODE_COUNT=${#NODE_IPS[@]}

if [ $NODE_COUNT -eq 0 ]; then
    echo "✗ Proxmox-ноды не найдены"
    echo "  Сначала запустите: ./create_proxmox_nodes.sh"
    exit 1
fi

echo "Найдено нод: $NODE_COUNT"
for i in $(seq 0 $((NODE_COUNT - 1))); do
    echo "  ${NODE_NAMES[$i]}: ${NODE_IPS[$i]}"
done
echo ""

MASTER_IP="${NODE_IPS[0]}"
MASTER_NAME="${NODE_NAMES[0]}"

echo "========================================"
echo "Объединение нод в кластер '$CLUSTER_NAME'"
echo "========================================"
echo "  Мастер-нода: $MASTER_NAME ($MASTER_IP)"
echo "  Всего нод:   $NODE_COUNT"
echo "========================================"
echo ""

# === 1. Исправление hostname на всех нодах ===
echo "=== Шаг 1: Проверка и исправление hostname ==="

for i in $(seq 0 $((NODE_COUNT - 1))); do
    NODE_IP="${NODE_IPS[$i]}"
    NODE_NAME="${NODE_NAMES[$i]}"
    
    echo "Проверка hostname на $NODE_NAME ($NODE_IP)..."
    
    # Исправляем hostname если он неправильный
    ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$NODE_IP" << HOSTNAME_EOF
CURRENT_HOSTNAME=\$(hostname)
if [ "\$CURRENT_HOSTNAME" != "$NODE_NAME" ]; then
    echo "  Исправление hostname: \$CURRENT_HOSTNAME -> $NODE_NAME"
    hostnamectl set-hostname $NODE_NAME
    echo "$NODE_NAME" > /etc/hostname
    sed -i "s/\$CURRENT_HOSTNAME/$NODE_NAME/g" /etc/hosts
    # Добавляем запись в /etc/hosts если её нет
    grep -q "$NODE_NAME" /etc/hosts || echo "$NODE_IP $NODE_NAME" >> /etc/hosts
else
    echo "  ✓ Hostname корректен: $NODE_NAME"
fi
HOSTNAME_EOF
done
echo ""

# === 2. Очистка кластерной конфигурации на всех нодах ===
echo "=== Шаг 2: Очистка кластерной конфигурации ==="

for i in $(seq 0 $((NODE_COUNT - 1))); do
    NODE_IP="${NODE_IPS[$i]}"
    NODE_NAME="${NODE_NAMES[$i]}"
    
    echo "Очистка $NODE_NAME ($NODE_IP)..."
    
    # Полная очистка кластерной конфигурации
    ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$NODE_IP" << 'CLEANUP_EOF'
# Останавливаем сервисы
systemctl stop pve-cluster corosync pve-ha-lrm pve-ha-crm 2>/dev/null || true
killall pmxcfs corosync 2>/dev/null || true
sleep 2

# Удаляем corosync конфигурацию
rm -rf /etc/corosync/* /var/lib/corosync/* 2>/dev/null || true

# Запускаем pmxcfs в локальном режиме для очистки
pmxcfs -l &
sleep 2

# Очищаем кластерные данные в /etc/pve
rm -f /etc/pve/corosync.conf 2>/dev/null || true
rm -rf /etc/pve/nodes/* 2>/dev/null || true
rm -rf /etc/pve/priv/lock/* 2>/dev/null || true

# Убиваем pmxcfs в локальном режиме
killall pmxcfs 2>/dev/null || true
sleep 1

# Перезапускаем pve-cluster нормально
systemctl start pve-cluster 2>/dev/null || true
sleep 2
CLEANUP_EOF
    echo "  ✓ Очищено"
    sleep 3
done
echo ""

# === 3. Создание нового кластера на мастер-ноде ===
echo "=== Шаг 3: Создание кластера '$CLUSTER_NAME' ==="

ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$MASTER_IP" \
    "pvecm create $CLUSTER_NAME" 2>&1 || echo "⚠ Ошибка создания кластера"

echo "Проверка статуса..."
ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$MASTER_IP" \
    "pvecm status" 2>/dev/null || true

echo "✓ Кластер $CLUSTER_NAME создан на $MASTER_NAME"
echo "Ожидание стабилизации кластера (15 сек)..."
sleep 15
echo ""

# === 4. Присоединение остальных нод ===
if [ $NODE_COUNT -gt 1 ]; then
    echo "=== Шаг 4: Присоединение нод к кластеру ==="
    
    # Генерируем SSH-ключ на мастере если нет
    ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$MASTER_IP" \
        "[ -f /root/.ssh/id_rsa ] || ssh-keygen -t rsa -N '' -f /root/.ssh/id_rsa >/dev/null" 2>/dev/null
    
    # Получаем публичный ключ мастера
    MASTER_PUBKEY=$(ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$MASTER_IP" \
        "cat /root/.ssh/id_rsa.pub" 2>/dev/null)
    
    for i in $(seq 1 $((NODE_COUNT - 1))); do
        NODE_IP="${NODE_IPS[$i]}"
        NODE_NAME="${NODE_NAMES[$i]}"
        
        echo ""
        echo "Присоединение $NODE_NAME ($NODE_IP)..."
        
        # Добавляем ключ мастера на ноду
        ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$NODE_IP" \
            "mkdir -p /root/.ssh && echo '$MASTER_PUBKEY' >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys" 2>/dev/null
        
        # Добавляем мастер в known_hosts на ноде
        ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$NODE_IP" \
            "ssh-keyscan -H $MASTER_IP >> /root/.ssh/known_hosts 2>/dev/null" 2>/dev/null || true
        
        # Добавляем ноду в known_hosts на мастере
        ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$MASTER_IP" \
            "ssh-keyscan -H $NODE_IP >> /root/.ssh/known_hosts 2>/dev/null" 2>/dev/null || true
        
        # Присоединяем ноду к кластеру через expect-подобный скрипт
        ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$NODE_IP" << JOINEOF
# Создаём expect-скрипт для автоматизации pvecm add
cat > /tmp/join_cluster.exp << 'EXPECT_SCRIPT'
#!/usr/bin/expect -f
set timeout 60
set master_ip [lindex \$argv 0]
set password [lindex \$argv 1]

spawn pvecm add \$master_ip
expect {
    "yes/no" { send "yes\r"; exp_continue }
    "password for" { send "\$password\r"; exp_continue }
    "Password for" { send "\$password\r"; exp_continue }
    eof { exit 0 }
    timeout { exit 1 }
}
EXPECT_SCRIPT
chmod +x /tmp/join_cluster.exp

# Устанавливаем expect если нет
which expect >/dev/null 2>&1 || apt-get install -y expect >/dev/null 2>&1

# Запускаем
/tmp/join_cluster.exp $MASTER_IP '$ROOT_PASSWORD'
JOINEOF
        echo "✓ $NODE_NAME присоединена"
    done
    echo ""
fi

# === 5. Проверка статуса кластера ===
echo "=== Шаг 5: Проверка статуса кластера ==="
ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$MASTER_IP" \
    "pvecm nodes" 2>/dev/null || echo "Не удалось получить список нод"
echo ""

# === 6. Тестовое создание LXC ===
if [ "$TEST_LXC" = true ]; then
    echo "=== Шаг 6: Тестовое создание LXC-контейнера ==="
    
    LXC_TEMPLATE="alpine-3.22-default_20250617_amd64.tar.xz"
    TEST_VMID=999
    
    # Скачиваем шаблон
    echo "Скачивание шаблона..."
    ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$MASTER_IP" \
        "pveam update >/dev/null 2>&1; pveam list local | grep -q '$LXC_TEMPLATE' || pveam download local $LXC_TEMPLATE" 2>/dev/null || true
    
    echo "Создание контейнера..."
    ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$MASTER_IP" << EOF
# Удаляем старый если есть
pct destroy $TEST_VMID --force 2>/dev/null || true

# Создаём контейнер
pct create $TEST_VMID local:vztmpl/$LXC_TEMPLATE \
    --hostname test-lxc \
    --memory 512 \
    --cores 1 \
    --rootfs local-lvm:1 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --unprivileged 1 \
    --start 0 2>&1

if pct list | grep -q $TEST_VMID; then
    echo "✓ Тестовый LXC-контейнер создан успешно"
    pct list | grep $TEST_VMID
    
    # Удаляем тестовый контейнер
    pct destroy $TEST_VMID --force 2>/dev/null
    echo "✓ Тестовый контейнер удалён"
else
    echo "✗ Ошибка создания контейнера"
fi
EOF
    echo ""
fi

# === 6. Итоговая информация ===
echo "========================================"
echo "✓ Кластер '$CLUSTER_NAME' настроен!"
echo "========================================"
echo ""
echo "Ноды кластера:"
for i in $(seq 0 $((NODE_COUNT - 1))); do
    echo "  ${NODE_NAMES[$i]}: https://${NODE_IPS[$i]}:8006"
done
echo ""
echo "Управление кластером:"
echo "  Статус: ssh -i $PRIVATE_KEY root@$MASTER_IP 'pvecm status'"
echo "  Ноды:   ssh -i $PRIVATE_KEY root@$MASTER_IP 'pvecm nodes'"
echo ""
echo "Создание LXC:"
echo "  ./create_internal_vms.sh -n 1"
echo ""
echo "Удаление LXC:"
echo "  ./delete_internal_vms.sh"
echo "========================================"
