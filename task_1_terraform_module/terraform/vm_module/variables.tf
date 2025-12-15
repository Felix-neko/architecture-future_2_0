# =============================================================================
# Входные переменные Terraform-модуля для создания LXC-контейнеров в Proxmox
# =============================================================================

variable "proxmox_node_ips" {
  description = "Список IP-адресов нод Proxmox-кластера"
  type        = list(string)
  default     = []  # По умолчанию читается из файла .node_ips
}

variable "proxmox_root_password" {
  description = "Пароль для root-пользователя на нодах Proxmox"
  type        = string
  default     = "mega_root_password"
  sensitive   = true
}

variable "lxc_count" {
  description = "Количество LXC-контейнеров для создания"
  type        = number
  default     = 2
}

variable "lxc_cpus" {
  description = "Количество CPU-ядер для каждого LXC-контейнера"
  type        = number
  default     = 2
}

variable "lxc_memory_mb" {
  description = "Объём RAM для каждого LXC-контейнера в мегабайтах"
  type        = number
  default     = 8192  # 8 ГБ
}

variable "lxc_disk_gb" {
  description = "Размер диска для каждого LXC-контейнера в гигабайтах"
  type        = number
  default     = 10
}

variable "ssh_public_key_path" {
  description = "Путь к публичному SSH-ключу для доступа к LXC-контейнерам"
  type        = string
  default     = ""  # По умолчанию читается из vm_access_key.pub
}

variable "ssh_private_key_path" {
  description = "Путь к приватному SSH-ключу для подключения к Proxmox-нодам"
  type        = string
  default     = ""  # По умолчанию читается из vm_access_key
}

variable "network_cidr" {
  description = "CIDR-маска подсети для LXC-контейнеров (например, 192.168.122.0/24)"
  type        = string
  default     = "192.168.122.0/24"
}

variable "start_vmid" {
  description = "Начальный VMID для LXC-контейнеров"
  type        = number
  default     = 100
}

variable "lxc_template" {
  description = "Шаблон LXC-контейнера для использования"
  type        = string
  default     = "alpine-3.22-default_20250617_amd64.tar.xz"
}

variable "target_node" {
  description = "Имя целевой ноды Proxmox для размещения контейнеров"
  type        = string
  default     = "pve-node-1"
}

variable "lxc_name_prefix" {
  description = "Префикс имени для LXC-контейнеров"
  type        = string
  default     = "lxc-container"
}

variable "enable_resource_check" {
  description = "Включить проверку ресурсов на нодах перед созданием контейнеров"
  type        = bool
  default     = true
}

variable "ip_start_offset" {
  description = "Начальное смещение для IP-адресов контейнеров (например, 100 -> 192.168.122.100)"
  type        = number
  default     = 100
}

variable "output_dir" {
  description = "Директория для сохранения выходных файлов (.lxc_ips). Если пусто - используется текущая директория"
  type        = string
  default     = ""
}
