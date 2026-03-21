#!/usr/bin/env bash

SPLUNK_URL="https://10.2.50.1:8089"
USER="admin"
PASS="thisisapassword"
RANGE_ID="${1:-}"
LOOKBACK="1h"

if [[ -z "$RANGE_ID" ]]; then
  echo "Usage: $0 <range_id>"
  echo "  range_id: your Ludus range prefix (e.g. JD)"
  exit 1
fi

EXPECTED=(
  "${RANGE_ID}-DC01-2022"
  "${RANGE_ID}-DC01-SEC"
  "${RANGE_ID}-WIN11-22H2-1"
  "${RANGE_ID}-WIN11-22H2-2"
  "${RANGE_ID}-ADCS"
  "${RANGE_ID}-WEB"
  "${RANGE_ID}-gitlab"
  "${RANGE_ID}-ops"
)

SEARCH="search index=* earliest=-${LOOKBACK} | stats latest(_time) as last_seen count by host | eval last_seen=strftime(last_seen, \"%Y-%m-%dT%H:%M:%S\") | fields host last_seen count"

response=$(curl -sk \
  -u "${USER}:${PASS}" \
  "${SPLUNK_URL}/services/search/jobs/export" \
  --data-urlencode "search=${SEARCH}" \
  -d "output_mode=json" \
  -d "exec_mode=oneshot" \
  -d "count=0")

declare -A HOST_LASTSEEN
declare -A HOST_COUNT
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  host=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result',{}).get('host',''))" 2>/dev/null)
  last=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result',{}).get('last_seen','never'))" 2>/dev/null)
  count=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result',{}).get('count','0'))" 2>/dev/null)
  [[ -n "$host" ]] && HOST_LASTSEEN["$host"]="$last" && HOST_COUNT["$host"]="$count"
done <<< "$response"

echo "=== Splunk Forwarder Status - $(date) ==="
echo ""

printf "%-2s %-35s %-10s %-28s\n" "" "HOST" "EVENTS" "LAST SEEN"
for HOST in "${EXPECTED[@]}"; do
  matched=""
  for key in "${!HOST_LASTSEEN[@]}"; do
    [[ "${key,,}" == "${HOST,,}" ]] && matched="$key" && break
  done
  if [[ -n "$matched" ]]; then
    printf "%-2s %-35s %-10s %-28s\n" "✓" "$HOST" "${HOST_COUNT[$matched]}" "${HOST_LASTSEEN[$matched]}"
  else
    printf "%-2s %-35s\n" "✗" "$HOST"
  fi
done

echo ""
echo "--- Resumen ---"
ok=0; missing=0
for HOST in "${EXPECTED[@]}"; do
  matched=""
  for key in "${!HOST_LASTSEEN[@]}"; do
    [[ "${key,,}" == "${HOST,,}" ]] && matched="$key" && break
  done
  [[ -n "$matched" ]] && ((ok++)) || ((missing++))
done
echo "  online:  $ok"
echo "  missing: $missing"
echo "  Total esperados: ${#EXPECTED[@]}"
