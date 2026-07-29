#!/usr/bin/env bash
# install-roles.sh — Register all ThruntOps roles with ludus
set -euo pipefail

ROLES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILED=()

for role_dir in "$ROLES_DIR"/ludus_*/; do
    role="$(basename "$role_dir")"
    echo -n "Adding $role ... "
    if ludus ansible role add -d "$role_dir" --force 2>&1; then
        echo "ok"
    else
        echo "FAILED"
        FAILED+=("$role")
    fi
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo ""
    echo "Failed roles: ${FAILED[*]}"
    exit 1
fi

echo ""
echo "All roles registered."
