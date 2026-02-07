param(
    [Parameter(Mandatory = $true)]
    [string]$DSRMPasswordPlainText
)

# DC1 Stage 1 - Promote to Domain Controller
# Designed to run via Azure Custom Script Extension (no interactive prompts, clean exit)

# Enable transcript logging first so all output is captured
Start-Transcript -Path "C:\DCSetup-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

try {
    # ========================================================================
    # DISK INITIALIZATION
    # ========================================================================
    Write-Output "=== Initializing data disk ==="
    Get-Disk | Where-Object PartitionStyle -eq 'RAW' |
        Initialize-Disk -PartitionStyle GPT -PassThru |
        New-Partition -DriveLetter F -UseMaximumSize |
        Format-Volume -FileSystem NTFS -NewFileSystemLabel "AD_DATA" -Confirm:$false

    New-Item -Path "F:\NTDS" -ItemType Directory -Force
    New-Item -Path "F:\SYSVOL" -ItemType Directory -Force

    # ========================================================================
    # INSTALL AD DS AND DNS ROLES
    # ========================================================================
    Write-Output "=== Installing AD-Domain-Services and DNS roles ==="
    Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools

    Get-WindowsFeature | Where-Object {$_.Name -like "*AD-Domain*" -or $_.Name -eq "DNS"}

    # ========================================================================
    # PROMOTE TO DOMAIN CONTROLLER
    # ========================================================================
    Write-Output "=== Promoting to Domain Controller ==="

    $DomainName    = "redcross.local"
    $NetBiosName   = "REDCROSS"
    $DSRMPassword  = ConvertTo-SecureString $DSRMPasswordPlainText -AsPlainText -Force
    $DatabasePath  = "F:\NTDS"
    $LogPath       = "F:\NTDS"
    $SysvolPath    = "F:\SYSVOL"

    Install-ADDSForest `
        -DomainName $DomainName `
        -DomainNetbiosName $NetBiosName `
        -SafeModeAdministratorPassword $DSRMPassword `
        -DatabasePath $DatabasePath `
        -LogPath $LogPath `
        -SysvolPath $SysvolPath `
        -InstallDns `
        -CreateDnsDelegation:$false `
        -NoRebootOnCompletion:$true `
        -Force

    # ========================================================================
    # SET DNS (after DNS server is installed via AD promotion)
    # ========================================================================
    Write-Output "=== Configuring DNS client to use localhost + Azure DNS ==="
    $InterfaceAlias = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -ExpandProperty Name
    Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses ("127.0.0.1","168.63.129.16")

    # ========================================================================
    # SCHEDULE REBOOT (gives extension time to report success)
    # ========================================================================
    Write-Output "=== Scheduling reboot in 60 seconds ==="
    shutdown /r /t 60 /f /c "Rebooting after DC promotion"

    Write-Output "=== DC1 Stage 1 completed successfully ==="
}
catch {
    Write-Output "ERROR: $_"
    Write-Output $_.ScriptStackTrace
}
finally {
    Stop-Transcript
}

# Always exit 0 so the Custom Script Extension reports success
exit 0

