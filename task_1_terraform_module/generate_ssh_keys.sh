#!/bin/bash
# Скрипт генерации пары SSH-ключей для доступа к виртуальным машинам
# Использование: ./generate_ssh_keys.sh [--quiet]
# --quiet: тихий режим для вызова из других скриптов

set -e

BASEDIR=$(cd "$(dirname "$0")" && pwd)
KEY_NAME="vm_access_key"
PRIVATE_KEY="$BASEDIR/$KEY_NAME"
PUBLIC_KEY="$BASEDIR/${KEY_NAME}.pub"

# Тихий режим (для вызова из других скриптов)
QUIET=0
if [ "$1" = "--quiet" ]; then
  QUIET=1
fi

# Проверяем, существуют ли уже ключи
if [ -f "$PRIVATE_KEY" ] && [ -f "$PUBLIC_KEY" ]; then
  if [ $QUIET -eq 0 ]; then
    echo "SSH-ключи уже существуют:"
    echo "  Приватный: $PRIVATE_KEY"
    echo "  Публичный: $PUBLIC_KEY"
  fi
  exit 0
fi

# Генерируем новую пару ключей
if [ $QUIET -eq 0 ]; then
  echo "Генерация новой пары SSH-ключей..."
  ssh-keygen -t ed25519 -f "$PRIVATE_KEY" -N "" -C "vm-access-key"
else
  ssh-keygen -t ed25519 -f "$PRIVATE_KEY" -N "" -C "vm-access-key" -q
fi

# Устанавливаем правильные права доступа
chmod 600 "$PRIVATE_KEY"
chmod 644 "$PUBLIC_KEY"

if [ $QUIET -eq 0 ]; then
  echo ""
  echo "✓ SSH-ключи успешно сгенерированы:"
  echo "  Приватный: $PRIVATE_KEY"
  echo "  Публичный: $PUBLIC_KEY"
  echo ""
  echo "Для подключения к ВМ используйте:"
  echo "  ssh -i $PRIVATE_KEY root@<IP_АДРЕС>"
fi
