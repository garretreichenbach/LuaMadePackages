// LuaMadePackages – Azure infrastructure
// Deploys a Storage Account + Function App (Consumption plan) for the package registry.
//
// Parameters
// ----------
// All parameters have defaults suitable for a development deployment.
// Override them via a parameters file or the --parameters flag.

@description('Azure region to deploy all resources into.')
param location string = resourceGroup().location

@description('Short environment name appended to resource names (e.g. dev, prod).')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Base name used to derive all resource names.')
@minLength(3)
@maxLength(16)
param appName string = 'luamadepkgs'

@description('SHA-256 hex digest of the API key used to authenticate publish/delete requests.')
@secure()
param apiKeyHash string

// ---------------------------------------------------------------------------
// Derived names – unique per subscription via uniqueString()
// ---------------------------------------------------------------------------

var suffix = uniqueString(resourceGroup().id)
var storageAccountName = toLower('${appName}${environment}${take(suffix, 6)}')
var functionAppName = '${appName}-${environment}-func'
var hostingPlanName = '${appName}-${environment}-plan'
var appInsightsName = '${appName}-${environment}-ai'

// ---------------------------------------------------------------------------
// Storage Account (Blob Storage for packages and metadata)
// ---------------------------------------------------------------------------

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: true // Required for anonymous package downloads
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource packagesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'packages'
  properties: {
    publicAccess: 'Blob' // Blobs are publicly readable; write requires the storage key
  }
}

// ---------------------------------------------------------------------------
// Application Insights (for monitoring and diagnostics)
// ---------------------------------------------------------------------------

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    RetentionInDays: 30
  }
}

// ---------------------------------------------------------------------------
// Consumption Plan (serverless Azure Functions)
// ---------------------------------------------------------------------------

resource hostingPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: hostingPlanName
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: false // Windows; set true for Linux
  }
}

// ---------------------------------------------------------------------------
// Function App
// ---------------------------------------------------------------------------

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${az.environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${az.environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~18'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'AZURE_STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${az.environment().suffixes.storage}'
        }
        {
          name: 'PACKAGES_CONTAINER'
          value: 'packages'
        }
        {
          name: 'API_KEY_HASH'
          value: apiKeyHash
        }
      ]
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
    }
    httpsOnly: true
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Public hostname of the deployed Function App.')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('Base API URL for the package registry.')
output apiBaseUrl string = 'https://${functionApp.properties.defaultHostName}/api'

@description('Storage account name.')
output storageAccountName string = storageAccount.name

@description('Packages container name.')
output packagesContainerName string = packagesContainer.name
