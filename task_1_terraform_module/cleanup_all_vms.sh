#!/bin/bash
# Скрипт удаления всех виртуальных машин и их дисков
# Использование: ./cleanup_all_vms.sh [--force]
# --force: удалять без подтверждения

set -e

FORCE=false
if [ "$1" = "--force" ]; then
  FORCE=true
fi

echo "========================================"
echo "Удаление всех виртуальных машин"
echo "========================================"
echo ""

# Получаем список всех ВМ
VMS=$(virsh list --all --name 2>/dev/null | grep -v '^$' || true)

if [ -z "$VMS" ]; then
  echo "Нет виртуальных машин для удаления."
  exit 0
fi

echo "Найдены следующие ВМ:"
echo "--------------------------------"
for VM in $VMS; do
  STATE=$(virsh domstate "$VM" 2>/dev/null || echo "unknown")
  echo "  $VM ($STATE)"
done
echo ""

# Запрос подтверждения (если не --force)
if [ "$FORCE" = false ]; then
  read -p "Удалить все эти ВМ вместе с дисками? (y/N): " CONFIRM
  if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Отменено."
    exit 0
  fi
fi

echo ""
echo "Удаление ВМ..."
echo "--------------------------------"

for VM in $VMS; do
  echo -n "  $VM: "
  
  # Останавливаем ВМ, если запущена
  STATE=$(virsh domstate "$VM" 2>/dev/null || echo "unknown")
  if [ "$STATE" = "running" ]; then
    virsh destroy "$VM" 2>/dev/null || true
    echo -n "остановлена, "
  fi
  
  # Удаляем ВМ вместе со всеми дисками
  if virsh undefine "$VM" --remove-all-storage 2>/dev/null; then
    echo "удалена ✓"
  else
    # Пробуем без --remove-all-storage (для старых версий)
    virsh undefine "$VM" 2>/dev/null || true
    echo "удалена (диски могли остаться) ✓"
  fi
done

echo ""
echo "========================================"
echo "✓ Все ВМ удалены"
echo "========================================"

# Показываем оставшиеся ВМ (если есть)
REMAINING=$(virsh list --all --name 2>/dev/null | grep -v '^$' || true)
if [ -n "$REMAINING" ]; then
  echo ""
  echo "⚠ Остались ВМ (возможно, системные):"
  for VM in $REMAINING; do
    echo "  $VM"
  done
fi
