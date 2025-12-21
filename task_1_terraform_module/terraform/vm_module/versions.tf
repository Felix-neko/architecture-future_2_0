# =============================================================================
# Требования к версиям Terraform и провайдеров
# =============================================================================

terraform {
  # Минимальная версия Terraform
  required_version = ">= 1.0.0"

  required_providers {
    # Провайдер bpg/proxmox для работы с Proxmox VE
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.50.0"
    }

    # Провайдер null для проверки ошибок размещения
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0.0"
    }

    # Провайдер local для сохранения файла с IP-адресами
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0.0"
    }

    # Провайдер external для вызова внешних скриптов
    external = {
      source  = "hashicorp/external"
      version = ">= 2.0.0"
    }
  }
}
