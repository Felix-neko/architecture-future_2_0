#!/bin/bash
# Скрипт генерации пары SSH-ключей для доступа к виртуальным машинам

set -e

BASEDIR=$(cd "$(dirname "$0")" && pwd)
KEY_NAME="vm_access_key"
PRIVATE_KEY="$BASEDIR/$KEY_NAME"
PUBLIC_KEY="$BASEDIR/${KEY_NAME}.pub"

# Проверяем, существуют ли уже ключи
if [ -f "$PRIVATE_KEY" ] && [ -f "$PUBLIC_KEY" ]; then
  echo "SSH-ключи уже существуют:"
  echo "  Приватный: $PRIVATE_KEY"
  echo "  Публичный: $PUBLIC_KEY"
  exit 0
fi

# Генерируем новую пару ключей
echo "Генерация новой пары SSH-ключей..."
ssh-keygen -t ed25519 -f "$PRIVATE_KEY" -N "" -C "vm-access-key"

# Устанавливаем правильные права доступа
chmod 600 "$PRIVATE_KEY"
chmod 644 "$PUBLIC_KEY"

echo ""
echo "✓ SSH-ключи успешно сгенерированы:"
echo "  Приватный: $PRIVATE_KEY"
echo "  Публичный: $PUBLIC_KEY"
echo ""
echo "Для подключения к ВМ используйте:"
echo "  ssh -i $PRIVATE_KEY root@<IP_АДРЕС>"
