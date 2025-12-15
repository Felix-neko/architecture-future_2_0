# Terraform-модуль для LXC-контейнеров в Proxmox

Этот модуль позволяет создавать и управлять LXC-контейнерами в существующем Proxmox-кластере.

## Структура

```
terraform/
├── vm_module/           # Terraform-модуль
│   ├── main.tf          # Основная конфигурация
│   ├── variables.tf     # Входные переменные
│   ├── outputs.tf       # Выходные переменные
│   └── versions.tf      # Версии провайдеров
└── envs/                # Наборы переменных для окружений
    ├── dev.tfvars       # DEV: 1 контейнер, 2 CPU, 8 ГБ RAM
    ├── stage.tfvars     # STAGE: 2 контейнера, 2 CPU, 8 ГБ RAM
    └── prod.tfvars      # PROD: 3 контейнера, 4 CPU, 12 ГБ RAM
```

## Быстрый старт

### 1. Подготовка

Убедитесь, что:
- Proxmox-кластер запущен и доступен
- Файл `.node_ips` содержит IP-адреса нод (или они будут определены автоматически)
- SSH-ключ `vm_access_key.pub` существует

### 2. Инициализация Terraform

```bash
cd task_1_terraform_module/terraform/vm_module
terraform init
```

### 3. Создание контейнеров

#### Для DEV-окружения (1 контейнер):
```bash
terraform plan -var-file="../envs/dev.tfvars" -out=tfplan
terraform apply tfplan
```

#### Для STAGE-окружения (2 контейнера):
```bash
terraform plan -var-file="../envs/stage.tfvars" -out=tfplan
terraform apply tfplan
```

#### Для PROD-окружения (3 контейнера):
```bash
terraform plan -var-file="../envs/prod.tfvars" -out=tfplan
terraform apply tfplan
```

### 4. Получение IP-адресов созданных контейнеров

```bash
terraform output lxc_ips
```

### 5. Удаление контейнеров

```bash
terraform destroy -var-file="../envs/dev.tfvars"
```

## Входные переменные

| Переменная | Описание | По умолчанию |
|------------|----------|--------------|
| `proxmox_node_ips` | Список IP-адресов нод Proxmox | Читается из `.node_ips` |
| `proxmox_root_password` | Пароль root для нод Proxmox | `mega_root_password` |
| `lxc_count` | Количество LXC-контейнеров | `2` |
| `lxc_cpus` | CPU-ядра на контейнер | `2` |
| `lxc_memory_mb` | RAM на контейнер (МБ) | `8192` (8 ГБ) |
| `lxc_disk_gb` | Размер диска (ГБ) | `10` |
| `ssh_public_key_path` | Путь к SSH-ключу | `vm_access_key.pub` |
| `network_cidr` | CIDR подсети | `192.168.122.0/24` |
| `start_vmid` | Начальный VMID | `100` |
| `lxc_template` | Шаблон контейнера | `alpine-3.22-default_...` |
| `target_node` | Целевая нода Proxmox | `pve-node-1` |
| `lxc_name_prefix` | Префикс имени контейнера | `lxc-container` |

## Выходные переменные

| Переменная | Описание |
|------------|----------|
| `lxc_ips` | Список IP-адресов созданных контейнеров |
| `lxc_vmids` | Список VMID контейнеров |
| `lxc_names` | Список имён контейнеров |
| `proxmox_api_endpoint` | URL Proxmox API |

## Примеры использования

### Создание кастомной конфигурации

Создайте файл `my_config.tfvars`:

```hcl
# Кастомная конфигурация
lxc_count       = 5
lxc_cpus        = 4
lxc_memory_mb   = 16384
lxc_disk_gb     = 50
lxc_name_prefix = "my-app"
start_vmid      = 500
```

Применение:
```bash
terraform plan -var-file="my_config.tfvars" -out=tfplan
terraform apply tfplan
```

### Переопределение переменных через командную строку

```bash
terraform apply -var-file="../envs/dev.tfvars" \
  -var="lxc_count=3" \
  -var="lxc_cpus=4"
```

### Использование другого Proxmox-пароля

```bash
export TF_VAR_proxmox_root_password="my_secret_password"
terraform apply -var-file="../envs/dev.tfvars"
```

## Модификация существующей инфраструктуры

### Изменение количества контейнеров

1. Измените `lxc_count` в файле `.tfvars`
2. Запустите:
```bash
terraform plan -var-file="../envs/dev.tfvars" -out=tfplan
terraform apply tfplan
```

Terraform автоматически:
- **Добавит** новые контейнеры (если количество увеличилось)
- **Удалит** лишние контейнеры (если количество уменьшилось)

### Изменение ресурсов контейнеров

**Важно:** Изменение CPU/RAM требует пересоздания контейнеров.

```bash
# Изменяем ресурсы в .tfvars, затем:
terraform plan -var-file="../envs/dev.tfvars" -out=tfplan
# Проверяем план — убеждаемся, что изменения корректны
terraform apply tfplan
```

## Тестирование модуля

Используйте тестовый скрипт:

```bash
cd task_1_terraform_module
./test_terraform_module.sh -e dev      # Тест DEV-окружения
./test_terraform_module.sh -e stage    # Тест STAGE-окружения
./test_terraform_module.sh -e prod     # Тест PROD-окружения
```

Опции скрипта:
- `-e, --env ENV` — окружение (dev/stage/prod)
- `--skip-cleanup` — пропустить удаление существующих контейнеров
- `--skip-terraform` — пропустить запуск Terraform (только проверка)

## Устранение проблем

### Ошибка "File already exists in the datastore"

Шаблон уже загружен. Модуль автоматически использует существующий файл.

### Ошибка подключения к Proxmox API

1. Проверьте, что Proxmox-ноды запущены:
```bash
virsh list --all
```

2. Проверьте IP-адреса:
```bash
cat .node_ips
```

3. Проверьте SSH-доступ:
```bash
ssh -i vm_access_key root@<IP_НОДЫ>
```

### Контейнер не запускается

Проверьте логи на Proxmox-ноде:
```bash
ssh -i vm_access_key root@<IP_НОДЫ> "pct start <VMID> && pct console <VMID>"
```
