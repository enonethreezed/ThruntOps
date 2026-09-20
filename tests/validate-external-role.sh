#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROLE_DIR="${1:-$ROOT_DIR/../ThruntOps-vulnerabilities}"
REQUIREMENTS="$ROOT_DIR/roles/requirements.yml"

if [[ ! -d "$ROLE_DIR/.git" ]]; then
    echo "External role checkout not found: $ROLE_DIR" >&2
    exit 1
fi

expected_revision="$(grep 'version:' "$REQUIREMENTS" | cut -d: -f2- | tr -d ' ')"
actual_revision="$(git -C "$ROLE_DIR" rev-parse HEAD)"

if [[ "$actual_revision" != "$expected_revision" ]]; then
    echo "ludus_ad revision mismatch: expected $expected_revision, got $actual_revision" >&2
    exit 1
fi

grep -q '^  role_name: ludus_ad$' "$ROLE_DIR/meta/main.yml"

for scenario in CRED-ASREP-01 CRED-KERBEROAST-01 CRED-DESCRIPTION-01; do
    grep -q "^  - $scenario$" "$ROLE_DIR/vars/main.yml"
done

for variable in \
    ludus_ad_enabled \
    ludus_ad_isolated_lab \
    ludus_ad_scenarios \
    ludus_ad_asrep_users \
    ludus_ad_kerberoast_accounts \
    ludus_ad_description_credentials; do
    grep -q "^${variable}:" "$ROLE_DIR/defaults/main.yml"
done

echo "External ludus_ad role contract is compatible."
