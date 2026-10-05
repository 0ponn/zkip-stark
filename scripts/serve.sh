#!/usr/bin/env bash
# Run the API server with the prover's threads capped (default 4), so proofs
# leave the rest of the machine alone. Rayon reads RAYON_NUM_THREADS when its
# pool starts, so it must be set before launch.
#   ZKIP_API_KEY=<16+ chars> scripts/serve.sh [PORT] [--public]
set -euo pipefail
: "${ZKIP_API_KEY:?set ZKIP_API_KEY (16 or more characters)}"
export RAYON_NUM_THREADS="${RAYON_NUM_THREADS:-4}"
exec "$(dirname "$0")/../.lake/build/bin/Main" "$@"
