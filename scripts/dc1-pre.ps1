# Run in PowerShell on the VM after attaching disk in Azure Portal
Get-Disk | Where-Object PartitionStyle -eq 'RAW' | 
    Initialize-Disk -PartitionStyle GPT -PassThru | 
    New-Partition -DriveLetter F -UseMaximumSize | 
    Format-Volume -FileSystem NTFS -NewFileSystemLabel "AD_DATA" -Confirm:$false

# Create directories
New-Item -Path "F:\NTDS" -ItemType Directory -Force
New-Item -Path "F:\SYSVOL" -ItemType Directory -Force

# Run in PowerShell as Administrator
$InterfaceAlias = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -ExpandProperty Name
Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses "127.0.0.1"

# Verify
Get-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4

# Enable transcript logging
Start-Transcript -Path "C:\DCSetup-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Install roles
Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools

# Verify installation
Get-WindowsFeature | Where-Object {$_.Name -like "*AD-Domain*" -or $_.Name -eq "DNS"}


sleep 300

# Define your domain name
$DomainName = "redcross.local"  # Change this to your domain
$NetBiosName = "REDCROSS"             # Change this (15 chars max)

# Prompt for DSRM password securely
$DSRMPassword = Read-Host -AsSecureString -Prompt "Enter Directory Services Restore Mode (DSRM) Password"


# Use data disk if created, otherwise use C: drive
$DatabasePath = "F:\NTDS"
$LogPath = "F:\NTDS"
$SysvolPath = "F:\SYSVOL"

# If using C: drive (not recommended for production)
# $DatabasePath = "C:\Windows\NTDS"
# $LogPath = "C:\Windows\NTDS"
# $SysvolPath = "C:\Windows\SYSVOL"

# Promote to DC and create new forest
Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $NetBiosName `
    -SafeModeAdministratorPassword $DSRMPassword `
    -DatabasePath $DatabasePath `
    -LogPath $LogPath `
    -SysvolPath $SysvolPath `
    -InstallDns `
    -CreateDnsDelegation:$false `
    -NoRebootOnCompletion:$false `
    -Force

# The system will automatically reboot


