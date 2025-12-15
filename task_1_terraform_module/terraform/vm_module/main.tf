# =============================================================================
# Основной файл Terraform-модуля для создания LXC-контейнеров в Proxmox
# С политикой размещения и проверкой ресурсов на нодах
# =============================================================================

# -----------------------------------------------------------------------------
# Локальные переменные
# -----------------------------------------------------------------------------
locals {
  # Путь к базовой директории проекта (task_1_terraform_module)
  base_dir = abspath("${path.module}/../..")

  # Читаем IP-адреса нод из файла .node_ips, если не указаны явно
  node_ips_from_file = fileexists("${local.base_dir}/.node_ips") ? compact(split("\n", file("${local.base_dir}/.node_ips"))) : []
  node_ips           = length(var.proxmox_node_ips) > 0 ? var.proxmox_node_ips : local.node_ips_from_file

  # Первая нода кластера используется для API-подключения
  master_ip = length(local.node_ips) > 0 ? local.node_ips[0] : ""

  # URL для подключения к Proxmox API
  proxmox_api_url = "https://${local.master_ip}:8006"

  # Путь к приватному SSH-ключу для подключения к нодам
  ssh_private_key_path = var.ssh_private_key_path != "" ? var.ssh_private_key_path : "${local.base_dir}/vm_access_key"

  # Читаем публичный SSH-ключ из файла, если путь не указан явно
  ssh_key_path = var.ssh_public_key_path != "" ? var.ssh_public_key_path : "${local.base_dir}/vm_access_key.pub"
  ssh_key      = fileexists(local.ssh_key_path) ? trimspace(file(local.ssh_key_path)) : ""

  # Вычисляем базовый IP из CIDR для присвоения статических адресов
  network_parts = split("/", var.network_cidr)
  network_base  = local.network_parts[0]
  network_mask  = length(local.network_parts) > 1 ? local.network_parts[1] : "24"

  # Разбиваем базовый IP на октеты
  ip_octets = split(".", local.network_base)

  # Генерируем IP-адреса для контейнеров, начиная с ip_start_offset
  container_ips = [
    for i in range(var.lxc_count) : format(
      "%s.%s.%s.%d/%s",
      local.ip_octets[0],
      local.ip_octets[1],
      local.ip_octets[2],
      var.ip_start_offset + i,
      local.network_mask
    )
  ]

  # Gateway - первый IP в подсети
  gateway_ip = format("%s.%s.%s.1", local.ip_octets[0], local.ip_octets[1], local.ip_octets[2])

  # Результат проверки ресурсов
  resource_check = var.enable_resource_check ? data.external.check_resources[0].result : {
    error            = ""
    selected_nodes   = "[\"${var.target_node}\"]"
    node_assignments = join(",", [for i in range(var.lxc_count) : var.target_node])
  }

  # Проверяем наличие ошибки размещения
  placement_error = local.resource_check.error

  # Парсим назначения нод для контейнеров
  node_assignments = local.placement_error == "" ? split(",", local.resource_check.node_assignments) : []

  # Путь к файлу с IP-адресами контейнеров
  lxc_ips_file = "${local.base_dir}/.lxc_ips"
}

# -----------------------------------------------------------------------------
# Провайдер Proxmox
# -----------------------------------------------------------------------------
provider "proxmox" {
  # Endpoint API Proxmox
  endpoint = local.proxmox_api_url

  # Учётные данные для подключения
  username = "root@pam"
  password = var.proxmox_root_password

  # Отключаем проверку SSL-сертификата (для самоподписанных сертификатов)
  insecure = true

  # Настройки SSH для операций, требующих прямого доступа
  ssh {
    agent    = false
    username = "root"
    password = var.proxmox_root_password
  }
}

# -----------------------------------------------------------------------------
# Проверка ресурсов на нодах перед созданием контейнеров
# -----------------------------------------------------------------------------
data "external" "check_resources" {
  count = var.enable_resource_check ? 1 : 0

  program = ["${path.module}/scripts/check_node_resources.sh"]

  query = {
    node_ips           = join(",", local.node_ips)
    required_memory_mb = tostring(var.lxc_memory_mb)
    required_cpus      = tostring(var.lxc_cpus)
    required_disk_gb   = tostring(var.lxc_disk_gb)
    ssh_key_path       = local.ssh_private_key_path
    ssh_password       = var.proxmox_root_password
    container_count    = tostring(var.lxc_count)
  }
}

# -----------------------------------------------------------------------------
# Проверка ошибки размещения (останавливает apply при недостатке ресурсов)
# -----------------------------------------------------------------------------
resource "null_resource" "validate_placement" {
  count = var.enable_resource_check && local.placement_error != "" ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'ОШИБКА РАЗМЕЩЕНИЯ: ${local.placement_error}' && exit 1"
  }
}

# -----------------------------------------------------------------------------
# LXC-контейнеры
# -----------------------------------------------------------------------------
resource "proxmox_virtual_environment_container" "lxc" {
  # Создаём указанное количество контейнеров (только если нет ошибки размещения)
  count = local.placement_error == "" ? var.lxc_count : 0

  # Зависимость от загрузки шаблона и проверки ресурсов
  depends_on = [
    proxmox_virtual_environment_download_file.lxc_template,
    null_resource.validate_placement
  ]

  # Идентификатор виртуальной машины
  vm_id = var.start_vmid + count.index

  # Целевая нода для размещения контейнера (из результатов проверки ресурсов)
  node_name = var.enable_resource_check ? local.node_assignments[count.index] : var.target_node

  # Описание контейнера
  description = "${var.lxc_name_prefix}-${var.start_vmid + count.index}"

  # Запускать контейнер при старте ноды
  start_on_boot = true

  # Непривилегированный контейнер (более безопасно)
  unprivileged = true

  # Шаблон операционной системы
  operating_system {
    template_file_id = "local:vztmpl/${var.lxc_template}"
    type             = "alpine"
  }

  # Настройки CPU
  cpu {
    cores = var.lxc_cpus
  }

  # Настройки памяти
  memory {
    dedicated = var.lxc_memory_mb
  }

  # Корневой диск
  disk {
    datastore_id = "local-lvm"
    size         = var.lxc_disk_gb
  }

  # Сетевой интерфейс
  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  # Инициализация (сеть и SSH-ключи)
  initialization {
    hostname = "${var.lxc_name_prefix}-${var.start_vmid + count.index}"

    ip_config {
      ipv4 {
        address = local.container_ips[count.index]
        gateway = local.gateway_ip
      }
    }

    user_account {
      keys = local.ssh_key != "" ? [local.ssh_key] : []
    }
  }

  # Запускаем контейнер сразу после создания
  started = true
}

# -----------------------------------------------------------------------------
# Загрузка шаблона контейнера (если не существует)
# -----------------------------------------------------------------------------
resource "proxmox_virtual_environment_download_file" "lxc_template" {
  # Загружаем шаблон только если нет ошибки размещения
  count = local.placement_error == "" ? 1 : 0

  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = var.enable_resource_check && length(local.node_assignments) > 0 ? local.node_assignments[0] : var.target_node

  # URL шаблона Alpine Linux
  url = "http://download.proxmox.com/images/system/${var.lxc_template}"

  # Разрешаем использовать существующий файл, созданный вне Terraform
  overwrite_unmanaged = true
}

# -----------------------------------------------------------------------------
# Сохранение IP-адресов контейнеров в файл
# -----------------------------------------------------------------------------
resource "local_file" "lxc_ips" {
  count = local.placement_error == "" && var.lxc_count > 0 ? 1 : 0

  depends_on = [proxmox_virtual_environment_container.lxc]

  filename = local.lxc_ips_file
  content  = join("\n", [for ip in local.container_ips : split("/", ip)[0]])

  file_permission = "0644"
}
