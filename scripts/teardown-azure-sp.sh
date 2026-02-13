#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# teardown-azure-sp.sh
#
# Removes the app registration, service principal, role assignments, and
# federated credentials created by the setup scripts.
#
# Usage:
#   ./scripts/teardown-azure-sp.sh [APP_NAME]
# ---------------------------------------------------------------------------
set -euo pipefail

APP_NAME="${1:-sp-lb-lab-ghactions}"

echo "==> Looking up app registration: $APP_NAME"

APP_ID=$(az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv 2>/dev/null || true)

if [[ -z "$APP_ID" || "$APP_ID" == "None" ]]; then
  echo "App registration '$APP_NAME' not found. Nothing to do."
  exit 0
fi

echo "==> App (client) ID: $APP_ID"

# Remove role assignments for the SP
SP_OBJECT_ID=$(az ad sp list --filter "appId eq '$APP_ID'" --query '[0].id' -o tsv 2>/dev/null || true)
if [[ -n "$SP_OBJECT_ID" && "$SP_OBJECT_ID" != "None" ]]; then
  echo "==> Removing role assignments for SP $SP_OBJECT_ID ..."
  az role assignment delete --assignee "$SP_OBJECT_ID" --yes 2>/dev/null || true
fi

# Delete the app registration (this also deletes the SP and federated creds)
echo "==> Deleting app registration (and associated SP + federated credentials)..."
APP_OBJECT_ID=$(az ad app list --display-name "$APP_NAME" --query '[0].id' -o tsv)
az ad app delete --id "$APP_OBJECT_ID"

echo ""
echo "Done. App registration '$APP_NAME' has been deleted."
echo ""
