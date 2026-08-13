#!/bin/sh
set -eu

failure_count=0
while true; do
  if curl --fail --silent --show-error --max-time 8 \
    "https://$MUTO_API_DOMAIN/health/ready" >/dev/null; then
    failure_count=0
  else
    failure_count=$((failure_count + 1))
    if [ "$failure_count" -eq 3 ]; then
      message="Muto readiness failed three consecutive checks"
      echo "$message" >&2
      if [ -n "${ALERT_WEBHOOK_URL:-}" ]; then
        escaped=$(printf '%s' "$message" | sed 's/"/\\"/g')
        curl --fail --silent --show-error --max-time 8 \
          -H 'Content-Type: application/json' \
          --data "{\"text\":\"$escaped\"}" "$ALERT_WEBHOOK_URL" >/dev/null || true
      fi
    fi
  fi
  sleep 60
done
