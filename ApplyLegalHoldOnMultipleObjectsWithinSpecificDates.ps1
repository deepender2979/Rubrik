# This script applies legal hold on specified date snapshots for snappable FIDs read from a provided file. 
# Modify line 11, 51, 125, 129 and 130 as required.
# You will need a service account created with Administrator role and please set the execution policy on your system running powershell as required.

# Create a file with snappable IDs in new line - snappableIds.txt
# eb4572df-1bdb-5641-929b-f232bf2d0cb0
# another-snappable-id
# another-snappable-id

# Import Service Account Info (For Windows path: C:\Users\Username\Desktop\File.json)
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
Write-Output "Access Token Response: $($response | ConvertTo-Json -Compress)"

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

    Write-Output "GraphQL Payload: $($payload | ConvertTo-Json -Compress)"

    $response = Invoke-RestMethod -Uri "https://rubrik-support.my.rubrik.com/api/graphql" -Method Post -Body $payload -ContentType "application/json" -Headers $Headers -UseBasicParsing

    # Debug output to check the GraphQL response
    Write-Output "GraphQL Response: $($response | ConvertTo-Json -Compress)"

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

# Define the function to place snapshots on legal hold
function Place-OnLegalHold {
    param (
        [array]$snapshotFids,
        [bool]$shouldHoldInPlace,
        [string]$userNote,
        [hashtable]$Headers
    )

    $legalHoldMutation = @"
mutation PlaceOnLegalHoldMutation(`$snapshotFids: [String!]!, `$shouldHoldInPlace: Boolean!, `$userNote: String) {
    createLegalHold(input: {holdConfig: {shouldHoldInPlace: `$shouldHoldInPlace}, snapshotIds: `$snapshotFids, userNote: `$userNote}) {
        snapshotIds
        __typename
    }
}
"@

    $legalHoldVariables = @{
        snapshotFids = $snapshotFids
        shouldHoldInPlace = $shouldHoldInPlace
        userNote = $userNote
    }

    Write-Output "Applying legal hold with the following variables: $($legalHoldVariables | ConvertTo-Json -Compress)"

    $legalHoldResult = Invoke-GraphQL -Query $legalHoldMutation -Variables $legalHoldVariables -Headers $Headers

    Write-Output "Legal Hold Application Result: $($legalHoldResult | ConvertTo-Json -Compress)"

    return $legalHoldResult
}

# Read snappable IDs from a text file
$snappableIdsFilePath = "/Users/Deepender.Singh/Downloads/snappableIds.txt"
$snappableIds = Get-Content $snappableIdsFilePath

# Define the date range for filtering
$startDate = Get-Date "2024-05-19T00:00:00Z"
$endDate = Get-Date "2024-05-21T23:59:59Z"

# Iterate over each snappable ID
foreach ($snappableId in $snappableIds) {
    Write-Output "Processing snappable ID: $snappableId"

    # Retrieve snapshot FIDs and dates for the current snappable ID
    $snapshots = Get-SnapshotFids -snappableId $snappableId -Headers $headers

    # Filter snapshots based on the date range
    $filteredSnapshots = $snapshots | Where-Object {
        ($_.date -ge $startDate) -and ($_.date -le $endDate)
    }

    # Output the filtered snapshot details
    foreach ($snapshot in $filteredSnapshots) {
        Write-Output "Snapshot ID: $($snapshot.id), Date: $($snapshot.date)"
    }

    # Extract filtered snapshot IDs for the mutation
    $snapshotFids = $filteredSnapshots | ForEach-Object { $_.id }

    # Place the snapshots on legal hold if there are any filtered snapshots
    if ($snapshotFids.Count -gt 0) {
        $legalHoldResult = Place-OnLegalHold -snapshotFids $snapshotFids -shouldHoldInPlace $true -userNote "" -Headers $headers
        # Output the result
        Write-Output "Legal hold applied for snappable ID: $snappableId"
        Write-Output "Result: $($legalHoldResult | ConvertTo-Json -Compress)"
    } else {
        Write-Output "No snapshots found in the specified date range for snappable ID: $snappableId"
    }
}