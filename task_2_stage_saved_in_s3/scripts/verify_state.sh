#!/bin/sh
# =============================================================================
# Скрипт проверки Terraform state из S3 и соответствия с Proxmox
# Используется в GitLab CI job verify_infra
#
# Выполняет:
# 1. Скачивание terraform.tfstate файлов из S3 для каждого environment
# 2. Проверка структуры папок в S3 соответствует environments/
# 3. Подключение к Proxmox API и получение списка LXC контейнеров
# 4. Сравнение state с реальной инфраструктурой Proxmox
#
# Переменные окружения:
# - TF_ROOT: путь к terraform конфигурациям
# - NODE_IPS_FILE: путь к файлу с IP адресами Proxmox нод
# - YC_ACCESS_KEY_ID, YC_SECRET_ACCESS_KEY: S3 credentials
# - YC_S3_BUCKET, YC_S3_ENDPOINT: S3 настройки
# - PROXMOX_PASSWORD: пароль root@pam для Proxmox
# - PROXMOX_PORT: порт Proxmox API (по умолчанию 8006)
# =============================================================================

set -e

echo "=============================================="
echo "=== VERIFY INFRASTRUCTURE ==="
echo "=============================================="
echo ""
echo "TF_ROOT: ${TF_ROOT}"
echo "NODE_IPS_FILE: ${NODE_IPS_FILE}"
echo "YC_S3_BUCKET: ${YC_S3_BUCKET}"
echo ""

# -----------------------------------------------------------------------------
# Проверка S3 credentials
# -----------------------------------------------------------------------------
if [ -z "$YC_ACCESS_KEY_ID" ] || [ -z "$YC_SECRET_ACCESS_KEY" ]; then
    echo "[ERROR] S3 credentials not set"
    exit 1
fi

# -----------------------------------------------------------------------------
# Настройка AWS CLI для Yandex S3
# -----------------------------------------------------------------------------
mkdir -p ~/.aws
echo "[default]" > ~/.aws/credentials
echo "aws_access_key_id = $YC_ACCESS_KEY_ID" >> ~/.aws/credentials
echo "aws_secret_access_key = $YC_SECRET_ACCESS_KEY" >> ~/.aws/credentials
echo "[default]" > ~/.aws/config
echo "region = ru-central1" >> ~/.aws/config

# -----------------------------------------------------------------------------
# STEP 1: Проверка структуры S3 и скачивание state файлов
# -----------------------------------------------------------------------------
echo ""
echo "=== STEP 1: Download state files from S3 ==="
echo ""

# Показываем текущую структуру S3
echo "Current S3 structure:"
aws s3 ls "s3://${YC_S3_BUCKET}/terraform-states/" --recursive --endpoint-url "${YC_S3_ENDPOINT}" 2>/dev/null || echo "  (empty)"
echo ""

# Получаем список environments из репозитория
ENVS_IN_REPO=""
for ENV_DIR in ${TF_ROOT}/environments/*/; do
    if [ -d "$ENV_DIR" ]; then
        ENV_NAME=$(basename "$ENV_DIR")
        ENVS_IN_REPO="$ENVS_IN_REPO $ENV_NAME"
    fi
done
echo "Environments in repo:$ENVS_IN_REPO"
echo ""

# Скачиваем state файлы из S3
STATES_DOWNLOADED=0
STATES_MISSING=0

for ENV_NAME in $ENVS_IN_REPO; do
    S3_PATH="s3://${YC_S3_BUCKET}/terraform-states/${ENV_NAME}/terraform.tfstate"
    LOCAL_DIR="/tmp/states/${ENV_NAME}"
    LOCAL_FILE="${LOCAL_DIR}/terraform.tfstate"
    
    echo "--- $ENV_NAME ---"
    
    # Проверяем существование в S3
    if aws s3 ls "$S3_PATH" --endpoint-url "${YC_S3_ENDPOINT}" > /dev/null 2>&1; then
        mkdir -p "$LOCAL_DIR"
        aws s3 cp "$S3_PATH" "$LOCAL_FILE" --endpoint-url "${YC_S3_ENDPOINT}" --quiet
        
        # Проверяем валидность JSON
        if jq -e .version "$LOCAL_FILE" > /dev/null 2>&1; then
            VERSION=$(jq -r .version "$LOCAL_FILE")
            SERIAL=$(jq -r .serial "$LOCAL_FILE")
            RESOURCE_COUNT=$(jq -r '.resources | length' "$LOCAL_FILE")
            echo "  [OK] Downloaded (version=$VERSION, serial=$SERIAL, resources=$RESOURCE_COUNT)"
            STATES_DOWNLOADED=$((STATES_DOWNLOADED + 1))
        else
            echo "  [ERROR] Invalid JSON in state file"
        fi
    else
        echo "  [MISSING] No state in S3"
        STATES_MISSING=$((STATES_MISSING + 1))
    fi
done

echo ""
echo "Summary: $STATES_DOWNLOADED downloaded, $STATES_MISSING missing"

# -----------------------------------------------------------------------------
# STEP 2: Получение IP адреса Proxmox из .node_ips файла
# -----------------------------------------------------------------------------
echo ""
echo "=== STEP 2: Get Proxmox connection info ==="
echo ""

# Читаем первый IP из .node_ips файла
if [ -f "${NODE_IPS_FILE}" ]; then
    PROXMOX_HOST=$(head -1 "${NODE_IPS_FILE}")
    echo "PROXMOX_HOST from ${NODE_IPS_FILE}: $PROXMOX_HOST"
else
    echo "[ERROR] File ${NODE_IPS_FILE} not found"
    echo "Cannot verify Proxmox infrastructure without node IPs"
    exit 1
fi

# Устанавливаем порт
PROXMOX_PORT="${PROXMOX_PORT:-8006}"
echo "PROXMOX_PORT: $PROXMOX_PORT"

# Проверяем пароль
if [ -z "$PROXMOX_PASSWORD" ]; then
    echo "[ERROR] PROXMOX_PASSWORD not set"
    echo "Set PROXMOX_PASSWORD CI variable to enable infrastructure verification"
    exit 1
fi
echo "PROXMOX_PASSWORD: (set)"

# -----------------------------------------------------------------------------
# STEP 3: Подключение к Proxmox API
# -----------------------------------------------------------------------------
echo ""
echo "=== STEP 3: Connect to Proxmox API ==="
echo ""

PROXMOX_URL="https://${PROXMOX_HOST}:${PROXMOX_PORT}"
echo "Connecting to: $PROXMOX_URL"

# Проверяем доступность Proxmox API
echo "Testing connection..."
if ! curl -s -k --connect-timeout 10 "${PROXMOX_URL}/api2/json/version" > /dev/null 2>&1; then
    echo "[ERROR] Proxmox API not reachable at ${PROXMOX_URL}"
    echo ""
    echo "Proxmox должен быть доступен для верификации инфраструктуры."
    echo "Проверьте:"
    echo "  1. Proxmox ноды включены"
    echo "  2. IP адрес в .node_ips корректен"
    echo "  3. Сеть между runner и Proxmox работает"
    echo ""
    exit 1
fi

# Получаем API ticket
TICKET_RESPONSE=$(curl -s -k -d "username=root@pam&password=${PROXMOX_PASSWORD}" \
    "${PROXMOX_URL}/api2/json/access/ticket" 2>&1)

TICKET=$(echo "$TICKET_RESPONSE" | jq -r '.data.ticket // empty')

if [ -z "$TICKET" ]; then
    echo "[WARNING] Failed to get Proxmox API ticket"
    echo "Response: $TICKET_RESPONSE"
    echo "Skipping Proxmox verification (auth issue)"
    exit 0
fi

echo "[OK] Got Proxmox API ticket"

# Получаем список нод
NODES=$(curl -s -k -b "PVEAuthCookie=$TICKET" \
    "${PROXMOX_URL}/api2/json/nodes" | jq -r '.data[].node')
echo "Proxmox nodes: $NODES"

# -----------------------------------------------------------------------------
# STEP 4: Получение списка LXC контейнеров из Proxmox
# -----------------------------------------------------------------------------
echo ""
echo "=== STEP 4: Get LXC containers from Proxmox ==="
echo ""

# Сохраняем все LXC в файл для сравнения
> /tmp/proxmox_lxc.txt

for NODE in $NODES; do
    echo "--- Node: $NODE ---"
    
    LXC_LIST=$(curl -s -k -b "PVEAuthCookie=$TICKET" \
        "${PROXMOX_URL}/api2/json/nodes/${NODE}/lxc")
    
    # Выводим и сохраняем
    echo "$LXC_LIST" | jq -r '.data[] | "  VMID=\(.vmid) Name=\(.name) Status=\(.status)"'
    echo "$LXC_LIST" | jq -r '.data[] | "\(.vmid)|\(.name)|\(.status)"' >> /tmp/proxmox_lxc.txt
done

PROXMOX_LXC_COUNT=$(wc -l < /tmp/proxmox_lxc.txt | tr -d ' ')
echo ""
echo "Total LXC in Proxmox: $PROXMOX_LXC_COUNT"

# -----------------------------------------------------------------------------
# STEP 5: Сравнение Terraform state с Proxmox
# -----------------------------------------------------------------------------
echo ""
echo "=== STEP 5: Compare state with Proxmox ==="
echo ""

MATCH_COUNT=0
MISMATCH_COUNT=0

for STATE_FILE in /tmp/states/*/terraform.tfstate; do
    if [ ! -f "$STATE_FILE" ]; then
        continue
    fi
    
    ENV_NAME=$(dirname "$STATE_FILE" | xargs basename)
    echo "--- Environment: $ENV_NAME ---"
    
    # Извлекаем LXC из state (ищем разные типы ресурсов proxmox)
    VMIDS_IN_STATE=$(jq -r '
        .resources[]? | 
        select(.type == "proxmox_lxc" or .type == "proxmox_virtual_environment_container") | 
        .instances[]?.attributes.vmid // .instances[]?.attributes.vm_id
    ' "$STATE_FILE" 2>/dev/null | sort -u)
    
    # Также проверяем outputs
    OUTPUT_VMIDS=$(jq -r '.outputs.lxc_vmids.value[]?' "$STATE_FILE" 2>/dev/null | sort -u)
    
    if [ -n "$OUTPUT_VMIDS" ]; then
        VMIDS_IN_STATE="$OUTPUT_VMIDS"
    fi
    
    if [ -z "$VMIDS_IN_STATE" ]; then
        echo "  No LXC VMIDs found in state"
        continue
    fi
    
    echo "  VMIDs in state: $(echo $VMIDS_IN_STATE | tr '\n' ' ')"
    
    # Проверяем каждый VMID
    for VMID in $VMIDS_IN_STATE; do
        if grep -q "^${VMID}|" /tmp/proxmox_lxc.txt; then
            LXC_INFO=$(grep "^${VMID}|" /tmp/proxmox_lxc.txt)
            LXC_NAME=$(echo "$LXC_INFO" | cut -d'|' -f2)
            LXC_STATUS=$(echo "$LXC_INFO" | cut -d'|' -f3)
            echo "  [MATCH] VMID=$VMID exists in Proxmox (name=$LXC_NAME, status=$LXC_STATUS)"
            MATCH_COUNT=$((MATCH_COUNT + 1))
        else
            echo "  [MISMATCH] VMID=$VMID in state but NOT in Proxmox!"
            MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
        fi
    done
done

# -----------------------------------------------------------------------------
# ИТОГ
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "=== VERIFICATION SUMMARY ==="
echo "=============================================="
echo ""
echo "States downloaded: $STATES_DOWNLOADED"
echo "States missing:    $STATES_MISSING"
echo "LXC in Proxmox:    $PROXMOX_LXC_COUNT"
echo "Matches:           $MATCH_COUNT"
echo "Mismatches:        $MISMATCH_COUNT"
echo ""

# -----------------------------------------------------------------------------
# STEP 6: Проверка соответствия state спецификации terraform
# -----------------------------------------------------------------------------
echo ""
echo "=== STEP 6: Check state matches terraform specification ==="
echo ""

SPEC_MISMATCH=0

for ENV_NAME in $ENVS_IN_REPO; do
    ENV_DIR="${TF_ROOT}/environments/${ENV_NAME}"
    TFVARS_FILE="${ENV_DIR}/terraform.tfvars"
    VARS_FILE="${ENV_DIR}/variables.tf"
    STATE_FILE="/tmp/states/${ENV_NAME}/terraform.tfstate"
    
    echo "--- $ENV_NAME ---"
    
    # Получаем ожидаемое количество LXC из terraform.tfvars или variables.tf
    EXPECTED_COUNT=0
    if [ -f "$TFVARS_FILE" ]; then
        EXPECTED_COUNT=$(grep -E "^lxc_count\s*=" "$TFVARS_FILE" 2>/dev/null | sed 's/.*=\s*//' | tr -d ' "' || echo "0")
    fi
    if [ -z "$EXPECTED_COUNT" ] || [ "$EXPECTED_COUNT" = "0" ]; then
        if [ -f "$VARS_FILE" ]; then
            EXPECTED_COUNT=$(grep -A2 'variable "lxc_count"' "$VARS_FILE" 2>/dev/null | grep "default" | sed 's/.*=\s*//' | tr -d ' "' || echo "0")
        fi
    fi
    [ -z "$EXPECTED_COUNT" ] && EXPECTED_COUNT=0
    
    echo "  Expected LXC count (from spec): $EXPECTED_COUNT"
    
    # Получаем фактическое количество из state
    ACTUAL_COUNT=0
    if [ -f "$STATE_FILE" ]; then
        ACTUAL_COUNT=$(jq -r '.resources | length' "$STATE_FILE" 2>/dev/null || echo "0")
    fi
    echo "  Actual resources in state: $ACTUAL_COUNT"
    
    # Проверяем соответствие
    if [ "$EXPECTED_COUNT" -gt 0 ] && [ "$ACTUAL_COUNT" -eq 0 ]; then
        echo "  [ERROR] Spec requires $EXPECTED_COUNT LXC but state is empty!"
        echo "  Terraform apply may not have been run."
        SPEC_MISMATCH=$((SPEC_MISMATCH + 1))
    elif [ "$EXPECTED_COUNT" -gt 0 ]; then
        echo "  [OK] State has resources as expected"
    else
        echo "  [OK] No LXC expected, state is consistent"
    fi
done

# -----------------------------------------------------------------------------
# ИТОГ
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "=== VERIFICATION SUMMARY ==="
echo "=============================================="
echo ""
echo "States downloaded: $STATES_DOWNLOADED"
echo "States missing:    $STATES_MISSING"
echo "LXC in Proxmox:    $PROXMOX_LXC_COUNT"
echo "Matches:           $MATCH_COUNT"
echo "Mismatches:        $MISMATCH_COUNT"
echo "Spec mismatches:   $SPEC_MISMATCH"
echo ""

if [ "$SPEC_MISMATCH" -gt 0 ]; then
    echo "[ERROR] State does not match terraform specification!"
    echo "Expected LXC resources are missing from state."
    echo "Run 'terraform apply' to create the infrastructure."
    exit 1
elif [ "$MISMATCH_COUNT" -gt 0 ]; then
    echo "[ERROR] Some resources in state do not exist in Proxmox!"
    echo "This may indicate drift between Terraform state and actual infrastructure."
    exit 1
elif [ "$MATCH_COUNT" -eq 0 ] && [ "$PROXMOX_LXC_COUNT" -eq 0 ]; then
    echo "[OK] No LXC in Proxmox and no LXC in state - consistent"
else
    echo "[OK] All resources in state exist in Proxmox"
fi

echo ""
echo "=== Verification complete ==="
