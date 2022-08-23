<#
.SYNOPSIS
Copies CRL files from a Windows Enterprise PKI up to Azure AD Blob Storage using AzCopy

.DESCRIPTION 
This script was written to facilitate a highly-available Azure-based CDP and AIA
location instead of the traditional technique of hosting CRLs and AIAs on
internal web servers and/or opening them up to the Internet through
a DMZ or via a reverse proxy like Azure AD App Proxy.

#>


# Blob storage location to upload files to
$azCopyDestination = "https://<storage account name>.blob.core.windows.net/<container name>/?"

# SAS key for the above destination
$azCopyDestinationSASKey = "SAS Token for the container"

# Log location for AzCopy
$azCopyLogLocation = Join-Path $env:SystemRoot 'PKI\AzCopy-PKI.log'

# Long-term log for successful copy actions
$azCopyLogArchiveLocation = Join-Path $env:ProgramData 'PKI\Invoke-UpdateAzureBlobPKIStorage.log'

# If the archive log file doesn't exist
if ((Test-Path $azCopyLogArchiveLocation) -eq $false) {
    $archiveLogFolder = Split-Path $azCopyLogArchiveLocation -Parent

    # If the ScriptLogs folder doesn't exist in %ProgramData%, create it
    if ((Test-Path $archiveLogFolder) -eq $false) {
        New-Item $archiveLogFolder -ItemType Directory -Force
    }
}

# Determine if AzCopy is installed
$azCopyBinaryPath = 'C:\azcopy.exe'
if ((Test-Path $azCopyBinaryPath -ErrorAction SilentlyContinue -WarningAction SilentlyContinue) -eq $false) {
    throw "Missing AzCopy.exe"
}

# Check for the defaul CertEnroll folder
$cdpLocalLocation = Join-Path $env:SystemRoot 'System32\CertSrv\CertEnroll\'
if ((Test-Path $cdpLocalLocation -ErrorAction SilentlyContinue -WarningAction SilentlyContinue) -eq $false) {
    throw "It doesn't appear that the default local CDP and AIA location is being used"
}

# Grab the existing ErrorActionPreference and save it for later
$existingErrorActionPreference = $ErrorActionPreference

# Force PowerShell to stop on errors for the Call Operator below
$ErrorActionPreference = 'Stop'

try {
    # Run AzCopy to copy only .crl files that are newer than already exist at the destination
    &$azCopyBinaryPath cp $cdpLocalLocation $azCopyDestination$azCopyDestinationSASKey --include-pattern="*.crl" --log-level="error" --check-length=false --recursive
    }
catch {
    $error | Out-File $azCopyLogArchiveLocation -Append
    Remove-Item $azCopyLogLocation -Force
    exit 9999
}

# Set the ErrorActionPreference back to what it was prior to running AzCopy
$ErrorActionPreference = $existingErrorActionPreference

# Read in the contents of the latest AzCopy Log and archive it if there have been successful or failed transfers
if (Test-Path $azCopyLogLocation) {
    $transferSummaryText = Get-Content $azCopyLogLocation -Tail 5

    # Extract the Total Files Transferred count
    $totalFilesTransferred = (($transferSummaryText | Where-Object {$_ -like "Total files transferred*"}) | Select-String -Pattern "\d+").Matches[0].Value

    # Extract the Transfer Failed count
    $transferFailed = (($transferSummaryText | Where-Object {$_ -like "Transfer failed*"}) | Select-String -Pattern "\d+").Matches[0].Value

    # If a transfer failed or some files were actually transferred, archive the log
    if (($transferFailed -gt 0) -or ($totalFilesTransferred -gt 0)) {
        (Get-Content $azCopyLogLocation) | Out-File $azCopyLogArchiveLocation -Append
    }

    # Remove the log for this run
    Remove-Item $azCopyLogLocation -Force

    # Throw an error code if transfers failed. This will bubble up to the scheduled task status
    if ($transferFailed -gt 0) {
        exit 9999
    }
}
