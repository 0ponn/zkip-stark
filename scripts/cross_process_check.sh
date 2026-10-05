#!/usr/bin/env bash
# A certificate must verify in a process other than the one that proved it
# (the verifying key once depended on the prover's RNG). Proves on one server,
# stops it, and verifies on a freshly started one.
#   ZKIP_API_KEY=<key> scripts/cross_process_check.sh [PORT]
set -euo pipefail
: "${ZKIP_API_KEY:?set ZKIP_API_KEY}"
PORT="${1:-8081}"
DIR="$(cd "$(dirname "$0")" && pwd)"
CERT="$(mktemp)"
trap 'rm -f "$CERT"; kill "${PID:-0}" 2>/dev/null || true' EXIT

start() {
  "$DIR/serve.sh" "$PORT" >/dev/null 2>&1 &
  PID=$!
  for _ in $(seq 1 120); do
    curl -s -o /dev/null "http://localhost:$PORT/health" && return 0
    sleep 1
  done
  echo "server did not start"; exit 1
}

start
curl -s --max-time 120 -H "Authorization: Bearer $ZKIP_API_KEY" -H "Content-Type: application/json" \
  -X POST "http://localhost:$PORT/api/v1/certificate/generate" \
  -d '{"id": 5, "attributes": [{"type": "performance", "value": 1500}, {"type": "custom", "name": "uptime", "value": 99}],
       "disclosures": [{"attributeIndex": 0, "predicate": {"threshold": 1000, "operator": ">"}},
                       {"attributeIndex": 1, "predicate": {"threshold": 95, "operator": ">"}}]}' \
  | jq -c '.certificate' > "$CERT"
kill "$PID"; wait "$PID" 2>/dev/null || true

start
VERIFIED=$(curl -s --max-time 120 -X POST "http://localhost:$PORT/api/v1/certificate/verify" \
  -H "Content-Type: application/json" --data @"$CERT" | jq -r '.verified')
if [ "$VERIFIED" = "true" ]; then
  echo "✓ certificate proved in one process verifies in another"
else
  echo "✗ cross-process verification failed (verified=$VERIFIED)"; exit 1
fi
