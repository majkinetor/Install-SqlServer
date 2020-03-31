# Install-SqlServer

This PowerShell script that automates installation of MS SQL Server.

The installer is tested with SQL Servers 2016-2019.

## Prerequisites

1. MS SQL Server ISO image


## Usage

SQL Server is installed on the `db` role via this command:

```ps1
$params = @{
    IsoPath      = "<path_to>/en_sql_server_2019_developer_x64_dvd_e0079655.iso"
    Credentials  = Get-Credential domain user     # SMB Share credentials where ISO resides if needed
}
.\Install-SqlServer.ps1 @params
```

This assumes number of [default parameters](Install-SqlServer.ps1#L24-60).


## Notes

- If share is already mounted Credentials are not required to access remote ISO file.
- SQL Server Management Studio isn't distributed along with SQL Server any more. Install via chocolatey: [`cinst sql-server-management-studio`](https://chocolatey.org/packages/sql-server-management-studio)
