#!/bin/bash
# Скрипт автоматической установки Proxmox VE из ISO на libvirt VM
#
# Использование: ./install_proxmox_iso.sh
# Переменные окружения:
#   VM_NAME         - имя виртуалки (по умолчанию: pve-auto)
#   VM_VCPUS        - количество ядер CPU (по умолчанию: 4)
#   VM_RAM_MB       - объём памяти в MB (по умолчанию: 16384)
#   VM_DISK_SIZE    - объём диска (по умолчанию: 40G)
#   ROOT_PASSWORD   - пароль root (по умолчанию: mega_root_password)
#   (ISO всегда пересоздаётся с уникальным hostname для каждой VM)

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
PVE_ISO_ORIG="$BASEDIR/proxmox-ve_9.1-1.iso"
PVE_ISO_AUTO="$BASEDIR/proxmox-ve_9.1-1-auto.iso"
PVE_ISO_URL="https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso"
ISO_EXTRACT_DIR="/tmp/pve-iso-extract-$$"
PRIVATE_KEY="$BASEDIR/vm_access_key"
PUBLIC_KEY="$BASEDIR/vm_access_key.pub"
TEMPLATES_DIR="$BASEDIR/pve-auto-install-templates"

echo "========================================"
echo "Установка Proxmox VE 9.1 из ISO"
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
    "$BASEDIR/generate_ssh_keys.sh" --quiet
fi
# Гарантируем правильные права на ключ (иначе SSH откажется использовать)
chmod 600 "$PRIVATE_KEY"
SSH_PUBKEY=$(cat "$PUBLIC_KEY")
echo "✓ SSH-ключи готовы"

# === 2. Подготовка libvirt ===
echo "Настройка libvirt..."
virsh net-start default 2>/dev/null || true
virsh net-autostart default 2>/dev/null || true

# === 3. Удаление старой VM ===
echo "Удаление старой VM (если была)..."
virsh destroy "$VM_NAME" 2>/dev/null || true
virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
rm -f "$VM_DISK"

# === 4. Скачивание Proxmox ISO ===
if [ ! -f "$PVE_ISO_ORIG" ]; then
    echo "Скачивание Proxmox VE 9.1 ISO..."
    wget -O "$PVE_ISO_ORIG" "$PVE_ISO_URL"
fi
echo "✓ ISO: $PVE_ISO_ORIG"

# === 5. Создание модифицированного ISO для автоустановки ===
# Всегда пересоздаём ISO с уникальным hostname для каждой VM
echo "Создание автоматического ISO для $VM_NAME..."
rm -rf "$ISO_EXTRACT_DIR"
mkdir -p "$ISO_EXTRACT_DIR"

echo "  Извлечение ISO..."
# 7z может выдавать ошибки из-за символических ссылок в ISO, но файлы извлекаются корректно
7z x -o"$ISO_EXTRACT_DIR" "$PVE_ISO_ORIG" -y >/dev/null 2>&1 || true

# Копируем файл активации автоустановки из шаблонов
cp "$TEMPLATES_DIR/auto-installer-mode.toml" "$ISO_EXTRACT_DIR/auto-installer-mode.toml"

# Генерируем answer.toml из шаблона с подстановкой переменных (уникальный для каждой VM)
export VM_NAME ROOT_PASSWORD SSH_PUBKEY
envsubst < "$TEMPLATES_DIR/answer.toml.template" > "$ISO_EXTRACT_DIR/answer.toml"

# Модифицируем grub.cfg для автоматического выбора (timeout=3)
if [ -f "$ISO_EXTRACT_DIR/boot/grub/grub.cfg" ]; then
    sed -i 's/set timeout=10/set timeout=3/' "$ISO_EXTRACT_DIR/boot/grub/grub.cfg"
    sed -i 's/set timeout=30/set timeout=3/' "$ISO_EXTRACT_DIR/boot/grub/grub.cfg"
fi

echo "  Создание ISO..."
rm -f "$PVE_ISO_AUTO"
xorriso -as mkisofs -r -V "PVE-AUTO" -o "$PVE_ISO_AUTO" \
    -b boot/grub/i386-pc/eltorito.img -c boot/grub/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot -e efi.img -no-emul-boot \
    -isohybrid-gpt-basdat "$ISO_EXTRACT_DIR" >/dev/null 2>&1

rm -rf "$ISO_EXTRACT_DIR"
echo "✓ Автоматический ISO создан: $PVE_ISO_AUTO"

# === 6. Создание диска VM ===
echo "Создание диска VM..."
qemu-img create -f qcow2 "$VM_DISK" "$VM_DISK_SIZE"

# === 7. Запуск VM ===
echo "Запуск VM $VM_NAME..."
virt-install \
    --name "$VM_NAME" \
    --memory "$VM_RAM_MB" \
    --vcpus "$VM_VCPUS" \
    --cpu host-passthrough \
    --disk "path=$VM_DISK,format=qcow2,bus=sata" \
    --cdrom "$PVE_ISO_AUTO" \
    --os-variant debian12 \
    --network network=default,model=virtio \
    --graphics vnc,listen=0.0.0.0 \
    --boot cdrom,hd \
    --noautoconsole

echo "✓ VM запущена"
echo "  VNC консоль: virt-viewer $VM_NAME"

# === 8. Получение MAC-адреса ===
VM_MAC=$(virsh domiflist "$VM_NAME" 2>/dev/null | grep -oE '([0-9a-f]{2}:){5}[0-9a-f]{2}' | head -1)
echo "  MAC: $VM_MAC"

# === 9. Функция получения IP ===
get_ip() {
    virsh domifaddr "$VM_NAME" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || \
    virsh net-dhcp-leases default 2>/dev/null | grep -i "$VM_MAC" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true
}

# === 10. Ожидание установки ===
echo ""
echo "Ожидание установки Proxmox VE (10-25 минут)..."
echo "Консоль: virt-viewer $VM_NAME"
echo ""

MAX_WAIT=1800
ELAPSED=0
VM_IP=""
REBOOT_COUNT=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    STATE=$(virsh domstate "$VM_NAME" 2>/dev/null || echo "unknown")
    
    # VM выключилась - перезагрузка после установки
    if [ "$STATE" = "shut off" ]; then
        REBOOT_COUNT=$((REBOOT_COUNT + 1))
        echo "[$ELAPSED сек] VM выключена (перезагрузка #$REBOOT_COUNT), запускаем..."
        sleep 5
        virsh start "$VM_NAME" 2>/dev/null || true
        sleep 10
        continue
    fi
    
    VM_IP=$(get_ip)
    
    if [ -n "$VM_IP" ]; then
        # Проверяем SSH с ключом
        if ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes root@"$VM_IP" "exit 0" 2>/dev/null; then
            echo ""
            echo "========================================"
            echo "✓ SSH доступен!"
            echo "========================================"
            
            # Проверяем pveversion
            PVE_VERSION=$(ssh -i "$PRIVATE_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$VM_IP" "pveversion 2>/dev/null" 2>/dev/null || echo "недоступно")
            echo "Версия Proxmox: $PVE_VERSION"
            
            # Проверяем веб-интерфейс
            echo ""
            echo "Проверка веб-интерфейса Proxmox..."
            for i in {1..12}; do
                if curl -sk --connect-timeout 5 "https://$VM_IP:8006" >/dev/null 2>&1; then
                    echo "✓ Веб-интерфейс Proxmox доступен!"
                    echo ""
                    echo "========================================"
                    echo "✓ Proxmox VE установлен успешно!"
                    echo "========================================"
                    echo ""
                    echo "Подключение:"
                    echo "  SSH:  ssh -i $PRIVATE_KEY root@$VM_IP"
                    echo "  Web:  https://$VM_IP:8006"
                    echo "  Логин: root / $ROOT_PASSWORD"
                    echo ""
                    echo "IP-адрес: $VM_IP"
                    echo "========================================"
                    exit 0
                fi
                echo "  [$i/12] Ожидание веб-интерфейса..."
                sleep 5
            done
            
            echo "⚠ SSH работает, но веб-интерфейс недоступен"
            echo "  Возможно, требуется дополнительное время для запуска сервисов"
            echo ""
            echo "SSH:  ssh -i $PRIVATE_KEY root@$VM_IP"
            echo "Web:  https://$VM_IP:8006"
            exit 0
        fi
        echo "[$ELAPSED сек] IP: $VM_IP - ожидание SSH..."
    else
        echo "[$ELAPSED сек] Ожидание IP... (VM: $STATE, перезагрузок: $REBOOT_COUNT)"
    fi
    
    # Снимаем скриншот каждые 60 секунд для отладки
    if [ $((ELAPSED % 60)) -eq 0 ] && [ $ELAPSED -gt 0 ]; then
        SCREENSHOT_FILE="$BASEDIR/debug-screenshots/${VM_NAME}-${ELAPSED}s.png"
        mkdir -p "$BASEDIR/debug-screenshots"
        virsh screenshot "$VM_NAME" "$SCREENSHOT_FILE" >/dev/null 2>&1 && \
            echo "  [DEBUG] Скриншот: $SCREENSHOT_FILE"
    fi
    
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

echo ""
echo "✗ Установка не завершена за $MAX_WAIT секунд"
echo "Проверьте консоль: virt-viewer $VM_NAME"
[ -n "$VM_IP" ] && echo "IP: $VM_IP"
exit 1
