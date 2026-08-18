#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <--base|--dual|--adcs>"
    exit 1
}

[[ $# -ne 1 ]] && usage

case "$1" in
    --base) config="ranges/wazuh-base.yml" ;;
    --dual) config="ranges/wazuh-dual.yml" ;;
    --adcs) config="ranges/wazuh-adcs.yml" ;;
    *)      usage ;;
esac

ludus range destroy --no-prompt && \
ludus range config set -f "$config" && \
ludus range deploy && \
ludus range logs -f
