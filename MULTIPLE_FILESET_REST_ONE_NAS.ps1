<#
 
  **This script comes with no warranty, use at you own risk

        .SYNOPSIS
        Assign Multiple Fileset Templates from CSV and Associate a SLA Domain

        .DESCRIPTION
        This script connects to a Rubrik Cluster and completes the following tasks:

        * Reads Fileset Template Names from a CSV file
        * Associates multiple Filesets with the NAS Share (assumes the NAS Share has already been added)
        * Associates each Fileset to a SLA Domain

        This process makes use of both the Rubrik PowerShell Module and 
        (https://github.com/rubrikinc/PowerShell-Module) Invoke-WebRequest.
        

        .EXAMPLES:
        #Execute Script
        ./Set-Multiple-Fileset-Templates-and-SLA.ps1

        In Excel:
        FilesetName
        Template1
        Template2
        Template3
        
#>

###################################################
############### User Variables ####################

$RubrikAddress = "X.X.X.X"
$UserId = "User:::c61XXXXXXabc"
$Secret = "X0ClXXXXXXXXXjQVzE"
$Hostname = ''
$SharePath = ''
$SLA = ''
$CsvFilePath = 'C:\path\to\fileset_templates.csv'  # Path to the CSV file containing Fileset Template Names

# Examples
# $Hostname = '172.17.25.11'
# $SharePath = '/home'
# $SLA = 'Gold'
# $CsvFilePath = 'C:\path\to\fileset_templates.csv'

###################################################
#######         Script Execution            #######
###################################################

try {
    Add-Type -TypeDefinition @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object -TypeName TrustAllCertsPolicy
}
catch {}

# Convert UserId and Secret to Base64 for authentication
$RubrikRESTHeader = @{
		"Authorization" = "Basic " + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($UserId+':'+$Secret))
	}

# Define the Rubrik API Version
$RubrikApi = "/api/v1"

# Validate Authentication to Rubrik
try {
    $result = Invoke-WebRequest -Uri ("https://$RubrikAddress$RubrikApi" + "/cluster/me") -Headers $RubrikRESTHeader -Method "GET" -ErrorAction Stop
    
    if($result.StatusCode -ne 200) {
        throw "Bad status code returned from Rubrik cluster at $RubrikAddress"
    }
    else {
        Write-Host 'Executing Script...'
    }
}
catch {
    throw $_
}

# Connect to the Rubrik Cluster using the given UserId and Secret
Connect-Rubrik -Server $RubrikAddress -Id $UserId -Secret $Secret | Out-Null

# Get the Host ID
$HostId = (Get-RubrikHost -PrimaryClusterID 'local' -Hostname $Hostname).id 

# Read the Fileset Template Names from CSV
$FilesetNames = Import-Csv -Path $CsvFilePath | Select-Object -ExpandProperty FilesetName

# Assign each Fileset Template to the NAS Share
foreach ($Fileset in $FilesetNames) {
    $FilesetTemplateId = (Get-RubrikFilesetTemplate -Name $Fileset).id

    $ShareId = (Get-RubrikShare -HostId $HostId -SharePath $SharePath).id

    $RESTBody = @{
        "hostId" = "$HostId"
        "shareId" = "$ShareId"
        "templateId" = "$FilesetTemplateId"
    }

    $AddFilesetTemplateEndpoint = '/fileset/bulk'

    $RubrikApi = "/api/internal"

    $uri = "https://$RubrikAddress$RubrikApi$AddFilesetTemplateEndpoint"

    $body = '[ ' + (ConvertTo-Json -InputObject $RESTBody) + ']'

    try {
        $result = Invoke-WebRequest -Uri $uri -Headers $RubrikRESTHeader -Method POST -Body $body -ErrorAction Stop
    }
    catch {
        throw $_
    }
}

# Associate the SLA Domain to the NAS Share/Filesets
foreach ($Fileset in $FilesetNames) {
    Get-RubrikFileset $Fileset -HostName $Hostname | Where-Object {$_.isRelic -ne 'True'} | Protect-RubrikFileset -SLA $SLA -Confirm:$False | Out-Null
}

Write-Host 'Fileset Templates and SLA Domain successfully associated.'