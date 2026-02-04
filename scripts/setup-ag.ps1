# Always On Availability Group Setup Script
# This script configures SQL Server Always On Availability Group on the deployed VMs
# Run this AFTER all VMs have completed domain join and SQL Server is running

# This script should be run interactively or via scheduled task after VM setup is complete

param(
    [Parameter(Mandatory=$false)]
    [string]$SQL1VMName = "vm-sql-1",
    
    [Parameter(Mandatory=$false)]
    [string]$SQL2VMName = "vm-sql-2",
    
    [Parameter(Mandatory=$false)]
    [string]$DomainName = "redcross.local",
    
    [Parameter(Mandatory=$false)]
    [string]$AGName = "AG-RedCross",
    
    [Parameter(Mandatory=$false)]
    [string]$ListenerName = "Listener-RedCross",
    
    [Parameter(Mandatory=$false)]
    [string]$ListenerPort = "1433"
)

# Logging function
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path "C:\ag-setup.log" -Value "[$timestamp] $Message" -ErrorAction SilentlyContinue
    Write-Output "[$timestamp] $Message"
}

Write-Log "=========================================="
Write-Log "SQL Server Always On Availability Group Setup"
Write-Log "=========================================="
Write-Log "SQL Server 1: $SQL1VMName"
Write-Log "SQL Server 2: $SQL2VMName"
Write-Log "Domain: $DomainName"
Write-Log "AG Name: $AGName"
Write-Log "Listener Name: $ListenerName"
Write-Log "Listener Port: $ListenerPort"

Write-Log ""
Write-Log "STEP 1: Enable Always On Availability Groups on both SQL instances"
Write-Log "=========================================="

Write-Log "Connecting to SQL Server instance on $SQL1VMName..."
$sql1FQDN = "$SQL1VMName.$DomainName"

try {
    # Enable Always On on SQL1
    Write-Log "Enabling Always On on $sql1FQDN..."
    
    $enableAlwaysOnScript = @"
        Enable-SqlAlwaysOn -Path SQLSERVER:\SQL\$sql1FQDN\DEFAULT -Force
        Write-Host "Always On enabled on $sql1FQDN"
"@
    
    Write-Log "Execute on $SQL1VMName via SQL Server Management Studio or PowerShell:"
    Write-Log "   Enable-SqlAlwaysOn -Path SQLSERVER:\SQL\$sql1FQDN\DEFAULT -Force"
}
catch {
    Write-Log "ERROR: Could not enable Always On on $sql1FQDN : $($_.Exception.Message)"
}

Write-Log ""
Write-Log "Connecting to SQL Server instance on $SQL2VMName..."
$sql2FQDN = "$SQL2VMName.$DomainName"

try {
    # Enable Always On on SQL2
    Write-Log "Enabling Always On on $sql2FQDN..."
    
    $enableAlwaysOnScript = @"
        Enable-SqlAlwaysOn -Path SQLSERVER:\SQL\$sql2FQDN\DEFAULT -Force
        Write-Host "Always On enabled on $sql2FQDN"
"@
    
    Write-Log "Execute on $SQL2VMName via SQL Server Management Studio or PowerShell:"
    Write-Log "   Enable-SqlAlwaysOn -Path SQLSERVER:\SQL\$sql2FQDN\DEFAULT -Force"
}
catch {
    Write-Log "ERROR: Could not enable Always On on $sql2FQDN : $($_.Exception.Message)"
}

Write-Log ""
Write-Log "STEP 2: Create Database Mirroring Endpoints"
Write-Log "=========================================="

Write-Log "Execute on BOTH SQL instances:"
Write-Log ""
Write-Log "On $SQL1VMName and $SQL2VMName:"
Write-Log "@"
Write-Log "
CREATE ENDPOINT [Hadr_endpoint] 
    STATE=STARTED
    AS TCP (LISTENER_PORT = 5022, LISTENER_IP = ALL)
    FOR DATA_MIRRORING (
        ROLE = ALL,
        AUTHENTICATION = CERTIFICATE cn_cert,
        ENCRYPTION = REQUIRED ALGORITHM AES)
GO

GRANT CONNECT ON ENDPOINT::[Hadr_endpoint] 
    TO [redcross\sql_service]
GO
"@
Write-Log ""

Write-Log "STEP 3: Create Availability Group"
Write-Log "=========================================="

Write-Log "Execute on PRIMARY SQL Server ($SQL1VMName):"
Write-Log "@"
Write-Log "
CREATE AVAILABILITY GROUP [$AGName]
    WITH (
        AUTOMATED_BACKUP_PREFERENCE = SECONDARY,
        DB_FAILOVER = OFF,
        FAILURE_CONDITION_LEVEL = 3,
        HEALTH_CHECK_TIMEOUT = 30000
    )
    FOR REPLICA ON
        N'$sql1FQDN' WITH (
            ENDPOINT_URL = N'TCP://$sql1FQDN:5022',
            FAILOVER_MODE = AUTOMATIC,
            AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
            BACKUP_PRIORITY = 50,
            PRIMARY_ROLE (ALLOW_CONNECTIONS = ALL),
            SECONDARY_ROLE (ALLOW_CONNECTIONS = ALL)
        ),
        N'$sql2FQDN' WITH (
            ENDPOINT_URL = N'TCP://$sql2FQDN:5022',
            FAILOVER_MODE = AUTOMATIC,
            AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
            BACKUP_PRIORITY = 60,
            PRIMARY_ROLE (ALLOW_CONNECTIONS = ALL),
            SECONDARY_ROLE (ALLOW_CONNECTIONS = ALL)
        )
GO
"@
Write-Log ""

Write-Log "STEP 4: Join Availability Group on Secondary"
Write-Log "=========================================="

Write-Log "Execute on SECONDARY SQL Server ($SQL2VMName):"
Write-Log "@"
Write-Log "ALTER AVAILABILITY GROUP [$AGName] JOIN
GO"
Write-Log ""

Write-Log "STEP 5: Create Availability Group Listener"
Write-Log "=========================================="

Write-Log "Execute on PRIMARY SQL Server ($SQL1VMName):"
Write-Log "@"
Write-Log "
ALTER AVAILABILITY GROUP [$AGName]
    ADD LISTENER N'$ListenerName' (
        WITH IP (
            (N'10.38.1.11', N'255.255.255.0'),
            (N'10.38.2.11', N'255.255.255.0')
        ),
        PORT = $ListenerPort
    )
GO
"@
Write-Log ""

Write-Log "STEP 6: Add Databases to Availability Group"
Write-Log "=========================================="

Write-Log "For each database you want to add to the Availability Group:"
Write-Log "@"
Write-Log "
-- On PRIMARY ($SQL1VMName):
ALTER AVAILABILITY GROUP [$AGName] ADD DATABASE [YourDatabaseName]
GO

-- Backup the database and logs:
BACKUP DATABASE [YourDatabaseName] 
    TO DISK = N'\\path\to\backup\YourDatabaseName.bak' 
    WITH COPY_ONLY
GO

BACKUP LOG [YourDatabaseName] 
    TO DISK = N'\\path\to\backup\YourDatabaseName.log'
GO

-- On SECONDARY ($SQL2VMName):
RESTORE DATABASE [YourDatabaseName] 
    FROM DISK = N'\\path\to\backup\YourDatabaseName.bak' 
    WITH NORECOVERY
GO

RESTORE LOG [YourDatabaseName] 
    FROM DISK = N'\\path\to\backup\YourDatabaseName.log' 
    WITH NORECOVERY
GO

-- Then join to AG on secondary:
ALTER DATABASE [YourDatabaseName] SET HADR AVAILABILITY GROUP = [$AGName]
GO
"@
Write-Log ""

Write-Log "=========================================="
Write-Log "CONFIGURATION SUMMARY"
Write-Log "=========================================="
Write-Log ""
Write-Log "Always On Availability Group Configuration:"
Write-Log "  AG Name: $AGName"
Write-Log "  Listener Name: $ListenerName"
Write-Log "  Listener IP (SQL-Subnet-1): 10.38.1.11"
Write-Log "  Listener IP (SQL-Subnet-2): 10.38.2.11"
Write-Log "  Listener Port: $ListenerPort"
Write-Log "  Primary Replica: $sql1FQDN (10.38.1.4)"
Write-Log "  Secondary Replica: $sql2FQDN (10.38.2.4)"
Write-Log ""
Write-Log "Network Configuration:"
Write-Log "  Primary NIC: 10.38.1.4 / 10.38.2.4"
Write-Log "  Cluster NIC: 10.38.1.10 / 10.38.2.10"
Write-Log "  Listener NIC: 10.38.1.11 / 10.38.2.11"
Write-Log ""
Write-Log "Service Account: redcross\sql_service"
Write-Log ""
Write-Log "SQL Server Endpoint Port: 5022"
Write-Log "Client Connection Port: $ListenerPort"
Write-Log ""
Write-Log "=========================================="
Write-Log "Setup script completed at $(Get-Date)"
Write-Log "=========================================="
