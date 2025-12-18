# Задание 2. Интеграция с CI/CD и удалённым хранением состояния


В этом задании мы запустим GitLab в docker-compose и настроим CI/CD pipeline, который:
- Скачивает Terraform state из S3
- Выполняет `terraform plan` и `terraform apply`
- Загружает обновлённый state обратно в S3
- Проверяет соответствие state реальной инфраструктуре в Proxmox

Наши декларативные описания инфраструктуры для этого задания  `task_2_stage_saved_in_s3/terraform/environments`, и мы оттуда будем обращаться к Terraform-модулю из `task_1_terraform_module`

Состояние будем хранить в S3-бакете `rubber-duck-infra-states` на Yandex Object Storage.

## Основные файлы

### Конфигурация и запуск GitLab
* `docker-compose.yaml` -- docker-compose для запуска GitLab и GitLab Runner;
* `.env` -- переменные окружения (S3-credentials, GitLab-пароли);
* `init-gitlab.sh` -- скрипт инициализации GitLab (создание проекта, регистрация runner'а);
* `gitlab-init/entrypoint.sh` -- entrypoint для контейнера инициализации;

### Тестовые скрипты
* `test_gitlab.sh` -- тест запуска GitLab и базовой функциональности;
* `test_pipeline.sh` -- тест CI/CD pipeline с Terraform;
* `test_terraform_action.sh` -- тест Terraform action с S3-хранилищем;

### Вспомогательные скрипты
* `switch-to-gitlab.sh` -- переключить git remote на локальный GitLab;
* `switch-to-github.sh` -- переключить git remote обратно на GitHub;
* `scripts/verify_state.sh` -- скрипт проверки Terraform state из S3 и соответствия с Proxmox;

### Декларативные описания:
* `terraform/environments/` -- конфигурации окружений (`dev-1`, `dev-2`), использующие `vm_module` из задания 1;

## Как протестировать?

1) Заходим в наш бакет -- и удаляем старые состояния:
![img.png](img.png)
2) 