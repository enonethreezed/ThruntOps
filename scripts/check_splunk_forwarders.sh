#!/usr/bin/env bash
# check_splunk_forwarders.sh
# Queries the Splunk REST API and checks which expected hosts are reporting.
#
# Usage:
#   ./scripts/check_splunk_forwarders.sh <range_id> [splunk_ip] [password]
#
# Defaults:
#   splunk_ip  -> 10.2.50.1
#   password   -> thisisapassword
#
# Run from the ops VM or any host with network access to the Splunk server.

set -euo pipefail

RANGE_ID="${1:-}"
SPLUNK_IP="${2:-10.2.50.1}"
SPLUNK_PASS="${3:-thisisapassword}"
SPLUNK_USER="admin"
SPLUNK_PORT="8089"
LOOKBACK="1h"

if [[ -z "$RANGE_ID" ]]; then
  echo "Usage: $0 <range_id> [splunk_ip] [password]"
  echo "  range_id: your Ludus range prefix (e.g. JD)"
  exit 1
fi

# Expected hostnames (must match what Splunk receives as 'host' field)
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

echo "==> Querying Splunk at https://${SPLUNK_IP}:${SPLUNK_PORT} (last ${LOOKBACK})"
echo ""

# Run a one-shot search via REST API
SEARCH="search index=* earliest=-${LOOKBACK} | stats count by host | fields host"

RESPONSE=$(curl -sk \
  -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
  "https://${SPLUNK_IP}:${SPLUNK_PORT}/services/search/jobs/export" \
  --data-urlencode "search=${SEARCH}" \
  -d "output_mode=json" \
  -d "exec_mode=oneshot" \
  -d "count=0")

# Extract host values from JSON results
REPORTING_HOSTS=$(echo "$RESPONSE" | python3 -c "
import sys, json
hosts = set()
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        if obj.get('result', {}).get('host'):
            hosts.add(obj['result']['host'])
    except json.JSONDecodeError:
        pass
for h in sorted(hosts):
    print(h)
")

echo "Hosts reporting to Splunk (last ${LOOKBACK}):"
echo "$REPORTING_HOSTS" | sed 's/^/  ✓ /'
echo ""

echo "Forwarder status by expected host:"
ALL_OK=true
for HOST in "${EXPECTED[@]}"; do
  if echo "$REPORTING_HOSTS" | grep -qiF "$HOST"; then
    echo "  [OK]     $HOST"
  else
    echo "  [MISSING] $HOST"
    ALL_OK=false
  fi
done

echo ""
if $ALL_OK; then
  echo "All forwarders reporting."
else
  echo "One or more forwarders not reporting. Check:"
  echo "  - Windows: services.msc -> SplunkForwarder"
  echo "  - Linux:   systemctl status SplunkForwarder"
  echo "  - Firewall: port 9997/tcp to ${SPLUNK_IP}"
fi
