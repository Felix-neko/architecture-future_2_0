#!/bin/bash
# =============================================================================
# Скрипт инициализации GitLab после запуска
# Создаёт пользователя, проект и настраивает переменные CI/CD
# =============================================================================

set -e

GITLAB_URL="http://localhost:8929"
GITLAB_USER="developer"
GITLAB_PASSWORD="Xk9#mN2\$pL7@qR4!"
GITLAB_EMAIL="developer@local.dev"
PROJECT_NAME="architecture-future_2_0"

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Ожидание запуска GitLab
log_info "Ожидание запуска GitLab..."
for i in {1..120}; do
    if curl -s -f "$GITLAB_URL/-/readiness" > /dev/null 2>&1 || \
       curl -s "$GITLAB_URL" 2>&1 | grep -q "GitLab\|sign_in"; then
        log_info "✓ GitLab готов к работе (попытка $i)"
        sleep 5
        break
    fi
    echo "  Попытка $i/120..."
    sleep 5
done

# Проверяем, что GitLab запустился
if ! curl -s "$GITLAB_URL" 2>&1 | grep -q "GitLab\|sign_in\|users"; then
    log_error "GitLab не запустился"
    exit 1
fi

# Читаем GITHUB_TOKEN из .env
GITHUB_TOKEN=""
if [ -f "$(dirname "$0")/.env" ]; then
    source "$(dirname "$0")/.env"
fi

log_info "Создание проекта под пользователем root..."

# Используем root пользователя - он уже существует
# Создаём проект через gitlab-rails
docker exec gitlab gitlab-rails runner "
# Используем root пользователя
user = User.find_by(username: 'root')
puts 'Using user: root'

# Создаём проект если не существует
project = Project.find_by_full_path('root/$PROJECT_NAME')
if project.nil?
  project = Projects::CreateService.new(
    user,
    name: '$PROJECT_NAME',
    path: '$PROJECT_NAME',
    visibility_level: Gitlab::VisibilityLevel::PRIVATE,
    initialize_with_readme: false
  ).execute
  
  if project.persisted?
    puts 'Project created: ' + project.full_path
  else
    puts 'Project creation failed: ' + project.errors.full_messages.join(', ')
  end
else
  puts 'Project already exists: ' + project.full_path
end

# Добавляем GITHUB_TOKEN как CI/CD переменную
if project && project.persisted? && '$GITHUB_TOKEN'.length > 0
  var = project.variables.find_or_initialize_by(key: 'GITHUB_TOKEN')
  var.value = '$GITHUB_TOKEN'
  var.protected = false
  var.masked = true
  var.save!
  puts 'CI/CD variable GITHUB_TOKEN set'
end
"

# Получаем пароль root
ROOT_PASSWORD=$(docker exec gitlab grep 'Password:' /etc/gitlab/initial_root_password 2>/dev/null | awk '{print $2}' || echo "unknown")

log_info "✓ Инициализация завершена"
log_info ""
log_info "Данные для входа:"
log_info "  URL: $GITLAB_URL"
log_info "  User: root"
log_info "  Password: $ROOT_PASSWORD"
log_info ""
log_info "Теперь выполните:"
log_info "  ./switch-to-gitlab.sh"
log_info "  git push gitlab terraform"
