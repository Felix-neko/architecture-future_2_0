# architecture-future_2_0

Учебный репозиторий по курсу "Архитектура ПО Pro", 11 спринт.

## Оглавление

### [Задание 1. Модульная инфраструктура для нескольких сред](task_1_terraform_module/README.md)
Создание Terraform-модуля для автоматизированного развёртывания LXC-контейнеров в Proxmox-кластере. Включает скрипты для поднятия локального Proxmox-кластера из KVM-виртуалок, генерации SSH-ключей и управления инфраструктурой.

### [Задание 2. Интеграция с CI/CD и удалённым хранением состояния](task_2_stage_saved_in_s3/README.md)
GitOps-подход: GitLab CI/CD pipeline, который скачивает Terraform state из Yandex Object Storage (S3), выполняет `terraform apply` и загружает обновлённый state обратно. Docker-compose для локального GitLab + Runner.

### [Задание 3. Проектирование целевой архитектуры и оценка рисков](task_3_to_be_architecture/README.md)
Анализ проблем текущей архитектуры (MS SQL Server как универсальное хранилище, Apache Camel как централизованная шина). Проектирование целевой архитектуры на базе Data Lakehouse (MinIO + Iceberg + Spark) и Data Mesh. Карта рисков и план их митигации.

### [Задание 4. Моделирование домена и интеграций](task_4_domains_and_events/README.md)
DDD-анализ бизнес-областей холдинга: клиники, банк, ИИ-сервисы, фармацевтика, медицинская электроника. Выделение bounded contexts, агрегатов и доменных событий. Обоснование Event-Driven Architecture для междоменных интеграций через Kafka.

### [Задание 5. Технологический стек и расчёт стоимости](task_5_tech_stack_and_tco/README.md)
Технологический радар (Adopt/Trial/Assess/Hold). Сравнение TCO на 3 года: On-Premise MS SQL vs Облачный MS SQL vs On-Premise LakeHouse vs Облачный LakeHouse. Стратегический роадмап внедрения Data Mesh с Gantt-диаграммой.

