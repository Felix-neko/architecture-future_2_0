#!/bin/bash
# Скрипт создания одной ноды Proxmox VE
# Использование: VM_NAME=pve-node-01 ./create_proxmox_node.sh
# Требования: nested virtualization, минимум 4GB RAM, 32GB диск

set -e

BASEDIR=$(cd "$(dirname "$0")" && pwd)

# VM_NAME из переменной среды или значение по умолчанию
VM_NAME="${VM_NAME:-pve-node}"
VM_DISK="$BASEDIR/${VM_NAME}.qcow2"
BASE_IMAGE="$BASEDIR/ubuntu-24.04-server-cloudimg-amd64.img"
SEED_DIR="$BASEDIR/cloud-init-proxmox"
SEED_ISO="$BASEDIR/${VM_NAME}-seed.iso"
DISK_SIZE="50G"
RAM_MB=4096
VCPUS=2

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
rm -f "$VM_DISK" "$SEED_ISO"

# === 3. Скачивание Ubuntu cloud-образа (если нет) ===
if [ ! -f "$BASE_IMAGE" ]; then
  echo "Скачивание Ubuntu 24.04 Cloud Image..."
  wget -O "$BASE_IMAGE" https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img
fi

# === 4. Подготовка cloud-init ===
echo "Подготовка cloud-init..."
mkdir -p "$SEED_DIR"

cat > "$SEED_DIR/meta-data" <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

# Ubuntu cloud image работает с DHCP по умолчанию
rm -f "$SEED_DIR/network-config"

# Скрипт установки Proxmox VE на Debian 12
cat > "$SEED_DIR/user-data" <<EOF
#cloud-config
hostname: $VM_NAME
manage_etc_hosts: true
locale: en_US.UTF-8
timezone: Europe/Moscow

ssh_pwauth: false
disable_root: false

users:
  - name: root
    lock_passwd: true
    ssh_authorized_keys:
      - $SSH_PUBKEY

write_files:
  - path: /root/install_proxmox.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -e
      
      # Установка Proxmox VE на Ubuntu (неофициально, но работает)
      export DEBIAN_FRONTEND=noninteractive
      
      # Настройка hostname и /etc/hosts
      HOSTNAME=\$(hostname)
      IP=\$(hostname -I | awk '{print \$1}')
      echo "\$IP \$HOSTNAME.local \$HOSTNAME" >> /etc/hosts
      
      # Добавление репозитория Proxmox VE (используем bookworm, т.к. Ubuntu 24.04 основан на похожих пакетах)
      echo "deb [arch=amd64] http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list
      
      # Импорт GPG-ключа Proxmox
      wget -qO- https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg | gpg --dearmor > /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg
      
      # Установка зависимостей
      apt-get update
      apt-get install -y ifupdown2 || apt-get install -y ifupdown
      
      # Попытка установки Proxmox VE
      apt-get install -y proxmox-ve postfix open-iscsi chrony 2>/dev/null || {
        echo "Proxmox VE не удалось установить на Ubuntu"
        echo "Устанавливаем альтернативу: Cockpit + libvirt"
        apt-get install -y cockpit cockpit-machines qemu-kvm libvirt-daemon-system virtinst
        systemctl enable --now cockpit.socket
      }
      
      # Удаление enterprise-репозитория
      rm -f /etc/apt/sources.list.d/pve-enterprise.list 2>/dev/null || true
      
      touch /root/.proxmox_installed
      echo "Установка завершена!"

runcmd:
  - sed -i 's/^#PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
  - mkdir -p /etc/ssh/sshd_config.d
  - echo 'PermitRootLogin prohibit-password' > /etc/ssh/sshd_config.d/99-root-login.conf
  - systemctl restart ssh
  - /root/install_proxmox.sh
EOF

# Создание ISO с cloud-init (NoCloud)
echo "Создание seed ISO..."
# Добавляем network-config только если он существует
if [ -f "$SEED_DIR/network-config" ]; then
  genisoimage -output "$SEED_ISO" -volid cidata -joliet -rock \
    "$SEED_DIR"/user-data "$SEED_DIR"/meta-data "$SEED_DIR"/network-config
else
  genisoimage -output "$SEED_ISO" -volid cidata -joliet -rock \
    "$SEED_DIR"/user-data "$SEED_DIR"/meta-data
fi

# === 5. Создание диска ВМ из cloud-образа ===
echo "Создание диска ВМ из cloud-образа..."
cp "$BASE_IMAGE" "$VM_DISK"
qemu-img resize "$VM_DISK" "$DISK_SIZE"

# === 6. Создание ВМ с nested virtualization ===
echo "Создание и запуск ВМ $VM_NAME..."
virt-install \
  --name "$VM_NAME" \
  --memory "$RAM_MB" \
  --vcpus "$VCPUS" \
  --cpu host-passthrough \
  --disk path="$VM_DISK",format=qcow2 \
  --disk path="$SEED_ISO",device=cdrom \
  --os-variant debian12 \
  --network network=default,model=virtio \
  --graphics none \
  --import \
  --noautoconsole

echo "ВМ запущена. Ожидание готовности..."

# === 7. Ожидание готовности ВМ и SSH ===
MAX_WAIT=300
WAIT_INTERVAL=5
ELAPSED=0
VM_IP=""

# Получаем MAC-адрес ВМ
VM_MAC=$(virsh domiflist "$VM_NAME" 2>/dev/null | grep -oE '([0-9a-f]{2}:){5}[0-9a-f]{2}' | head -1 || true)
echo "MAC-адрес ВМ: $VM_MAC"

echo "Ожидание получения IP-адреса..."
while [ $ELAPSED -lt $MAX_WAIT ]; do
  # Пробуем virsh domifaddr (работает с qemu-guest-agent)
  VM_IP=$(virsh domifaddr "$VM_NAME" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)
  
  # Если не получилось, пробуем через DHCP-аренды по MAC
  if [ -z "$VM_IP" ] && [ -n "$VM_MAC" ]; then
    VM_IP=$(virsh net-dhcp-leases default 2>/dev/null | grep -i "$VM_MAC" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)
  fi
  
  if [ -n "$VM_IP" ]; then
    echo "✓ ВМ получила IP-адрес: $VM_IP (через $ELAPSED сек)"
    break
  fi
  echo "Ожидание IP-адреса... ($ELAPSED/$MAX_WAIT сек)"
  sleep $WAIT_INTERVAL
  ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done

if [ -z "$VM_IP" ]; then
  echo "✗ ВМ не получила IP-адрес за $MAX_WAIT секунд"
  exit 1
fi

# === 8. Ожидание SSH-подключения ===
echo "Ожидание готовности SSH для root@$VM_IP..."
SSH_CONNECTED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
  if nc -z -w 2 "$VM_IP" 22 2>/dev/null; then
    if ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes root@"$VM_IP" "exit 0" 2>/dev/null; then
      echo "✓ SSH-подключение к root@$VM_IP работает! (через $ELAPSED сек)"
      SSH_CONNECTED=1
      break
    fi
  fi
  echo "Ожидание SSH... ($ELAPSED/$MAX_WAIT сек)"
  sleep $WAIT_INTERVAL
  ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done

if [ $SSH_CONNECTED -eq 0 ]; then
  echo "✗ Не удалось подключиться по SSH к root@$VM_IP за $MAX_WAIT секунд"
  exit 1
fi

# === 9. Ожидание установки Proxmox VE ===
echo ""
echo "Запуск установки Proxmox VE (это займёт 10-20 минут)..."
echo "Можно следить за прогрессом: ssh -i $PRIVATE_KEY root@$VM_IP 'tail -f /var/log/cloud-init-output.log'"
echo ""

MAX_PVE_WAIT=1800  # 30 минут на установку
PVE_ELAPSED=0

while [ $PVE_ELAPSED -lt $MAX_PVE_WAIT ]; do
  # Проверяем, установлен ли Proxmox VE
  if ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes root@"$VM_IP" "test -f /root/.proxmox_installed && pveversion" 2>/dev/null; then
    echo "✓ Proxmox VE установлен!"
    break
  fi
  
  # Проверяем, идёт ли ещё установка
  if ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes root@"$VM_IP" "pgrep -f 'apt|dpkg|cloud-init'" 2>/dev/null; then
    echo "Установка Proxmox VE продолжается... ($PVE_ELAPSED/$MAX_PVE_WAIT сек)"
  else
    echo "Ожидание... ($PVE_ELAPSED/$MAX_PVE_WAIT сек)"
  fi
  
  sleep 30
  PVE_ELAPSED=$((PVE_ELAPSED + 30))
done

# Финальная проверка
echo ""
echo "Проверка Proxmox VE..."
if ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@"$VM_IP" "pveversion" 2>/dev/null; then
  PVE_VERSION=$(ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$VM_IP" "pveversion 2>/dev/null" 2>/dev/null)
  echo ""
  echo "========================================"
  echo "✓ Proxmox VE нода готова!"
  echo "========================================"
  echo "  Версия: $PVE_VERSION"
  echo "  SSH: ssh -i $PRIVATE_KEY root@$VM_IP"
  echo "  Web UI: https://$VM_IP:8006"
  echo "========================================"
else
  echo "✗ Proxmox VE не установлен или не запущен"
  echo "Проверьте логи: ssh -i $PRIVATE_KEY root@$VM_IP 'cat /var/log/cloud-init-output.log'"
  exit 1
fi
