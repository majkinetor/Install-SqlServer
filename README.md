# Install-SqlServer

[![](https://img.shields.io/badge/version-1.1-green)](https://github.com/majkinetor/Install-SqlServer)

This script installs MS SQL Server on Windows OS silently from ISO image that can be available locally or downloaded from the Internet.
Transcript of entire operation is recorded in the log file.

The script lists parameters provided to the native setup but hides sensitive data. See the provided links for SQL Server silent install details.

The installer is tested with SQL Servers 2016-2022 and PowerShell 3-7.

## Prerequisites

1. Windows OS
2. Administrative rights
1. MS SQL Server ISO image [optional]

## Usage

The fastest way to install core SQL Server is to run in administrative shell:

```ps1
./Install-SqlServer.ps1 -EnableProtocols
```

This will download and install **SQL Server Development Edition** and enable all protocols. Provide your own ISO image of any edition using `ISOPath` script parameter.

This assumes number of default parameters and installs by default only `SQLEngine` feature. Run `Get-Help ./Install-SqlServer.ps1 -Full` for parameter details.

To **test installation**, after running this script execute:

```ps1
# Set-Alias sqlcmd "$Env:ProgramFiles\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE"
"SELECT @@version" | sqlcmd
```

## Notes

- Behind the proxy use `HTTP_PROXY` environment variable
- SQL Server Management Studio isn't distributed along with SQL Server any more. Install via chocolatey: [`cinst sql-server-management-studio`](https://chocolatey.org/packages/sql-server-management-studio)
- On PowerShell 5 progress bar significantly slows down the download. Use `$progressPreference = 'silentlyContinue'` to disable it prior to calling this function.
- SQL Server Development Edition has all features of Enterprise Edition and you can license it as Enterprise edition if needed.

### How to find SQL Server direct download

1. Download evaluation installer from official site
    - Example for v2022: https://www.microsoft.com/en-us/evalcenter/download-sql-server-2022
    - This downloads file: `SQL2022-SSEI-Eval.exe`
1. Unpack evalutation installer exe using 7zip
    - This unpacks its resources and other stuff as text files
1. Search for `.iso` in files
    - For example using [dngrep](https://dngrep.github.io)

See ticket [#3](https://github.com/majkinetor/Install-SqlServer/issues/3#issuecomment-1536174746) for details.

### Direct download list

1. [2022 Development Edition](https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SQLServer2022-x64-ENU-Dev.iso)
2. [2019 Development Edition](https://download.microsoft.com/download/7/c/1/7c14e92e-bdcb-4f89-b7cf-93543e7112d1/SQLServer2019-x64-ENU-Dev.iso)

## Troubleshooting

### Installing on remote machine using PowerShell remote session

The following errors may occur:

    There was an error generating the XML document
        ... Access denied
        ... The computer must be trusted for delegation and the current user account must be configured to allow delegation

**The solution**: Use WinRM session parameter `-Authentication CredSSP`.

To be able to use it, the following settings needs to be done on both local and remote machine:

1. On local machine using `gpedit.msc`, go to *Computer Configuration -> Administrative Templates -> System -> Credentials Delegation*.<br>
Add `wsman/*.<domain>` (set your own domain) in the following settings
    1. *Allow delegating fresh credentials with NTLM-only server authentication*
    2. *Allow delegating fresh credentials*
1. The remote machine must be set to behave as CredSSP server with `Enable-WSManCredSSP -Role server`

## Links

- [Install SQL Server from the Command Prompt](https://docs.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server-2016-from-the-command-prompt)
    - [Features](https://docs.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server-2016-from-the-command-prompt#Feature)
    - [Accounts](https://docs.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server-2016-from-the-command-prompt#Accounts)
- [Download SQL Server Management Studio](https://docs.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms)
- [Editions and features](https://docs.microsoft.com/en-us/sql/sql-server/editions-and-components-of-sql-server-2017)
