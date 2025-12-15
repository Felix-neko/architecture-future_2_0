# =============================================================================
# Окружение DEV-2 (второй экземпляр dev-окружения)
# Использует общий модуль vm_module с собственным terraform-состоянием
# =============================================================================

# Путь к модулю
module "lxc_cluster" {
  source = "../../vm_module"

  # Основные параметры контейнеров
  lxc_count       = var.lxc_count
  lxc_cpus        = var.lxc_cpus
  lxc_memory_mb   = var.lxc_memory_mb
  lxc_disk_gb     = var.lxc_disk_gb
  lxc_name_prefix = var.lxc_name_prefix
  lxc_template    = var.lxc_template

  # Идентификаторы (уникальные для каждого окружения)
  start_vmid      = var.start_vmid
  ip_start_offset = var.ip_start_offset

  # Подключение к Proxmox
  proxmox_node_ips      = var.proxmox_node_ips
  proxmox_root_password = var.proxmox_root_password
  target_node           = var.target_node

  # Сеть
  network_cidr = var.network_cidr

  # SSH-ключи
  ssh_public_key_path  = var.ssh_public_key_path
  ssh_private_key_path = var.ssh_private_key_path

  # Проверка ресурсов
  enable_resource_check = var.enable_resource_check
}

# Выходные переменные
output "lxc_ips" {
  description = "IP-адреса созданных контейнеров"
  value       = module.lxc_cluster.lxc_ips
}

output "lxc_vmids" {
  description = "VMID созданных контейнеров"
  value       = module.lxc_cluster.lxc_vmids
}

output "lxc_names" {
  description = "Имена созданных контейнеров"
  value       = module.lxc_cluster.lxc_names
}

output "node_assignments" {
  description = "Назначения контейнеров на ноды"
  value       = module.lxc_cluster.node_assignments
}

output "placement_error" {
  description = "Ошибка размещения (если есть)"
  value       = module.lxc_cluster.placement_error
}

output "lxc_ips_file" {
  description = "Путь к файлу с IP-адресами"
  value       = module.lxc_cluster.lxc_ips_file
}
