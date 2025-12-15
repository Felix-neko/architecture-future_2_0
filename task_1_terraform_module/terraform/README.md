# Terraform-модуль для LXC-контейнеров в Proxmox

Этот модуль позволяет создавать и управлять LXC-контейнерами в существующем Proxmox-кластере с **автоматической проверкой ресурсов** и **политикой размещения**.

## Ключевые возможности

- **Проверка ресурсов**: перед созданием контейнеров проверяется доступность RAM, CPU и диска на нодах
- **Автоматическое размещение**: контейнеры распределяются по нодам с достаточными ресурсами
- **Изолированные окружения**: поддержка нескольких terraform-окружений с отдельным состоянием
- **Файл с IP-адресами**: автоматическое создание файла `.lxc_ips` с адресами созданных контейнеров

## Структура

```
terraform/
├── vm_module/                  # Основной Terraform-модуль
│   ├── main.tf                 # Основная конфигурация
│   ├── variables.tf            # Входные переменные
│   ├── outputs.tf              # Выходные переменные
│   ├── versions.tf             # Версии провайдеров
│   └── scripts/                # Вспомогательные скрипты
│       └── check_node_resources.sh  # Проверка ресурсов на нодах
├── envs/                       # Пресеты переменных для окружений
│   ├── dev.tfvars              # DEV: 1 контейнер, 2 CPU, 2 ГБ RAM
│   ├── stage.tfvars            # STAGE: 2 контейнера, 2 CPU, 3 ГБ RAM
│   └── prod.tfvars             # PROD: 3 контейнера, 4 CPU, 4 ГБ RAM
└── environments/               # Изолированные terraform-окружения
    ├── dev-1/                  # Первый экземпляр dev (VMID 100-109, IP .100-.109)
    └── dev-2/                  # Второй экземпляр dev (VMID 110-119, IP .110-.119)
```

## Быстрый старт

### 1. Подготовка

Убедитесь, что:
- Proxmox-кластер запущен и доступен
- Файл `.node_ips` содержит IP-адреса нод (или они будут определены автоматически)
- SSH-ключи `vm_access_key` и `vm_access_key.pub` существуют

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
# Через Terraform output
terraform output lxc_ips

# Из автоматически созданного файла
cat ../../.lxc_ips
```

### 5. Удаление контейнеров

```bash
terraform destroy -var-file="../envs/dev.tfvars"
```

---

## Подключение к LXC-контейнерам по SSH

После создания контейнеров их IP-адреса сохраняются в файл `.lxc_ips`.

### Подключение с использованием SSH-ключа:

```bash
# Получить IP-адреса из файла
cat .lxc_ips

# Подключиться к контейнеру (Alpine Linux использует пользователя root)
ssh -i vm_access_key root@<IP_КОНТЕЙНЕРА>

# Пример с первым IP из файла:
ssh -i vm_access_key root@$(head -1 .lxc_ips)
```

### Подключение ко всем контейнерам:

```bash
# Выполнить команду на всех контейнерах
for IP in $(cat .lxc_ips); do
    echo "=== Контейнер $IP ==="
    ssh -i vm_access_key -o StrictHostKeyChecking=no root@$IP "hostname; uptime"
done
```

### Если SSH недоступен (Alpine minimal):

Контейнеры Alpine по умолчанию могут не иметь SSH-сервер. Используйте `pct exec` через Proxmox:

```bash
# Подключение через Proxmox-ноду
ssh -i vm_access_key root@<IP_PROXMOX_НОДЫ> "pct exec <VMID> -- /bin/sh"

# Пример:
ssh -i vm_access_key root@192.168.122.10 "pct exec 100 -- /bin/sh"
```

---

## Политика размещения и проверка ресурсов

### Как это работает

1. **Перед созданием** контейнеров скрипт `check_node_resources.sh` проверяет:
   - Доступную RAM на каждой ноде
   - Свободные CPU-ядра
   - Доступное место на диске (local-lvm)

2. **Алгоритм размещения**:
   - Для каждого контейнера выбирается нода с достаточными ресурсами
   - Контейнеры распределяются последовательно по нодам
   - Если ни на одной ноде нет достаточно ресурсов — Terraform выдаёт ошибку **до создания** контейнеров

3. **Ошибка при недостатке ресурсов**:
   ```
   ОШИБКА РАЗМЕЩЕНИЯ: Недостаточно ресурсов для размещения контейнера 2.
   Требуется: 12288MB RAM, 4 CPU, 20GB диска.
   Доступные ноды не имеют достаточно свободных ресурсов.
   ```

### Отключение проверки ресурсов

Если нужно отключить проверку (не рекомендуется):

```bash
terraform apply -var-file="../envs/dev.tfvars" -var="enable_resource_check=false"
```

---

## Изолированные terraform-окружения

Для запуска нескольких независимых окружений с одним модулем используйте папку `environments/`.

### Преимущества:

- **Отдельное состояние** Terraform для каждого окружения
- **Уникальные VMID и IP-адреса** (не пересекаются)
- **Переиспользование** одного модуля `vm_module`

### Структура диапазонов:

| Окружение | VMID диапазон | IP диапазон |
|-----------|---------------|-------------|
| dev-1     | 100-109       | .100-.109   |
| dev-2     | 110-119       | .110-.119   |
| stage     | 200-299       | .120-.139   |
| prod      | 300-399       | .140-.159   |

### Использование:

```bash
# Окружение dev-1
cd terraform/environments/dev-1
terraform init
terraform apply

# Окружение dev-2 (параллельно с dev-1)
cd terraform/environments/dev-2
terraform init
terraform apply
```

### Создание нового окружения:

1. Скопируйте папку `dev-1` в новую (например, `dev-3`)
2. Измените `terraform.tfvars`:
   - `start_vmid` — уникальный диапазон VMID
   - `ip_start_offset` — уникальный диапазон IP
   - `lxc_name_prefix` — уникальный префикс имён

---

## Входные переменные

| Переменная | Описание | По умолчанию |
|------------|----------|--------------|
| `proxmox_node_ips` | Список IP-адресов нод Proxmox | Читается из `.node_ips` |
| `proxmox_root_password` | Пароль root для нод Proxmox | `mega_root_password` |
| `lxc_count` | Количество LXC-контейнеров | `2` |
| `lxc_cpus` | CPU-ядра на контейнер | `2` |
| `lxc_memory_mb` | RAM на контейнер (МБ) | `8192` (8 ГБ) |
| `lxc_disk_gb` | Размер диска (ГБ) | `10` |
| `ssh_public_key_path` | Путь к публичному SSH-ключу | `vm_access_key.pub` |
| `ssh_private_key_path` | Путь к приватному SSH-ключу | `vm_access_key` |
| `network_cidr` | CIDR подсети | `192.168.122.0/24` |
| `start_vmid` | Начальный VMID | `100` |
| `ip_start_offset` | Начальное смещение IP (4-й октет) | `100` |
| `lxc_template` | Шаблон контейнера | `alpine-3.22-default_...` |
| `target_node` | Целевая нода (без проверки ресурсов) | `pve-node-1` |
| `lxc_name_prefix` | Префикс имени контейнера | `lxc-container` |
| `enable_resource_check` | Включить проверку ресурсов | `true` |

## Выходные переменные

| Переменная | Описание |
|------------|----------|
| `lxc_ips` | Список IP-адресов созданных контейнеров |
| `lxc_vmids` | Список VMID контейнеров |
| `lxc_names` | Список имён контейнеров |
| `proxmox_api_endpoint` | URL Proxmox API |
| `node_assignments` | На каких нодах размещены контейнеры |
| `placement_error` | Ошибка размещения (если есть) |
| `lxc_ips_file` | Путь к файлу с IP-адресами |

---

## Как посмотреть output-переменные

```bash
# Все выходные переменные
terraform output

# Конкретная переменная
terraform output lxc_ips

# В JSON-формате
terraform output -json

# Значение без кавычек (для скриптов)
terraform output -raw lxc_ips_file
```

## Как проверить, инициализирована ли среда

```bash
# Проверка наличия папки .terraform
ls -la .terraform/

# Если папка существует и содержит провайдеры — среда инициализирована
ls -la .terraform/providers/

# Альтернативно — попробовать validate (покажет ошибку, если не инициализировано)
terraform validate
```

## Как посмотреть текущее состояние

```bash
# Список ресурсов в состоянии
terraform state list

# Подробная информация о конкретном ресурсе
terraform state show proxmox_virtual_environment_container.lxc[0]

# Полное состояние (JSON)
terraform show -json

# Человекочитаемый вид
terraform show
```

---

## Тестирование модуля

Используйте тестовый скрипт:

```bash
cd task_1_terraform_module
./test_terraform_module.sh -e dev      # Тест DEV-окружения
./test_terraform_module.sh -e stage    # Тест STAGE-окружения
./test_terraform_module.sh -e prod     # Тест PROD-окружения
```

### Тестирование проверки ресурсов:

```bash
# Тест: ошибка при превышении ресурсов на одной ноде
./test_terraform_module.sh --test-resource-overflow

# Тест: ошибка при общем превышении ресурсов кластера
./test_terraform_module.sh --test-cluster-overflow
```

### Тестирование отдельных окружений:

```bash
# Тест окружения dev-1
./test_terraform_module.sh --environment dev-1

# Тест окружения dev-2
./test_terraform_module.sh --environment dev-2

# Тест на конфликт VMID между окружениями
./test_terraform_module.sh --test-vmid-conflict
```

Опции скрипта:
- `-e, --env ENV` — пресет окружения (dev/stage/prod)
- `--environment NAME` — отдельное окружение из `environments/`
- `--skip-cleanup` — пропустить удаление существующих контейнеров
- `--skip-terraform` — пропустить запуск Terraform (только проверка)
- `--test-resource-overflow` — тест ошибки превышения ресурсов
- `--test-cluster-overflow` — тест ошибки превышения ресурсов кластера
- `--test-vmid-conflict` — тест уникальности VMID между окружениями

---

## Устранение проблем

### Ошибка "Недостаточно ресурсов для размещения"

Проверка ресурсов показала, что на нодах недостаточно RAM/CPU/диска:

1. Уменьшите `lxc_memory_mb` или `lxc_count`
2. Освободите ресурсы на нодах (удалите неиспользуемые контейнеры)
3. Добавьте новые ноды в кластер

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

### Конфликт VMID между окружениями

Убедитесь, что `start_vmid` в каждом окружении уникален и диапазоны не пересекаются.
