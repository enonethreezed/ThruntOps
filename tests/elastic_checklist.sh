#!/usr/bin/env bash
# Checklist de validación post-deploy — variante Elastic
# Cubre: VMs levantadas / usuarios de dominio / SIEM up / endpoints reportando (Fleet).
#
# Requiere: curl, jq. Opcional: ldapwhoami (paquete ldap-utils) para el check de
# usuarios de dominio.
#
# Uso:
#   ./tests/elastic_checklist.sh --base   # ranges/elk-base.yml  (1 AD + 1 WRK)
#   ./tests/elastic_checklist.sh --dual   # ranges/elk-dual.yml  (2 AD + 2 WRK)
#   ./tests/elastic_checklist.sh --adcs   # ranges/elk-adcs.yml  (1 AD + ADCS + 1 WRK)
#
# Override de red vía env vars si la autodetección falla:
#   RANGE_PREFIX=10.2 ./tests/elastic_checklist.sh --dual

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

ELASTIC_USER="elastic"
ELASTIC_PASS="thisisapassword"
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
ELASTIC_IP="${BASE}.1"
DC1_IP="${BASE}.11"
DC2_IP="${BASE}.12"
KIBANA_URL="https://${ELASTIC_IP}:5601"

# --- Forma del perfil ---
case "$PROFILE" in
  --base)
    VM_PATTERNS=(
      "elastic:-elastic$"
      "DC01-2022:-ad-dc-win2022-server-x64$"
      "WIN11-22H2-1:-ad-win11-22h2-enterprise-x64-1$"
    )
    declare -A DOMAINS=( ["thruntops.domain"]="$DC1_IP" )
    ;;
  --dual)
    VM_PATTERNS=(
      "elastic:-elastic$"
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
      "elastic:-elastic$"
      "DC01-2022:-ad-dc-win2022-server-x64$"
      "ADCS:-adcs$"
      "WIN11-22H2-1:-ad-win11-22h2-enterprise-x64-1$"
    )
    declare -A DOMAINS=( ["thruntops.domain"]="$DC1_IP" )
    ;;
esac

echo "Perfil: ${PROFILE#--}  |  Prefijo de red: ${RANGE_PREFIX}  (elastic: ${ELASTIC_IP})"

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
section "3. SIEM (Kibana) levantado"
# ------------------------------------------------------------------
status_response=$(curl -sk -u "${ELASTIC_USER}:${ELASTIC_PASS}" "${KIBANA_URL}/api/status" 2>/dev/null)
overall_state=$(echo "$status_response" | jq -r '.status.overall.level // empty' 2>/dev/null)

if [[ "$overall_state" == "available" ]]; then
  ok "Kibana disponible (${KIBANA_URL})"
elif [[ -n "$overall_state" ]]; then
  bad "Kibana en estado '${overall_state}' (${KIBANA_URL})"
else
  bad "No se pudo contactar con Kibana (${KIBANA_URL})"
fi

# ------------------------------------------------------------------
section "4. Endpoints dados de alta y reportando (Fleet)"
# ------------------------------------------------------------------
fleet_response=$(curl -sk -u "${ELASTIC_USER}:${ELASTIC_PASS}" -H "kbn-xsrf: true" \
  "${KIBANA_URL}/api/fleet/agents?perPage=100" 2>/dev/null)

if ! echo "$fleet_response" | jq -e '.items' >/dev/null 2>&1; then
  bad "No se pudo obtener la lista de agentes Fleet"
else
  agent_lines=$(echo "$fleet_response" | jq -r '
    [ .items[] | select(.active == true and .status != "uninstalled") ] |
    group_by(.local_metadata.host.hostname // .id) |
    .[] | sort_by(.last_checkin) | last |
    [ (.local_metadata.host.hostname // .id), (.status // "unknown") ] | @tsv
  ')
  if [[ -z "$agent_lines" ]]; then
    bad "No hay agentes Fleet activos registrados"
  else
    while IFS=$'\t' read -r hostname status; do
      if [[ "$status" == "online" ]]; then
        ok "${hostname} — online"
      else
        bad "${hostname} — ${status}"
      fi
    done <<< "$agent_lines"
  fi
fi

# ------------------------------------------------------------------
section "Resumen"
# ------------------------------------------------------------------
echo "  OK: ${PASS}   FAIL: ${FAIL}   WARN: ${WARN}"

[[ $FAIL -eq 0 ]]
