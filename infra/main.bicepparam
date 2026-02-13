using './main.bicep'

param location = 'eastus2'
param baseName = 'lblab'
param funcAPrivateEndpointIp = '10.0.3.10'
param funcBPrivateEndpointIp = '10.0.3.20'
// param deployerPrincipalId = '<SP_OBJECT_ID>'  // passed at deploy time by the workflow
