#!/usr/bin/env bash
# Rollback demo switch: turn the simulated fault in prod's task definition on or off.
# It only edits deploy/taskdef.json; you commit and push it, and the pipeline does the rest.
# Usage: scripts/fault.sh on|off
set -euo pipefail

FILE="$(cd "$(dirname "$0")/.." && pwd)/deploy/taskdef.json"
case "${1:-}" in
  on)  VALUE=1 ;;
  off) VALUE=0 ;;
  *) echo "Usage: $0 on|off" >&2; exit 2 ;;
esac

sed -i -E 's/("name": "SIMULATE_FAULT", "value": ")[01]"/\1'"${VALUE}"'"/' "${FILE}"
grep SIMULATE_FAULT "${FILE}"
