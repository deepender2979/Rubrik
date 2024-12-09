# Paths and service account information
$ServiceAccountFilePath = "/Users/Deepender.Singh/Downloads/deepender.json"
$ServiceAccount = Get-Content $ServiceAccountFilePath | ConvertFrom-Json

# Headers
$headers = @{
    "Content-Type" = "application/json"
}

# Payload to retrieve the access token
$body = @{
    client_id = $ServiceAccount.client_id
    client_secret = $ServiceAccount.client_secret
}
$bodyJson = $body | ConvertTo-Json

# Get Access Token
$response = Invoke-RestMethod -Uri $ServiceAccount.access_token_uri -Method Post -Body $bodyJson -Headers $headers -UseBasicParsing

# Debug output to check the response
Write-Output "Access Token Response: $response"

# Add access token to headers
$headers["Authorization"] = "Bearer $($response.access_token)"

# Function to run a GraphQL Query/Mutation
function Invoke-GraphQL {
    param (
        [string]$query,
        [hashtable]$variables,
        [hashtable]$headers
    )

    # Construct payload
    $payloadJson = @{
        query = $query
        variables = $variables
    } | ConvertTo-Json -Depth 10

    $response = Invoke-RestMethod -Uri "https://rubrik-support.my.rubrik.com/api/graphql" -Method Post -Body $payloadJson -ContentType "application/json" -Headers $headers -UseBasicParsing

    return $response
}

# GraphQL mutation
$mutation = 'mutation MssqlDatabaseExportMutation($input: ExportMssqlDatabaseInput!) {
  exportMssqlDatabase(input: $input) {
    id
    links {
      href
      rel
      __typename
    }
    __typename
  }
}'

# Variables for the mutation
$variables = @{
    "input" = @{
        "id" = "3cf776b6-a3b8-5d15-a693-47adb38c2a50"
        "config" = @{
            "recoveryPoint" = @{
                "date" = "2024-12-09T00:00:12.000Z"
            }
            "targetInstanceId" = "269c0afc-f9b9-51cf-9b79-5ee4f56e4344"
            "targetDatabaseName" = "master23"
            "targetDataFilePath" = "c:/temp"
            "targetLogFilePath" = "c:/temp"
            "targetFilePaths" = @()
            "allowOverwrite" = $false
            "finishRecovery" = $true
        }
    }
}

# Call the GraphQL function
$response = Invoke-GraphQL -Query $mutation -Variables $variables -Headers $headers

# Handle the response
if ($response -ne $null -and $response -ne "") {
    Write-Output "GraphQL Response: $($response | ConvertTo-Json -Depth 10)"
} else {
    Write-Output "Error: No response from GraphQL API."
}