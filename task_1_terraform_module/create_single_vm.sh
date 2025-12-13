#!/bin/bash
set -e

# === Базовые переменные ===
BASEDIR=$(cd "$(dirname "$0")" && pwd)
VM_NAME="ubuntu-vm-01"
VM_DISK="$BASEDIR/${VM_NAME}.qcow2"
BASE_IMAGE="$BASEDIR/ubuntu-24.04-server-cloudimg-amd64.img"
SEED_DIR="$BASEDIR/cloud-init"
SEED_ISO="$BASEDIR/${VM_NAME}-seed.iso"
DISK_SIZE="30G"

# === 0. SSH-ключи для доступа к ВМ ===
KEY_NAME="vm_access_key"
PRIVATE_KEY="$BASEDIR/$KEY_NAME"
PUBLIC_KEY="$BASEDIR/${KEY_NAME}.pub"

# Генерация SSH-ключей, если их нет
if [ ! -f "$PRIVATE_KEY" ] || [ ! -f "$PUBLIC_KEY" ]; then
  echo "Генерация SSH-ключей для доступа к ВМ..."
  ssh-keygen -t ed25519 -f "$PRIVATE_KEY" -N "" -C "vm-access-key"
  chmod 600 "$PRIVATE_KEY"
  chmod 644 "$PUBLIC_KEY"
  echo "✓ SSH-ключи сгенерированы: $PRIVATE_KEY, $PUBLIC_KEY"
else
  echo "Используются существующие SSH-ключи: $PRIVATE_KEY"
fi

SSH_PUBKEY=$(cat "$PUBLIC_KEY")

# === 1. Сеть libvirt ===
virsh net-start default 2>/dev/null || true
virsh net-autostart default 2>/dev/null || true

# === 2. Удаление старой ВМ и дисков ===
echo "Удаление старой ВМ (если была)..."
virsh destroy "$VM_NAME" 2>/dev/null || true
virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
rm -f "$VM_DISK" "$SEED_ISO"

# === 3. Скачивание cloud-образа Ubuntu (если нет) ===
if [ ! -f "$BASE_IMAGE" ]; then
  echo "Скачивание Ubuntu Cloud Image..."
  wget -O "$BASE_IMAGE" https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img
fi

# === 4. Подготовка cloud-init ===
echo "Подготовка cloud-init..."
mkdir -p "$SEED_DIR"

cat > "$SEED_DIR/meta-data" <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

cat > "$SEED_DIR/user-data" <<EOF
#cloud-config
hostname: $VM_NAME
manage_etc_hosts: true
locale: ru_RU.UTF-8
timezone: Europe/Moscow

# Отключаем парольную аутентификацию, только SSH-ключи
ssh_pwauth: false
disable_root: false

users:
  - name: root
    lock_passwd: true
    ssh_authorized_keys:
      - $SSH_PUBKEY

runcmd:
  - sed -i 's/^#PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
  - sed -i 's/^PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
  - mkdir -p /etc/ssh/sshd_config.d
  - echo 'PermitRootLogin prohibit-password' > /etc/ssh/sshd_config.d/99-root-login.conf
  - echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config.d/99-root-login.conf
  - systemctl restart ssh
EOF

# Создание ISO с cloud-init (NoCloud)
echo "Создание seed ISO..."
genisoimage -output "$SEED_ISO" -volid cidata -joliet -rock \
  "$SEED_DIR"/user-data "$SEED_DIR"/meta-data

# === 5. Создание диска ВМ из cloud-образа ===
echo "Создание диска ВМ из cloud-образа..."
cp "$BASE_IMAGE" "$VM_DISK"
qemu-img resize "$VM_DISK" "$DISK_SIZE"

# === 6. Создание ВМ ===
echo "Создание и запуск ВМ $VM_NAME..."
virt-install \
  --name "$VM_NAME" \
  --memory 4096 \
  --vcpus 2 \
  --disk path="$VM_DISK",format=qcow2 \
  --disk path="$SEED_ISO",device=cdrom \
  --os-variant ubuntu24.04 \
  --network network=default,model=virtio \
  --graphics none \
  --import \
  --noautoconsole

echo "Установка запущена. Ожидание готовности ВМ..."

# === 7. Ожидание готовности ВМ и SSH ===
MAX_WAIT=300  # 5 минут максимум (cloud-init быстрее, чем установка)
WAIT_INTERVAL=5
ELAPSED=0
VM_IP=""

# Ожидание получения IP-адреса
echo "Ожидание получения IP-адреса..."
while [ $ELAPSED -lt $MAX_WAIT ]; do
  VM_IP=$(virsh domifaddr "$VM_NAME" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)
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

# === 8. Ожидание реального SSH-подключения к root по ключу ===
echo "Ожидание готовности SSH для root@$VM_IP (cloud-init обычно занимает 1-2 минуты)..."
SSH_CONNECTED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
  # Сначала проверяем, что порт открыт
  if nc -z -w 2 "$VM_IP" 22 2>/dev/null; then
    # Пробуем SSH-подключение по ключу
    if ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes root@"$VM_IP" "exit 0" 2>/dev/null; then
      echo "✓ SSH-подключение к root@$VM_IP работает! (через $ELAPSED сек)"
      SSH_CONNECTED=1
      break
    else
      echo "SSH-порт открыт, но root ещё не готов (cloud-init продолжается)... ($ELAPSED/$MAX_WAIT сек)"
    fi
  else
    echo "Ожидание SSH-порта... ($ELAPSED/$MAX_WAIT сек)"
  fi
  sleep $WAIT_INTERVAL
  ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done

if [ $SSH_CONNECTED -eq 0 ]; then
  echo "✗ Не удалось подключиться по SSH к root@$VM_IP за $MAX_WAIT секунд"
  exit 1
fi

# Финальная проверка с выводом
echo ""
echo "Проверка SSH-подключения к root@$VM_IP..."
if ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@"$VM_IP" "echo 'SSH-подключение успешно! Hostname:' && hostname"; then
  echo ""
  echo "✓ ВМ готова к работе!"
  echo "Для подключения используйте:"
  echo "  ssh -i $PRIVATE_KEY root@$VM_IP"
else
  echo "✗ Финальная проверка SSH не прошла"
  exit 1
fi
