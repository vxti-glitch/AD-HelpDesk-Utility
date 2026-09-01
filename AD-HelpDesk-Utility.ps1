#Requires -Version 5.1

<#
.SYNOPSIS
    Active Directory Help Desk Utility Tool

.DESCRIPTION
    An interactive command-line utility for Help Desk technicians to perform
    common Active Directory tasks without opening ADUC (Active Directory Users
    and Computers). Supports bulk user provisioning from CSV, account unlock and
    password reset, security group management, and an editable structured local activity log.

    Use -DemoMode to run a fully simulated session with no AD infrastructure
    required. Ideal for portfolios, training environments, and offline demos.

.NOTES
    Author      : Help Desk Utility Tool
    Version     : 1.1.0
    Requirements: ActiveDirectory PowerShell module (RSAT), Windows PowerShell 5.1+
                  (Not required in -DemoMode)

.EXAMPLE
    .\AD-HelpDesk-Utility.ps1
    Launches the interactive menu against a real domain.

.EXAMPLE
    .\AD-HelpDesk-Utility.ps1 -DemoMode
    Launches in Demo Mode — all AD calls are simulated with realistic data.

.EXAMPLE
    .\AD-HelpDesk-Utility.ps1 -LogPath "D:\Logs\ADHelpDesk.log"
    Launches the tool and writes the local activity log to a custom path.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    # Run in Demo Mode: all AD operations are simulated. No domain or RSAT needed.
    [Parameter(Mandatory = $false)]
    [switch]$DemoMode,

    # Path to the editable local activity log. Defaults to a monthly file.
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$PSScriptRoot\Logs\ADHelpDesk_$(Get-Date -Format 'yyyy-MM').log",

    # Default OU base path used when a department OU does not exist yet.
    [Parameter(Mandatory = $false)]
    [string]$DefaultUserOU = "",

    # Default domain for UPN suffixes. Auto-detected if left blank (or set to demo value).
    [Parameter(Mandatory = $false)]
    [string]$Domain = "",

    # Explicitly permit creation of missing department OUs. Disabled by default.
    [switch]$CreateMissingOUs,

    # Distinguished-name boundaries within which provisioning is allowed.
    [string[]]$AllowedBaseDN = @()
)

# ---------------------------------------------------------------------------
# REGION: INITIALIZATION
# ---------------------------------------------------------------------------
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:LogPath    = $LogPath
$script:Domain     = $Domain
$script:DefaultOU  = $DefaultUserOU
$script:DemoMode   = $DemoMode.IsPresent
$script:ScriptName = "AD Help Desk Utility v1.1.0"


Import-Module "$PSScriptRoot\modules\ADHelpDeskCore.psm1" -Force
Initialize-ADHelpDeskCore -DemoMode $script:DemoMode -LogPath $script:LogPath -DefaultOU $script:DefaultOU -Domain $script:Domain -ScriptName $script:ScriptName


# ===========================================================================
# MAIN EXECUTION ENTRY POINT
# ===========================================================================
try {
    Initialize-Environment
}
catch {
    Write-Host ""
    Write-Host "  [FATAL] Initialization failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Tip: run with -DemoMode to use simulated data without a domain." -ForegroundColor Cyan
    exit 1
}

$running = $true
while ($running) {
    $choice = Show-Menu

    switch ($choice.ToUpper()) {
        "1" { Invoke-BulkProvisioning -CreateMissingOUs:$CreateMissingOUs -AllowedBaseDN $AllowedBaseDN -WhatIf:$WhatIfPreference }
        "2" { Invoke-AccountUnlockReset }
        "3" { Invoke-GroupManagement    }
        "4" { Show-RecentLogs           }
        "Q" {
            Write-Log -Message "Session ended by operator." -Level "INFO" -Action "INIT"
            Write-Host ""
            Write-Host "  Goodbye. Local activity log saved to: $script:LogPath" -ForegroundColor Cyan
            Write-Host ""
            $running = $false
        }
        default {
            Write-Host "  Invalid choice '$choice'. Please enter 1, 2, 3, 4, or Q." -ForegroundColor Yellow
            Start-Sleep -Seconds 1
        }
    }
}
