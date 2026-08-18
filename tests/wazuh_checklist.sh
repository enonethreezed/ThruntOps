#!/usr/bin/env bash
# Checklist de validación post-deploy — variante Wazuh
# Cubre: VMs levantadas / usuarios de dominio / SIEM up / endpoints reportando / Sysmon.
#
# Requiere: curl, jq. Opcional: ldapwhoami (paquete ldap-utils) para el check de
# usuarios de dominio.
#
# Uso:
#   ./tests/wazuh_checklist.sh --base   # ranges/wazuh-base.yml  (1 AD + 1 WRK)
#   ./tests/wazuh_checklist.sh --dual   # ranges/wazuh-dual.yml  (2 AD + 2 WRK)
#   ./tests/wazuh_checklist.sh --adcs   # ranges/wazuh-adcs.yml  (1 AD + ADCS + 1 WRK)
#
# Override de red vía env vars si la autodetección falla:
#   RANGE_PREFIX=10.2 ./tests/wazuh_checklist.sh --dual

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

WAZUH_USER="wazuh"
WAZUH_PASS="Thisisapassword1-"
DOMAIN_ADMIN_PASS="password"
DOMAIN_USER_PASS="password"

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
WAZUH_IP="${BASE}.1"
DC1_IP="${BASE}.11"
DC2_IP="${BASE}.12"
WAZUH_URL="https://${WAZUH_IP}:55000"

# --- Forma del perfil ---
case "$PROFILE" in
  --base)
    VM_PATTERNS=(
      "wazuh:-wazuh$"
      "DC01-2022:-ad-dc-win2022-server-x64$"
      "WIN11-22H2-1:-ad-win11-22h2-enterprise-x64-1$"
    )
    declare -A DOMAINS=( ["thruntops.domain"]="$DC1_IP" )
    WINDOWS_HOSTS_REGEX="(DC01-2022|WIN11-22H2-1)$"
    WINDOWS_HOSTS_COUNT=2
    ;;
  --dual)
    VM_PATTERNS=(
      "wazuh:-wazuh$"
      "DC01-2022:-ad-dc-win2022-server-x64$"
      "DC01-SEC:-ad-dc-win2022-secondary$"
      "WIN11-22H2-1:-ad-win11-22h2-enterprise-x64-1$"
      "WIN11-22H2-2:-ad-win11-22h2-enterprise-x64-2$"
    )
    declare -A DOMAINS=(
      ["thruntops.domain"]="$DC1_IP"
      ["secondary.thruntops.domain"]="$DC2_IP"
    )
    WINDOWS_HOSTS_REGEX="(DC01-2022|DC01-SEC|WIN11-22H2-1|WIN11-22H2-2)$"
    WINDOWS_HOSTS_COUNT=4
    ;;
  --adcs)
    VM_PATTERNS=(
      "wazuh:-wazuh$"
      "DC01-2022:-ad-dc-win2022-server-x64$"
      "ADCS:-adcs$"
      "WIN11-22H2-1:-ad-win11-22h2-enterprise-x64-1$"
    )
    declare -A DOMAINS=( ["thruntops.domain"]="$DC1_IP" )
    WINDOWS_HOSTS_REGEX="(DC01-2022|ADCS|WIN11-22H2-1)$"
    WINDOWS_HOSTS_COUNT=3
    ;;
esac

echo "Perfil: ${PROFILE#--}  |  Prefijo de red: ${RANGE_PREFIX}  (wazuh: ${WAZUH_IP})"

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
section "3. SIEM (Wazuh) levantado"
# ------------------------------------------------------------------
token=$(curl -sk -u "${WAZUH_USER}:${WAZUH_PASS}" -X POST "${WAZUH_URL}/security/user/authenticate" 2>/dev/null | jq -r '.data.token // empty')

if [[ -n "$token" ]]; then
  ok "Wazuh API disponible y autentica (${WAZUH_URL})"
else
  bad "No se pudo autenticar con la API de Wazuh (${WAZUH_URL})"
fi

# ------------------------------------------------------------------
section "4. Endpoints dados de alta y reportando"
# ------------------------------------------------------------------
if [[ -z "$token" ]]; then
  bad "Sin token — no se puede consultar el listado de agentes"
else
  agents_response=$(curl -sk -H "Authorization: Bearer ${token}" "${WAZUH_URL}/agents?limit=500&q=id!=000" 2>/dev/null)

  if ! echo "$agents_response" | jq -e '.data.affected_items' >/dev/null 2>&1; then
    bad "No se pudo obtener la lista de agentes"
  else
    echo "$agents_response" | jq -r '.data.affected_items[] | [.name, (.status // "unknown")] | @tsv' \
    | while IFS=$'\t' read -r name status; do
      if [[ "$status" == "active" ]]; then
        echo "  ✓ ${name} — active"
      else
        echo "  ✗ ${name} — ${status}"
      fi
    done
  fi
fi

# ------------------------------------------------------------------
section "5. Sysmon activo en endpoints Windows"
# ------------------------------------------------------------------
if [[ -z "$token" ]]; then
  bad "Sin token — no se puede comprobar Sysmon"
elif [[ -z "${agents_response:-}" ]]; then
  bad "Sin listado de agentes — no se puede comprobar Sysmon"
else
  sysmon_agent_count=$(echo "$agents_response" | jq --arg re "$WINDOWS_HOSTS_REGEX" '
    [.data.affected_items[] | select(.name | test($re; "i"))] | length
  ' 2>/dev/null)
  sysmon_agents=$(echo "$agents_response" | jq -r --arg re "$WINDOWS_HOSTS_REGEX" '
    .data.affected_items[] | select(.name | test($re; "i")) | [.id, .name] | @tsv
  ' 2>/dev/null)

  if [[ "$sysmon_agent_count" != "$WINDOWS_HOSTS_COUNT" ]]; then
    bad "No se encontraron los ${WINDOWS_HOSTS_COUNT} endpoints Windows esperados para comprobar Sysmon"
  else
    while IFS=$'\t' read -r agent_id agent_name; do
      services_response=$(curl -sk -H "Authorization: Bearer ${token}" \
        "${WAZUH_URL}/syscollector/${agent_id}/services?limit=1000" 2>/dev/null)
      if echo "$services_response" | jq -e '
        any(.data.affected_items[]?; .service.name == "Sysmon64" and .service.state == "RUNNING")
      ' >/dev/null 2>&1; then
        ok "${agent_name} — Sysmon64 activo"
      else
        bad "${agent_name} — Sysmon64 no está activo en Syscollector"
      fi
    done <<< "$sysmon_agents"
  fi
fi

# ------------------------------------------------------------------
section "Resumen"
# ------------------------------------------------------------------
echo "  OK: ${PASS}   FAIL: ${FAIL}   WARN: ${WARN}"

[[ $FAIL -eq 0 ]]
