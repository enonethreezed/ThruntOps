#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <elk|splunk|wazuh>"
    exit 1
}

[[ $# -ne 1 ]] && usage

case "$1" in
    elk)    config="ranges/elastic-core.yml" ;;
    splunk) config="ranges/splunk-core.yml" ;;
    wazuh)  config="ranges/wazuh-core.yml" ;;
    *)      usage ;;
esac

ludus range destroy && \
ludus range config set -f "$config" && \
ludus range deploy && \
ludus range logs -f
