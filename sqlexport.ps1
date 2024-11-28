Import-Module Rubrik

# Source variables
$RubrikCluster = '10.38.139.151' # Do not change
$DBName = 'master' # Change to the name of the database you want to export
$DBServer = '10.38.136.18' # Change to the name of the DB Server, if AG group, must be AG group name

# Target variables
$DBMountName = 'master_deep_test' # Change to whatever export name you want
$targetserver = '10.38.136.31' # Modify to whichever server you want as the export target
$DBInstance = 'MSSQLSERVER' # Do not change

# Connect to Rubrik cluster
Write-Output "Connecting to Rubrik Cluster at $RubrikCluster..."
try {
    Connect-Rubrik -Server $RubrikCluster -Token J1YnJpay5jb21bTG9jYWxdIiwiY3NyZlRva2VuIjoiUkUzOTdhTVFnckNVYkFMU1BPakJJcEM1SmtEcU5vUG03M2dSOE5jak1vND0iLCJpc01mYVJlbWVtYmVyVG9rZW4iOmZhbHNlLCJpc3MiOiIwMGI1ODIyZC1hNjQxLTQ2MTktYjFhMy0zZDlhNzlmMTZhN2QiLCJpYXQiOjE3MzI4MjAwOTQsImp0aSI6IjMyMjFmMjcyLTJhYjktNGZhZC1hYjY3LWRmMjU1NWIyNjUzOCJ9.U6WtQTMGzZ-jynAi3ntzaQHVJ0YyprU0uooRWEUOnRE
} catch {
    Write-Error "Failed to connect to Rubrik Cluster: $_"
    exit
}

# Retrieve database details
Write-Output "Retrieving database details for $DBName on server $DBServer..."
try {
    $DBDetails = Get-RubrikDatabase -HostName $DBServer -Instance $DBInstance -Database $DBName -DetailedObject 
    if ($DBDetails -eq $null -or $DBDetails.Count -eq 0) {
        Write-Error "Failed to retrieve details for the database $DBName on server $DBServer."
        exit
    } else {
        Write-Output "Retrieved database details:"
        Write-Output $DBDetails
    }
} catch {
    Write-Error "Exception while retrieving database details: $_"
    exit
}
    
# Get first database detail
$DBDetail = $DBDetails | Select-Object -First 1
if ($DBDetail -eq $null) {
    Write-Error "No database details found for $DBName."
    exit
}

Write-Output "Retrieved database detail:"
Write-Output $DBDetail

# Extract database UUID
$ValidDBDetailId = $DBDetail.id.split(':::')[-1]
Write-Output "Extracted UUID: $ValidDBDetailId"

# Retrieve the last full snapshot date
Write-Output "Retrieving the last full snapshot date for database $DBName..."
try {
    $LastFullSnapshotDate = Get-RubrikDatabaseRecoveryPoint -id "MssqlDatabase:::$ValidDBDetailId" -LastFull 
    if ($LastFullSnapshotDate -eq $null) {
        Write-Error "Failed to retrieve the last full snapshot date for database $DBName."
        exit
    } else {
        Write-Output "Retrieved last full snapshot date:"
        Write-Output $LastFullSnapshotDate
    }
} catch {
    Write-Error "Exception while retrieving the last full snapshot date: $_"
    exit
}

# Using the UUIDs directly and formatting the target instance ID correctly
$TargetInstanceId = "MssqlInstance:::" + $($DBDetail.instanceId.Split(':::')[1])
Write-Output "Target Instance ID: $TargetInstanceId"

# Validate all necessary parameters before performing export
if (![string]::IsNullOrEmpty($ValidDBDetailId) -and $LastFullSnapshotDate -ne $null -and (![string]::IsNullOrEmpty($TargetInstanceId))) {
    Write-Output "All required parameters are valid. Proceeding with database export."
    Write-Output "DBDetailId: MssqlDatabase:::$ValidDBDetailId"
    Write-Output "LastFullSnapshotDate: $LastFullSnapshotDate"
    Write-Output "TargetInstanceId: $TargetInstanceId"

    try {
        # Export the database using the given format
        $RubrikRequest = Export-RubrikDatabase -id "MssqlDatabase:::$ValidDBDetailId" -recoveryDateTime $LastFullSnapshotDate -targetInstanceId $TargetInstanceId -targetDatabaseName $DBMountName -Overwrite -FinishRecovery
        if ($RubrikRequest -eq $null) {
            Write-Error "Export-RubrikDatabase command failed."
            exit
        } else {
            Write-Output "Export-RubrikDatabase request initiated successfully."
            Write-Output $RubrikRequest
        }

        # Monitor the Rubrik request for completion
        Get-RubrikRequest -id $RubrikRequest.id -Type mssql -WaitForCompletion
        Start-Sleep -Seconds 10
    } catch {
        Write-Error "Exception during database export: $_"
    }
} else {
    Write-Error "One or more required parameters are invalid. Cannot proceed with database export."
}