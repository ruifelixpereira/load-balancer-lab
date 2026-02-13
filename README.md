# Azure Load Balancer Lab – Port Range Routing to Azure Functions

This project deploys a **public Azure Load Balancer** that routes traffic by port
range to two **Azure Functions (Flex Consumption, Python 3.11)** via private
endpoints.

| Port Range  | Target       |
|-------------|-------------|
| 8000 – 8020 | Function A (`apiA`) |
| 9000 – 9020 | Function B (`apiB`) |

## Architecture

```
Internet
   │
   ▼
┌──────────────────────────┐
│  Public IP  (Standard)   │
└──────────┬───────────────┘
           ▼
┌──────────────────────────┐
│  Azure Load Balancer     │
│  (Standard, Regional)    │
│                          │
│  Rules 8000-8020 ──► pool-func-a ──► PE apiA (10.0.3.10)
│  Rules 9000-9020 ──► pool-func-b ──► PE apiB (10.0.3.20)
└──────────────────────────┘
           │
     ┌─────┴──────┐
     ▼            ▼
┌─────────┐  ┌─────────┐
│ apiA    │  │ apiB    │
│ (Flex)  │  │ (Flex)  │
└─────────┘  └─────────┘
```

## Directory Layout

```
├── infra/
│   ├── main.bicep              # Orchestrator
│   ├── main.bicepparam         # Default parameter values
│   └── modules/
│       ├── networking.bicep    # VNet, subnets, public IP, private DNS
│       ├── function-app.bicep  # Storage, plan, function app, PE, RBAC
│       └── load-balancer.bicep # LB, backend pools, per-port rules
├── src/
│   ├── apiA/                   # Python v2 Azure Function (API A)
│   └── apiB/                   # Python v2 Azure Function (API B)
├── scripts/
│   ├── setup-azure-sp.sh          # Create app reg + SP + roles
│   ├── setup-github-federation.sh # Add OIDC federated credentials
│   └── teardown-azure-sp.sh       # Delete everything created above
└── .github/workflows/
    ├── deploy-infra.yml        # Deploy Bicep infrastructure
    └── deploy-functions.yml    # Deploy function app code
```

## Prerequisites

| Requirement | Purpose |
|-------------|---------|
| Azure subscription | Host all resources |
| GitHub repo secrets | Authenticate to Azure from GitHub Actions |
| Bicep CLI or Azure CLI ≥ 2.61 | Compile & deploy Bicep |

### GitHub Secrets (OIDC federation)

Run the setup scripts in `scripts/` to create the service principal and federate
it with your GitHub repository:

```bash
# 1. Create the Entra ID app registration + service principal + role assignments
./scripts/setup-azure-sp.sh              # uses defaults: sp-lb-lab-ghactions, current subscription
# or with explicit values:
# ./scripts/setup-azure-sp.sh  sp-lb-lab-ghactions  <SUBSCRIPTION_ID>

# 2. Add OIDC federated credentials for GitHub Actions
./scripts/setup-github-federation.sh  <YOUR_GITHUB_ORG>/<YOUR_REPO>
# e.g. ./scripts/setup-github-federation.sh  myorg/load-balancer-lab
```

The first script prints the three values you need. Add them as **GitHub
repository secrets**:

| Secret | Description |
|--------|-------------|
| `AZURE_CLIENT_ID` | App registration client/application ID |
| `AZURE_TENANT_ID` | Microsoft Entra tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target Azure subscription |

The service principal is assigned **Contributor** + **User Access Administrator**
on the target subscription so it can create resources and assign RBAC roles.

To tear everything down later:

```bash
./scripts/teardown-azure-sp.sh           # deletes the app, SP, role assignments & federated creds
```

## Deploying

### Option 1 — GitHub Actions (recommended)

1. Push to `main` or trigger the **Deploy Infrastructure** workflow manually.
2. After infra completes, push changes under `src/` or trigger the
   **Deploy Functions** workflow manually.

### Option 2 — Azure CLI

```bash
# Create the resource group
az group create -n rg-lb-lab -l eastus2

# Deploy infrastructure
az deployment group create \
  -g rg-lb-lab \
  -f infra/main.bicep \
  -p location=eastus2 \
  --name main

# Deploy function code (requires Azure Functions Core Tools v4)
FUNC_A=$(az deployment group show -g rg-lb-lab -n main \
  --query 'properties.outputs.functionAppAName.value' -o tsv)
FUNC_B=$(az deployment group show -g rg-lb-lab -n main \
  --query 'properties.outputs.functionAppBName.value' -o tsv)

cd src/apiA && func azure functionapp publish "$FUNC_A" --python && cd -
cd src/apiB && func azure functionapp publish "$FUNC_B" --python && cd -
```

## Testing

After deployment, get the public IP from the outputs:

```bash
PIP=$(az deployment group show -g rg-lb-lab -n main \
  --query 'properties.outputs.publicIpAddress.value' -o tsv)

# Should reach API A (port range 8000-8020 → function A, backend 443)
curl https://$PIP:8000/api/health --insecure

# Should reach API B (port range 9000-9020 → function B, backend 443)
curl https://$PIP:9000/api/health --insecure
```

> **Note:** The LB forwards each frontend port to backend port **443** on the
> respective function's private endpoint. Azure Functions respond on 443 via the
> private link connection. TLS certificate validation will fail with `--insecure`
> because the cert is issued for `*.azurewebsites.net`, not the public IP.

## Design Notes

- **Port ranges via Bicep loops**: Azure LB rules support a single
  `frontendPort`/`backendPort` pair. To cover a range, the
  [load-balancer.bicep](infra/modules/load-balancer.bicep) module generates one
  rule per port using `for … in range()` and `concat()` to merge both ranges
  into a single `loadBalancingRules` array.
- **IP-based backend pools**: The private endpoints are assigned static IPs
  (`10.0.3.10` / `10.0.3.20`). The backend pools reference these IPs directly
  (no NIC association required).
- **Private DNS zone**: A `privatelink.azurewebsites.net` zone is linked to the
  VNet so that the functions' hostnames resolve to the private endpoint IPs
  inside the network.

## Cleanup

```bash
az group delete -n rg-lb-lab --yes --no-wait
```
