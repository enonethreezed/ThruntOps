#!/usr/bin/env bash

if [[ -z "${RANGE_PREFIX:-}" ]]; then
  RANGE_NUM=$(ludus range status --json 2>/dev/null | jq -r '.rangeNumber // .range_number // empty' 2>/dev/null)
  if [[ -z "$RANGE_NUM" ]]; then
    echo "Error: could not autodetect the network prefix. Set RANGE_PREFIX, e.g.: RANGE_PREFIX=10.1 $0"
    exit 1
  fi
  RANGE_PREFIX="10.${RANGE_NUM}"
fi

KIBANA_URL="https://${RANGE_PREFIX}.20.1:5601"
USER="elastic"
PASS="thisisapassword"

response=$(curl -sk --max-time 10 \
  -u "${USER}:${PASS}" \
  -H "kbn-xsrf: true" \
  "${KIBANA_URL}/api/fleet/agents?perPage=100")

if ! echo "$response" | jq -e '.items' > /dev/null 2>&1; then
  echo "Error contacting the Fleet API:"
  echo "$response" | jq '.' 2>/dev/null || echo "$response"
  exit 1
fi

echo "=== Fleet Agent Status - $(date) ==="
echo ""

echo "$response" | jq -r '
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
echo "$response" | jq -r '[ .items[] | select(.active == true and .status != "uninstalled") ] | group_by(.local_metadata.host.hostname // .id) | .[] | sort_by(.last_checkin) | last | .status // "unknown"' | sort | uniq -c | while read -r count status; do
  echo "  $status: $count"
done
