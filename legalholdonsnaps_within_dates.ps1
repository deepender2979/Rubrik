#This script applies legal hold on snaps between specific dates for one snappable FID. Modify line 110 and 111 as required date and time. Modify line 106 to provide snappale FID.

# Import Service Account Info
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

    $legalHoldResult = Invoke-GraphQL -Query $legalHoldMutation -Variables $legalHoldVariables -Headers $Headers
    return $legalHoldResult
}

# Retrieve snapshot FIDs and dates for a given snappable ID
$snappableId = "56c6a401-0faf-538a-b29b-9f99105422d3"
$snapshots = Get-SnapshotFids -snappableId $snappableId -Headers $headers

# Define the date range for filtering
$startDate = Get-Date "2024-05-19T00:00:00Z"
$endDate = Get-Date "2024-05-23T23:59:59Z"

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

# Place the snapshots on legal hold
if ($snapshotFids.Count -gt 0) {
    $legalHoldResult = Place-OnLegalHold -snapshotFids $snapshotFids -shouldHoldInPlace $true -userNote "" -Headers $headers
    # Output the result
    $legalHoldResult
} else {
    Write-Output "No snapshots found in the specified date range."
}
