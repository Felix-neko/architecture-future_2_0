#!/bin/bash
# =============================================================================
# Скрипт автоинициализации GitLab при первом запуске
# Устанавливает пароль root, создаёт проект и настраивает CI/CD переменные
# =============================================================================

set -e

INIT_MARKER="/etc/gitlab/.initialized"
PROJECT_NAME="${GITLAB_PROJECT_NAME:-architecture-future_2_0}"

# Цвета для вывода
log_info() { echo "[INIT] $1"; }
log_warn() { echo "[WARN] $1"; }
log_error() { echo "[ERROR] $1"; }

# Функция инициализации GitLab
initialize_gitlab() {
    log_info "Ожидание запуска GitLab..."
    
    # Ждём, пока GitLab полностью запустится
    for i in {1..120}; do
        if gitlab-rails runner "puts 'GitLab ready'" 2>/dev/null; then
            log_info "GitLab готов к инициализации (попытка $i)"
            break
        fi
        echo "  Ожидание GitLab... (попытка $i/120)"
        sleep 5
    done
    
    # Проверяем, что GitLab запустился
    if ! gitlab-rails runner "puts 'OK'" 2>/dev/null; then
        log_error "GitLab не запустился за отведённое время"
        return 1
    fi
    
    log_info "Установка пароля для root пользователя..."
    
    # Устанавливаем пароль root
    gitlab-rails runner "
user = User.find_by(username: 'root')
if user
  user.password = '${GITLAB_ROOT_PASSWORD}'
  user.password_confirmation = '${GITLAB_ROOT_PASSWORD}'
  user.password_automatically_set = false
  user.save!
  puts 'Root password set successfully'
else
  puts 'ERROR: Root user not found'
  exit 1
end
"
    
    log_info "Создание проекта $PROJECT_NAME..."
    
    # Создаём проект и настраиваем CI/CD переменные
    gitlab-rails runner "
user = User.find_by(username: 'root')

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
  if '${GITHUB_TOKEN}'.length > 0
    var = project.variables.find_or_initialize_by(key: 'GITHUB_TOKEN')
    var.value = '${GITHUB_TOKEN}'
    var.protected = false
    var.masked = true
    var.save!
    puts 'CI/CD variable GITHUB_TOKEN set'
  end
  
  # YC_ACCESS_KEY_ID
  if '${YC_ACCESS_KEY_ID}'.length > 0
    var = project.variables.find_or_initialize_by(key: 'YC_ACCESS_KEY_ID')
    var.value = '${YC_ACCESS_KEY_ID}'
    var.protected = false
    var.masked = false
    var.save!
    puts 'CI/CD variable YC_ACCESS_KEY_ID set'
  end
  
  # YC_SECRET_ACCESS_KEY
  if '${YC_SECRET_ACCESS_KEY}'.length > 0
    var = project.variables.find_or_initialize_by(key: 'YC_SECRET_ACCESS_KEY')
    var.value = '${YC_SECRET_ACCESS_KEY}'
    var.protected = false
    var.masked = true
    var.save!
    puts 'CI/CD variable YC_SECRET_ACCESS_KEY set'
  end
  
  # YC_S3_BUCKET
  if '${YC_S3_BUCKET}'.length > 0
    var = project.variables.find_or_initialize_by(key: 'YC_S3_BUCKET')
    var.value = '${YC_S3_BUCKET}'
    var.protected = false
    var.masked = false
    var.save!
    puts 'CI/CD variable YC_S3_BUCKET set'
  end
  
  # YC_S3_ENDPOINT
  if '${YC_S3_ENDPOINT}'.length > 0
    var = project.variables.find_or_initialize_by(key: 'YC_S3_ENDPOINT')
    var.value = '${YC_S3_ENDPOINT}'
    var.protected = false
    var.masked = false
    var.save!
    puts 'CI/CD variable YC_S3_ENDPOINT set'
  end
end
"
    
    # Создаём маркер инициализации
    touch "$INIT_MARKER"
    log_info "✓ Инициализация GitLab завершена"
}

# Основная логика
if [ -f "$INIT_MARKER" ]; then
    log_info "GitLab уже инициализирован, пропускаем инициализацию"
else
    log_info "Первый запуск, запускаем инициализацию в фоне..."
    # Запускаем инициализацию в фоне после запуска основного процесса
    (sleep 30 && initialize_gitlab) &
fi

# Запускаем оригинальный entrypoint GitLab
exec /assets/init-container

