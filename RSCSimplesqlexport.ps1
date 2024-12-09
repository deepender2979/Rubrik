#RSC Script to export Sql Database with latest recovery point available. Modify line 4, 49 and 112 to 118 as required. 

# Path for service account JSON file downloaded from RSC (For Windows path: C:\Users\Username\Desktop\File.json)
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

# Get the fid for the MSSQL database from RSC URL
$fid = "3cf776b6-a3b8-5d15-a693-47adb38c2a50"

# GraphQL query for recoverable ranges
$recoverableRangesQuery = @'
query MssqlDatabaseRecoverableRangesQuery($fid: String!) {
  mssqlRecoverableRanges(input: {id: $fid}) {
    data {
      beginTime
      endTime
      __typename
    }
    __typename
  }
}
'@

# Variables for the query
$recoverableRangesVariables = @{
    "fid" = $fid
}

# Call the GraphQL function to get recoverable ranges
$responseRecoverableRanges = Invoke-GraphQL -Query $recoverableRangesQuery -Variables $recoverableRangesVariables -Headers $headers

# Handle the response and get the latest recoverable range
if ($responseRecoverableRanges -ne $null -and $responseRecoverableRanges -ne "") {
    Write-Output "Recoverable Ranges Response: $($responseRecoverableRanges | ConvertTo-Json -Depth 10)"
    $latestRecoverableRange = $responseRecoverableRanges.data.mssqlRecoverableRanges.data | Sort-Object -Property endTime -Descending | Select-Object -First 1
    if ($latestRecoverableRange -ne $null) {
        Write-Output "Latest Recoverable Range: Begin Time: $($latestRecoverableRange.beginTime), End Time: $($latestRecoverableRange.endTime)"
        $recoveryPointDate = $latestRecoverableRange.endTime
    } else {
        Write-Output "Error: No recoverable ranges found."
        exit
    }
} else {
    Write-Output "Error: No response from GraphQL API for recoverable ranges."
    exit
}

# GraphQL mutation for exporting MSSQL database
$mutation = @'
mutation MssqlDatabaseExportMutation($input: ExportMssqlDatabaseInput!) {
  exportMssqlDatabase(input: $input) {
    id
    links {
      href
      rel
      __typename
    }
    __typename
  }
}
'@

# Variables for the mutation
$variables = @{
    "input" = @{
        "id" = $fid
        "config" = @{
            "recoveryPoint" = @{
                "date" = $recoveryPointDate
            }
            "targetInstanceId" = "269c0afc-f9b9-51cf-9b79-5ee4f56e4344" #Instance ID from RSC URL
            "targetDatabaseName" = "master_deep"
            "targetDataFilePath" = "c:/temp"
            "targetLogFilePath" = "c:/temp"
            "targetFilePaths" = @()
            "allowOverwrite" = $false
            "finishRecovery" = $true
        }
    }
}

# Call the GraphQL function to export MSSQL database
$responseExport = Invoke-GraphQL -Query $mutation -Variables $variables -Headers $headers

# Handle the response
if ($responseExport -ne $null -and $responseExport -ne "") {
    Write-Output "GraphQL Response: $($responseExport | ConvertTo-Json -Depth 10)"
} else {
    Write-Output "Error: No response from GraphQL API."
}
