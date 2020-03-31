#require -version 3

<#
.SYNOPSIS
    Sql Server Silent installation script

.DESCRIPTION
    This script installs MS SQL Server silently from ISO image that can be availble locally or on SMB share.
    Transcript of entire operation is recorded in the log file with the same name (previous logs are overwritten).

    The script lists parameters provided to the native setup but hides sensitive data. See the provided
    links for SQL Server silent install details.

    To check if existing SQL Server instance is registered execute `SELECT @@version`.

.NOTES
    When installing over remote powershell session, the followin errors may occur: 
        There was an error generating the XML document 
            ... Access denied
            ... The computer must be trusted for delegation and the current user account must be configured to allow delegation

    The solution: Use session parameter -Authentication CredSSP.
        
        To set it up, connecting machine must have group policy set (with gpedit.msc):

            Computer Configuration -> Administrative Templates -> System -> Credentials Delegation.
            Add wsman/*.<domain>
                - allow delegating fresh credentials with NTLM-only server authentication
                - allow delegating fresh credentials
        
        The remote machine must be set to behve as CredSSP server:  Enable-WSManCredSSP -Role server
    
.LINK
    https://docs.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server-2016-from-the-command-prompt
    https://msdn.microsoft.com/library/bb500441.aspx?f=255&MSPPError=-2147217396#Anchor_1
#>
param(
    # Path to ISO file, if empty and current directory contains single ISO file, it will be used.
    # If IsoPath is on the SMB share, it will be copied locally to c:\install\sql-server.
    [string]$IsoPath = '',

    # Credential is used if ISO is on the SMB share. It must have read access.
    [PSCredential] $ShareCredential,

    # Sql Server features, see https://docs.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server-2016-from-the-command-prompt#Feature
    [ValidateSet('SQL', 'SQLEngine', 'Replication', 'FullText', 'DQ', 'PolyBase', 'AdvancedAnalytics', 'AS', 'RS', 'DQC', 'IS', 'MDS', 'SQL_SHARED_MR', 'Tools', 'BC', 'BOL', 'Conn', 'DREPLAY_CLT', 'SNAC_SDK', 'SDK', 'LocalDB')]
    [string[]] $Features = @('SQLEngine', 'Replication', 'RS'),

    # Installation directory, mandatory
    [string] $InstallDir,

    # Data directory. Mandatory, by default "$Env:ProgramFiles\Microsoft SQL Server"
    [string] $DataDir,

    # Service name. Mandatory, by default MSSQLSERVER
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
    # Mandatory, by default current user will be added as system adminitrator
    [string[]] $SystemAdminAccounts = @("$Env:USERDOMAIN\$Env:USERNAME"),

    # Product key, if omitted, evaluation is used unless VL edition which is already activated
    [string] $ProductKey
)

$ErrorActionPreference = 'STOP'

$start = Get-Date
Start-Transcript "$PSScriptRoot\Install-Sql-$($start.ToString('s').Replace(':','-')).log"

if ($ShareCredential) { 
    $root = Split-Path $IsoPath
    Write-Host "Mounting share:" $root
    New-PSDrive -Name sqliso -PSProvider FileSystem -Root $root -Credential $ShareCredential | Out-Null

    # Executing from the share directly makes remote installation fails due to delegation problems. See http://archive.is/f18Fc
    Write-Host "Coping the ISO file to local file system"
    $local_iso_path = Join-Path "c:\install\sql-server" (Split-Path -Leaf $IsoPath)
    mkdir -Force (Split-Path $local_iso_path)    
    if (!(Test-Path $local_iso_path)) { cp $IsoPath $local_iso_path }
    $IsoPath = $local_iso_path
}

if (!$IsoPath) {
    $IsoPath = gi *.iso;
    if (!$IsoPath) { throw 'Parameter $IsoPath is invalid' }
    if ($IsoPath.Count -gt 1) { throw 'More then 1 iso files found in the current directory' }
    Write-Warning 'Using ISO from the current dir'
}

Write-Host "`IsoPath: " $IsoPath -ForegroundColor green

if ([string]::IsNullOrWhiteSpace($InstanceName)) { throw "Parameter $InstanceId must not be empty" }

$d1 = Get-PSDrive

Mount-DiskImage $IsoPath   # With -PassThru it doesn't report the drive it creates ?!

$d2 = Get-PSDrive
$sql_drive = Compare-Object $d1 $d2 | % InputObject
if (!$sql_drive) { throw "Can't find mounted drive letter" }
$sql_drive | select name, description
$sql_drive = $sql_drive.Root

ls $sql_drive | ft -auto | Out-String

gwmi win32_process | ? { $_.commandLine -like '*setup.exe*/ACTION=install*' } | % { 
    Write-Host "Sql Server installer is already running, killing it:" $_.Path  "pid: " $_.processId -ForegroundColor red
    kill $_.processId -Force
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
iex "$cmd"
if ($LastExitCode) { throw "SqlServer installation failed, exit code: $LastExitCode" }

"`nInstallation length: {0:f1} minutes" -f ((Get-Date) - $start).TotalMinutes

Dismount-DiskImage $IsoPath
Stop-Transcript
trap { Stop-Transcript; if ($IsoPath) { Dismount-DiskImage $IsoPath -ea 0 } }
