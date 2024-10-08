# This script removes legal hold on all snapshots for snappable FIDs read from provided file.
# Modify line 11, 49 and 111 as required.
# You will need a service account created with Administrator role and please set the execution policy on your system running powershell as required.

#create a file with snappable IDs in new lines- snappableIds.txt
#eb4572df-1bdb-5641-929b-f232bf2d0cb0
#another-snappable-id
#another-snappable-id

# Import Service Account Info(For Windows path: C:\Users\Username\Desktop\File.json)
$ServiceAccountFilePath = "/Users/Deepender.Singh/Downloads/deepender.json"
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
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri "https://rubrik-support.my.rubrik.com/api/graphql" -Method Post -Body $payload -ContentType "application/json" -Headers $Headers -UseBasicParsing

    return $response.data
}

# Define the function to fetch snapshot FIDs
function Get-SnapshotFids {
    param (
        [string]$snappableId,
        [hashtable]$Headers
    )

    $snapshotsQuery = @"
query SnapshotsListSingleQuery(`$snappableId: String!) {
    snapshotsListConnection: snapshotOfASnappableConnection(workloadId: `$snappableId) {
        edges {
            node {
                id
                date
            }
        }
    }
}
"@

    $snapshotsQueryVariables = @{
        snappableId = $snappableId
    }

    $snapshotsResult = Invoke-GraphQL -Query $snapshotsQuery -Variables $snapshotsQueryVariables -Headers $Headers
    $snapshots = $snapshotsResult.snapshotsListConnection.edges.node

    return $snapshots
}

# Define the function to remove snapshots from legal hold
function Remove-LegalHold {
    param (
        [array]$snapshotFids,
        [string]$userNote,
        [hashtable]$Headers
    )

    $removeLegalHoldMutation = @"
mutation RemoveLegalHoldMutation(`$snapshotFids: [String!]!, `$userNote: String) {
    dissolveLegalHold(input: {snapshotIds: `$snapshotFids, userNote: `$userNote}) {
        snapshotIds
        __typename
    }
}
"@

    $removeLegalHoldVariables = @{
        snapshotFids = $snapshotFids
        userNote = $userNote
    }

    $removeLegalHoldResult = Invoke-GraphQL -Query $removeLegalHoldMutation -Variables $removeLegalHoldVariables -Headers $Headers
    return $removeLegalHoldResult
}

# Read snappable IDs from a text file
$snappableIdsFilePath = "/Users/Deepender.Singh/Downloads/snappableIds.txt"
$snappableIds = Get-Content $snappableIdsFilePath

# Iterate over each snappable ID
foreach ($snappableId in $snappableIds) {
    Write-Output "Processing snappable ID: $snappableId"

    # Retrieve snapshot FIDs and dates for the current snappable ID
    $snapshots = Get-SnapshotFids -snappableId $snappableId -Headers $headers

    # Output the snapshot details
    foreach ($snapshot in $snapshots) {
        Write-Output "Snapshot ID: $($snapshot.id), Date: $($snapshot.date)"
    }

    # Extract snapshot IDs for the mutation
    $snapshotFids = $snapshots | ForEach-Object { $_.id }

    # Remove the snapshots from legal hold if there are any snapshots
    if ($snapshotFids.Count -gt 0) {
        $removeLegalHoldResult = Remove-LegalHold -snapshotFids $snapshotFids -userNote "" -Headers $headers
        # Output the result
        Write-Output "Legal hold removed for snappable ID: $snappableId"
        Write-Output "Result: $($removeLegalHoldResult)"
    } else {
        Write-Output "No snapshots found for snappable ID: $snappableId"
    }
}