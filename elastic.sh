#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <--base|--dual|--adcs>"
    exit 1
}

[[ $# -ne 1 ]] && usage

case "$1" in
    --base) config="ranges/elk-base.yml" ;;
    --dual) config="ranges/elk-dual.yml" ;;
    --adcs) config="ranges/elk-adcs.yml" ;;
    *)      usage ;;
esac

ludus range destroy --no-prompt && \
ludus range config set -f "$config" && \
ludus range deploy && \
ludus range logs -f
