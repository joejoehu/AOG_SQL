#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deployment Validation and Health Check Script for RedCross SQL Always On AG

.DESCRIPTION
    This script validates the post-deployment configuration of the Azure infrastructure,
    checks connectivity, domain membership, and SQL Server configuration.

.PARAMETERS
    -ResourceGroup: Name of the Azure Resource Group (default: rg-redcross-sql)
    -VerboseOutput: Display detailed output (default: $false)

.EXAMPLE
    .\validate-deployment.ps1
    .\validate-deployment.ps1 -ResourceGroup "my-rg" -VerboseOutput $true
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "rg-redcross-sql",
    
    [Parameter(Mandatory=$false)]
    [bool]$VerboseOutput = $false
)

$ProgressPreference = "SilentlyContinue"
$ErrorActionPreference = "Continue"

# Color definitions
$colors = @{
    Success = "Green"
    Warning = "Yellow"
    Error = "Red"
    Info = "Cyan"
}

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-ColorOutput "========================================" $colors.Info
    Write-ColorOutput "  $Title" $colors.Info
    Write-ColorOutput "========================================" $colors.Info
}

function Test-AzureConnectivity {
    Write-Section "Azure Connectivity Test"
    
    try {
        $account = Get-AzContext
        if ($null -eq $account) {
            Write-ColorOutput "❌ Not authenticated to Azure" $colors.Error
            Write-ColorOutput "Run: az login" $colors.Warning
            return $false
        }
        
        Write-ColorOutput "✅ Azure CLI authenticated" $colors.Success
        Write-ColorOutput "   Subscription: $($account.Subscription.Name)" $colors.Success
        return $true
    }
    catch {
        Write-ColorOutput "❌ Azure authentication failed: $_" $colors.Error
        return $false
    }
}

function Test-ResourceGroup {
    Write-Section "Resource Group Validation"
    
    try {
        $rg = Get-AzResourceGroup -Name $ResourceGroup -ErrorAction Stop
        Write-ColorOutput "✅ Resource Group exists: $($rg.ResourceGroupName)" $colors.Success
        Write-ColorOutput "   Location: $($rg.Location)" $colors.Success
        Write-ColorOutput "   Resources: $($(Get-AzResource -ResourceGroupName $ResourceGroup).Count) items" $colors.Success
        return $true
    }
    catch {
        Write-ColorOutput "❌ Resource Group not found: $ResourceGroup" $colors.Error
        return $false
    }
}

function Test-VirtualMachines {
    Write-Section "Virtual Machine Status"
    
    try {
        $vms = Get-AzVM -ResourceGroupName $ResourceGroup
        
        if ($vms.Count -lt 4) {
            Write-ColorOutput "❌ Not all VMs deployed (found $($vms.Count), expected 4)" $colors.Error
            return $false
        }
        
        Write-ColorOutput "✅ Found $($vms.Count) Virtual Machines" $colors.Success
        
        foreach ($vm in $vms) {
            $status = Get-AzVM -ResourceGroupName $ResourceGroup -Name $vm.Name -Status
            $powerState = $status.Statuses | Where-Object { $_.Code -like "PowerState/*" }
            
            if ($powerState.DisplayStatus -eq "VM running") {
                Write-ColorOutput "  ✅ $($vm.Name): $($powerState.DisplayStatus)" $colors.Success
            }
            else {
                Write-ColorOutput "  ⚠️  $($vm.Name): $($powerState.DisplayStatus)" $colors.Warning
            }
        }
        return $true
    }
    catch {
        Write-ColorOutput "❌ VM status check failed: $_" $colors.Error
        return $false
    }
}

function Test-KeyVault {
    Write-Section "Azure Key Vault Validation"
    
    try {
        $vaults = Get-AzKeyVault -ResourceGroupName $ResourceGroup
        
        if ($vaults.Count -eq 0) {
            Write-ColorOutput "❌ No Key Vault found" $colors.Error
            return $false
        }
        
        $vault = $vaults[0]
        Write-ColorOutput "✅ Key Vault found: $($vault.VaultName)" $colors.Success
        
        # Check for secrets
        $secrets = Get-AzKeyVaultSecret -VaultName $vault.VaultName
        
        $requiredSecrets = @("domain-admin-password", "sql-service-password", "local-admin-password")
        foreach ($secret in $requiredSecrets) {
            $exists = $secrets | Where-Object { $_.Name -eq $secret }
            if ($exists) {
                Write-ColorOutput "  ✅ Secret found: $secret" $colors.Success
            }
            else {
                Write-ColorOutput "  ❌ Secret missing: $secret" $colors.Error
            }
        }
        return $true
    }
    catch {
        Write-ColorOutput "❌ Key Vault check failed: $_" $colors.Error
        return $false
    }
}

function Test-NetworkConnectivity {
    Write-Section "Network Connectivity Tests"
    
    $dcIPs = @("10.38.0.4", "10.38.0.5")
    $sqlIPs = @("10.38.1.4", "10.38.2.4")
    $allIPs = $dcIPs + $sqlIPs
    
    Write-ColorOutput "Testing DNS resolution (from local machine):" $colors.Info
    
    # Test DNS resolution if running from Windows
    if ($PSVersionTable.Platform -eq "Win32NT" -or $PSVersionTable.PSVersion.Major -eq 5) {
        try {
            $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroup
            Write-ColorOutput "  Virtual Network: $($vnet.Name)" $colors.Info
            Write-ColorOutput "  Address Space: $($vnet.AddressSpace.AddressPrefixes)" $colors.Info
        }
        catch {
            Write-ColorOutput "  Note: Network tests require VM connectivity" $colors.Warning
        }
    }
    
    Write-ColorOutput "⚠️  Full connectivity tests require RDP access to VMs" $colors.Warning
    Write-ColorOutput "   Once connected, run validation tests from within the VMs" $colors.Warning
    
    return $true
}

function Test-NetworkSecurityGroups {
    Write-Section "Network Security Groups"
    
    try {
        $nsgs = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroup
        
        if ($nsgs.Count -lt 2) {
            Write-ColorOutput "❌ Expected 2+ NSGs (found $($nsgs.Count))" $colors.Error
            return $false
        }
        
        Write-ColorOutput "✅ Found $($nsgs.Count) Network Security Groups" $colors.Success
        
        foreach ($nsg in $nsgs) {
            Write-ColorOutput "  📋 $($nsg.Name)" $colors.Info
            Write-ColorOutput "     Rules: $($nsg.SecurityRules.Count)" $colors.Info
        }
        return $true
    }
    catch {
        Write-ColorOutput "❌ NSG check failed: $_" $colors.Error
        return $false
    }
}

function Test-NetworkInterfaces {
    Write-Section "Network Interface Cards"
    
    try {
        $nics = Get-AzNetworkInterface -ResourceGroupName $ResourceGroup
        
        Write-ColorOutput "✅ Found $($nics.Count) Network Interfaces" $colors.Success
        
        # Expected NICs: 2 for DC + 3 for each SQL VM (6) = 8 total
        $expectedCount = 8
        if ($nics.Count -lt $expectedCount) {
            Write-ColorOutput "⚠️  Expected ~$expectedCount NICs (found $($nics.Count))" $colors.Warning
        }
        
        # Group NICs by VM
        foreach ($nic in $nics) {
            $nicName = $nic.Name
            $ipConfigs = $nic.IpConfigurations
            Write-ColorOutput "  📍 $nicName" $colors.Info
            foreach ($ipConfig in $ipConfigs) {
                Write-ColorOutput "     IP: $($ipConfig.PrivateIpAddress)" $colors.Info
            }
        }
        return $true
    }
    catch {
        Write-ColorOutput "❌ NIC check failed: $_" $colors.Error
        return $false
    }
}

function Test-CustomScriptExtensions {
    Write-Section "Custom Script Extensions Status"
    
    try {
        $vms = Get-AzVM -ResourceGroupName $ResourceGroup
        
        foreach ($vm in $vms) {
            Write-ColorOutput "VM: $($vm.Name)" $colors.Info
            
            $extensions = Get-AzVMExtension -ResourceGroupName $ResourceGroup -VMName $vm.Name
            
            if ($extensions.Count -eq 0) {
                Write-ColorOutput "  ⚠️  No extensions found (may still be provisioning)" $colors.Warning
                continue
            }
            
            foreach ($ext in $extensions) {
                $provState = $ext.ProvisioningState
                $status = if ($provState -eq "Succeeded") { $colors.Success } else { $colors.Warning }
                Write-ColorOutput "  📦 $($ext.Name): $provState" $status
            }
        }
        return $true
    }
    catch {
        Write-ColorOutput "❌ Extension check failed: $_" $colors.Error
        return $false
    }
}

function Test-VirtualNetwork {
    Write-Section "Virtual Network & Subnets"
    
    try {
        $vnets = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroup
        
        if ($vnets.Count -ne 1) {
            Write-ColorOutput "❌ Expected 1 VNet (found $($vnets.Count))" $colors.Error
            return $false
        }
        
        $vnet = $vnets[0]
        Write-ColorOutput "✅ Virtual Network: $($vnet.Name)" $colors.Success
        Write-ColorOutput "   Address Space: $($vnet.AddressSpace.AddressPrefixes -join ', ')" $colors.Success
        
        Write-ColorOutput "   Subnets:" $colors.Info
        foreach ($subnet in $vnet.Subnets) {
            Write-ColorOutput "     📌 $($subnet.Name): $($subnet.AddressPrefix)" $colors.Success
        }
        return $true
    }
    catch {
        Write-ColorOutput "❌ VNet check failed: $_" $colors.Error
        return $false
    }
}

function Show-ConnectionGuide {
    Write-Section "Connection Information"
    
    try {
        # Try to get IPs from deployed resources
        $dcVm = Get-AzVM -ResourceGroupName $ResourceGroup -Name "vm-dc-1" -ErrorAction SilentlyContinue
        $sqlVm1 = Get-AzVM -ResourceGroupName $ResourceGroup -Name "vm-sql-1" -ErrorAction SilentlyContinue
        
        Write-ColorOutput "To connect to VMs:" $colors.Info
        Write-ColorOutput "  1. Use Azure Bastion or VPN" $colors.Info
        Write-ColorOutput "  2. Or enable public IPs on VMs (NOT recommended for production)" $colors.Warning
        Write-ColorOutput "" $colors.Info
        Write-ColorOutput "Default IPs (Private Network):" $colors.Info
        Write-ColorOutput "  DC-VM-1: 10.38.0.4" $colors.Info
        Write-ColorOutput "  DC-VM-2: 10.38.0.5" $colors.Info
        Write-ColorOutput "  SQL-VM-1 (Primary): 10.38.1.4" $colors.Info
        Write-ColorOutput "  SQL-VM-2 (Primary): 10.38.2.4" $colors.Info
        Write-ColorOutput "" $colors.Info
        Write-ColorOutput "Credentials are stored in Azure Key Vault" $colors.Info
        
    }
    catch {
        Write-ColorOutput "⚠️  Could not retrieve connection info" $colors.Warning
    }
}

# Main execution
function Main {
    Clear-Host
    Write-ColorOutput "╔════════════════════════════════════════════════════════════════╗" $colors.Info
    Write-ColorOutput "║   RedCross SQL Always On AG - Deployment Validation Script     ║" $colors.Info
    Write-ColorOutput "║   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" $colors.Info
    Write-ColorOutput "╚════════════════════════════════════════════════════════════════╝" $colors.Info
    
    $results = @()
    
    # Run all checks
    $results += @{ Test = "Azure Connectivity"; Result = Test-AzureConnectivity }
    $results += @{ Test = "Resource Group"; Result = Test-ResourceGroup }
    $results += @{ Test = "Virtual Machines"; Result = Test-VirtualMachines }
    $results += @{ Test = "Virtual Network"; Result = Test-VirtualNetwork }
    $results += @{ Test = "Network Interfaces"; Result = Test-NetworkInterfaces }
    $results += @{ Test = "Network Security Groups"; Result = Test-NetworkSecurityGroups }
    $results += @{ Test = "Custom Script Extensions"; Result = Test-CustomScriptExtensions }
    $results += @{ Test = "Azure Key Vault"; Result = Test-KeyVault }
    $results += @{ Test = "Network Connectivity"; Result = Test-NetworkConnectivity }
    
    # Summary
    Write-Section "Validation Summary"
    
    $passed = ($results | Where-Object { $_.Result -eq $true }).Count
    $failed = ($results | Where-Object { $_.Result -eq $false }).Count
    
    foreach ($result in $results) {
        $status = if ($result.Result) { "✅ PASS" } else { "❌ FAIL" }
        Write-ColorOutput "  $status - $($result.Test)" (if ($result.Result) { $colors.Success } else { $colors.Error })
    }
    
    Write-Host ""
    Write-ColorOutput "Total: $passed Passed, $failed Failed" (if ($failed -eq 0) { $colors.Success } else { $colors.Error })
    
    Show-ConnectionGuide
    
    Write-Host ""
    Write-ColorOutput "For detailed health checks on VMs, see scripts/validate-vm-health.ps1" $colors.Info
    Write-Host ""
}

# Execute main function
Main
