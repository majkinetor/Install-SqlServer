#Requires -RunAsAdministrator

<#
.SYNOPSIS
    MS SQL Server silent installation script

.DESCRIPTION
    This script installs MS SQL Server unattended from the ISO image.
    Transcript of entire operation is recorded in the log file.

    The script lists parameters provided to the native setup but hides sensitive data. See the provided
    links for SQL Server silent install details.
#>
param(
    # Path to ISO file, if empty and current directory contains single ISO file, it will be used.
    [string] $IsoPath = $ENV:SQLSERVER_ISOPATH,

    # Sql Server features, see https://docs.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server-2016-from-the-command-prompt#Feature
    [ValidateSet('SQL', 'SQLEngine', 'Replication', 'FullText', 'DQ', 'PolyBase', 'AdvancedAnalytics', 'AS', 'RS', 'DQC', 'IS', 'MDS', 'SQL_SHARED_MR', 'Tools', 'BC', 'BOL', 'Conn', 'DREPLAY_CLT', 'SNAC_SDK', 'SDK', 'LocalDB')]
    [string[]] $Features = @('SQLEngine'),

    # Specifies a nondefault installation directory
    [string] $InstallDir,

    # Data directory, by default "$Env:ProgramFiles\Microsoft SQL Server"
    [string] $DataDir,

    # Service name. Mandatory, by default MSSQLSERVER
    [ValidateNotNullOrEmpty()]
    [string] $InstanceName = 'MSSQLSERVER',

    # sa user password. If empty, SQL security mode (mixed mode) is disabled
    [string] $SaPassword = "P@ssw0rd",

    # Username for the service account, see https://docs.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server-2016-from-the-command-prompt#Accounts
    # Optional, by default 'NT Service\MSSQLSERVER'
    [string] $ServiceAccountName, # = "$Env:USERDOMAIN\$Env:USERNAME"

    # Password for the service account, should be used for domain accounts only
    # Mandatory with ServiceAccountName
    [string] $ServiceAccountPassword,

    # List of system administrative accounts in the form <domain>\<user>
    # Mandatory, by default current user will be added as system administrator
    [string[]] $SystemAdminAccounts = @("$Env:USERDOMAIN\$Env:USERNAME"),

    # Product key, if omitted, evaluation is used unless VL edition which is already activated
    [string] $ProductKey
)

$ErrorActionPreference = 'STOP'
$scriptName = (Split-Path -Leaf $PSCommandPath).Replace('.ps1', '')

$start = Get-Date
Start-Transcript "$PSScriptRoot\$scriptName-$($start.ToString('s').Replace(':','-')).log"

if (!$IsoPath) {
    Write-Host "SQLSERVER_ISOPATH environment variable not specified, using defaults"
    $IsoPath = "https://download.microsoft.com/download/7/c/1/7c14e92e-bdcb-4f89-b7cf-93543e7112d1/SQLServer2019-x64-ENU-Dev.iso"

    $saveDir = Join-Path $Env:TEMP $scriptName
    New-item $saveDir -ItemType Directory -ErrorAction 0 | Out-Null

    $isoName = $isoPath -split '/' | Select-Object -Last 1
    $savePath = Join-Path $saveDir $isoName

    if (Test-Path $savePath){
        Write-Host "ISO already downloaded, checking hashsum..."
        $hash    = Get-FileHash -Algorithm MD5 $savePath | % Hash
        $oldHash = Get-Content "$savePath.md5" -ErrorAction 0
    }
    
    if ($hash -and $hash -eq $oldHash) { Write-Host "Hash is OK" } else {
        if ($hash) { Write-Host "Hash is NOT OK"}
        Write-Host "Downloading: $isoPath"
        Invoke-WebRequest $IsoPath -OutFile $savePath -UseBasicParsing
        Get-FileHash -Algorithm MD5 $savePath | % Hash | Out-File "$savePath.md5"
    }

    $IsoPath = $savePath
}

Write-Host "`IsoPath: " $IsoPath

$volume    = Mount-DiskImage $IsoPath -StorageType ISO -PassThru | Get-Volume
$sql_drive = $volume.DriveLetter + ':'
Get-ChildItem $sql_drive | ft -auto | Out-String

Get-CimInstance win32_process | ? { $_.commandLine -like '*setup.exe*/ACTION=install*' } | % { 
    Write-Host "Sql Server installer is already running, killing it:" $_.Path  "pid: " $_.processId
    Stop-Process $_.processId -Force
}

$cmd =@(
    "${sql_drive}setup.exe"
    '/Q'                                # Silent install
    '/INDICATEPROGRESS'                 # Specifies that the verbose Setup log file is piped to the console
    '/IACCEPTSQLSERVERLICENSETERMS'     # Must be included in unattended installations
    '/ACTION=install'                   # Required to indicate the installation workflow
    '/UPDATEENABLED=false'              # Should it discover and include product updates.

    "/INSTANCEDIR=""$InstallDir"""
    "/INSTALLSQLDATADIR=""$DataDir"""

    "/FEATURES=" + ($Features -join ',')

    #Security
    "/SQLSYSADMINACCOUNTS=""$SystemAdminAccounts"""
    '/SECURITYMODE=SQL'                 # Specifies the security mode for SQL Server. By default, Windows-only authentication mode is supported.
    "/SAPWD=""$SaPassword"""            # Sa user password

    "/INSTANCENAME=$InstanceName"       # Server instance name

    "/SQLSVCACCOUNT=""$ServiceAccountName"""
    "/SQLSVCPASSWORD=""$ServiceAccountPassword"""

    # Service startup types
    "/SQLSVCSTARTUPTYPE=automatic"
    "/AGTSVCSTARTUPTYPE=automatic"
    "/ASSVCSTARTUPTYPE=manual"

    "/PID=$ProductKey"
)

# remove empty arguments
$cmd_out = $cmd = $cmd -notmatch '/.+?=("")?$'

# show all parameters but remove password details
Write-Host "Install parameters:`n"
'SAPWD', 'SQLSVCPASSWORD' | % { $cmd_out = $cmd_out -replace "(/$_=).+", '$1"****"' }
$cmd_out[1..100] | % { $a = $_ -split '='; Write-Host '   ' $a[0].PadRight(40).Substring(1), $a[1] }
Write-Host

"$cmd_out"
Invoke-Expression "$cmd"
if ($LastExitCode) { throw "SqlServer installation failed, exit code: $LastExitCode" }

"`nInstallation length: {0:f1} minutes" -f ((Get-Date) - $start).TotalMinutes

Dismount-DiskImage $IsoPath
Stop-Transcript
trap { Stop-Transcript; if ($IsoPath) { Dismount-DiskImage $IsoPath -ErrorAction 0 } }