// ---------------------------------------------------------------------------
// Main orchestrator – deploys networking, two Flex Consumption function apps
// (apiA & apiB) with private endpoints, and a public Azure Load Balancer
// that routes port ranges 8000-8020 → apiA and 9000-9020 → apiB.
// ---------------------------------------------------------------------------
targetScope = 'resourceGroup'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Base name prefix used for naming resources')
param baseName string = 'lblab'

@description('Static private IP for Function A private endpoint (must be in snet-pe 10.0.3.0/24)')
param funcAPrivateEndpointIp string = '10.0.3.10'

@description('Static private IP for Function B private endpoint (must be in snet-pe 10.0.3.0/24)')
param funcBPrivateEndpointIp string = '10.0.3.20'

@description('Object (principal) ID of the deploying service principal – granted Storage Blob Data Contributor on deployment storage accounts')
param deployerPrincipalId string = ''

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------
var suffix = uniqueString(resourceGroup().id)
var funcAName = 'func-apia-${suffix}'
var funcBName = 'func-apib-${suffix}'
var storageAName = 'stapia${suffix}'
var storageBName = 'stapib${suffix}'

// ---------------------------------------------------------------------------
// Observability – Log Analytics + Application Insights
// ---------------------------------------------------------------------------
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${baseName}-${suffix}'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${baseName}-${suffix}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// ---------------------------------------------------------------------------
// Networking (VNet, subnets, public IP, private DNS zone)
// ---------------------------------------------------------------------------
module networking 'modules/networking.bicep' = {
  name: 'networking'
  params: {
    location: location
    baseName: '${baseName}-${suffix}'
  }
}

// ---------------------------------------------------------------------------
// Function App A  (apiA – Python, Flex Consumption)
// ---------------------------------------------------------------------------
module funcAppA 'modules/function-app.bicep' = {
  name: 'funcAppA'
  params: {
    location: location
    funcAppName: funcAName
    storageAccountName: storageAName
    funcSubnetId: networking.outputs.snetFuncAId
    peSubnetId: networking.outputs.snetPeId
    privateEndpointIp: funcAPrivateEndpointIp
    privateDnsZoneId: networking.outputs.privateDnsZoneId
    appInsightsConnectionString: appInsights.properties.ConnectionString
    deployerPrincipalId: deployerPrincipalId
  }
}

// ---------------------------------------------------------------------------
// Function App B  (apiB – Python, Flex Consumption)
// ---------------------------------------------------------------------------
module funcAppB 'modules/function-app.bicep' = {
  name: 'funcAppB'
  params: {
    location: location
    funcAppName: funcBName
    storageAccountName: storageBName
    funcSubnetId: networking.outputs.snetFuncBId
    peSubnetId: networking.outputs.snetPeId
    privateEndpointIp: funcBPrivateEndpointIp
    privateDnsZoneId: networking.outputs.privateDnsZoneId
    appInsightsConnectionString: appInsights.properties.ConnectionString
    deployerPrincipalId: deployerPrincipalId
  }
}

// ---------------------------------------------------------------------------
// Load Balancer (public, Standard SKU)
//   Ports 8000-8020 → Function A    |    Ports 9000-9020 → Function B
// ---------------------------------------------------------------------------
module loadBalancer 'modules/load-balancer.bicep' = {
  name: 'loadBalancer'
  params: {
    location: location
    lbName: 'lb-${baseName}-${suffix}'
    publicIpId: networking.outputs.publicIpId
    vnetId: networking.outputs.vnetId
    funcAPrivateIp: funcAPrivateEndpointIp
    funcBPrivateIp: funcBPrivateEndpointIp
    funcAPortStart: 8000
    funcAPortEnd: 8020
    funcBPortStart: 9000
    funcBPortEnd: 9020
  }
  dependsOn: [funcAppA, funcAppB]
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output functionAppAName string = funcAppA.outputs.functionAppName
output functionAppBName string = funcAppB.outputs.functionAppName
output functionAppAHostName string = funcAppA.outputs.defaultHostName
output functionAppBHostName string = funcAppB.outputs.defaultHostName
output publicIpAddress string = networking.outputs.publicIpAddress
output loadBalancerName string = loadBalancer.outputs.lbName
