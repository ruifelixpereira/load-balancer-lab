// ---------------------------------------------------------------------------
// Load Balancer – Standard SKU, public-facing
// Port-range rules route to separate backend pools via Bicep loops.
// ---------------------------------------------------------------------------

@description('Azure region')
param location string

@description('Load balancer resource name')
param lbName string

@description('Public IP resource ID for the frontend')
param publicIpId string

@description('VNet resource ID (required by IP-based backend pools)')
param vnetId string

@description('Private endpoint IP for Function A')
param funcAPrivateIp string

@description('Private endpoint IP for Function B')
param funcBPrivateIp string

@description('Start of the frontend port range routed to Function A')
param funcAPortStart int = 8000

@description('End of the frontend port range routed to Function A')
param funcAPortEnd int = 8020

@description('Start of the frontend port range routed to Function B')
param funcBPortStart int = 9000

@description('End of the frontend port range routed to Function B')
param funcBPortEnd int = 9020

// ---------------------------------------------------------------------------
// Computed helpers
// ---------------------------------------------------------------------------
var funcAPortCount = funcAPortEnd - funcAPortStart + 1
var funcBPortCount = funcBPortEnd - funcBPortStart + 1

// Self-referencing IDs – needed because the sub-resources are defined inline
var frontendConfigId = resourceId(
  'Microsoft.Network/loadBalancers/frontendIPConfigurations',
  lbName,
  'fe-public'
)
var poolFuncAId = resourceId(
  'Microsoft.Network/loadBalancers/backendAddressPools',
  lbName,
  'pool-func-a'
)
var poolFuncBId = resourceId(
  'Microsoft.Network/loadBalancers/backendAddressPools',
  lbName,
  'pool-func-b'
)
var probeHttpsId = resourceId(
  'Microsoft.Network/loadBalancers/probes',
  lbName,
  'probe-tcp-443'
)

// LB rules for Function A (one rule per port in the range)
var rulesA = [
  for i in range(0, funcAPortCount): {
    name: 'rule-funcA-${funcAPortStart + i}'
    properties: {
      frontendIPConfiguration: { id: frontendConfigId }
      backendAddressPool: { id: poolFuncAId }
      probe: { id: probeHttpsId }
      frontendPort: funcAPortStart + i
      backendPort: 443
      protocol: 'Tcp'
      enableFloatingIP: false
      enableTcpReset: true
      idleTimeoutInMinutes: 4
      loadDistribution: 'Default'
    }
  }
]

// LB rules for Function B (one rule per port in the range)
var rulesB = [
  for i in range(0, funcBPortCount): {
    name: 'rule-funcB-${funcBPortStart + i}'
    properties: {
      frontendIPConfiguration: { id: frontendConfigId }
      backendAddressPool: { id: poolFuncBId }
      probe: { id: probeHttpsId }
      frontendPort: funcBPortStart + i
      backendPort: 443
      protocol: 'Tcp'
      enableFloatingIP: false
      enableTcpReset: true
      idleTimeoutInMinutes: 4
      loadDistribution: 'Default'
    }
  }
]

// ---------------------------------------------------------------------------
// Load Balancer resource
// ---------------------------------------------------------------------------
resource lb 'Microsoft.Network/loadBalancers@2023-11-01' = {
  name: lbName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'fe-public'
        properties: {
          publicIPAddress: { id: publicIpId }
        }
      }
    ]
    backendAddressPools: [
      { name: 'pool-func-a' }
      { name: 'pool-func-b' }
    ]
    probes: [
      {
        name: 'probe-tcp-443'
        properties: {
          protocol: 'Tcp'
          port: 443
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
    ]
    //loadBalancingRules: concat(rulesA, rulesB)
  }
}

// ---------------------------------------------------------------------------
// Populate backend pools with the private-endpoint static IPs
// ---------------------------------------------------------------------------
resource poolFuncA 'Microsoft.Network/loadBalancers/backendAddressPools@2023-11-01' = {
  parent: lb
  name: 'pool-func-a'
  properties: {
    loadBalancerBackendAddresses: [
      {
        name: 'addr-func-a'
        properties: {
          virtualNetwork: { id: vnetId }
          ipAddress: funcAPrivateIp
        }
      }
    ]
  }
}

resource poolFuncB 'Microsoft.Network/loadBalancers/backendAddressPools@2023-11-01' = {
  parent: lb
  name: 'pool-func-b'
  properties: {
    loadBalancerBackendAddresses: [
      {
        name: 'addr-func-b'
        properties: {
          virtualNetwork: { id: vnetId }
          ipAddress: funcBPrivateIp
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output lbId string = lb.id
output lbName string = lb.name
output publicFrontendIpConfigId string = lb.properties.frontendIPConfigurations[0].id
