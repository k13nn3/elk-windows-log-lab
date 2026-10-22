#!/usr/bin/env bash
# Nạp fingerprint CA (do bước certs sinh ra) vào biến môi trường cho kibana.yml
set -euo pipefail

FP_FILE=/usr/share/kibana/config/certs/ca/ca.fingerprint
if [ -z "${CA_FINGERPRINT:-}" ] && [ -f "$FP_FILE" ]; then
  export CA_FINGERPRINT="$(cat "$FP_FILE")"
fi

exec /usr/local/bin/kibana-docker "$@"
