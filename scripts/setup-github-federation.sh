#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# setup-github-federation.sh
#
# Adds OIDC federated identity credentials to an existing Entra ID app
# registration so GitHub Actions can authenticate without secrets.
#
# Creates three credentials:
#   1. main branch pushes
#   2. pull requests
#   3. manual workflow_dispatch / environment (optional)
#
# Usage:
#   ./scripts/setup-github-federation.sh <GITHUB_ORG/REPO> [APP_NAME]
#
# Example:
#   ./scripts/setup-github-federation.sh myorg/load-balancer-lab
#
# Defaults:
#   APP_NAME = sp-lb-lab-ghactions
# ---------------------------------------------------------------------------
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <GITHUB_ORG/REPO> [APP_NAME]"
  echo "  e.g. $0 myorg/load-balancer-lab"
  exit 1
fi

GITHUB_REPO="$1"          # e.g. myorg/load-balancer-lab
APP_NAME="${2:-sp-lb-lab-ghactions}"

echo "==> GitHub repo : $GITHUB_REPO"
echo "==> App name    : $APP_NAME"
echo ""

# ---------------------------------------------------------------------------
# 1. Resolve the app registration object ID
# ---------------------------------------------------------------------------
APP_OBJECT_ID=$(az ad app list --display-name "$APP_NAME" --query '[0].id' -o tsv 2>/dev/null || true)

if [[ -z "$APP_OBJECT_ID" || "$APP_OBJECT_ID" == "None" ]]; then
  echo "ERROR: App registration '$APP_NAME' not found."
  echo "Run ./scripts/setup-azure-sp.sh first."
  exit 1
fi

echo "==> App object ID: $APP_OBJECT_ID"

# ---------------------------------------------------------------------------
# Helper – create a federated credential (idempotent)
# ---------------------------------------------------------------------------
add_credential() {
  local name="$1"
  local subject="$2"
  local description="$3"

  echo "==> Adding credential: $name"
  echo "    subject: $subject"

  # Check if it already exists
  EXISTING=$(az ad app federated-credential list \
    --id "$APP_OBJECT_ID" \
    --query "[?name=='$name'].name" \
    -o tsv 2>/dev/null || true)

  if [[ -n "$EXISTING" ]]; then
    echo "    (already exists – skipping)"
    return
  fi

  az ad app federated-credential create \
    --id "$APP_OBJECT_ID" \
    --parameters "{
      \"name\": \"$name\",
      \"issuer\": \"https://token.actions.githubusercontent.com\",
      \"subject\": \"$subject\",
      \"description\": \"$description\",
      \"audiences\": [\"api://AzureADTokenExchange\"]
    }" \
    -o none

  echo "    done."
}

# ---------------------------------------------------------------------------
# 2. Create federated credentials
# ---------------------------------------------------------------------------

# a) main branch
add_credential \
  "github-main" \
  "repo:${GITHUB_REPO}:ref:refs/heads/main" \
  "GitHub Actions – push to main branch"

# b) pull requests
add_credential \
  "github-pr" \
  "repo:${GITHUB_REPO}:pull_request" \
  "GitHub Actions – pull requests"

# c) environment (useful for workflow_dispatch with environments)
add_credential \
  "github-env-production" \
  "repo:${GITHUB_REPO}:environment:production" \
  "GitHub Actions – production environment"

# ---------------------------------------------------------------------------
# 3. Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================="
echo " Federated credentials configured."
echo "============================================="
echo ""
echo " Credentials added for repo: $GITHUB_REPO"
echo ""
echo "   1. github-main            – push to main"
echo "   2. github-pr              – pull requests"
echo "   3. github-env-production  – production environment"
echo ""
echo " Your GitHub Actions workflows can now authenticate"
echo " using azure/login@v2 with OIDC (no client secret needed)."
echo ""
