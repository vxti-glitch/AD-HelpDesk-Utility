Write-Host ""
Write-Host "=== Environment Check ===" -ForegroundColor Cyan
Write-Host "PowerShell Version : $($PSVersionTable.PSVersion)" -ForegroundColor White
Write-Host "OS                 : $([System.Environment]::OSVersion.VersionString)" -ForegroundColor White
Write-Host "Running as         : $env:USERNAME on $env:COMPUTERNAME" -ForegroundColor White

# Check domain join
$domainStatus = (Get-CimInstance -ClassName Win32_ComputerSystem).PartOfDomain
Write-Host "Domain Joined      : $domainStatus" -ForegroundColor $(if ($domainStatus) {"Green"} else {"Red"})

# Check AD module
$adMod = Get-Module -ListAvailable -Name ActiveDirectory
if ($adMod) {
    Write-Host "ActiveDirectory    : INSTALLED (v$($adMod.Version))" -ForegroundColor Green
} else {
    Write-Host "ActiveDirectory    : NOT INSTALLED — RSAT required" -ForegroundColor Red
}

# Check execution policy
$policy = Get-ExecutionPolicy -Scope CurrentUser
Write-Host "Exec Policy (User) : $policy" -ForegroundColor White

Write-Host ""
