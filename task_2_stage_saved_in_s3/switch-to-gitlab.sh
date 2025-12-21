#!/bin/bash
# =============================================================================
# Скрипт переключения репозитория на GitLab
# =============================================================================

REPO_PATH="/home/felix/Projects/yandex_swa_pro/architecture-future_2_0"
GITLAB_URL="http://localhost:8929"
GITLAB_USER="root"
PROJECT_NAME="architecture-future_2_0"

cd "$REPO_PATH" || exit 1

echo "Переключение репозитория на GitLab..."

# Добавляем или обновляем remote gitlab
if git remote | grep -q "^gitlab$"; then
    git remote set-url gitlab "$GITLAB_URL/$GITLAB_USER/$PROJECT_NAME.git"
    echo "✓ Remote 'gitlab' обновлён"
else
    git remote add gitlab "$GITLAB_URL/$GITLAB_USER/$PROJECT_NAME.git"
    echo "✓ Remote 'gitlab' добавлен"
fi

# Показываем текущие remote
echo ""
echo "Текущие remote:"
git remote -v

echo ""
echo "Для push в GitLab используйте:"
echo "  git push gitlab <branch>"
echo ""
echo "Например:"
echo "  git push gitlab terraform"
