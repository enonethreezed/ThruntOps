#!/usr/bin/env bash
# Post-deploy validation checklist — Splunk variant
# Covers: VMs up / domain users / SIEM up / endpoints reporting / Sysmon.
#
# Requires: curl, jq. Optional: ldapwhoami (ldap-utils package) for the
# domain user check.
#
# Usage:
#   ./tests/splunk_checklist.sh --base   # ranges/splunk-base.yml  (1 AD + 1 WRK)
#   ./tests/splunk_checklist.sh --dual   # ranges/splunk-dual.yml  (2 AD + 2 WRK)
#   ./tests/splunk_checklist.sh --adcs   # ranges/splunk-adcs.yml  (1 AD + ADCS + 1 WRK)
#
# Network override via env vars if autodetection fails:
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
SPLUNK_IP="${BASE}.1"
DC1_IP="${BASE}.11"
DC2_IP="${BASE}.12"
SPLUNK_URL="https://${SPLUNK_IP}:8089"

# --- Profile shape ---
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

echo "Profile: ${PROFILE#--}  |  Network prefix: ${RANGE_PREFIX}  (splunk: ${SPLUNK_IP})"

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
section "3. SIEM (Splunk) up"
# ------------------------------------------------------------------
info_response=$(curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" "${SPLUNK_URL}/services/server/info?output_mode=json" 2>/dev/null)
server_name=$(echo "$info_response" | jq -r '.entry[0].content.serverName // empty' 2>/dev/null)

if [[ -n "$server_name" ]]; then
  ok "Splunk available (${SPLUNK_URL}, serverName=${server_name})"
else
  bad "Could not reach Splunk (${SPLUNK_URL})"
fi

# ------------------------------------------------------------------
section "4. Endpoints enrolled and reporting"
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
    ok "${HOST} — reporting (last_seen=${HOST_LASTSEEN[$matched]})"
  else
    bad "${HOST} — no events in the last ${LOOKBACK}"
  fi
done

# ------------------------------------------------------------------
section "5. Sysmon active on Windows endpoints"
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
    ok "${HOST} — Sysmon active (last_seen=${SYSMON_LASTSEEN[$matched]})"
  else
    bad "${HOST} — no events in index=sysmon in the last ${LOOKBACK}"
  fi
done

# ------------------------------------------------------------------
section "Summary"
# ------------------------------------------------------------------
echo "  OK: ${PASS}   FAIL: ${FAIL}   WARN: ${WARN}"

[[ $FAIL -eq 0 ]]
