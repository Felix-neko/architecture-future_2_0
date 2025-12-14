#!/bin/bash
# Скрипт создания Proxmox VE ноды из официального ISO
# Использование: VM_NAME=pve-node-01 ./create_proxmox_node_iso.sh
# Требования: nested virtualization, минимум 4GB RAM, 32GB диск

set -e

BASEDIR=$(cd "$(dirname "$0")" && pwd)

# VM_NAME из переменной среды или значение по умолчанию
VM_NAME="${VM_NAME:-pve-node}"
VM_DISK="$BASEDIR/${VM_NAME}.qcow2"
PVE_ISO="$BASEDIR/proxmox-ve_9.1-1.iso"
ANSWER_ISO="$BASEDIR/${VM_NAME}-answer.iso"
ANSWER_DIR="$BASEDIR/pve-answer"
DISK_SIZE="50G"
RAM_MB=4096
VCPUS=2

# Пароль root для Proxmox (можно изменить)
ROOT_PASSWORD="proxmox123"

# === 0. SSH-ключи для доступа к ВМ ===
KEY_NAME="vm_access_key"
PRIVATE_KEY="$BASEDIR/$KEY_NAME"
PUBLIC_KEY="$BASEDIR/${KEY_NAME}.pub"

# Генерация SSH-ключей через отдельный скрипт (если их нет)
"$BASEDIR/generate_ssh_keys.sh" --quiet

SSH_PUBKEY=$(cat "$PUBLIC_KEY")

echo "========================================"
echo "Создание Proxmox VE ноды: $VM_NAME"
echo "========================================"

# === 1. Сеть libvirt ===
virsh net-start default 2>/dev/null || true
virsh net-autostart default 2>/dev/null || true

# === 2. Удаление старой ВМ и дисков ===
echo "Удаление старой ВМ (если была)..."
virsh destroy "$VM_NAME" 2>/dev/null || true
virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
rm -f "$VM_DISK" "$ANSWER_ISO"

# === 3. Скачивание Proxmox VE ISO (если нет) ===
if [ ! -f "$PVE_ISO" ]; then
  echo "Скачивание Proxmox VE 9.1 ISO (около 1.7GB)..."
  wget -O "$PVE_ISO" "https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso"
fi

# === 4. Создание answer file для автоматической установки ===
echo "Подготовка answer file для автоустановки..."
mkdir -p "$ANSWER_DIR"

cat > "$ANSWER_DIR/answer.toml" <<EOF
[global]
keyboard = "en-us"
country = "ru"
fqdn = "${VM_NAME}.local"
mailto = "root@localhost"
timezone = "Europe/Moscow"
root_password = "${ROOT_PASSWORD}"

[network]
source = "from-dhcp"

[disk-setup]
filesystem = "ext4"
disk_list = ["sda"]
EOF

# Создание ISO с answer file
echo "Создание answer ISO..."
genisoimage -output "$ANSWER_ISO" -volid INTRD -joliet -rock "$ANSWER_DIR"/answer.toml

# === 5. Создание пустого диска ВМ ===
echo "Создание диска ВМ..."
qemu-img create -f qcow2 "$VM_DISK" "$DISK_SIZE"

# === 6. Создание ВМ с nested virtualization ===
echo "Создание и запуск ВМ $VM_NAME..."
echo ""
echo "⚠ ВНИМАНИЕ: Proxmox VE требует интерактивной установки!"
echo "После запуска ВМ:"
echo "  1. Откройте консоль: virt-viewer $VM_NAME"
echo "  2. Следуйте инструкциям установщика"
echo "  3. После установки ВМ перезагрузится"
echo ""

virt-install \
  --name "$VM_NAME" \
  --memory "$RAM_MB" \
  --vcpus "$VCPUS" \
  --cpu host-passthrough \
  --disk path="$VM_DISK",format=qcow2,bus=sata \
  --cdrom "$PVE_ISO" \
  --os-variant debian12 \
  --network network=default,model=virtio \
  --graphics vnc,listen=0.0.0.0 \
  --noautoconsole \
  --boot cdrom,hd

echo ""
echo "ВМ запущена. Для установки Proxmox VE:"
echo "  1. Откройте консоль: virt-viewer $VM_NAME"
echo "  2. Или подключитесь через VNC"
echo ""
echo "После завершения установки и перезагрузки:"
echo "  - Веб-интерфейс: https://<IP>:8006"
echo "  - Логин: root"
echo "  - Пароль: $ROOT_PASSWORD"
echo ""

# === 7. Ожидание готовности ВМ и SSH ===
echo "Ожидание получения IP-адреса (после установки)..."
MAX_WAIT=1800  # 30 минут на установку
WAIT_INTERVAL=10
ELAPSED=0
VM_IP=""

# Получаем MAC-адрес ВМ
VM_MAC=$(virsh domiflist "$VM_NAME" 2>/dev/null | grep -oE '([0-9a-f]{2}:){5}[0-9a-f]{2}' | head -1 || true)
echo "MAC-адрес ВМ: $VM_MAC"

while [ $ELAPSED -lt $MAX_WAIT ]; do
  # Пробуем virsh domifaddr
  VM_IP=$(virsh domifaddr "$VM_NAME" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)
  
  # Если не получилось, пробуем через DHCP-аренды по MAC
  if [ -z "$VM_IP" ] && [ -n "$VM_MAC" ]; then
    VM_IP=$(virsh net-dhcp-leases default 2>/dev/null | grep -i "$VM_MAC" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)
  fi
  
  if [ -n "$VM_IP" ]; then
    # Проверяем, доступен ли веб-интерфейс Proxmox
    if curl -sk --connect-timeout 5 "https://$VM_IP:8006" > /dev/null 2>&1; then
      echo ""
      echo "========================================"
      echo "✓ Proxmox VE нода готова!"
      echo "========================================"
      echo "  IP: $VM_IP"
      echo "  Web UI: https://$VM_IP:8006"
      echo "  Логин: root"
      echo "  Пароль: $ROOT_PASSWORD"
      echo "========================================"
      exit 0
    else
      echo "IP получен ($VM_IP), ожидание веб-интерфейса... ($ELAPSED/$MAX_WAIT сек)"
    fi
  else
    echo "Ожидание установки... ($ELAPSED/$MAX_WAIT сек) - откройте virt-viewer $VM_NAME для установки"
  fi
  
  sleep $WAIT_INTERVAL
  ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done

echo ""
echo "Установка не завершена автоматически."
echo "Проверьте консоль ВМ: virt-viewer $VM_NAME"
