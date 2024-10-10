#Modify Line 5, 49, 72 and 75 accordingly. Line 75 is the DB FID which can be grabbed from RSC URL of that DB page.


# Import Service Account Info (For Windows path: C:\Users\Username\Desktop\File.json)
$ServiceAccountFilePath = "/Users/Deepender.Singh/Downloads/Deep00717879.json"
$ServiceAccount = Get-Content $ServiceAccountFilePath | ConvertFrom-Json

# Create Headers
$headers = @{
    "Content-Type" = "application/json"
}

# Payload to retrieve access token
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
        [string]$Query,
        [hashtable]$Variables,
        [hashtable]$Headers
    )

    $payload = @{
        query = $Query
        variables = $Variables
    }

    # Manually convert nested hashtables to JSON
    $payloadJson = $payload | ConvertTo-Json -Depth 10

    # Debug output to check the payload
    Write-Output "GraphQL Payload: $payloadJson"

    $response = Invoke-RestMethod -Uri "https://rubrik-support.my.rubrik.com/api/graphql" -Method Post -Body $payloadJson -ContentType "application/json" -Headers $Headers -UseBasicParsing

    return $response
}

# Define the GraphQL Mutation for on-demand backup
$mutation = @'
mutation MssqlTakeOnDemandSnapshotMutation($input: CreateOnDemandMssqlBackupInput!) {
  createOnDemandMssqlBackup(input: $input) {
    links {
      href
      __typename
    }
    __typename
  }
}
'@

# Define the Variables
$variables = @{
    input = @{
        config = @{
            baseOnDemandSnapshotConfig = @{
                slaId = "86fd0c70-1f2e-54b4-9bea-530220b0fdef"
            }
        }
        id = "5a3aba89-94fb-5eb3-b4b6-a3046007058d"
        userNote = ""
    }
}

# Execute the GraphQL Mutation
$response = Invoke-GraphQL -Query $mutation -Variables $variables -Headers $headers

# Check the response for errors or confirmation of success
if ($response.data.createOnDemandMssqlBackup -ne $null) {
    Write-Output "Backup started successfully."
    # Further inspect useful fields from the response
    if ($response.data.createOnDemandMssqlBackup.links -ne $null) {
        $links = $response.data.createOnDemandMssqlBackup.links
        Write-Output "Links:"
        $links | ForEach-Object { Write-Output $_.href }
    }
} elseif ($response.errors -ne $null) {
    Write-Output "Errors:"
    $response.errors | ForEach-Object { Write-Output $_.message }
} else {
    Write-Output "Unexpected response structure:"
    Write-Output $response
}