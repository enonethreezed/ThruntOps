#!/usr/bin/env bash

if [[ -z "${RANGE_PREFIX:-}" ]]; then
  RANGE_NUM=$(ludus range status --json 2>/dev/null | jq -r '.rangeNumber // .range_number // empty' 2>/dev/null)
  if [[ -z "$RANGE_NUM" ]]; then
    echo "Error: no se pudo autodetectar el prefijo de red. Define RANGE_PREFIX, p.ej.: RANGE_PREFIX=10.1 $0"
    exit 1
  fi
  RANGE_PREFIX="10.${RANGE_NUM}"
fi

WAZUH_URL="https://${RANGE_PREFIX}.20.1:55000"
USER="wazuh"
PASS="Thisisapassword1-"

# Obtain JWT token
token=$(curl -sk --max-time 10 \
  -u "${USER}:${PASS}" \
  -X POST \
  "${WAZUH_URL}/security/user/authenticate" \
  | jq -r '.data.token // empty')

if [[ -z "$token" ]]; then
  echo "Error: no se pudo autenticar con la API de Wazuh (${WAZUH_URL})"
  echo "Comprueba que el servidor está activo y las credenciales son correctas."
  exit 1
fi

# Fetch all agents (excludes manager itself: id != 000)
response=$(curl -sk --max-time 10 \
  -H "Authorization: Bearer ${token}" \
  "${WAZUH_URL}/agents?limit=500&q=id!=000")

if ! echo "$response" | jq -e '.data.affected_items' > /dev/null 2>&1; then
  echo "Error al obtener agentes:"
  echo "$response" | jq '.' 2>/dev/null || echo "$response"
  exit 1
fi

echo "=== Wazuh Agent Status - $(date) ==="
echo ""

echo "$response" | jq -r '
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
echo "--- Resumen ---"
echo "$response" | jq -r '.data.affected_items[].status' | sort | uniq -c | while read -r count status; do
  echo "  $status: $count"
done

total=$(echo "$response" | jq '.data.total_affected_items')
echo "  Total agentes: $total"
