#!/bin/bash
# =============================================================================
# Скрипт для проверки ресурсов на Proxmox-нодах и выбора подходящей ноды
# Используется как external data source в Terraform
#
# Входные данные (JSON через stdin):
#   - node_ips: список IP-адресов нод через запятую
#   - required_memory_mb: требуемая память в МБ
#   - required_cpus: требуемое количество CPU-ядер
#   - required_disk_gb: требуемый размер диска в ГБ
#   - ssh_key_path: путь к SSH-ключу
#   - ssh_password: пароль для SSH (если нет ключа)
#   - container_count: количество контейнеров для размещения
#
# Выходные данные (JSON):
#   - selected_nodes: JSON-массив нод с назначенными контейнерами
#   - error: сообщение об ошибке (если есть)
# =============================================================================

set -e

# Читаем входные данные из stdin (JSON)
eval "$(jq -r '@sh "
NODE_IPS=\(.node_ips)
REQUIRED_MEMORY_MB=\(.required_memory_mb)
REQUIRED_CPUS=\(.required_cpus)
REQUIRED_DISK_GB=\(.required_disk_gb)
SSH_KEY_PATH=\(.ssh_key_path)
SSH_PASSWORD=\(.ssh_password)
CONTAINER_COUNT=\(.container_count)
"')"

# Преобразуем список IP в массив
IFS=',' read -ra NODE_IPS_ARRAY <<< "$NODE_IPS"

# Функция для SSH-подключения
ssh_cmd() {
    local ip=$1
    shift
    if [ -n "$SSH_KEY_PATH" ] && [ -f "$SSH_KEY_PATH" ]; then
        ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=10 -o BatchMode=yes root@"$ip" "$@" 2>/dev/null
    else
        sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=10 root@"$ip" "$@" 2>/dev/null
    fi
}

# Функция для получения ресурсов ноды
get_node_resources() {
    local ip=$1
    local node_name=$2
    
    # Получаем информацию о памяти (в КБ, конвертируем в МБ)
    local mem_info=$(ssh_cmd "$ip" "cat /proc/meminfo")
    local total_mem_kb=$(echo "$mem_info" | grep "^MemTotal:" | awk '{print $2}')
    local free_mem_kb=$(echo "$mem_info" | grep "^MemAvailable:" | awk '{print $2}')
    
    # Если MemAvailable недоступен, используем MemFree + Buffers + Cached
    if [ -z "$free_mem_kb" ]; then
        local mem_free=$(echo "$mem_info" | grep "^MemFree:" | awk '{print $2}')
        local buffers=$(echo "$mem_info" | grep "^Buffers:" | awk '{print $2}')
        local cached=$(echo "$mem_info" | grep "^Cached:" | awk '{print $2}')
        free_mem_kb=$((mem_free + buffers + cached))
    fi
    
    local total_mem_mb=$((total_mem_kb / 1024))
    local free_mem_mb=$((free_mem_kb / 1024))
    
    # Получаем информацию о CPU (количество ядер)
    local total_cpus=$(ssh_cmd "$ip" "nproc")
    
    # Получаем загрузку CPU (средняя за 1 минуту)
    local load_avg=$(ssh_cmd "$ip" "cat /proc/loadavg | awk '{print \$1}'")
    local used_cpus=$(echo "$load_avg" | awk '{printf "%.0f", $1}')
    local free_cpus=$((total_cpus - used_cpus))
    if [ "$free_cpus" -lt 0 ]; then
        free_cpus=0
    fi
    
    # Получаем информацию о диске local-lvm
    local disk_info=$(ssh_cmd "$ip" "pvesm status 2>/dev/null | grep 'local-lvm' || echo 'local-lvm unknown 0 0 0'")
    local total_disk_kb=$(echo "$disk_info" | awk '{print $4}')
    local used_disk_kb=$(echo "$disk_info" | awk '{print $5}')
    
    # Если pvesm не вернул данные, пробуем через lvs
    if [ "$total_disk_kb" = "0" ] || [ -z "$total_disk_kb" ]; then
        disk_info=$(ssh_cmd "$ip" "vgs --noheadings --units g --nosuffix -o vg_size,vg_free pve 2>/dev/null || echo '0 0'")
        local total_disk_gb=$(echo "$disk_info" | awk '{printf "%.0f", $1}')
        local free_disk_gb=$(echo "$disk_info" | awk '{printf "%.0f", $2}')
    else
        local total_disk_gb=$((total_disk_kb / 1024 / 1024))
        local free_disk_gb=$(((total_disk_kb - used_disk_kb) / 1024 / 1024))
    fi
    
    # Получаем память, уже использованную LXC-контейнерами
    local lxc_mem_used=$(ssh_cmd "$ip" "pct list 2>/dev/null | tail -n +2 | awk '{print \$1}' | while read vmid; do pct config \$vmid 2>/dev/null | grep '^memory:' | awk '{print \$2}'; done | awk '{s+=\$1} END {print s+0}'")
    
    # Корректируем свободную память с учётом LXC
    local adjusted_free_mem_mb=$((free_mem_mb))
    
    echo "$node_name $ip $total_mem_mb $adjusted_free_mem_mb $total_cpus $free_cpus $total_disk_gb $free_disk_gb $lxc_mem_used"
}

# Собираем информацию о всех нодах
declare -a NODE_INFO
for ip in "${NODE_IPS_ARRAY[@]}"; do
    # Получаем имя ноды
    node_name=$(ssh_cmd "$ip" "hostname" 2>/dev/null || echo "unknown")
    if [ "$node_name" = "unknown" ]; then
        continue
    fi
    
    info=$(get_node_resources "$ip" "$node_name")
    NODE_INFO+=("$info")
done

if [ ${#NODE_INFO[@]} -eq 0 ]; then
    echo '{"error": "Не удалось получить информацию ни об одной ноде", "selected_nodes": "[]", "node_assignments": ""}'
    exit 0
fi

# Алгоритм размещения контейнеров с учётом ресурсов
# Для каждого контейнера выбираем ноду с достаточными ресурсами
declare -A NODE_ALLOCATED_MEM
declare -A NODE_ALLOCATED_CPUS
declare -A NODE_ALLOCATED_DISK
declare -A NODE_FREE_MEM
declare -A NODE_FREE_CPUS
declare -A NODE_FREE_DISK
declare -A NODE_NAMES_MAP

# Инициализируем свободные ресурсы
for info in "${NODE_INFO[@]}"; do
    read -r name ip total_mem free_mem total_cpus free_cpus total_disk free_disk lxc_used <<< "$info"
    NODE_FREE_MEM["$name"]=$free_mem
    NODE_FREE_CPUS["$name"]=$free_cpus
    NODE_FREE_DISK["$name"]=$free_disk
    NODE_ALLOCATED_MEM["$name"]=0
    NODE_ALLOCATED_CPUS["$name"]=0
    NODE_ALLOCATED_DISK["$name"]=0
    NODE_NAMES_MAP["$name"]=$ip
done

# Размещаем контейнеры
declare -a ASSIGNMENTS
PLACEMENT_ERROR=""

for i in $(seq 1 "$CONTAINER_COUNT"); do
    PLACED=false
    
    for info in "${NODE_INFO[@]}"; do
        read -r name ip total_mem free_mem total_cpus free_cpus total_disk free_disk lxc_used <<< "$info"
        
        # Вычисляем оставшиеся ресурсы с учётом уже запланированных контейнеров
        remaining_mem=$((NODE_FREE_MEM["$name"] - NODE_ALLOCATED_MEM["$name"]))
        remaining_cpus=$((NODE_FREE_CPUS["$name"] - NODE_ALLOCATED_CPUS["$name"]))
        remaining_disk=$((NODE_FREE_DISK["$name"] - NODE_ALLOCATED_DISK["$name"]))
        
        # Проверяем, достаточно ли ресурсов
        if [ "$remaining_mem" -ge "$REQUIRED_MEMORY_MB" ] && \
           [ "$remaining_cpus" -ge "$REQUIRED_CPUS" ] && \
           [ "$remaining_disk" -ge "$REQUIRED_DISK_GB" ]; then
            # Размещаем контейнер на этой ноде
            ASSIGNMENTS+=("$name")
            NODE_ALLOCATED_MEM["$name"]=$((NODE_ALLOCATED_MEM["$name"] + REQUIRED_MEMORY_MB))
            NODE_ALLOCATED_CPUS["$name"]=$((NODE_ALLOCATED_CPUS["$name"] + REQUIRED_CPUS))
            NODE_ALLOCATED_DISK["$name"]=$((NODE_ALLOCATED_DISK["$name"] + REQUIRED_DISK_GB))
            PLACED=true
            break
        fi
    done
    
    if [ "$PLACED" = false ]; then
        PLACEMENT_ERROR="Недостаточно ресурсов для размещения контейнера $i. Требуется: ${REQUIRED_MEMORY_MB}MB RAM, ${REQUIRED_CPUS} CPU, ${REQUIRED_DISK_GB}GB диска. Доступные ноды не имеют достаточно свободных ресурсов."
        break
    fi
done

# Формируем JSON-вывод
# ВАЖНО: Terraform external data source требует плоский JSON со строковыми значениями
if [ -n "$PLACEMENT_ERROR" ]; then
    # Экранируем кавычки в сообщении об ошибке
    ESCAPED_ERROR=$(echo "$PLACEMENT_ERROR" | sed 's/"/\\"/g')
    cat <<EOF
{"error": "$ESCAPED_ERROR", "selected_nodes": "", "node_assignments": ""}
EOF
else
    # Формируем строку назначений (node1,node2,node3)
    ASSIGNMENTS_STR=$(IFS=','; echo "${ASSIGNMENTS[*]}")
    
    # Формируем список уникальных нод через запятую (не JSON-массив!)
    declare -A UNIQUE_NODES
    for node in "${ASSIGNMENTS[@]}"; do
        UNIQUE_NODES["$node"]=1
    done
    
    NODES_LIST=""
    first=true
    for node in "${!UNIQUE_NODES[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            NODES_LIST+=","
        fi
        NODES_LIST+="$node"
    done
    
    cat <<EOF
{"error": "", "selected_nodes": "$NODES_LIST", "node_assignments": "$ASSIGNMENTS_STR"}
EOF
fi
