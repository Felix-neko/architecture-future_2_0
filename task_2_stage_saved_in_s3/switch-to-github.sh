#!/bin/bash
# =============================================================================
# Скрипт переключения репозитория на GitHub
# =============================================================================

REPO_PATH="/home/felix/Projects/yandex_swa_pro/architecture-future_2_0"
GITHUB_REPO="git@github.com:Felix-neko/architecture-future_2_0.git"

cd "$REPO_PATH" || exit 1

echo "Переключение репозитория на GitHub..."

# Проверяем, что origin указывает на GitHub
CURRENT_ORIGIN=$(git remote get-url origin 2>/dev/null || echo "")

if echo "$CURRENT_ORIGIN" | grep -q "github.com"; then
    echo "✓ Remote 'origin' уже указывает на GitHub"
else
    echo "⚠ Remote 'origin' не указывает на GitHub: $CURRENT_ORIGIN"
    echo "  Добавляем github как отдельный remote..."
fi

# Добавляем или обновляем remote github
if git remote | grep -q "^github$"; then
    git remote set-url github "$GITHUB_REPO"
    echo "✓ Remote 'github' обновлён"
else
    git remote add github "$GITHUB_REPO"
    echo "✓ Remote 'github' добавлен"
fi

# Показываем текущие remote
echo ""
echo "Текущие remote:"
git remote -v

echo ""
echo "Для push в GitHub используйте:"
echo "  git push origin <branch>   # если origin = GitHub"
echo "  git push github <branch>   # через отдельный remote"
echo ""
echo "Например:"
echo "  git push origin main"
