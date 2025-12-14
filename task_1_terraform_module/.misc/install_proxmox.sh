#!/bin/bash
# Скрипт установки Proxmox VE 9.1 из ISO
# Использование: ./install_proxmox.sh
#
# Параметры (через переменные окружения):
#   VM_NAME       - имя виртуалки (по умолчанию: pve-node)
#   VM_CPUS       - количество ядер CPU (по умолчанию: 4)
#   VM_RAM_MB     - объём памяти в МБ (по умолчанию: 16384 = 16GB)
#   VM_DISK_GB    - объём диска в ГБ (по умолчанию: 40)
#   ROOT_PASSWORD - пароль root (по умолчанию: mega_root_password)
#
# Пример: VM_NAME=my-pve VM_CPUS=2 ROOT_PASSWORD=mypass ./install_proxmox.sh

set -e

BASEDIR=$(cd "$(dirname "$0")" && pwd)

# === Параметры с значениями по умолчанию ===
VM_NAME="${VM_NAME:-pve-node}"
VM_CPUS="${VM_CPUS:-4}"
VM_RAM_MB="${VM_RAM_MB:-16384}"
VM_DISK_GB="${VM_DISK_GB:-40}"
ROOT_PASSWORD="${ROOT_PASSWORD:-mega_root_password}"

# Пути к файлам
VM_DISK="$BASEDIR/${VM_NAME}.qcow2"
PVE_ISO="$BASEDIR/proxmox-ve_9.1-1.iso"

echo "========================================"
echo "Установка Proxmox VE 9.1"
echo "========================================"
echo "Параметры:"
echo "  Имя ВМ:        $VM_NAME"
echo "  CPU:           $VM_CPUS ядер"
echo "  RAM:           $((VM_RAM_MB / 1024)) GB"
echo "  Диск:          ${VM_DISK_GB} GB"
echo "  Root пароль:   $ROOT_PASSWORD"
echo "========================================"
echo ""

# === 1. Сеть libvirt ===
virsh net-start default 2>/dev/null || true
virsh net-autostart default 2>/dev/null || true

# === 2. Удаление старой ВМ (если была) ===
echo "Удаление старой ВМ (если была)..."
virsh destroy "$VM_NAME" 2>/dev/null || true
virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
rm -f "$VM_DISK"

# === 3. Скачивание Proxmox VE ISO (если нет) ===
if [ ! -f "$PVE_ISO" ]; then
  echo "Скачивание Proxmox VE 9.1 ISO (около 1.7GB)..."
  wget -O "$PVE_ISO" "https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso"
fi

# === 4. Создание диска ВМ ===
echo "Создание диска ВМ (${VM_DISK_GB}GB)..."
qemu-img create -f qcow2 "$VM_DISK" "${VM_DISK_GB}G"

# === 5. Создание и запуск ВМ ===
echo "Создание и запуск ВМ $VM_NAME..."
virt-install \
  --name "$VM_NAME" \
  --memory "$VM_RAM_MB" \
  --vcpus "$VM_CPUS" \
  --cpu host-passthrough \
  --disk path="$VM_DISK",format=qcow2,bus=virtio \
  --cdrom "$PVE_ISO" \
  --os-variant debian12 \
  --network network=default,model=virtio \
  --graphics vnc,listen=0.0.0.0 \
  --boot cdrom,hd \
  --noautoconsole

echo ""
echo "========================================"
echo "ВМ запущена!"
echo "========================================"
echo ""
echo "Открывается консоль для установки Proxmox VE..."
echo ""
echo "При установке используйте:"
echo "  - Country: Russia"
echo "  - Timezone: Europe/Moscow"
echo "  - Password: $ROOT_PASSWORD"
echo "  - Email: admin@localhost"
echo "  - Hostname: ${VM_NAME}.local"
echo "  - Сеть: DHCP"
echo ""
echo "После завершения установки ВМ перезагрузится."
echo "Скрипт автоматически дождётся завершения..."
echo "========================================"
echo ""

# Запуск virt-viewer в фоне
virt-viewer "$VM_NAME" &
VIEWER_PID=$!

# === 6. Ожидание получения IP и готовности SSH ===
MAX_WAIT=1800  # 30 минут на установку
WAIT_INTERVAL=15
ELAPSED=0
VM_IP=""

# Получаем MAC-адрес ВМ
VM_MAC=$(virsh domiflist "$VM_NAME" 2>/dev/null | grep -oE '([0-9a-f]{2}:){5}[0-9a-f]{2}' | head -1 || true)
echo "MAC-адрес ВМ: $VM_MAC"

while [ $ELAPSED -lt $MAX_WAIT ]; do
  # Проверяем, работает ли ВМ
  VM_STATE=$(virsh domstate "$VM_NAME" 2>/dev/null || echo "unknown")
  
  # Пробуем получить IP через virsh domifaddr
  VM_IP=$(virsh domifaddr "$VM_NAME" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)
  
  # Если не получилось, пробуем через DHCP-аренды по MAC
  if [ -z "$VM_IP" ] && [ -n "$VM_MAC" ]; then
    VM_IP=$(virsh net-dhcp-leases default 2>/dev/null | grep -i "$VM_MAC" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)
  fi
  
  if [ -n "$VM_IP" ]; then
    # Проверяем, доступен ли SSH
    if nc -z -w 2 "$VM_IP" 22 2>/dev/null; then
      # Пробуем подключиться по SSH
      if sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 root@"$VM_IP" "pveversion" 2>/dev/null; then
        echo ""
        echo "========================================"
        echo "✓ Proxmox VE успешно установлен!"
        echo "========================================"
        break
      else
        echo "IP: $VM_IP, SSH открыт, но Proxmox ещё не готов... ($ELAPSED/$MAX_WAIT сек)"
      fi
    else
      echo "IP: $VM_IP, ожидание SSH... ($ELAPSED/$MAX_WAIT сек)"
    fi
  else
    echo "Установка продолжается (состояние: $VM_STATE)... ($ELAPSED/$MAX_WAIT сек)"
  fi
  
  sleep $WAIT_INTERVAL
  ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done

# === 7. Финальная проверка и вывод информации ===
if [ -z "$VM_IP" ]; then
  echo ""
  echo "✗ Не удалось получить IP-адрес ВМ за $MAX_WAIT секунд"
  echo "Проверьте консоль ВМ: virt-viewer $VM_NAME"
  exit 1
fi

# Проверка SSH с sshpass
echo ""
echo "Проверка SSH-подключения..."
if sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$VM_IP" "pveversion" 2>/dev/null; then
  PVE_VERSION=$(sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$VM_IP" "pveversion" 2>/dev/null)
  
  echo ""
  echo "========================================"
  echo "✓ Proxmox VE готов к работе!"
  echo "========================================"
  echo ""
  echo "Версия:     $PVE_VERSION"
  echo "IP-адрес:   $VM_IP"
  echo ""
  echo "Веб-интерфейс:"
  echo "  URL:      https://$VM_IP:8006"
  echo "  Логин:    root"
  echo "  Пароль:   $ROOT_PASSWORD"
  echo ""
  echo "SSH-подключение:"
  echo "  sshpass -p '$ROOT_PASSWORD' ssh root@$VM_IP"
  echo ""
  echo "Или без sshpass (введите пароль вручную):"
  echo "  ssh root@$VM_IP"
  echo "========================================"
else
  echo ""
  echo "✗ Не удалось подключиться по SSH"
  echo "IP-адрес: $VM_IP"
  echo "Проверьте консоль ВМ: virt-viewer $VM_NAME"
  exit 1
fi
