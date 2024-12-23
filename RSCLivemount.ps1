#RSC Script to LiveMount Sql Database with latest recovery point available. Modify line 4, 65, 71, 134 and 135 as required. 

# Path for service account JSON file downloaded from RSC (For Windows path: C:\Users\Username\Desktop\File.json)
$ServiceAccountFilePath = "/Users/deependersingh/Downloads/deepender.json"

# Function to Read and Validate the Service Account JSON File
function Get-ServiceAccount {
    param (
        [string]$filepath
    )

    if (-not (Test-Path -Path $filepath -PathType Leaf)) {
        Write-Error "Cannot find path '$filepath' because it does not exist."
        exit
    }

    $content = Get-Content -Path $filepath -Raw
    return $content | ConvertFrom-Json
}

# Read and Validate the Service Account JSON File
$ServiceAccount = Get-ServiceAccount -filepath $ServiceAccountFilePath

# Ensure access_token_uri is present
if (-not $ServiceAccount.access_token_uri) {
    Write-Error "The 'access_token_uri' field is missing or empty in the JSON file."
    exit
}

# Headers
$headers = @{
    "Content-Type" = "application/json"
}

# Payload to retrieve the access token
$body = @{
    client_id    = $ServiceAccount.client_id
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
$fid = "dffedb45-030f-5959-b417-b43f463e871e"

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
mutation MssqlDatabaseMountMutation($input: CreateMssqlLiveMountInput!) {
  createMssqlLiveMount(input: $input) {
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
            "targetInstanceId" = "7890e54a-c859-5569-ad47-a8a85431f2a7" #Instance ID from RSC URL
            "mountedDatabaseName" = "YourNewMount"
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
