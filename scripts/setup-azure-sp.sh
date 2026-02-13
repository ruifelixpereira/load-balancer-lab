#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# setup-azure-sp.sh
#
# Creates a Microsoft Entra ID app registration + service principal, assigns
# Contributor + User Access Administrator roles on the target subscription,
# and outputs the values you need for GitHub secrets.
#
# Usage:
#   ./scripts/setup-azure-sp.sh [APP_NAME] [SUBSCRIPTION_ID]
#
# Defaults:
#   APP_NAME         = sp-lb-lab-ghactions
#   SUBSCRIPTION_ID  = current az account subscription
# ---------------------------------------------------------------------------
set -euo pipefail

APP_NAME="${1:-sp-lb-lab-ghactions}"
SUBSCRIPTION_ID="${2:-$(az account show --query id -o tsv)}"

echo "==> Subscription : $SUBSCRIPTION_ID"
echo "==> App name     : $APP_NAME"
echo ""

# ---------------------------------------------------------------------------
# 1. Create the app registration (idempotent – reuses if it already exists)
# ---------------------------------------------------------------------------
EXISTING_APP_ID=$(az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv 2>/dev/null || true)

if [[ -n "$EXISTING_APP_ID" && "$EXISTING_APP_ID" != "None" ]]; then
  echo "==> App registration already exists: $EXISTING_APP_ID"
  APP_ID="$EXISTING_APP_ID"
else
  echo "==> Creating app registration..."
  APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
  echo "    App (client) ID: $APP_ID"
fi

# ---------------------------------------------------------------------------
# 2. Ensure a service principal exists for the app
# ---------------------------------------------------------------------------
EXISTING_SP=$(az ad sp list --filter "appId eq '$APP_ID'" --query '[0].id' -o tsv 2>/dev/null || true)

if [[ -n "$EXISTING_SP" && "$EXISTING_SP" != "None" ]]; then
  echo "==> Service principal already exists."
  SP_OBJECT_ID="$EXISTING_SP"
else
  echo "==> Creating service principal..."
  SP_OBJECT_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)
fi
echo "    SP object ID: $SP_OBJECT_ID"

# ---------------------------------------------------------------------------
# 3. Assign roles at subscription scope
# ---------------------------------------------------------------------------
SCOPE="/subscriptions/$SUBSCRIPTION_ID"

assign_role() {
  local role="$1"
  echo "==> Assigning role: $role"
  az role assignment create \
    --assignee-object-id "$SP_OBJECT_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "$role" \
    --scope "$SCOPE" \
    --only-show-errors \
    -o none 2>/dev/null || echo "    (role may already be assigned)"
}

assign_role "Contributor"
assign_role "User Access Administrator"

# ---------------------------------------------------------------------------
# 4. Retrieve tenant ID
# ---------------------------------------------------------------------------
TENANT_ID=$(az account show --query tenantId -o tsv)

# ---------------------------------------------------------------------------
# 5. Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================="
echo " Add these as GitHub repository secrets:"
echo "============================================="
echo ""
echo "  AZURE_CLIENT_ID        = $APP_ID"
echo "  AZURE_TENANT_ID        = $TENANT_ID"
echo "  AZURE_SUBSCRIPTION_ID  = $SUBSCRIPTION_ID"
echo ""
echo "Next step: run ./scripts/setup-github-federation.sh to create"
echo "the OIDC federated credentials for your GitHub repo."
echo ""
