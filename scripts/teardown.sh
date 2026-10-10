#!/usr/bin/env bash
# Destroys billable infrastructure in reverse dependency order.
# Does NOT touch infra/bootstrap (the state bucket is cheap and must survive).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Add new modules at the TOP of this list as later phases are built
# (e.g. pipeline, platform), so they are destroyed before the network.
MODULES=(
  network
)

for module in "${MODULES[@]}"; do
  dir="$ROOT/infra/$module"
  if [ -d "$dir/.terraform" ]; then
    echo "==> Destroying $module"
    (cd "$dir" && terraform destroy)
  else
    echo "==> Skipping $module (not initialised)"
  fi
done

echo "Done. Check the VPC console for leftovers (NAT gateways and Elastic IPs cost money)."
