#!/usr/bin/env bash
# Add a Kali Linux attacker VM to the range and deploy it.
# Safe to run multiple times — checks if kali is already present.

set -euo pipefail

KALI_VM_NAME_PATTERN="-kali"

# Check if kali is already in the range config
if ludus range config get 2>/dev/null | grep -q "${KALI_VM_NAME_PATTERN}"; then
  echo "Kali is already in the range config."
  echo "To redeploy: ludus range deploy --tags all-tasks --limit '*-kali'"
  exit 0
fi

echo "Adding Kali to range config..."

# Get current config and append kali definition
CURRENT_CONFIG=$(ludus range config get)
KALI_DEFINITION=$(cat <<'EOF'
  - vm_name: "{{ range_id }}-kali"
    hostname: "{{ range_id }}-kali"
    template: kali-x64-desktop-template
    vlan: 50
    ip_last_octet: 250
    ram_gb: 4
    cpus: 4
    linux: true
    testing:
      snapshot: false
      block_internet: false
EOF
)

NEW_CONFIG="${CURRENT_CONFIG}
${KALI_DEFINITION}"

echo "$NEW_CONFIG" | ludus range config set -f /dev/stdin

echo "Deploying Kali..."
ludus range deploy --tags all-tasks --limit '*-kali'

echo ""
echo "Monitor progress: ludus range logs -f"
echo "Kali IP: 10.2.50.250"
