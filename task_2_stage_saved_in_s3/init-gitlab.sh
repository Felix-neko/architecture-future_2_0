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

# Добавляем CI/CD переменные
if project && project.persisted?
  # GITHUB_TOKEN
  if '$GITHUB_TOKEN'.length > 0
    var = project.variables.find_or_initialize_by(key: 'GITHUB_TOKEN')
    var.value = '$GITHUB_TOKEN'
    var.protected = false
    var.masked = true
    var.save!
    puts 'GITHUB_TOKEN set'
  end
  
  # PROXMOX_PASSWORD (для verify_proxmox job)
  var = project.variables.find_or_initialize_by(key: 'PROXMOX_PASSWORD')
  var.value = 'mega_proxmox_password'
  var.protected = false
  var.masked = true
  var.save!
  puts 'PROXMOX_PASSWORD set'
  
  # YC_ACCESS_KEY_ID
  var = project.variables.find_or_initialize_by(key: 'YC_ACCESS_KEY_ID')
  var.value = '$YC_ACCESS_KEY_ID'
  var.protected = false
  var.masked = false
  var.save!
  puts 'YC_ACCESS_KEY_ID set'
  
  # YC_SECRET_ACCESS_KEY
  var = project.variables.find_or_initialize_by(key: 'YC_SECRET_ACCESS_KEY')
  var.value = '$YC_SECRET_ACCESS_KEY'
  var.protected = false
  var.masked = true
  var.save!
  puts 'YC_SECRET_ACCESS_KEY set'
  
  # YC_S3_BUCKET
  var = project.variables.find_or_initialize_by(key: 'YC_S3_BUCKET')
  var.value = '$YC_S3_BUCKET'
  var.protected = false
  var.masked = false
  var.save!
  puts 'YC_S3_BUCKET set'
  
  # YC_S3_ENDPOINT
  var = project.variables.find_or_initialize_by(key: 'YC_S3_ENDPOINT')
  var.value = '$YC_S3_ENDPOINT'
  var.protected = false
  var.masked = false
  var.save!
  puts 'YC_S3_ENDPOINT set'
end
"

# =============================================================================
# Создаём Personal Access Token для push
# =============================================================================
log_info "Создание Personal Access Token для push..."

PUSH_TOKEN=$(docker exec gitlab gitlab-rails runner "
user = User.find_by(username: 'root')
# Удаляем старый токен если есть
user.personal_access_tokens.find_by(name: 'git-push-token')&.revoke!
# Создаём новый токен с правами write_repository
token = user.personal_access_tokens.create!(
  name: 'git-push-token',
  scopes: ['api', 'read_repository', 'write_repository'],
  expires_at: 30.days.from_now
)
puts token.token
" 2>/dev/null)

if [ -z "$PUSH_TOKEN" ]; then
    log_error "Не удалось создать токен для push"
    exit 1
fi
log_info "✓ Токен создан: ${PUSH_TOKEN:0:15}..."

# =============================================================================
# Автоматический push кода в GitLab
# =============================================================================
log_info "Настройка remote и push кода в GitLab..."

REPO_PATH="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_PATH" || exit 1

# URL с токеном для аутентификации
GITLAB_PUSH_URL="http://root:${PUSH_TOKEN}@localhost:8929/root/$PROJECT_NAME.git"

# Добавляем или обновляем remote gitlab (без токена в URL для безопасности)
if git remote | grep -q "^gitlab$"; then
    git remote set-url gitlab "$GITLAB_URL/root/$PROJECT_NAME.git"
    log_info "✓ Remote 'gitlab' обновлён"
else
    git remote add gitlab "$GITLAB_URL/root/$PROJECT_NAME.git"
    log_info "✓ Remote 'gitlab' добавлен"
fi

# Push всех основных веток в GitLab (используем URL с токеном)
log_info "Push веток в GitLab..."

# Push main (если существует)
if git rev-parse --verify main >/dev/null 2>&1; then
    git push -f "$GITLAB_PUSH_URL" main 2>/dev/null && log_info "✓ Ветка main запушена" || log_warn "Не удалось запушить main"
fi

# Push terraform (обязательно для pipeline)
if git rev-parse --verify terraform >/dev/null 2>&1; then
    git push -f "$GITLAB_PUSH_URL" terraform 2>/dev/null && log_info "✓ Ветка terraform запушена" || log_warn "Не удалось запушить terraform"
else
    log_error "Ветка terraform не найдена локально!"
    log_info "Создайте её: git checkout -b terraform"
    exit 1
fi

# =============================================================================
# Регистрация GitLab Runner
# =============================================================================
log_info "Регистрация GitLab Runner..."

# Получаем registration token для проекта
RUNNER_TOKEN=$(docker exec gitlab gitlab-rails runner "
project = Project.find_by_full_path('root/$PROJECT_NAME')
if project
  # Создаём новый runner token для проекта
  token = project.runners_token
  puts token
end
" 2>/dev/null)

if [ -z "$RUNNER_TOKEN" ]; then
    log_warn "Не удалось получить runner token, пробуем instance runner..."
    # Используем instance runner token
    RUNNER_TOKEN=$(docker exec gitlab gitlab-rails runner "puts Gitlab::CurrentSettings.runners_registration_token" 2>/dev/null)
fi

if [ -n "$RUNNER_TOKEN" ]; then
    log_info "Runner token: ${RUNNER_TOKEN:0:10}..."
    
    # Проверяем, зарегистрирован ли уже runner
    REGISTERED=$(docker exec gitlab-runner gitlab-runner list 2>&1 | grep -c "terraform-runner" || echo "0")
    
    if [ "$REGISTERED" = "0" ]; then
        # Регистрируем runner
        docker exec gitlab-runner gitlab-runner register \
            --non-interactive \
            --url "http://localhost:8929" \
            --registration-token "$RUNNER_TOKEN" \
            --executor "docker" \
            --docker-image "alpine:latest" \
            --docker-network-mode "host" \
            --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
            --description "terraform-runner" \
            --tag-list "terraform,docker" \
            --run-untagged="true" \
            --locked="false" \
            2>&1 && log_info "✓ Runner зарегистрирован" || log_warn "Ошибка регистрации runner"
    else
        log_info "✓ Runner уже зарегистрирован"
    fi
else
    log_warn "Не удалось получить runner token"
fi

# Получаем пароль root (если есть)
ROOT_PASSWORD=$(docker exec gitlab grep 'Password:' /etc/gitlab/initial_root_password 2>/dev/null | awk '{print $2}' || echo "см. GITLAB_ROOT_PASSWORD в .env")

log_info "✓ Инициализация завершена"
log_info ""
log_info "Данные для входа:"
log_info "  URL: $GITLAB_URL"
log_info "  User: root"
log_info "  Password: $ROOT_PASSWORD"
log_info ""
log_info "Теперь можно запустить pipeline:"
log_info "  ./test_pipeline.sh"
