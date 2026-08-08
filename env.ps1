$ver = $PSVersionTable.PSVersion
Write-Host "PowerShell Version : $ver"

$isDomain = (Get-WmiObject -Class Win32_ComputerSystem).PartOfDomain
Write-Host "Domain Joined      : $isDomain"

$adMod = Get-Module -ListAvailable -Name ActiveDirectory
if ($adMod) {
    Write-Host "ActiveDirectory    : INSTALLED - v$($adMod.Version)" -ForegroundColor Green
} else {
    Write-Host "ActiveDirectory    : NOT INSTALLED (RSAT required)" -ForegroundColor Red
}

$pol = Get-ExecutionPolicy -Scope CurrentUser
Write-Host "ExecPolicy (User)  : $pol"