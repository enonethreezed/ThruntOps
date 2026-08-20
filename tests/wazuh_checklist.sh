#!/usr/bin/env bash
# Post-deploy validation checklist — Wazuh variant
# Covers: VMs up / domain users / SIEM up / endpoints reporting / Sysmon.
#
# Requires: curl, jq. Optional: ldapwhoami (ldap-utils package) for the
# domain user check.
#
# Usage:
#   ./tests/wazuh_checklist.sh --base   # ranges/wazuh-base.yml  (1 AD + 1 WRK)
#   ./tests/wazuh_checklist.sh --dual   # ranges/wazuh-dual.yml  (2 AD + 2 WRK)
#   ./tests/wazuh_checklist.sh --adcs   # ranges/wazuh-adcs.yml  (1 AD + ADCS + 1 WRK)
#
# Network override via env vars if autodetection fails:
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

# --- Resolve the range's network prefix (10.<rangeNumber>) ---
if [[ -z "${RANGE_PREFIX:-}" ]]; then
  RANGE_NUM=$(ludus range status --json 2>/dev/null | jq -r '.rangeNumber // .range_number // empty' 2>/dev/null)
  if [[ -n "$RANGE_NUM" ]]; then
    RANGE_PREFIX="10.${RANGE_NUM}"
  else
    echo "Could not autodetect the network prefix from 'ludus range status --json'."
    echo "Set RANGE_PREFIX manually, e.g.: RANGE_PREFIX=10.2 $0 ${PROFILE}"
    exit 1
  fi
fi

BASE="${RANGE_PREFIX}.20"
WAZUH_IP="${BASE}.1"
DC1_IP="${BASE}.11"
DC2_IP="${BASE}.12"
WAZUH_URL="https://${WAZUH_IP}:55000"

# --- Profile shape ---
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

echo "Profile: ${PROFILE#--}  |  Network prefix: ${RANGE_PREFIX}  (wazuh: ${WAZUH_IP})"

# ------------------------------------------------------------------
section "1. VMs up"
# ------------------------------------------------------------------
STATUS_JSON=$(ludus range status --json 2>/dev/null)
if [[ -z "$STATUS_JSON" ]]; then
  bad "Could not get 'ludus range status --json'"
else
  # The .name field from 'ludus range status --json' is the Proxmox vm_name,
  # not the Windows/AD hostname — match against the real vm_name pattern.
  for entry in "${VM_PATTERNS[@]}"; do
    label="${entry%%:*}"
    pattern="${entry#*:}"
    powered=$(echo "$STATUS_JSON" | jq -r --arg p "$pattern" '
      [.VMs[]? // .vms[]? | select((.name // .Name // "") | test($p))] | .[0] |
      (.poweredOn // .powered_on // .PoweredOn // empty)' 2>/dev/null)
    case "$powered" in
      true)  ok "$label — powered on" ;;
      false) bad "$label — powered off" ;;
      *)     warn "$label — could not determine status (check 'ludus range status' manually)" ;;
    esac
  done
fi

# ------------------------------------------------------------------
section "2. Users — domain"
# ------------------------------------------------------------------
if ! command -v ldapwhoami >/dev/null 2>&1; then
  warn "ldapwhoami not installed (ldap-utils package) — cannot validate domain authentication"
else
  for domain in "${!DOMAINS[@]}"; do
    dc_ip="${DOMAINS[$domain]}"
    for user in "domainadmin:$DOMAIN_ADMIN_PASS" "domainuser:$DOMAIN_USER_PASS"; do
      uname="${user%%:*}"
      upass="${user##*:}"
      if ldapwhoami -x -H "ldap://${dc_ip}" -D "${uname}@${domain}" -w "${upass}" >/dev/null 2>&1; then
        ok "${domain}\\${uname} authenticates (${dc_ip})"
      else
        bad "${domain}\\${uname} does NOT authenticate (${dc_ip})"
      fi
    done
  done
fi

# ------------------------------------------------------------------
section "3. SIEM (Wazuh) up"
# ------------------------------------------------------------------
token=$(curl -sk -u "${WAZUH_USER}:${WAZUH_PASS}" -X POST "${WAZUH_URL}/security/user/authenticate" 2>/dev/null | jq -r '.data.token // empty')

if [[ -n "$token" ]]; then
  ok "Wazuh API available and authenticates (${WAZUH_URL})"
else
  bad "Could not authenticate with the Wazuh API (${WAZUH_URL})"
fi

# ------------------------------------------------------------------
section "4. Endpoints enrolled and reporting"
# ------------------------------------------------------------------
if [[ -z "$token" ]]; then
  bad "No token — cannot query the agent list"
else
  agents_response=$(curl -sk -H "Authorization: Bearer ${token}" "${WAZUH_URL}/agents?limit=500&q=id!=000" 2>/dev/null)

  if ! echo "$agents_response" | jq -e '.data.affected_items' >/dev/null 2>&1; then
    bad "Could not get the agent list"
  else
    agent_lines=$(echo "$agents_response" | jq -r '.data.affected_items[] | [.name, (.status // "unknown")] | @tsv')
    if [[ -z "$agent_lines" ]]; then
      bad "No agents enrolled"
    else
      while IFS=$'\t' read -r name status; do
        if [[ "$status" == "active" ]]; then
          ok "${name} — active"
        else
          bad "${name} — ${status}"
        fi
      done <<< "$agent_lines"
    fi
  fi
fi

# ------------------------------------------------------------------
section "5. Sysmon active on Windows endpoints"
# ------------------------------------------------------------------
if [[ -z "$token" ]]; then
  bad "No token — cannot check Sysmon"
elif [[ -z "${agents_response:-}" ]]; then
  bad "No agent list — cannot check Sysmon"
else
  sysmon_agent_count=$(echo "$agents_response" | jq --arg re "$WINDOWS_HOSTS_REGEX" '
    [.data.affected_items[] | select(.name | test($re; "i"))] | length
  ' 2>/dev/null)
  sysmon_agents=$(echo "$agents_response" | jq -r --arg re "$WINDOWS_HOSTS_REGEX" '
    .data.affected_items[] | select(.name | test($re; "i")) | [.id, .name] | @tsv
  ' 2>/dev/null)

  if [[ "$sysmon_agent_count" != "$WINDOWS_HOSTS_COUNT" ]]; then
    bad "Did not find the ${WINDOWS_HOSTS_COUNT} expected Windows endpoints to check Sysmon"
  else
    while IFS=$'\t' read -r agent_id agent_name; do
      services_response=$(curl -sk -H "Authorization: Bearer ${token}" \
        "${WAZUH_URL}/syscollector/${agent_id}/services?limit=1000" 2>/dev/null)
      if echo "$services_response" | jq -e '
        any(.data.affected_items[]?; .service.name == "Sysmon64" and .service.state == "RUNNING")
      ' >/dev/null 2>&1; then
        ok "${agent_name} — Sysmon64 active"
      else
        bad "${agent_name} — Sysmon64 is not active in Syscollector"
      fi
    done <<< "$sysmon_agents"
  fi
fi

# ------------------------------------------------------------------
section "Summary"
# ------------------------------------------------------------------
echo "  OK: ${PASS}   FAIL: ${FAIL}   WARN: ${WARN}"

[[ $FAIL -eq 0 ]]
