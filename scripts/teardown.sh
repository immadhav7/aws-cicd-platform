#!/usr/bin/env bash
# Destroys billable infrastructure in reverse dependency order:
# prod, then dev (platform workspaces), then the network.
# Does NOT touch infra/bootstrap (state bucket), infra/registry (ECR images) or
# infra/pipeline (idle cost is pennies, and destroying it would drop the GitHub authorization).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PLATFORM="$ROOT/infra/platform"
if [ -d "$PLATFORM/.terraform" ]; then
  cd "$PLATFORM"
  # Workspace "prod" is the prod environment; "default" is dev.
  for ws in prod default; do
    if terraform workspace list | grep -qw "$ws"; then
      echo "==> Destroying platform ($ws)"
      terraform workspace select "$ws"
      terraform destroy
    fi
  done
  terraform workspace select default
else
  echo "==> Skipping platform (not initialised)"
fi

NETWORK="$ROOT/infra/network"
if [ -d "$NETWORK/.terraform" ]; then
  echo "==> Destroying network"
  (cd "$NETWORK" && terraform destroy)
else
  echo "==> Skipping network (not initialised)"
fi

echo "Done. Check the EC2 console (Load Balancers) and VPC console (NAT gateways, Elastic IPs) for leftovers."
