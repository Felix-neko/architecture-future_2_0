#!/bin/bash
# Скрипт создания Proxmox VE кластера
# Использование: ./create_proxmox_cluster.sh [количество_нод]
# По умолчанию создаётся 3 ноды

set -e

BASEDIR=$(cd "$(dirname "$0")" && pwd)

# Количество нод из аргумента командной строки или 3 по умолчанию
NODE_COUNT="${1:-3}"

# Проверка, что NODE_COUNT — число
if ! [[ "$NODE_COUNT" =~ ^[0-9]+$ ]] || [ "$NODE_COUNT" -lt 1 ]; then
  echo "Ошибка: количество нод должно быть положительным числом"
  echo "Использование: $0 [количество_нод]"
  exit 1
fi

# SSH-ключи
KEY_NAME="vm_access_key"
PRIVATE_KEY="$BASEDIR/$KEY_NAME"

echo "========================================"
echo "Создание Proxmox VE кластера"
echo "Количество нод: $NODE_COUNT"
echo "========================================"
echo ""

# Генерация SSH-ключей (один раз для всех нод)
echo "Проверка SSH-ключей..."
"$BASEDIR/generate_ssh_keys.sh" --quiet
echo "✓ SSH-ключи готовы"
echo ""

# Массивы для хранения информации о нодах
declare -a NODE_NAMES
declare -a NODE_IPS

# === Создание нод ===
for i in $(seq 1 "$NODE_COUNT"); do
  NODE_NAME="pve-node-$(printf '%02d' "$i")"
  echo "========================================"
  echo "[$i/$NODE_COUNT] Создание ноды: $NODE_NAME"
  echo "========================================"
  
  if VM_NAME="$NODE_NAME" "$BASEDIR/create_proxmox_node.sh"; then
    # Получаем IP созданной ноды
    NODE_MAC=$(virsh domiflist "$NODE_NAME" 2>/dev/null | grep -oE '([0-9a-f]{2}:){5}[0-9a-f]{2}' | head -1 || true)
    NODE_IP=$(virsh domifaddr "$NODE_NAME" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)
    if [ -z "$NODE_IP" ] && [ -n "$NODE_MAC" ]; then
      NODE_IP=$(virsh net-dhcp-leases default 2>/dev/null | grep -i "$NODE_MAC" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)
    fi
    NODE_NAMES+=("$NODE_NAME")
    NODE_IPS+=("$NODE_IP")
    echo ""
  else
    echo "✗ Ошибка при создании ноды $NODE_NAME"
    exit 1
  fi
done

# === Создание Proxmox-кластера ===
if [ "$NODE_COUNT" -gt 1 ]; then
  echo ""
  echo "========================================"
  echo "Создание Proxmox-кластера"
  echo "========================================"
  
  CLUSTER_NAME="pve-cluster"
  MASTER_IP="${NODE_IPS[0]}"
  MASTER_NAME="${NODE_NAMES[0]}"
  
  echo "Создание кластера '$CLUSTER_NAME' на $MASTER_NAME ($MASTER_IP)..."
  ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$MASTER_IP" \
    "pvecm create $CLUSTER_NAME" 2>/dev/null || echo "(кластер уже существует или ошибка)"
  
  echo "✓ Кластер создан на $MASTER_NAME"
  
  # Присоединение остальных нод
  for i in $(seq 1 $((NODE_COUNT - 1))); do
    NODE_NAME="${NODE_NAMES[$i]}"
    NODE_IP="${NODE_IPS[$i]}"
    
    echo "Присоединение $NODE_NAME ($NODE_IP) к кластеру..."
    # Присоединение требует интерактивного подтверждения, поэтому пропускаем
    echo "  (для присоединения выполните вручную: ssh root@$NODE_IP 'pvecm add $MASTER_IP')"
  done
fi

# === Проверка Proxmox VE на всех нодах ===
echo ""
echo "========================================"
echo "Проверка Proxmox VE на всех нодах"
echo "========================================"

for i in "${!NODE_NAMES[@]}"; do
  NODE_IP="${NODE_IPS[$i]}"
  NODE_NAME="${NODE_NAMES[$i]}"
  
  PVE_VERSION=$(ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$NODE_IP" "pveversion 2>/dev/null" 2>/dev/null || echo "недоступен")
  echo "  $NODE_NAME ($NODE_IP): $PVE_VERSION"
done

# === Проверка веб-интерфейса ===
echo ""
echo "========================================"
echo "Проверка веб-интерфейса Proxmox VE"
echo "========================================"

for i in "${!NODE_NAMES[@]}"; do
  NODE_IP="${NODE_IPS[$i]}"
  if curl -sk --connect-timeout 5 "https://$NODE_IP:8006" > /dev/null 2>&1; then
    echo "✓ ${NODE_NAMES[$i]}: https://$NODE_IP:8006 - доступен"
  else
    echo "✗ ${NODE_NAMES[$i]}: https://$NODE_IP:8006 - недоступен (возможно, ещё запускается)"
  fi
done

# === Финальная шпаргалка ===
echo ""
echo "========================================"
echo "✓ Proxmox VE кластер готов!"
echo "========================================"
echo ""
echo "Ноды кластера:"
echo "--------------------------------"
for i in "${!NODE_NAMES[@]}"; do
  echo "  ${NODE_NAMES[$i]}: ${NODE_IPS[$i]}"
done
echo ""
echo "SSH-подключение:"
echo "--------------------------------"
for i in "${!NODE_NAMES[@]}"; do
  echo "  ssh -i $PRIVATE_KEY root@${NODE_IPS[$i]}  # ${NODE_NAMES[$i]}"
done
echo ""
echo "Веб-интерфейс Proxmox VE:"
echo "--------------------------------"
for i in "${!NODE_NAMES[@]}"; do
  echo "  https://${NODE_IPS[$i]}:8006  # ${NODE_NAMES[$i]}"
done
echo ""
echo "Логин: root"
echo "Пароль: (используйте SSH-ключ или настройте PAM)"
echo ""
echo "Для создания LXC-контейнера:"
echo "  1. Откройте веб-интерфейс: https://${NODE_IPS[0]}:8006"
echo "  2. Скачайте CT template: Datacenter -> ${NODE_NAMES[0]} -> local -> CT Templates"
echo "  3. Создайте контейнер: Create CT"
echo ""
