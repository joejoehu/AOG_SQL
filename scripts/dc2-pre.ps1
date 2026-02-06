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
Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses "10.38.0.4", "127.0.0.1"

# Test DNS resolution
Resolve-DnsName -Name redcross.local  # Replace with your domain


# Prompt for domain admin credentials
$DomainName = "redcross.local"  # Your domain
$DomainCred = Get-Credential -Message "Enter Domain Admin credentials (redcross.local\redcross_admin)"

# Join to domain
Add-Computer -DomainName $DomainName -Credential $DomainCred -Restart

#reboooot





# Log in as CORP\Administrator
Start-Transcript -Path "C:\DCSetup-Additional-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools

Get-WindowsFeature | Where-Object {$_.Name -like "*AD-Domain*" -or $_.Name -eq "DNS"}


# Define variables
$DomainName = "redcross.local"  # Your domain
$DSRMPassword = Read-Host -AsSecureString -Prompt "Enter DSRM Password"
$DomainCred = Get-Credential -Message "Enter Domain Admin credentials"

# Use data disk if available
$DatabasePath = "F:\NTDS"
$LogPath = "F:\NTDS"
$SysvolPath = "F:\SYSVOL"

# Promote to additional DC
Install-ADDSDomainController `
    -DomainName $DomainName `
    -Credential $DomainCred `
    -SafeModeAdministratorPassword $DSRMPassword `
    -DatabasePath $DatabasePath `
    -LogPath $LogPath `
    -SysvolPath $SysvolPath `
    -InstallDns `
    -NoRebootOnCompletion:$false `
    -Force

# The system will automatically reboot