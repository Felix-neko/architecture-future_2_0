# =============================================================================
# Выходные переменные Terraform-модуля для LXC-контейнеров
# =============================================================================

output "lxc_ips" {
  description = "Список IP-адресов созданных LXC-контейнеров"
  value       = [for container in proxmox_virtual_environment_container.lxc : container.initialization[0].ip_config[0].ipv4[0].address]
}

output "lxc_vmids" {
  description = "Список VMID созданных LXC-контейнеров"
  value       = [for container in proxmox_virtual_environment_container.lxc : container.vm_id]
}

output "lxc_names" {
  description = "Список имён созданных LXC-контейнеров"
  value       = [for container in proxmox_virtual_environment_container.lxc : container.description]
}

output "proxmox_api_endpoint" {
  description = "Endpoint Proxmox API, использованный для подключения"
  value       = local.proxmox_api_url
}

output "node_assignments" {
  description = "Назначения контейнеров на ноды Proxmox"
  value       = local.node_assignments
}

output "placement_error" {
  description = "Ошибка размещения (если есть)"
  value       = local.placement_error
}

output "lxc_ips_file" {
  description = "Путь к файлу с IP-адресами контейнеров"
  value       = local.lxc_ips_file
}
