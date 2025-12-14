#!/bin/bash
# Скрипт создания нескольких виртуальных машин
# Использование: ./create_vm_array.sh [количество_ВМ]
# По умолчанию создаётся 3 ВМ

set -e

BASEDIR=$(cd "$(dirname "$0")" && pwd)

# Количество ВМ из аргумента командной строки или 3 по умолчанию
VM_COUNT="${1:-3}"

# Проверка, что VM_COUNT — число
if ! [[ "$VM_COUNT" =~ ^[0-9]+$ ]] || [ "$VM_COUNT" -lt 1 ]; then
  echo "Ошибка: количество ВМ должно быть положительным числом"
  echo "Использование: $0 [количество_ВМ]"
  exit 1
fi

echo "========================================"
echo "Создание $VM_COUNT виртуальных машин"
echo "========================================"
echo ""

# Генерация SSH-ключей (один раз для всех ВМ)
echo "Проверка SSH-ключей..."
"$BASEDIR/generate_ssh_keys.sh" --quiet
echo "✓ SSH-ключи готовы"
echo ""

# Массив для хранения информации о созданных ВМ
declare -a VM_NAMES
declare -a VM_IPS

# Создание ВМ
for i in $(seq 1 "$VM_COUNT"); do
  VM_NAME="ubuntu-vm-$(printf '%02d' "$i")"
  echo "========================================"
  echo "[$i/$VM_COUNT] Создание ВМ: $VM_NAME"
  echo "========================================"
  
  # Экспортируем VM_NAME и вызываем скрипт создания
  if VM_NAME="$VM_NAME" "$BASEDIR/create_single_vm.sh"; then
    # Получаем IP созданной ВМ
    VM_IP=$(virsh domifaddr "$VM_NAME" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)
    VM_NAMES+=("$VM_NAME")
    VM_IPS+=("$VM_IP")
    echo ""
  else
    echo "✗ Ошибка при создании ВМ $VM_NAME"
    exit 1
  fi
done

# Финальная шпаргалка
PRIVATE_KEY="$BASEDIR/vm_access_key"

echo ""
echo "========================================"
echo "✓ Все $VM_COUNT ВМ успешно созданы!"
echo "========================================"
echo ""
echo "Шпаргалка для подключения по SSH:"
echo "--------------------------------"
for i in "${!VM_NAMES[@]}"; do
  echo "  ${VM_NAMES[$i]}: ssh -i $PRIVATE_KEY root@${VM_IPS[$i]}"
done
echo ""
echo "Или скопируйте команды:"
echo ""
for i in "${!VM_NAMES[@]}"; do
  echo "ssh -i $PRIVATE_KEY root@${VM_IPS[$i]}  # ${VM_NAMES[$i]}"
done
echo ""
