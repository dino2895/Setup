#!/bin/bash

# set -ex # Uncomment for debugging
set -e

RED='\033[0;31m'
NC='\033[0m' # No Color
GREEN='\033[0;32m'

# 捕捉 SIGINT（Ctrl-C） 和 SIGTERM 信號
trap "echo -e '\n[${RED}INFO${NC}] Script terminated by user'; exit 0" SIGINT SIGTERM

# 檢查所需工具是否安裝
function check_dependencies() {
  local dependencies=("bash" "curl" "jq" "tzdata")
  local missing=()

  for dep in "${dependencies[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
      missing+=("$dep")
    fi
  done

  if [[ ${#missing[@]} -ne 0 ]]; then
    echo -e "[${RED}ERROR${NC}] Missing dependencies: ${missing[*]}"
    echo -e "[${GREEN}INFO${NC}] Please install the missing tools and try again."
    exit 1
  fi
}

# 檢查依賴
# check_dependencies

if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# 檢查必要環境變數
: "${AUTH_EMAIL:?Please set AUTH_EMAIL}"
: "${AUTH_KEY:?Please set AUTH_KEY}"
: "${ZONE_IDENTIFIER:?Please set ZONE_IDENTIFIER}"
: "${DOMAIN_SUFFIX:?Please set DOMAIN_SUFFIX}"
: "${UPDATE_INTERVAL:=60}"
: "${ENABLE_IPV4:=true}"  # 默認啟用 IPv4 更新
: "${ENABLE_IPV6:=true}"  # 默認啟用 IPv6 更新

# 判斷系統類型並生成持久 ID
if [[ -f "/etc/machine-id" ]]; then
  UUID=$(cat /etc/machine-id)
elif [[ "$OSTYPE" == "darwin"* ]]; then
  # 使用 ioreg 提取硬碟序列號作為持久 ID
  UUID=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F\" '/IOPlatformUUID/{print $4}')
else
  echo -e "[${RED}ERROR${NC}] Unable to determine a persistent machine ID for $OSTYPE"
  exit 1
fi

DOMAIN="${UUID}${DOMAIN_SUFFIX}"

# # 生成 UUID 格式的 domain
# UUID=$(cat /proc/sys/kernel/random/uuid)
# DOMAIN="${UUID}${DOMAIN_SUFFIX}"

echo -e "[${GREEN}INFO${NC}] Generated domain: ${DOMAIN}"


while true; do
  echo -e "[${GREEN}INFO${NC}] Starting IP update process..."

  # 獲取 IPv4 和 IPv6 地址
  IP4=$(curl -s -4 https://api.ipify.org || echo "ERROR")
  IP6=$(curl -s -6 https://api64.ipify.org || echo "ERROR")

  if [[ "$ENABLE_IPV4" == "true" ]]; then
    if [[ "$IP4" == "ERROR" ]]; then
      echo -e "[${RED}ERROR${NC}] Failed to fetch IPv4 address."
    else
      echo -e "[${GREEN}INFO${NC}] Detected IPv4: $IP4"
    fi
  fi

  if [[ "$ENABLE_IPV6" == "true" ]]; then
    if [[ "$IP6" == "ERROR" || -z "$IP6" ]]; then
      echo -e "[${RED}WARNING${NC}] Failed to fetch IPv6 address or IPv6 not supported."
    else
      echo -e "[${GREEN}INFO${NC}] Detected IPv6: $IP6"
    fi
  fi

  # 獲取主機名和正確的 UTC+8 時間
  HOSTNAME=$(hostname)
  TIMESTAMP=$(TZ='Asia/Taipei' date +"[%Y-%m-%d %H:%M:%S] UTC+8")

  # 查詢是否已有 A 和 AAAA 記錄
  if [[ "$ENABLE_IPV4" == "true" ]]; then
    RECORD_A=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_IDENTIFIER}/dns_records?type=A&name=${DOMAIN}" \
      -H "X-Auth-Email: ${AUTH_EMAIL}" \
      -H "X-Auth-Key: ${AUTH_KEY}" \
      -H "Content-Type: application/json")

    RECORD_A_ID=$(echo "$RECORD_A" | jq -r '.result[0].id')
    CURRENT_IP4=$(echo "$RECORD_A" | jq -r '.result[0].content')

    if [[ "$IP4" != "ERROR" ]]; then
      if [[ "$RECORD_A_ID" == "null" ]]; then
        echo -e "[${GREEN}INFO${NC}] A record not found. Creating A record for ${DOMAIN}..."
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_IDENTIFIER}/dns_records" \
          -H "X-Auth-Email: ${AUTH_EMAIL}" \
          -H "X-Auth-Key: ${AUTH_KEY}" \
          -H "Content-Type: application/json" \
          --data '{"type":"A","name":"'"$DOMAIN"'","content":"'"$IP4"'","ttl":120,"proxied":false,"comment":"Updated by '"$HOSTNAME"' at '"$TIMESTAMP"'"}' > /dev/null
      elif [[ "$IP4" != "$CURRENT_IP4" ]]; then
        echo -e "[${GREEN}INFO${NC}] Updating A record for ${DOMAIN} to ${IP4}..."
        curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_IDENTIFIER}/dns_records/${RECORD_A_ID}" \
          -H "X-Auth-Email: ${AUTH_EMAIL}" \
          -H "X-Auth-Key: ${AUTH_KEY}" \
          -H "Content-Type: application/json" \
          --data '{"type":"A","name":"'"$DOMAIN"'","content":"'"$IP4"'","ttl":120,"proxied":false,"comment":"Updated by '"$HOSTNAME"' at '"$TIMESTAMP"'"}' > /dev/null
      else
        echo -e "[${GREEN}INFO${NC}] A record is already up-to-date: $IP4"
      fi
    fi
  fi

  if [[ "$ENABLE_IPV6" == "true" ]]; then
    RECORD_AAAA=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_IDENTIFIER}/dns_records?type=AAAA&name=${DOMAIN}" \
      -H "X-Auth-Email: ${AUTH_EMAIL}" \
      -H "X-Auth-Key: ${AUTH_KEY}" \
      -H "Content-Type: application/json")

    RECORD_AAAA_ID=$(echo "$RECORD_AAAA" | jq -r '.result[0].id')
    CURRENT_IP6=$(echo "$RECORD_AAAA" | jq -r '.result[0].content')

    if [[ "$IP6" != "ERROR" && -n "$IP6" ]]; then
      if [[ "$RECORD_AAAA_ID" == "null" ]]; then
        echo -e "[${GREEN}INFO${NC}] AAAA record not found. Creating AAAA record for ${DOMAIN}..."
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_IDENTIFIER}/dns_records" \
          -H "X-Auth-Email: ${AUTH_EMAIL}" \
          -H "X-Auth-Key: ${AUTH_KEY}" \
          -H "Content-Type: application/json" \
          --data '{"type":"AAAA","name":"'"$DOMAIN"'","content":"'"$IP6"'","ttl":120,"proxied":false,"comment":"Updated by '"$HOSTNAME"' at '"$TIMESTAMP"'"}' > /dev/null
      elif [[ "$IP6" != "$CURRENT_IP6" ]]; then
        echo -e "[${GREEN}INFO${NC}] Updating AAAA record for ${DOMAIN} to ${IP6}..."
        curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_IDENTIFIER}/dns_records/${RECORD_AAAA_ID}" \
          -H "X-Auth-Email: ${AUTH_EMAIL}" \
          -H "X-Auth-Key: ${AUTH_KEY}" \
          -H "Content-Type: application/json" \
          --data '{"type":"AAAA","name":"'"$DOMAIN"'","content":"'"$IP6"'","ttl":120,"proxied":false,"comment":"Updated by '"$HOSTNAME"' at '"$TIMESTAMP"'"}' > /dev/null
      else
        echo -e "[${GREEN}INFO${NC}] AAAA record is already up-to-date: $IP6"
      fi
    fi
  fi

  echo -e "[${GREEN}INFO${NC}] Update completed. Sleeping for ${UPDATE_INTERVAL} seconds..."
  sleep "${UPDATE_INTERVAL}" & wait $!
done
