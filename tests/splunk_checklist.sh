#!/usr/bin/env bash
# Checklist de validación post-deploy — variante Splunk
# Cubre: VMs levantadas / usuarios de dominio / SIEM up / endpoints reportando / Sysmon.
#
# Requiere: curl, jq. Opcional: ldapwhoami (paquete ldap-utils) para el check de
# usuarios de dominio.
#
# Uso:
#   ./tests/splunk_checklist.sh --base   # ranges/splunk-base.yml  (1 AD + 1 WRK)
#   ./tests/splunk_checklist.sh --dual   # ranges/splunk-dual.yml  (2 AD + 2 WRK)
#   ./tests/splunk_checklist.sh --adcs   # ranges/splunk-adcs.yml  (1 AD + ADCS + 1 WRK)
#
# Override de red vía env vars si la autodetección falla:
#   RANGE_PREFIX=10.2 ./tests/splunk_checklist.sh --dual

set -uo pipefail

usage() {
  echo "Usage: $0 <--base|--dual|--adcs>"
  exit 1
}

PROFILE="${1:-}"
case "$PROFILE" in
  --base|--dual|--adcs) ;;
  *) usage ;;
esac

SPLUNK_USER="admin"
SPLUNK_PASS="thisisapassword"
DOMAIN_ADMIN_PASS="password"
DOMAIN_USER_PASS="password"
LOOKBACK="1h"

PASS=0
FAIL=0
WARN=0

ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
bad()  { printf "  \033[31m✗\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); }
warn() { printf "  \033[33m~\033[0m %s\n" "$1"; WARN=$((WARN+1)); }
section() { printf "\n=== %s ===\n" "$1"; }

# --- Resolver prefijo de red del range (10.<rangeNumber>) ---
if [[ -z "${RANGE_PREFIX:-}" ]]; then
  RANGE_NUM=$(ludus range status --json 2>/dev/null | jq -r '.rangeNumber // .range_number // empty' 2>/dev/null)
  if [[ -n "$RANGE_NUM" ]]; then
    RANGE_PREFIX="10.${RANGE_NUM}"
  else
    echo "No se pudo autodetectar el prefijo de red desde 'ludus range status --json'."
    echo "Define RANGE_PREFIX manualmente, p.ej.: RANGE_PREFIX=10.2 $0 ${PROFILE}"
    exit 1
  fi
fi

BASE="${RANGE_PREFIX}.20"
SPLUNK_IP="${BASE}.1"
DC1_IP="${BASE}.11"
DC2_IP="${BASE}.12"
SPLUNK_URL="https://${SPLUNK_IP}:8089"

# --- Forma del perfil ---
case "$PROFILE" in
  --base)
    VM_PATTERNS=(
      "splunk:-splunk$"
      "DC01-2022:-ad-dc-win2022-server-x64$"
      "WIN11-22H2-1:-ad-win11-22h2-enterprise-x64-1$"
    )
    declare -A DOMAINS=( ["thruntops.domain"]="$DC1_IP" )
    ;;
  --dual)
    VM_PATTERNS=(
      "splunk:-splunk$"
      "DC01-2022:-ad-dc-win2022-server-x64$"
      "DC01-SEC:-ad-dc-win2022-secondary$"
      "WIN11-22H2-1:-ad-win11-22h2-enterprise-x64-1$"
      "WIN11-22H2-2:-ad-win11-22h2-enterprise-x64-2$"
    )
    declare -A DOMAINS=(
      ["thruntops.domain"]="$DC1_IP"
      ["secondary.thruntops.domain"]="$DC2_IP"
    )
    ;;
  --adcs)
    VM_PATTERNS=(
      "splunk:-splunk$"
      "DC01-2022:-ad-dc-win2022-server-x64$"
      "ADCS:-adcs$"
      "WIN11-22H2-1:-ad-win11-22h2-enterprise-x64-1$"
    )
    declare -A DOMAINS=( ["thruntops.domain"]="$DC1_IP" )
    ;;
esac

echo "Perfil: ${PROFILE#--}  |  Prefijo de red: ${RANGE_PREFIX}  (splunk: ${SPLUNK_IP})"

# ------------------------------------------------------------------
section "1. VMs levantadas"
# ------------------------------------------------------------------
STATUS_JSON=$(ludus range status --json 2>/dev/null)
if [[ -z "$STATUS_JSON" ]]; then
  bad "No se pudo obtener 'ludus range status --json'"
else
  # El campo .name de 'ludus range status --json' es el vm_name de Proxmox, no el
  # hostname de Windows/AD — hay que matchear contra el patrón de vm_name real.
  for entry in "${VM_PATTERNS[@]}"; do
    label="${entry%%:*}"
    pattern="${entry#*:}"
    powered=$(echo "$STATUS_JSON" | jq -r --arg p "$pattern" '
      [.VMs[]? // .vms[]? | select((.name // .Name // "") | test($p))] | .[0] |
      (.poweredOn // .powered_on // .PoweredOn // empty)' 2>/dev/null)
    case "$powered" in
      true)  ok "$label — encendida" ;;
      false) bad "$label — apagada" ;;
      *)     warn "$label — no se pudo determinar el estado (revisar 'ludus range status' manualmente)" ;;
    esac
  done
fi

# ------------------------------------------------------------------
section "2. Usuarios — dominio"
# ------------------------------------------------------------------
if ! command -v ldapwhoami >/dev/null 2>&1; then
  warn "ldapwhoami no instalado (paquete ldap-utils) — no se puede validar autenticación de dominio"
else
  for domain in "${!DOMAINS[@]}"; do
    dc_ip="${DOMAINS[$domain]}"
    for user in "domainadmin:$DOMAIN_ADMIN_PASS" "domainuser:$DOMAIN_USER_PASS"; do
      uname="${user%%:*}"
      upass="${user##*:}"
      if ldapwhoami -x -H "ldap://${dc_ip}" -D "${uname}@${domain}" -w "${upass}" >/dev/null 2>&1; then
        ok "${domain}\\${uname} autentica (${dc_ip})"
      else
        bad "${domain}\\${uname} NO autentica (${dc_ip})"
      fi
    done
  done
fi

# ------------------------------------------------------------------
section "3. SIEM (Splunk) levantado"
# ------------------------------------------------------------------
info_response=$(curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" "${SPLUNK_URL}/services/server/info?output_mode=json" 2>/dev/null)
server_name=$(echo "$info_response" | jq -r '.entry[0].content.serverName // empty' 2>/dev/null)

if [[ -n "$server_name" ]]; then
  ok "Splunk disponible (${SPLUNK_URL}, serverName=${server_name})"
else
  bad "No se pudo contactar con Splunk (${SPLUNK_URL})"
fi

# ------------------------------------------------------------------
section "4. Endpoints dados de alta y reportando"
# ------------------------------------------------------------------
RANGE_ID=$(echo "$STATUS_JSON" | jq -r '.rangeID // empty' 2>/dev/null)
EXPECTED=()
for entry in "${VM_PATTERNS[@]}"; do
  label="${entry%%:*}"
  [[ "$label" == "splunk" ]] && continue
  EXPECTED+=("${RANGE_ID}-${label}")
done

SEARCH="search index=* earliest=-${LOOKBACK} | stats latest(_time) as last_seen count by host | eval last_seen=strftime(last_seen, \"%Y-%m-%dT%H:%M:%S\") | fields host last_seen count"

search_response=$(curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" "${SPLUNK_URL}/services/search/jobs/export" \
  --data-urlencode "search=${SEARCH}" -d "output_mode=json" -d "exec_mode=oneshot" -d "count=0" 2>/dev/null)

declare -A HOST_LASTSEEN
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  host=$(echo "$line" | jq -r '.result.host // empty' 2>/dev/null)
  last=$(echo "$line" | jq -r '.result.last_seen // "never"' 2>/dev/null)
  [[ -n "$host" ]] && HOST_LASTSEEN["$host"]="$last"
done <<< "$search_response"

for HOST in "${EXPECTED[@]}"; do
  matched=""
  for key in "${!HOST_LASTSEEN[@]}"; do
    [[ "${key,,}" == "${HOST,,}" ]] && matched="$key" && break
  done
  if [[ -n "$matched" ]]; then
    ok "${HOST} — reportando (last_seen=${HOST_LASTSEEN[$matched]})"
  else
    bad "${HOST} — sin eventos en las últimas ${LOOKBACK}"
  fi
done

# ------------------------------------------------------------------
section "5. Sysmon activo en endpoints Windows"
# ------------------------------------------------------------------
SYSMON_SEARCH="search index=sysmon earliest=-${LOOKBACK} | stats latest(_time) as last_seen count by host | eval last_seen=strftime(last_seen, \"%Y-%m-%dT%H:%M:%S\") | fields host last_seen count"

sysmon_response=$(curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" "${SPLUNK_URL}/services/search/jobs/export" \
  --data-urlencode "search=${SYSMON_SEARCH}" -d "output_mode=json" -d "exec_mode=oneshot" -d "count=0" 2>/dev/null)

declare -A SYSMON_LASTSEEN
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  host=$(echo "$line" | jq -r '.result.host // empty' 2>/dev/null)
  last=$(echo "$line" | jq -r '.result.last_seen // "never"' 2>/dev/null)
  [[ -n "$host" ]] && SYSMON_LASTSEEN["$host"]="$last"
done <<< "$sysmon_response"

for HOST in "${EXPECTED[@]}"; do
  matched=""
  for key in "${!SYSMON_LASTSEEN[@]}"; do
    [[ "${key,,}" == "${HOST,,}" ]] && matched="$key" && break
  done
  if [[ -n "$matched" ]]; then
    ok "${HOST} — Sysmon activo (last_seen=${SYSMON_LASTSEEN[$matched]})"
  else
    bad "${HOST} — sin eventos en index=sysmon en las últimas ${LOOKBACK}"
  fi
done

# ------------------------------------------------------------------
section "Resumen"
# ------------------------------------------------------------------
echo "  OK: ${PASS}   FAIL: ${FAIL}   WARN: ${WARN}"

[[ $FAIL -eq 0 ]]
