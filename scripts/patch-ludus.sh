#!/usr/bin/env bash
# patch-ludus.sh — Apply ThruntOps fixes to local ludus installation
# Run once on each new ludus host before deploying any range.
#
# Fixes applied:
#   gh-45 / ThruntOps-clp: sysinternals ignore_checksums hardcode
#   gh-46 / ThruntOps-zr6: kibana-setup.py 409 idempotency + Defend non-fatal

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

LUDUS_TOOLS_TASK="/opt/ludus/ansible/range-management/tasks/windows/add-additional-windows-tools.yml"
KIBANA_SETUP_TEMPLATE="/opt/ludus/users/ludus-admin/.ansible/roles/badsectorlabs.ludus_elastic_container/templates/kibana-setup.py.j2"

echo "[1/2] Patching sysinternals ignore_checksums (gh-45)..."
if ! sudo grep -q 'ignore_checksums: true' "$LUDUS_TOOLS_TASK" 2>/dev/null; then
    sudo sed -i \
        's/ignore_checksums: "{{ true if ignore_chocolatey_checksums is defined and ignore_chocolatey_checksums else false }}"/ignore_checksums: true/g' \
        "$LUDUS_TOOLS_TASK"
    echo "  Applied."
else
    echo "  Already patched, skipping."
fi

echo "[2/2] Patching kibana-setup.py.j2 idempotency (gh-46)..."
if ! sudo grep -q 'get_existing_agent_policy' "$KIBANA_SETUP_TEMPLATE" 2>/dev/null; then
    sudo cp -f "$KIBANA_SETUP_TEMPLATE" "${KIBANA_SETUP_TEMPLATE}.bak"
    sudo cp -f "$REPO_DIR/scripts/kibana-setup.py.j2.patch" "$KIBANA_SETUP_TEMPLATE"
    echo "  Applied."
else
    echo "  Already patched, skipping."
fi

echo "All patches applied."
