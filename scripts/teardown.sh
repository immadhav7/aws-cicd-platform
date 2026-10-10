#!/usr/bin/env bash
# Destroys billable infrastructure in reverse dependency order.
# Does NOT touch infra/bootstrap (state bucket) or infra/registry (ECR images):
# both are nearly free and must survive.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Order matters: the platform (ECS, ALB) depends on the network, so it goes first.
# Add later modules (e.g. pipeline) at the TOP of this list.
MODULES=(
  platform
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

echo "Done. Check the EC2 console (Load Balancers) and VPC console (NAT gateways, Elastic IPs) for leftovers."
