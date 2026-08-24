#!/usr/bin/env bash
# Unified control script for the three validated SIEM stacks (elastic, wazuh,
# splunk): range deploy, post-deploy checklist, and live agent/forwarder
# status.
#
# Usage:
#   ./siem.sh <elastic|wazuh|splunk> deploy <--base|--dual|--adcs>
#   ./siem.sh <elastic|wazuh|splunk> check  <--base|--dual|--adcs>
#   ./siem.sh <elastic|wazuh>        status
#   ./siem.sh splunk                 status <--base|--dual|--adcs>
#   # splunk status needs the profile to know which hosts to expect;
#   # elastic/wazuh list whatever's actually enrolled in Fleet/Wazuh.
#
# Requires: curl, jq. Optional: ldapwhoami (ldap-utils package) for the
# domain user check; python3 for the splunk status column parsing.
#
# Network override via env var if autodetection fails:
#   RANGE_PREFIX=10.2 ./siem.sh wazuh check --dual

set -uo pipefail

usage() {
  echo "Usage: $0 <elastic|wazuh|splunk> <deploy|check> --base|--dual|--adcs"
  echo "       $0 <elastic|wazuh> status"
  echo "       $0 splunk status --base|--dual|--adcs"
  exit 1
}

SIEM="${1:-}"
ACTION="${2:-}"
EXTRA="${3:-}"

case "$SIEM" in
  elastic|wazuh|splunk) ;;
  *) usage ;;
esac

case "$ACTION" in
  deploy|check)
    case "$EXTRA" in --base|--dual|--adcs) ;; *) usage ;; esac
    PROFILE="$EXTRA"
    ;;
  status)
    if [[ "$SIEM" == "splunk" ]]; then
      case "$EXTRA" in --base|--dual|--adcs) ;; *) usage ;; esac
      PROFILE="$EXTRA"
    fi
    ;;
  *) usage ;;
esac

case "$SIEM" in
  elastic) RANGES_DIR_PREFIX="elk";    API_USER="elastic"; API_PASS="thisisapassword" ;;
  wazuh)   RANGES_DIR_PREFIX="wazuh";  API_USER="wazuh";   API_PASS="Thisisapassword1-" ;;
  splunk)  RANGES_DIR_PREFIX="splunk"; API_USER="admin";   API_PASS="thisisapassword" ;;
esac

DOMAIN_ADMIN_PASS="password"
DOMAIN_USER_PASS="password"
LOOKBACK="1h"

# ==================================================================
# deploy
# ==================================================================
cmd_deploy() {
  local config="ranges/${RANGES_DIR_PREFIX}-${PROFILE#--}.yml"
  ludus range destroy --no-prompt && \
  ludus range config set -f "$config" && \
  ludus range deploy && \
  ludus range logs -f
}

# ==================================================================
# shared checklist helpers
# ==================================================================
PASS=0
FAIL=0
WARN=0
ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
bad()  { printf "  \033[31m✗\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); }
warn() { printf "  \033[33m~\033[0m %s\n" "$1"; WARN=$((WARN+1)); }
section() { printf "\n=== %s ===\n" "$1"; }

resolve_range_prefix() {
  if [[ -z "${RANGE_PREFIX:-}" ]]; then
    local range_num
    range_num=$(ludus range status --json 2>/dev/null | jq -r '.rangeNumber // .range_number // empty' 2>/dev/null)
    if [[ -n "$range_num" ]]; then
      RANGE_PREFIX="10.${range_num}"
    else
      echo "Could not autodetect the network prefix from 'ludus range status --json'."
      echo "Set RANGE_PREFIX manually, e.g.: RANGE_PREFIX=10.2 $0 ${SIEM} ${ACTION} ${EXTRA}"
      exit 1
    fi
  fi
}

set_vm_patterns() {
  case "$PROFILE" in
    --base)
      VM_PATTERNS=(
        "${SIEM}:-${SIEM}$"
        "DC01-2022:-ad-dc-win2022-server-x64$"
        "WIN11-22H2-1:-ad-win11-22h2-enterprise-x64-1$"
      )
      declare -gA DOMAINS=( ["thruntops.domain"]="$DC1_IP" )
      WINDOWS_HOSTS_REGEX="(DC01-2022|WIN11-22H2-1)$"
      WINDOWS_HOSTS_COUNT=2
      ;;
    --dual)
      VM_PATTERNS=(
        "${SIEM}:-${SIEM}$"
        "DC01-2022:-ad-dc-win2022-server-x64$"
        "DC01-SEC:-ad-dc-win2022-secondary$"
        "WIN11-22H2-1:-ad-win11-22h2-enterprise-x64-1$"
        "WIN11-22H2-2:-ad-win11-22h2-enterprise-x64-2$"
      )
      declare -gA DOMAINS=(
        ["thruntops.domain"]="$DC1_IP"
        ["secondary.thruntops.domain"]="$DC2_IP"
      )
      WINDOWS_HOSTS_REGEX="(DC01-2022|DC01-SEC|WIN11-22H2-1|WIN11-22H2-2)$"
      WINDOWS_HOSTS_COUNT=4
      ;;
    --adcs)
      VM_PATTERNS=(
        "${SIEM}:-${SIEM}$"
        "DC01-2022:-ad-dc-win2022-server-x64$"
        "ADCS:-adcs$"
        "WIN11-22H2-1:-ad-win11-22h2-enterprise-x64-1$"
      )
      declare -gA DOMAINS=( ["thruntops.domain"]="$DC1_IP" )
      WINDOWS_HOSTS_REGEX="(DC01-2022|ADCS|WIN11-22H2-1)$"
      WINDOWS_HOSTS_COUNT=3
      ;;
  esac
}

check_vms_up() {
  section "1. VMs up"
  STATUS_JSON=$(ludus range status --json 2>/dev/null)
  if [[ -z "$STATUS_JSON" ]]; then
    bad "Could not get 'ludus range status --json'"
    return
  fi
  # The .name field from 'ludus range status --json' is the Proxmox vm_name,
  # not the Windows/AD hostname — match against the real vm_name pattern.
  for entry in "${VM_PATTERNS[@]}"; do
    local label="${entry%%:*}"
    local pattern="${entry#*:}"
    local powered
    powered=$(echo "$STATUS_JSON" | jq -r --arg p "$pattern" '
      [.VMs[]? // .vms[]? | select((.name // .Name // "") | test($p))] | .[0] |
      (.poweredOn // .powered_on // .PoweredOn // empty)' 2>/dev/null)
    case "$powered" in
      true)  ok "$label — powered on" ;;
      false) bad "$label — powered off" ;;
      *)     warn "$label — could not determine status (check 'ludus range status' manually)" ;;
    esac
  done
}

check_domain_users() {
  section "2. Users — domain"
  if ! command -v ldapwhoami >/dev/null 2>&1; then
    warn "ldapwhoami not installed (ldap-utils package) — cannot validate domain authentication"
    return
  fi
  for domain in "${!DOMAINS[@]}"; do
    local dc_ip="${DOMAINS[$domain]}"
    for user in "domainadmin:$DOMAIN_ADMIN_PASS" "domainuser:$DOMAIN_USER_PASS"; do
      local uname="${user%%:*}"
      local upass="${user##*:}"
      if ldapwhoami -x -H "ldap://${dc_ip}" -D "${uname}@${domain}" -w "${upass}" >/dev/null 2>&1; then
        ok "${domain}\\${uname} authenticates (${dc_ip})"
      else
        bad "${domain}\\${uname} does NOT authenticate (${dc_ip})"
      fi
    done
  done
}

# ==================================================================
# elastic
# ==================================================================
check_elastic_siem_up() {
  section "3. SIEM (Kibana) up"
  local resp state
  resp=$(curl -sk -u "${API_USER}:${API_PASS}" "${KIBANA_URL}/api/status" 2>/dev/null)
  state=$(echo "$resp" | jq -r '.status.overall.level // empty' 2>/dev/null)
  if [[ "$state" == "available" ]]; then
    ok "Kibana available (${KIBANA_URL})"
  elif [[ -n "$state" ]]; then
    bad "Kibana in state '${state}' (${KIBANA_URL})"
  else
    bad "Could not reach Kibana (${KIBANA_URL})"
  fi
}

fleet_agents() {
  curl -sk --max-time 10 -u "${API_USER}:${API_PASS}" -H "kbn-xsrf: true" "${KIBANA_URL}/api/fleet/agents?perPage=100" 2>/dev/null
}

check_elastic_endpoints() {
  section "4. Endpoints enrolled and reporting (Fleet)"
  local resp lines
  resp=$(fleet_agents)
  if ! echo "$resp" | jq -e '.items' >/dev/null 2>&1; then
    bad "Could not get the Fleet agent list"
    return
  fi
  lines=$(echo "$resp" | jq -r '
    [ .items[] | select(.active == true and .status != "uninstalled") ] |
    group_by(.local_metadata.host.hostname // .id) |
    .[] | sort_by(.last_checkin) | last |
    [ (.local_metadata.host.hostname // .id), (.status // "unknown") ] | @tsv
  ')
  if [[ -z "$lines" ]]; then
    bad "No active Fleet agents registered"
    return
  fi
  while IFS=$'\t' read -r hostname status; do
    if [[ "$status" == "online" ]]; then
      ok "${hostname} — online"
    else
      bad "${hostname} — ${status}"
    fi
  done <<< "$lines"
}

status_elastic() {
  local resp
  resp=$(fleet_agents)
  if ! echo "$resp" | jq -e '.items' > /dev/null 2>&1; then
    echo "Error contacting the Fleet API:"
    echo "$resp" | jq '.' 2>/dev/null || echo "$resp"
    exit 1
  fi

  echo "=== Fleet Agent Status - $(date) ==="
  echo ""

  echo "$resp" | jq -r '
    [ .items[] | select(.active == true and .status != "uninstalled") ] |
    group_by(.local_metadata.host.hostname // .id) |
    .[] | sort_by(.last_checkin) | last |
    [
      .local_metadata.host.hostname // .id,
      .status // "unknown",
      (.last_checkin // "never"),
      (.agent.version // "unknown")
    ] | @tsv
  ' | while IFS=$'\t' read -r hostname status last_checkin version; do
    case "$status" in
      online)    icon="✓" ;;
      offline)   icon="✗" ;;
      error)     icon="!" ;;
      degraded)  icon="~" ;;
      *)         icon="?" ;;
    esac
    printf "%s %-35s %-10s %-30s %s\n" "$icon" "$hostname" "$status" "$last_checkin" "$version"
  done

  echo ""
  echo "--- Summary ---"
  echo "$resp" | jq -r '[ .items[] | select(.active == true and .status != "uninstalled") ] | group_by(.local_metadata.host.hostname // .id) | .[] | sort_by(.last_checkin) | last | .status // "unknown"' | sort | uniq -c | while read -r count status; do
    echo "  $status: $count"
  done
}

# ==================================================================
# wazuh
# ==================================================================
get_wazuh_token() {
  curl -sk --max-time 10 -u "${API_USER}:${API_PASS}" -X POST "${WAZUH_URL}/security/user/authenticate" 2>/dev/null | jq -r '.data.token // empty'
}

check_wazuh_siem_up() {
  section "3. SIEM (Wazuh) up"
  WAZUH_TOKEN=$(get_wazuh_token)
  if [[ -n "$WAZUH_TOKEN" ]]; then
    ok "Wazuh API available and authenticates (${WAZUH_URL})"
  else
    bad "Could not authenticate with the Wazuh API (${WAZUH_URL})"
  fi
}

check_wazuh_endpoints() {
  section "4. Endpoints enrolled and reporting"
  if [[ -z "${WAZUH_TOKEN:-}" ]]; then
    bad "No token — cannot query the agent list"
    return
  fi
  WAZUH_AGENTS_RESPONSE=$(curl -sk -H "Authorization: Bearer ${WAZUH_TOKEN}" "${WAZUH_URL}/agents?limit=500&q=id!=000" 2>/dev/null)
  if ! echo "$WAZUH_AGENTS_RESPONSE" | jq -e '.data.affected_items' >/dev/null 2>&1; then
    bad "Could not get the agent list"
    return
  fi
  local lines
  lines=$(echo "$WAZUH_AGENTS_RESPONSE" | jq -r '.data.affected_items[] | [.name, (.status // "unknown")] | @tsv')
  if [[ -z "$lines" ]]; then
    bad "No agents enrolled"
    return
  fi
  while IFS=$'\t' read -r name status; do
    if [[ "$status" == "active" ]]; then
      ok "${name} — active"
    else
      bad "${name} — ${status}"
    fi
  done <<< "$lines"
}

check_wazuh_sysmon() {
  section "5. Sysmon active on Windows endpoints"
  if [[ -z "${WAZUH_TOKEN:-}" ]]; then
    bad "No token — cannot check Sysmon"
    return
  fi
  if [[ -z "${WAZUH_AGENTS_RESPONSE:-}" ]]; then
    bad "No agent list — cannot check Sysmon"
    return
  fi
  local count agents
  count=$(echo "$WAZUH_AGENTS_RESPONSE" | jq --arg re "$WINDOWS_HOSTS_REGEX" '
    [.data.affected_items[] | select(.name | test($re; "i"))] | length
  ' 2>/dev/null)
  agents=$(echo "$WAZUH_AGENTS_RESPONSE" | jq -r --arg re "$WINDOWS_HOSTS_REGEX" '
    .data.affected_items[] | select(.name | test($re; "i")) | [.id, .name] | @tsv
  ' 2>/dev/null)

  if [[ "$count" != "$WINDOWS_HOSTS_COUNT" ]]; then
    bad "Did not find the ${WINDOWS_HOSTS_COUNT} expected Windows endpoints to check Sysmon"
    return
  fi
  while IFS=$'\t' read -r agent_id agent_name; do
    local svc
    svc=$(curl -sk -H "Authorization: Bearer ${WAZUH_TOKEN}" \
      "${WAZUH_URL}/syscollector/${agent_id}/services?limit=1000" 2>/dev/null)
    if echo "$svc" | jq -e '
      any(.data.affected_items[]?; .service.name == "Sysmon64" and .service.state == "RUNNING")
    ' >/dev/null 2>&1; then
      ok "${agent_name} — Sysmon64 active"
    else
      bad "${agent_name} — Sysmon64 is not active in Syscollector"
    fi
  done <<< "$agents"
}

status_wazuh() {
  local token resp
  token=$(get_wazuh_token)
  if [[ -z "$token" ]]; then
    echo "Error: could not authenticate with the Wazuh API (${WAZUH_URL})"
    echo "Check that the server is up and the credentials are correct."
    exit 1
  fi

  resp=$(curl -sk --max-time 10 -H "Authorization: Bearer ${token}" "${WAZUH_URL}/agents?limit=500&q=id!=000")
  if ! echo "$resp" | jq -e '.data.affected_items' > /dev/null 2>&1; then
    echo "Error fetching agents:"
    echo "$resp" | jq '.' 2>/dev/null || echo "$resp"
    exit 1
  fi

  echo "=== Wazuh Agent Status - $(date) ==="
  echo ""

  echo "$resp" | jq -r '
    .data.affected_items[] |
    [
      .name,
      .status,
      (.lastKeepAlive // "never"),
      (.version // "unknown"),
      (.ip // "unknown")
    ] | @tsv
  ' | while IFS=$'\t' read -r name status last_keepalive version ip; do
    case "$status" in
      active)       icon="✓" ;;
      disconnected) icon="✗" ;;
      pending)      icon="~" ;;
      never_connected) icon="?" ;;
      *)            icon="?" ;;
    esac
    printf "%s %-35s %-15s %-15s %-30s %s\n" "$icon" "$name" "$status" "$ip" "$last_keepalive" "$version"
  done

  echo ""
  echo "--- Summary ---"
  echo "$resp" | jq -r '.data.affected_items[].status' | sort | uniq -c | while read -r count status; do
    echo "  $status: $count"
  done

  local total
  total=$(echo "$resp" | jq '.data.total_affected_items')
  echo "  Total agents: $total"
}

# ==================================================================
# splunk
# ==================================================================
splunk_search() {
  curl -sk -u "${API_USER}:${API_PASS}" "${SPLUNK_URL}/services/search/jobs/export" \
    --data-urlencode "search=$1" -d "output_mode=json" -d "exec_mode=oneshot" -d "count=0" 2>/dev/null
}

check_splunk_siem_up() {
  section "3. SIEM (Splunk) up"
  local resp name
  resp=$(curl -sk -u "${API_USER}:${API_PASS}" "${SPLUNK_URL}/services/server/info?output_mode=json" 2>/dev/null)
  name=$(echo "$resp" | jq -r '.entry[0].content.serverName // empty' 2>/dev/null)
  if [[ -n "$name" ]]; then
    ok "Splunk available (${SPLUNK_URL}, serverName=${name})"
  else
    bad "Could not reach Splunk (${SPLUNK_URL})"
  fi
}

check_splunk_endpoints() {
  section "4. Endpoints enrolled and reporting"
  local range_id search resp
  range_id=$(echo "$STATUS_JSON" | jq -r '.rangeID // empty' 2>/dev/null)
  SPLUNK_EXPECTED=()
  for entry in "${VM_PATTERNS[@]}"; do
    local label="${entry%%:*}"
    [[ "$label" == "splunk" ]] && continue
    SPLUNK_EXPECTED+=("${range_id}-${label}")
  done

  search="search index=* earliest=-${LOOKBACK} | stats latest(_time) as last_seen count by host | eval last_seen=strftime(last_seen, \"%Y-%m-%dT%H:%M:%S\") | fields host last_seen count"
  resp=$(splunk_search "$search")

  declare -A host_lastseen
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local host last
    host=$(echo "$line" | jq -r '.result.host // empty' 2>/dev/null)
    last=$(echo "$line" | jq -r '.result.last_seen // "never"' 2>/dev/null)
    [[ -n "$host" ]] && host_lastseen["$host"]="$last"
  done <<< "$resp"

  for HOST in "${SPLUNK_EXPECTED[@]}"; do
    local matched=""
    for key in "${!host_lastseen[@]}"; do
      [[ "${key,,}" == "${HOST,,}" ]] && matched="$key" && break
    done
    if [[ -n "$matched" ]]; then
      ok "${HOST} — reporting (last_seen=${host_lastseen[$matched]})"
    else
      bad "${HOST} — no events in the last ${LOOKBACK}"
    fi
  done
}

check_splunk_sysmon() {
  section "5. Sysmon active on Windows endpoints"
  local search resp
  search="search index=sysmon earliest=-${LOOKBACK} | stats latest(_time) as last_seen count by host | eval last_seen=strftime(last_seen, \"%Y-%m-%dT%H:%M:%S\") | fields host last_seen count"
  resp=$(splunk_search "$search")

  declare -A sysmon_lastseen
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local host last
    host=$(echo "$line" | jq -r '.result.host // empty' 2>/dev/null)
    last=$(echo "$line" | jq -r '.result.last_seen // "never"' 2>/dev/null)
    [[ -n "$host" ]] && sysmon_lastseen["$host"]="$last"
  done <<< "$resp"

  for HOST in "${SPLUNK_EXPECTED[@]}"; do
    local matched=""
    for key in "${!sysmon_lastseen[@]}"; do
      [[ "${key,,}" == "${HOST,,}" ]] && matched="$key" && break
    done
    if [[ -n "$matched" ]]; then
      ok "${HOST} — Sysmon active (last_seen=${sysmon_lastseen[$matched]})"
    else
      bad "${HOST} — no events in index=sysmon in the last ${LOOKBACK}"
    fi
  done
}

status_splunk() {
  set_vm_patterns
  local range_id
  range_id=$(ludus range status --json 2>/dev/null | jq -r '.rangeID // .range_id // empty' 2>/dev/null)
  if [[ -z "$range_id" ]]; then
    echo "Could not autodetect the range ID from 'ludus range status --json'."
    exit 1
  fi

  local expected=()
  for entry in "${VM_PATTERNS[@]}"; do
    local label="${entry%%:*}"
    [[ "$label" == "splunk" ]] && continue
    expected+=("${range_id}-${label}")
  done

  local search="search index=* earliest=-${LOOKBACK} | stats latest(_time) as last_seen count by host | eval last_seen=strftime(last_seen, \"%Y-%m-%dT%H:%M:%S\") | fields host last_seen count"
  local resp
  resp=$(splunk_search "$search")

  declare -A host_lastseen host_count
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local host last count
    host=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result',{}).get('host',''))" 2>/dev/null)
    last=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result',{}).get('last_seen','never'))" 2>/dev/null)
    count=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result',{}).get('count','0'))" 2>/dev/null)
    [[ -n "$host" ]] && host_lastseen["$host"]="$last" && host_count["$host"]="$count"
  done <<< "$resp"

  echo "=== Splunk Forwarder Status - $(date) ==="
  echo ""

  printf "%-2s %-35s %-10s %-28s\n" "" "HOST" "EVENTS" "LAST SEEN"
  for HOST in "${expected[@]}"; do
    local matched=""
    for key in "${!host_lastseen[@]}"; do
      [[ "${key,,}" == "${HOST,,}" ]] && matched="$key" && break
    done
    if [[ -n "$matched" ]]; then
      printf "%-2s %-35s %-10s %-28s\n" "✓" "$HOST" "${host_count[$matched]}" "${host_lastseen[$matched]}"
    else
      printf "%-2s %-35s\n" "✗" "$HOST"
    fi
  done

  echo ""
  echo "--- Summary ---"
  local up=0 missing=0
  for HOST in "${expected[@]}"; do
    local matched=""
    for key in "${!host_lastseen[@]}"; do
      [[ "${key,,}" == "${HOST,,}" ]] && matched="$key" && break
    done
    if [[ -n "$matched" ]]; then
      ((up++))
    else
      ((missing++))
    fi
  done
  echo "  online:  $up"
  echo "  missing: $missing"
  echo "  Total expected: ${#expected[@]}"
}

# ==================================================================
# main
# ==================================================================
if [[ "$ACTION" != "deploy" ]]; then
  resolve_range_prefix
  KIBANA_URL="https://${RANGE_PREFIX}.20.1:5601"
  WAZUH_URL="https://${RANGE_PREFIX}.20.1:55000"
  SPLUNK_URL="https://${RANGE_PREFIX}.20.1:8089"
  DC1_IP="${RANGE_PREFIX}.20.11"
  DC2_IP="${RANGE_PREFIX}.20.12"
fi

case "$ACTION" in
  deploy)
    cmd_deploy
    ;;
  check)
    set_vm_patterns
    echo "Profile: ${PROFILE#--}  |  Network prefix: ${RANGE_PREFIX}  (${SIEM}: ${RANGE_PREFIX}.20.1)"
    check_vms_up
    check_domain_users
    case "$SIEM" in
      elastic) check_elastic_siem_up; check_elastic_endpoints ;;
      wazuh)   check_wazuh_siem_up;   check_wazuh_endpoints;   check_wazuh_sysmon ;;
      splunk)  check_splunk_siem_up;  check_splunk_endpoints;  check_splunk_sysmon ;;
    esac
    section "Summary"
    echo "  OK: ${PASS}   FAIL: ${FAIL}   WARN: ${WARN}"
    [[ $FAIL -eq 0 ]]
    ;;
  status)
    case "$SIEM" in
      elastic) status_elastic ;;
      wazuh)   status_wazuh ;;
      splunk)  status_splunk ;;
    esac
    ;;
esac
