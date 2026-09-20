#!/usr/bin/env bash
# install-roles.sh — Register all ThruntOps roles with ludus
set -euo pipefail
shopt -s nullglob

ROLES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILED=()
EXTERNAL_ROLES_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$EXTERNAL_ROLES_DIR"
}
trap cleanup EXIT

for role_dir in "$ROLES_DIR"/ludus_*/ "$ROLES_DIR"/thruntops_*/; do
    role="$(basename "$role_dir")"
    echo -n "Adding $role ... "
    if ludus ansible role add -d "$role_dir" --force 2>&1; then
        echo "ok"
    else
        echo "FAILED"
        FAILED+=("$role")
    fi
done

echo "Installing pinned external roles..."
if ! ansible-galaxy role install \
    --role-file "$ROLES_DIR/requirements.yml" \
    --roles-path "$EXTERNAL_ROLES_DIR" \
    --force; then
    echo "Failed to download pinned external roles."
    exit 1
fi

for role_dir in "$EXTERNAL_ROLES_DIR"/ludus_*/; do
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
