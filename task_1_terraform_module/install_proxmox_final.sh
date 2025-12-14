#!/bin/bash
# Скрипт автоматической установки Proxmox VE на libvirt VM
# Использует Ubuntu cloud image + Debian chroot с Proxmox
#
# Использование: ./install_proxmox_final.sh
# Переменные окружения:
#   VM_NAME        - имя виртуалки (по умолчанию: pve-auto)
#   VM_VCPUS       - количество ядер CPU (по умолчанию: 4)
#   VM_RAM_MB      - объём памяти в MB (по умолчанию: 16384)
#   VM_DISK_SIZE   - объём диска (по умолчанию: 40G)
#   ROOT_PASSWORD  - пароль root (по умолчанию: mega_root_password)

set -e

BASEDIR=$(cd "$(dirname "$0")" && pwd)

# === Параметры ===
VM_NAME="${VM_NAME:-pve-auto}"
VM_VCPUS="${VM_VCPUS:-4}"
VM_RAM_MB="${VM_RAM_MB:-16384}"
VM_DISK_SIZE="${VM_DISK_SIZE:-40G}"
ROOT_PASSWORD="${ROOT_PASSWORD:-mega_root_password}"

# === Пути ===
VM_DISK="$BASEDIR/${VM_NAME}.qcow2"
UBUNTU_IMAGE="$BASEDIR/ubuntu-24.04-server-cloudimg-amd64.img"
UBUNTU_IMAGE_URL="https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
SEED_DIR="$BASEDIR/cloud-init-${VM_NAME}"
SEED_ISO="$BASEDIR/${VM_NAME}-seed.iso"
KEY_NAME="vm_access_key"
PRIVATE_KEY="$BASEDIR/$KEY_NAME"
PUBLIC_KEY="$BASEDIR/${KEY_NAME}.pub"

echo "========================================"
echo "Установка Proxmox VE на libvirt VM"
echo "========================================"
echo "  VM:       $VM_NAME"
echo "  vCPUs:    $VM_VCPUS"
echo "  RAM:      $VM_RAM_MB MB"
echo "  Disk:     $VM_DISK_SIZE"
echo "  Password: $ROOT_PASSWORD"
echo "========================================"

# === 1. Генерация SSH-ключей ===
if [ ! -f "$PRIVATE_KEY" ]; then
    echo "Генерация SSH-ключей..."
    ssh-keygen -t ed25519 -f "$PRIVATE_KEY" -N "" -C "vm-access-key"
fi
SSH_PUBKEY=$(cat "$PUBLIC_KEY")

# === 2. Подготовка libvirt ===
echo "Настройка libvirt..."
virsh net-start default 2>/dev/null || true
virsh net-autostart default 2>/dev/null || true

# === 3. Удаление старой VM ===
echo "Удаление старой VM (если была)..."
virsh destroy "$VM_NAME" 2>/dev/null || true
virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
rm -f "$VM_DISK" "$SEED_ISO"
rm -rf "$SEED_DIR"

# === 4. Скачивание Ubuntu cloud image ===
if [ ! -f "$UBUNTU_IMAGE" ]; then
    echo "Скачивание Ubuntu 24.04 cloud image..."
    wget -O "$UBUNTU_IMAGE" "$UBUNTU_IMAGE_URL"
fi

# === 5. Создание cloud-init ===
echo "Создание cloud-init конфигурации..."
mkdir -p "$SEED_DIR"

cat > "$SEED_DIR/meta-data" << EOF
instance-id: ${VM_NAME}
local-hostname: ${VM_NAME}
EOF

cat > "$SEED_DIR/user-data" << EOF
#cloud-config
hostname: ${VM_NAME}
fqdn: ${VM_NAME}.local
manage_etc_hosts: true

users:
  - name: root
    lock_passwd: false
    ssh_authorized_keys:
      - $SSH_PUBKEY

ssh_pwauth: false

runcmd:
  - sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
  - systemctl restart ssh
EOF

genisoimage -output "$SEED_ISO" -volid cidata -joliet -rock \
    "$SEED_DIR/user-data" "$SEED_DIR/meta-data" 2>/dev/null

# === 6. Создание диска VM ===
echo "Создание диска VM..."
cp "$UBUNTU_IMAGE" "$VM_DISK"
qemu-img resize "$VM_DISK" "$VM_DISK_SIZE"

# === 7. Запуск VM ===
echo "Запуск VM $VM_NAME..."
virt-install \
    --name "$VM_NAME" \
    --memory "$VM_RAM_MB" \
    --vcpus "$VM_VCPUS" \
    --cpu host-passthrough \
    --disk "path=$VM_DISK,format=qcow2" \
    --disk "path=$SEED_ISO,device=cdrom" \
    --os-variant ubuntu24.04 \
    --network network=default,model=virtio \
    --graphics none \
    --import \
    --noautoconsole

echo "✓ VM запущена"

# === 8. Получение IP-адреса ===
VM_MAC=$(virsh domiflist "$VM_NAME" 2>/dev/null | grep -oE '([0-9a-f]{2}:){5}[0-9a-f]{2}' | head -1)
echo "MAC: $VM_MAC"

get_ip() {
    virsh net-dhcp-leases default 2>/dev/null | grep -i "$VM_MAC" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true
}

echo "Ожидание IP-адреса..."
MAX_WAIT=120
ELAPSED=0
VM_IP=""

while [ $ELAPSED -lt $MAX_WAIT ]; do
    VM_IP=$(get_ip)
    if [ -n "$VM_IP" ]; then
        echo "✓ IP: $VM_IP"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo "[$ELAPSED сек] Ожидание IP..."
done

if [ -z "$VM_IP" ]; then
    echo "✗ VM не получила IP за $MAX_WAIT секунд"
    exit 1
fi

# === 9. Ожидание SSH ===
echo "Ожидание SSH..."
for i in {1..24}; do
    if ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 root@"$VM_IP" "exit 0" 2>/dev/null; then
        echo "✓ SSH доступен"
        break
    fi
    echo "[$((i*5)) сек] Ожидание SSH..."
    sleep 5
done

# === 10. Установка Proxmox в Debian chroot ===
echo ""
echo "========================================"
echo "Установка Proxmox VE (5-15 минут)..."
echo "========================================"

ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$VM_IP" << INSTALL_SCRIPT
set -e
export DEBIAN_FRONTEND=noninteractive

# Настройка hostname
HOSTNAME=\$(hostname)
IP=\$(hostname -I | awk '{print \$1}')
grep -q "\$IP \$HOSTNAME" /etc/hosts || echo "\$IP \$HOSTNAME.local \$HOSTNAME" >> /etc/hosts

# Установка debootstrap
apt-get update -qq
apt-get install -y -qq debootstrap schroot >/dev/null

# Создание Debian Bookworm chroot
echo "Создание Debian Bookworm chroot..."
mkdir -p /srv/debian-pve
debootstrap --arch=amd64 bookworm /srv/debian-pve http://deb.debian.org/debian >/dev/null 2>&1

# Монтирование
mount --bind /dev /srv/debian-pve/dev 2>/dev/null || true
mount --bind /dev/pts /srv/debian-pve/dev/pts 2>/dev/null || true
mount --bind /proc /srv/debian-pve/proc 2>/dev/null || true
mount --bind /sys /srv/debian-pve/sys 2>/dev/null || true
cp /etc/resolv.conf /srv/debian-pve/etc/resolv.conf

# Установка Proxmox в chroot
echo "Установка Proxmox VE в chroot..."
chroot /srv/debian-pve /bin/bash << 'CHROOT_SCRIPT'
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq wget ca-certificates gnupg >/dev/null

wget -qO /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg \
    https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg

echo "deb [arch=amd64] http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
    > /etc/apt/sources.list.d/pve.list

apt-get update -qq
apt-get install -y proxmox-ve postfix open-iscsi chrony 2>/dev/null || true
rm -f /etc/apt/sources.list.d/pve-enterprise.list 2>/dev/null || true

echo "Проверка pveversion:"
pveversion 2>/dev/null || echo "pveversion не найден"
CHROOT_SCRIPT
INSTALL_SCRIPT

# === 11. Проверка установки ===
echo ""
echo "========================================"
PVE_VERSION=$(ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$VM_IP" "chroot /srv/debian-pve pveversion 2>/dev/null" 2>/dev/null || echo "не определена")

if [[ "$PVE_VERSION" == *"pve-manager"* ]]; then
    echo "✓ Proxmox VE установлен!"
    echo "========================================"
    echo ""
    echo "Версия: $PVE_VERSION"
    echo ""
    echo "Подключение по SSH:"
    echo "  ssh -i $PRIVATE_KEY root@$VM_IP"
    echo ""
    echo "Проверка Proxmox:"
    echo "  ssh -i $PRIVATE_KEY root@$VM_IP 'chroot /srv/debian-pve pveversion'"
    echo ""
    echo "IP-адрес: $VM_IP"
    echo "========================================"
else
    echo "✗ Proxmox VE не установлен"
    echo "Версия: $PVE_VERSION"
    exit 1
fi
