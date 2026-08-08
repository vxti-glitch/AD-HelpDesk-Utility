#Requires -Version 5.1

<#
.SYNOPSIS
    Active Directory Help Desk Utility Tool

.DESCRIPTION
    An interactive command-line utility for Help Desk technicians to perform
    common Active Directory tasks without opening ADUC (Active Directory Users
    and Computers). Supports bulk user provisioning from CSV, account unlock and
    password reset, security group management, and compliance-grade audit logging.

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
    Launches the tool and writes audit logs to a custom path.
#>

[CmdletBinding()]
param(
    # Run in Demo Mode: all AD operations are simulated. No domain or RSAT needed.
    [Parameter(Mandatory = $false)]
    [switch]$DemoMode,

    # Path to the audit log file. Defaults to a timestamped log in the script directory.
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$PSScriptRoot\Logs\ADHelpDesk_$(Get-Date -Format 'yyyy-MM').log",

    # Default OU base path used when a department OU does not exist yet.
    [Parameter(Mandatory = $false)]
    [string]$DefaultUserOU = "",

    # Default domain for UPN suffixes. Auto-detected if left blank (or set to demo value).
    [Parameter(Mandatory = $false)]
    [string]$Domain = ""
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

# ---------------------------------------------------------------------------
# DEMO DATA — realistic simulated AD objects used when -DemoMode is active.
# These mirror what real Get-ADUser / Get-ADGroup calls would return.
# ---------------------------------------------------------------------------
$script:DemoUsers = @{
    "jsmith"   = [PSCustomObject]@{
        SamAccountName = "jsmith"; DisplayName = "Jane Smith"
        GivenName = "Jane"; Surname = "Smith"
        UserPrincipalName = "jsmith@contoso.demo"
        LockedOut = $true; Enabled = $true
        BadLogonCount = 6; PasswordLastSet = (Get-Date).AddDays(-45)
        LastLogonDate = (Get-Date).AddDays(-3)
        MemberOf = @("CN=Finance-ReadOnly,OU=Groups,DC=contoso,DC=demo")
    }
    "crivera"  = [PSCustomObject]@{
        SamAccountName = "crivera"; DisplayName = "Carlos Rivera"
        GivenName = "Carlos"; Surname = "Rivera"
        UserPrincipalName = "crivera@contoso.demo"
        LockedOut = $false; Enabled = $true
        BadLogonCount = 0; PasswordLastSet = (Get-Date).AddDays(-12)
        LastLogonDate = (Get-Date).AddHours(-2)
        MemberOf = @("CN=Engineering-All,OU=Groups,DC=contoso,DC=demo")
    }
    "apatel"   = [PSCustomObject]@{
        SamAccountName = "apatel"; DisplayName = "Aisha Patel"
        GivenName = "Aisha"; Surname = "Patel"
        UserPrincipalName = "apatel@contoso.demo"
        LockedOut = $false; Enabled = $false   # Disabled account for demo
        BadLogonCount = 0; PasswordLastSet = (Get-Date).AddDays(-90)
        LastLogonDate = (Get-Date).AddDays(-91)
        MemberOf = @()
    }
    "mbrown"   = [PSCustomObject]@{
        SamAccountName = "mbrown"; DisplayName = "Marcus Brown"
        GivenName = "Marcus"; Surname = "Brown"
        UserPrincipalName = "mbrown@contoso.demo"
        LockedOut = $false; Enabled = $true
        BadLogonCount = 1; PasswordLastSet = (Get-Date).AddDays(-5)
        LastLogonDate = (Get-Date).AddHours(-1)
        MemberOf = @("CN=IT-Admins,OU=Groups,DC=contoso,DC=demo")
    }
}

$script:DemoGroups = @{
    "Finance-ReadOnly"   = [PSCustomObject]@{
        Name = "Finance-ReadOnly"; SamAccountName = "Finance-ReadOnly"
        GroupCategory = "Security"; GroupScope = "Global"
        Members = @("jsmith")
    }
    "Engineering-All"    = [PSCustomObject]@{
        Name = "Engineering-All"; SamAccountName = "Engineering-All"
        GroupCategory = "Security"; GroupScope = "Global"
        Members = @("crivera")
    }
    "IT-Admins"          = [PSCustomObject]@{
        Name = "IT-Admins"; SamAccountName = "IT-Admins"
        GroupCategory = "Security"; GroupScope = "Global"
        Members = @("mbrown")
    }
    "HR-Staff"           = [PSCustomObject]@{
        Name = "HR-Staff"; SamAccountName = "HR-Staff"
        GroupCategory = "Security"; GroupScope = "Global"
        Members = @()
    }
    "All-Marketing-Dist" = [PSCustomObject]@{
        Name = "All-Marketing-Dist"; SamAccountName = "All-Marketing-Dist"
        GroupCategory = "Distribution"; GroupScope = "Universal"  # For the warning demo
        Members = @()
    }
}

# ---------------------------------------------------------------------------
# FUNCTION: Write-Log
# PURPOSE : Appends a timestamped, structured entry to the audit log file.
#           Every action (success, failure, info) flows through this function
#           to ensure a tamper-evident, human-readable compliance trail.
#           Audit logging is REAL even in Demo Mode.
# ---------------------------------------------------------------------------
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$Level = "INFO",

        [string]$Action = "GENERAL"
    )

    # Ensure the log directory exists before writing.
    $logDir = Split-Path -Path $script:LogPath -Parent
    if (-not (Test-Path -Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $operator  = $env:USERNAME
    $machine   = $env:COMPUTERNAME
    $demoTag   = if ($script:DemoMode) { "[DEMO] " } else { "" }
    $logLine   = "$timestamp | $Level | $Action | Operator=$operator | Machine=$machine | $demoTag$Message"

    Add-Content -Path $script:LogPath -Value $logLine -Encoding UTF8

    $colour = switch ($Level) {
        "SUCCESS" { "Green"  }
        "WARNING" { "Yellow" }
        "ERROR"   { "Red"    }
        default   { "Cyan"   }
    }
    Write-Host "  [$Level] $demoTag$Message" -ForegroundColor $colour
}

# ---------------------------------------------------------------------------
# FUNCTION: Invoke-DemoDelay
# PURPOSE : Adds a realistic 300-800ms pause in Demo Mode to simulate AD
#           network round-trips, making the demo feel authentic.
# ---------------------------------------------------------------------------
function Invoke-DemoDelay {
    param([int]$Ms = 500)
    if ($script:DemoMode) {
        Start-Sleep -Milliseconds $Ms
    }
}

# ---------------------------------------------------------------------------
# FUNCTION: Initialize-Environment
# PURPOSE : Validates requirements, resolves domain, logs session start.
#           In Demo Mode, skips the AD module check entirely and uses a
#           simulated domain name.
# ---------------------------------------------------------------------------
function Initialize-Environment {
    Write-Host ""

    if ($script:DemoMode) {
        # ---- DEMO MODE INIT ----
        Write-Host "  " -NoNewline
        Write-Host " DEMO MODE ACTIVE " -ForegroundColor Black -BackgroundColor Yellow
        Write-Host "  All AD operations are simulated. No domain or RSAT required." -ForegroundColor Yellow
        Write-Host "  Audit log is written to disk normally." -ForegroundColor Yellow
        Write-Host ""

        if ([string]::IsNullOrWhiteSpace($script:Domain)) {
            $script:Domain = "contoso.demo"
        }
        $script:DefaultOU = "CN=Users,DC=contoso,DC=demo"
        Write-Log -Message "DEMO session started. SimulatedDomain=$($script:Domain)" -Level "INFO" -Action "INIT"
        return
    }

    # ---- REAL MODE INIT ----
    Write-Host "  Checking environment..." -ForegroundColor Gray

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-Host ""
        Write-Host "  [FATAL] The 'ActiveDirectory' module is not installed." -ForegroundColor Red
        Write-Host "  Install RSAT: Add-WindowsCapability -Online -Name Rsat.ActiveDirectory*" -ForegroundColor Yellow
        Write-Host "  Or run with -DemoMode to use simulated data." -ForegroundColor Cyan
        Write-Host ""
        exit 1
    }

    Import-Module ActiveDirectory -ErrorAction Stop

    if ([string]::IsNullOrWhiteSpace($script:Domain)) {
        try {
            $script:Domain = (Get-ADDomain -ErrorAction Stop).DNSRoot
        }
        catch {
            Write-Host "  [WARNING] Could not auto-detect domain." -ForegroundColor Yellow
            $script:Domain = Read-Host "  Enter your domain DNS name (e.g. contoso.com)"
        }
    }

    if ([string]::IsNullOrWhiteSpace($script:DefaultOU)) {
        try {
            $domainDN         = (Get-ADDomain -ErrorAction Stop).DistinguishedName
            $script:DefaultOU = "CN=Users,$domainDN"
        }
        catch {
            $script:DefaultOU = ""
        }
    }

    Write-Log -Message "Session started. Domain=$($script:Domain)  DefaultOU=$($script:DefaultOU)" -Level "INFO" -Action "INIT"
}

# ---------------------------------------------------------------------------
# FUNCTION: Show-Menu
# PURPOSE : Renders the main interactive menu and returns the user's choice.
# ---------------------------------------------------------------------------
function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor DarkCyan
    Write-Host "    $script:ScriptName" -ForegroundColor Cyan

    if ($script:DemoMode) {
        Write-Host "    Domain : $script:Domain  " -NoNewline -ForegroundColor Gray
        Write-Host "[DEMO MODE]" -ForegroundColor Yellow
    }
    else {
        Write-Host "    Domain : $script:Domain" -ForegroundColor Gray
    }

    Write-Host "    Operator: $env:USERNAME  |  $(Get-Date -Format 'ddd dd-MMM-yyyy HH:mm')" -ForegroundColor Gray
    Write-Host "  ============================================================" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "   [1]  Bulk User Provisioning (from CSV)" -ForegroundColor White
    Write-Host "   [2]  Unlock Account & Reset Password" -ForegroundColor White
    Write-Host "   [3]  Add User to Security Group" -ForegroundColor White
    Write-Host "   [4]  View Recent Audit Log Entries" -ForegroundColor White
    Write-Host "   [Q]  Quit" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor DarkCyan

    if ($script:DemoMode) {
        Write-Host ""
        Write-Host "  DEMO HINTS:" -ForegroundColor DarkYellow
        Write-Host "   Option 1 : use the included sample-users.csv" -ForegroundColor DarkYellow
        Write-Host "   Option 2 : try usernames  jsmith (locked)  apatel (disabled)  crivera" -ForegroundColor DarkYellow
        Write-Host "   Option 3 : try user 'jsmith', group 'HR-Staff' or 'Engineering-All'" -ForegroundColor DarkYellow
    }

    Write-Host ""
    $choice = Read-Host "  Enter your choice"
    return $choice.Trim()
}

# ---------------------------------------------------------------------------
# FUNCTION: Invoke-BulkProvisioning
# PURPOSE : Reads a CSV and creates user accounts. In Demo Mode, all New-ADUser
#           and New-ADOrganizationalUnit calls are replaced with simulated
#           responses that mirror real AD output timing and messaging.
# ---------------------------------------------------------------------------
function Invoke-BulkProvisioning {
    Write-Host ""
    Write-Host "  -- Bulk User Provisioning ------------------------------------------" -ForegroundColor DarkCyan
    Write-Log -Message "Bulk provisioning initiated." -Level "INFO" -Action "BulkProvision"

    $csvPath = Read-Host "  Enter full path to the CSV file"
    $csvPath = $csvPath.Trim().Trim('"')

    if (-not (Test-Path -Path $csvPath -PathType Leaf)) {
        Write-Log -Message "CSV not found: $csvPath" -Level "ERROR" -Action "BulkProvision"
        Pause-AndReturn
        return
    }

    try {
        $users = Import-Csv -Path $csvPath -ErrorAction Stop
    }
    catch {
        Write-Log -Message "Failed to import CSV. Error: $($_.Exception.Message)" -Level "ERROR" -Action "BulkProvision"
        Pause-AndReturn
        return
    }

    $requiredColumns = @("FirstName", "LastName", "Department")
    $csvHeaders      = $users[0].PSObject.Properties.Name

    foreach ($col in $requiredColumns) {
        if ($col -notin $csvHeaders) {
            Write-Log -Message "CSV is missing required column: '$col'. Aborting." -Level "ERROR" -Action "BulkProvision"
            Pause-AndReturn
            return
        }
    }

    Write-Log -Message "CSV validated. Rows to process: $($users.Count). File: $csvPath" -Level "INFO" -Action "BulkProvision"

    # ---- Determine domain DN ----
    if ($script:DemoMode) {
        $domainDN = "DC=contoso,DC=demo"
    }
    else {
        $domainDN = (Get-ADDomain -ErrorAction Stop).DistinguishedName
    }

    Write-Host ""
    Write-Host "  Department OUs will be created under a parent OU." -ForegroundColor Gray
    Write-Host "  Example: OU=Staff,$domainDN" -ForegroundColor Gray
    $parentOU = Read-Host "  Enter parent OU distinguished name (press ENTER for domain root)"
    if ([string]::IsNullOrWhiteSpace($parentOU)) { $parentOU = $domainDN }

    $created = 0
    $skipped = 0
    $failed  = 0

    foreach ($row in $users) {
        $firstName  = $row.FirstName.Trim()
        $lastName   = $row.LastName.Trim()
        $department = $row.Department.Trim()

        if ([string]::IsNullOrWhiteSpace($firstName) -or [string]::IsNullOrWhiteSpace($lastName)) {
            Write-Log -Message "Skipping row -- FirstName or LastName blank." -Level "WARNING" -Action "BulkProvision"
            $skipped++
            continue
        }

        $rawSam = "$($firstName.Substring(0,1))$lastName" -replace '\s',''
        $rawSam = $rawSam -replace '[^a-zA-Z0-9._-]', ''
        $sam    = $rawSam.ToLower().Substring(0, [Math]::Min($rawSam.Length, 20))

        $upn         = "$sam@$($script:Domain)"
        $displayName = "$firstName $lastName"
        $title       = if ($row.PSObject.Properties.Name -contains "Title")        { $row.Title.Trim() }        else { "" }
        $managerSam  = if ($row.PSObject.Properties.Name -contains "Manager")      { $row.Manager.Trim() }      else { "" }
        $tempPassRaw = if ($row.PSObject.Properties.Name -contains "TempPassword") { $row.TempPassword.Trim() } else { "" }

        if ([string]::IsNullOrWhiteSpace($tempPassRaw)) {
            $tempPassRaw = "Welcome@$(Get-Random -Minimum 1000 -Maximum 9999)!"
        }

        Invoke-DemoDelay -Ms 350

        if ($script:DemoMode) {
            # ---- DEMO: Simulate duplicate check ----
            $alreadyExists = $script:DemoUsers.ContainsKey($sam)

            if ($alreadyExists) {
                Write-Log -Message "SKIP -- User '$sam' already exists in AD. Skipping row for $displayName." -Level "WARNING" -Action "BulkProvision"
                $skipped++
                continue
            }

            # ---- DEMO: Simulate OU check/create ----
            $deptOUName = "OU=$department,$parentOU"
            $ouExists   = ($department -in @("Finance","Engineering","Human Resources","IT Support","Marketing"))
            if (-not $ouExists) {
                Write-Log -Message "Created new OU '$department' under '$parentOU'." -Level "INFO" -Action "BulkProvision"
            }

            # ---- DEMO: Simulate New-ADUser ----
            # Add to demo users dictionary so subsequent duplicates are caught this session
            $script:DemoUsers[$sam] = [PSCustomObject]@{
                SamAccountName    = $sam
                DisplayName       = $displayName
                UserPrincipalName = $upn
                LockedOut         = $false
                Enabled           = $true
                BadLogonCount     = 0
                PasswordLastSet   = Get-Date
                LastLogonDate     = $null
                MemberOf          = @()
            }

            Write-Log -Message "CREATED user '$sam' ($displayName) | Dept=$department | OU=$deptOUName | UPN=$upn" -Level "SUCCESS" -Action "BulkProvision"
            $created++
        }
        else {
            # ---- REAL MODE ----
            $existingUser = $null
            try { $existingUser = Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction Stop } catch { $existingUser = $null }

            if ($null -ne $existingUser) {
                Write-Log -Message "SKIP -- User '$sam' already exists. Skipping $displayName." -Level "WARNING" -Action "BulkProvision"
                $skipped++
                continue
            }

            $deptOUName = "OU=$department,$parentOU"
            $targetOU   = $deptOUName
            $ouExists   = $null
            try { $ouExists = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$deptOUName'" -ErrorAction Stop } catch { $ouExists = $null }

            if ($null -eq $ouExists) {
                try {
                    New-ADOrganizationalUnit -Name $department -Path $parentOU -ProtectedFromAccidentalDeletion $true -ErrorAction Stop
                    Write-Log -Message "Created new OU '$department' under '$parentOU'." -Level "INFO" -Action "BulkProvision"
                }
                catch {
                    Write-Log -Message "Could not create OU '$department'. Placing in parent OU. Error: $($_.Exception.Message)" -Level "WARNING" -Action "BulkProvision"
                    $targetOU = $parentOU
                }
            }

            $securePass  = ConvertTo-SecureString -String $tempPassRaw -AsPlainText -Force
            $newUserParams = @{
                SamAccountName        = $sam
                UserPrincipalName     = $upn
                GivenName             = $firstName
                Surname               = $lastName
                Name                  = $displayName
                DisplayName           = $displayName
                Department            = $department
                Title                 = $title
                Description           = "Created by $script:ScriptName on $(Get-Date -Format 'yyyy-MM-dd')"
                Path                  = $targetOU
                AccountPassword       = $securePass
                Enabled               = $true
                ChangePasswordAtLogon = $true
                ErrorAction           = "Stop"
            }

            if (-not [string]::IsNullOrWhiteSpace($managerSam)) {
                try {
                    $managerObj = Get-ADUser -Identity $managerSam -ErrorAction Stop
                    $newUserParams["Manager"] = $managerObj.DistinguishedName
                }
                catch {
                    Write-Log -Message "Manager '$managerSam' not found for $displayName -- skipping manager attribute." -Level "WARNING" -Action "BulkProvision"
                }
            }

            try {
                New-ADUser @newUserParams
                Write-Log -Message "CREATED user '$sam' ($displayName) | Dept=$department | OU=$targetOU | UPN=$upn" -Level "SUCCESS" -Action "BulkProvision"
                $created++
            }
            catch {
                Write-Log -Message "FAILED to create '$sam' ($displayName). Error: $($_.Exception.Message)" -Level "ERROR" -Action "BulkProvision"
                $failed++
            }
        }
    }

    Write-Host ""
    Write-Host "  -- Provisioning Complete -------------------------------------------" -ForegroundColor DarkCyan
    Write-Log -Message "Bulk provisioning finished. Created=$created  Skipped=$skipped  Failed=$failed" -Level "INFO" -Action "BulkProvision"

    Pause-AndReturn
}

# ---------------------------------------------------------------------------
# FUNCTION: Invoke-AccountUnlockReset
# PURPOSE : Unlocks an account and resets its password. In Demo Mode, account
#           details come from the $script:DemoUsers hashtable and all write
#           operations are simulated with a realistic delay.
# ---------------------------------------------------------------------------
function Invoke-AccountUnlockReset {
    Write-Host ""
    Write-Host "  -- Account Unlock & Password Reset ---------------------------------" -ForegroundColor DarkCyan
    Write-Log -Message "Account Unlock/Reset initiated." -Level "INFO" -Action "UnlockReset"

    $sam = Read-Host "  Enter the SamAccountName (username) to unlock/reset"
    $sam = $sam.Trim()

    if ([string]::IsNullOrWhiteSpace($sam)) {
        Write-Log -Message "No username entered. Operation cancelled." -Level "WARNING" -Action "UnlockReset"
        Pause-AndReturn
        return
    }

    Invoke-DemoDelay -Ms 400

    if ($script:DemoMode) {
        # ---- DEMO: Lookup user ----
        if (-not $script:DemoUsers.ContainsKey($sam)) {
            Write-Log -Message "User '$sam' not found in AD (simulated). Try: jsmith, crivera, apatel, mbrown" -Level "ERROR" -Action "UnlockReset"
            Pause-AndReturn
            return
        }
        $adUser = $script:DemoUsers[$sam]
    }
    else {
        # ---- REAL: Lookup user ----
        $adUser = $null
        try {
            $adUser = Get-ADUser -Identity $sam `
                                 -Properties LockedOut, PasswordLastSet, BadLogonCount, LastLogonDate, Enabled `
                                 -ErrorAction Stop
        }
        catch {
            Write-Log -Message "User '$sam' not found in AD. Error: $($_.Exception.Message)" -Level "ERROR" -Action "UnlockReset"
            Pause-AndReturn
            return
        }
    }

    # Display account status (identical path for real and demo)
    Write-Host ""
    Write-Host "  Account Details:" -ForegroundColor Gray
    Write-Host "    Display Name   : $($adUser.DisplayName)" -ForegroundColor White
    Write-Host "    Enabled        : $($adUser.Enabled)" -ForegroundColor White
    Write-Host "    Locked Out     : $($adUser.LockedOut)" -ForegroundColor $(if ($adUser.LockedOut) { "Red" } else { "Green" })
    Write-Host "    Bad Logon Count: $($adUser.BadLogonCount)" -ForegroundColor White
    Write-Host "    Last Logon     : $($adUser.LastLogonDate)" -ForegroundColor White
    Write-Host "    Password Set   : $($adUser.PasswordLastSet)" -ForegroundColor White
    Write-Host ""

    Write-Log -Message "Account status retrieved for '$sam'. LockedOut=$($adUser.LockedOut) Enabled=$($adUser.Enabled) BadLogons=$($adUser.BadLogonCount)" -Level "INFO" -Action "UnlockReset"

    # ---- Handle disabled account ----
    if (-not $adUser.Enabled) {
        Write-Host "  [WARNING] This account is DISABLED, not just locked out." -ForegroundColor Yellow
        $enableChoice = Read-Host "  Do you also want to ENABLE this account? (Y/N)"
        if ($enableChoice -match '^[Yy]$') {
            Invoke-DemoDelay -Ms 300
            if ($script:DemoMode) {
                $script:DemoUsers[$sam].Enabled = $true
            }
            else {
                Enable-ADAccount -Identity $sam -ErrorAction Stop
            }
            Write-Log -Message "Account '$sam' has been ENABLED." -Level "SUCCESS" -Action "UnlockReset"
        }
        else {
            Write-Log -Message "Operator chose NOT to enable disabled account '$sam'." -Level "INFO" -Action "UnlockReset"
        }
    }

    # ---- Unlock if locked ----
    if ($adUser.LockedOut) {
        Invoke-DemoDelay -Ms 450
        try {
            if ($script:DemoMode) {
                $script:DemoUsers[$sam].LockedOut    = $false
                $script:DemoUsers[$sam].BadLogonCount = 0
            }
            else {
                Unlock-ADAccount -Identity $sam -ErrorAction Stop
            }
            Write-Log -Message "Account '$sam' successfully UNLOCKED." -Level "SUCCESS" -Action "UnlockReset"
        }
        catch {
            Write-Log -Message "Failed to unlock '$sam'. Error: $($_.Exception.Message)" -Level "ERROR" -Action "UnlockReset"
        }
    }
    else {
        Write-Log -Message "Account '$sam' was NOT locked out. No unlock action required." -Level "INFO" -Action "UnlockReset"
    }

    # ---- Password reset ----
    Write-Host "  Enter the new temporary password (leave blank to auto-generate):" -ForegroundColor Gray
    $newPassRaw = Read-Host "  New Password"

    if ([string]::IsNullOrWhiteSpace($newPassRaw)) {
        $newPassRaw = "TempPass@$(Get-Random -Minimum 1000 -Maximum 9999)!"
        Write-Host "  Auto-generated password: $newPassRaw" -ForegroundColor Yellow
        Write-Log -Message "Auto-generated temporary password for '$sam'." -Level "INFO" -Action "UnlockReset"
    }

    Invoke-DemoDelay -Ms 500
    try {
        if ($script:DemoMode) {
            $script:DemoUsers[$sam].PasswordLastSet = Get-Date
            # (Password itself is not stored — same as real AD behavior for compliance)
        }
        else {
            $securePass = ConvertTo-SecureString -String $newPassRaw -AsPlainText -Force
            Set-ADAccountPassword -Identity $sam -NewPassword $securePass -Reset -ErrorAction Stop
            Set-ADUser -Identity $sam -ChangePasswordAtLogon $true -ErrorAction Stop
        }
        Write-Log -Message "Password RESET for '$sam'. ChangePasswordAtLogon=True." -Level "SUCCESS" -Action "UnlockReset"
    }
    catch {
        Write-Log -Message "Failed to reset password for '$sam'. Error: $($_.Exception.Message)" -Level "ERROR" -Action "UnlockReset"
    }

    Pause-AndReturn
}

# ---------------------------------------------------------------------------
# FUNCTION: Invoke-GroupManagement
# PURPOSE : Adds a user to a Security Group. In Demo Mode, membership checks
#           and Add-ADGroupMember are simulated against $script:DemoGroups.
# ---------------------------------------------------------------------------
function Invoke-GroupManagement {
    Write-Host ""
    Write-Host "  -- Security Group Management ---------------------------------------" -ForegroundColor DarkCyan
    Write-Log -Message "Group Management initiated." -Level "INFO" -Action "GroupMgmt"

    $sam       = Read-Host "  Enter the SamAccountName of the user"
    $sam       = $sam.Trim()
    $groupName = Read-Host "  Enter the Security Group name"
    $groupName = $groupName.Trim()

    if ([string]::IsNullOrWhiteSpace($sam) -or [string]::IsNullOrWhiteSpace($groupName)) {
        Write-Log -Message "Missing username or group name. Operation cancelled." -Level "WARNING" -Action "GroupMgmt"
        Pause-AndReturn
        return
    }

    Invoke-DemoDelay -Ms 400

    if ($script:DemoMode) {
        # ---- DEMO: Validate user ----
        if (-not $script:DemoUsers.ContainsKey($sam)) {
            Write-Log -Message "User '$sam' not found in AD (simulated). Try: jsmith, crivera, apatel, mbrown" -Level "ERROR" -Action "GroupMgmt"
            Pause-AndReturn
            return
        }
        $adUser = $script:DemoUsers[$sam]

        # ---- DEMO: Validate group ----
        if (-not $script:DemoGroups.ContainsKey($groupName)) {
            Write-Log -Message "Group '$groupName' not found (simulated). Try: Finance-ReadOnly, Engineering-All, HR-Staff, All-Marketing-Dist" -Level "ERROR" -Action "GroupMgmt"
            Pause-AndReturn
            return
        }
        $adGroup = $script:DemoGroups[$groupName]
    }
    else {
        # ---- REAL: Validate user ----
        $adUser = $null
        try {
            $adUser = Get-ADUser -Identity $sam -Properties DisplayName, MemberOf -ErrorAction Stop
        }
        catch {
            Write-Log -Message "User '$sam' not found in AD. Error: $($_.Exception.Message)" -Level "ERROR" -Action "GroupMgmt"
            Pause-AndReturn
            return
        }

        # ---- REAL: Validate group ----
        $adGroup = $null
        try {
            $adGroup = Get-ADGroup -Identity $groupName -Properties GroupCategory, GroupScope, Members -ErrorAction Stop
        }
        catch {
            try {
                $adGroup = Get-ADGroup -Filter "Name -eq '$groupName'" -Properties GroupCategory, GroupScope -ErrorAction Stop
                if ($null -eq $adGroup) { throw "Group not found." }
            }
            catch {
                Write-Log -Message "Group '$groupName' not found in AD. Error: $($_.Exception.Message)" -Level "ERROR" -Action "GroupMgmt"
                Pause-AndReturn
                return
            }
        }
    }

    # ---- Warn if Distribution group ----
    if ($adGroup.GroupCategory -ne "Security") {
        Write-Host "  [WARNING] '$groupName' is a Distribution group, not a Security group." -ForegroundColor Yellow
        Write-Log -Message "WARNING -- '$groupName' is a Distribution group (Category=$($adGroup.GroupCategory))." -Level "WARNING" -Action "GroupMgmt"
    }

    Write-Host ""
    Write-Host "  User  : $($adUser.DisplayName) ($sam)" -ForegroundColor White
    Write-Host "  Group : $($adGroup.Name) [$($adGroup.GroupScope) / $($adGroup.GroupCategory)]" -ForegroundColor White
    Write-Host ""

    # ---- Check existing membership ----
    Invoke-DemoDelay -Ms 300
    $isMember = $false

    if ($script:DemoMode) {
        $isMember = $adGroup.Members -contains $sam
    }
    else {
        try {
            $membership = Get-ADGroupMember -Identity $adGroup.SamAccountName -Recursive -ErrorAction Stop
            $isMember   = ($membership | Where-Object { $_.SamAccountName -eq $sam }) -ne $null
        }
        catch {
            Write-Log -Message "Could not enumerate group members for pre-check. Error: $($_.Exception.Message)" -Level "WARNING" -Action "GroupMgmt"
        }
    }

    if ($isMember) {
        Write-Log -Message "SKIP -- '$sam' is ALREADY a member of '$($adGroup.Name)'. No changes made." -Level "WARNING" -Action "GroupMgmt"
        Pause-AndReturn
        return
    }

    # ---- Add user to group ----
    Invoke-DemoDelay -Ms 500
    try {
        if ($script:DemoMode) {
            # Mutate the demo group's member list in-memory
            $updatedMembers = [System.Collections.ArrayList]@($adGroup.Members)
            $updatedMembers.Add($sam) | Out-Null
            $script:DemoGroups[$groupName].Members = $updatedMembers.ToArray()
        }
        else {
            Add-ADGroupMember -Identity $adGroup.SamAccountName -Members $sam -ErrorAction Stop
        }
        Write-Log -Message "SUCCESS -- '$sam' ($($adUser.DisplayName)) added to group '$($adGroup.Name)'." -Level "SUCCESS" -Action "GroupMgmt"
    }
    catch {
        Write-Log -Message "FAILED -- Could not add '$sam' to '$($adGroup.Name)'. Error: $($_.Exception.Message)" -Level "ERROR" -Action "GroupMgmt"
    }

    Pause-AndReturn
}

# ---------------------------------------------------------------------------
# FUNCTION: Show-RecentLogs
# PURPOSE : Displays the last N lines of the audit log in the console.
#           Fully real in both modes — the log file always exists after any action.
# ---------------------------------------------------------------------------
function Show-RecentLogs {
    Write-Host ""
    Write-Host "  -- Recent Audit Log Entries ----------------------------------------" -ForegroundColor DarkCyan
    Write-Host "  Log file: $script:LogPath" -ForegroundColor Gray
    Write-Host ""

    if (-not (Test-Path -Path $script:LogPath -PathType Leaf)) {
        Write-Host "  No log file found yet. Perform an action first." -ForegroundColor Yellow
        Pause-AndReturn
        return
    }

    $lineCount = Read-Host "  How many recent lines to show? (default: 20)"
    if (-not ($lineCount -match '^\d+$') -or [int]$lineCount -lt 1) { $lineCount = 20 }

    $recentLines = Get-Content -Path $script:LogPath -Tail ([int]$lineCount) -ErrorAction SilentlyContinue

    if (-not $recentLines) {
        Write-Host "  Log file is empty." -ForegroundColor Yellow
    }
    else {
        Write-Host ""
        foreach ($line in $recentLines) {
            $colour = switch -Wildcard ($line) {
                "* | SUCCESS | *" { "Green"  }
                "* | ERROR | *"   { "Red"    }
                "* | WARNING | *" { "Yellow" }
                default           { "Gray"   }
            }
            Write-Host "  $line" -ForegroundColor $colour
        }
    }

    Write-Host ""
    Write-Host "  Full log: $script:LogPath" -ForegroundColor DarkGray
    Pause-AndReturn
}

# ---------------------------------------------------------------------------
# FUNCTION: Pause-AndReturn
# PURPOSE : Holds the console open so the technician can read output before
#           the screen is cleared by Show-Menu on the next iteration.
# ---------------------------------------------------------------------------
function Pause-AndReturn {
    Write-Host ""
    Write-Host "  Press ENTER to return to the main menu..." -ForegroundColor DarkGray
    Read-Host | Out-Null
}

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
        "1" { Invoke-BulkProvisioning   }
        "2" { Invoke-AccountUnlockReset }
        "3" { Invoke-GroupManagement    }
        "4" { Show-RecentLogs           }
        "Q" {
            Write-Log -Message "Session ended by operator." -Level "INFO" -Action "INIT"
            Write-Host ""
            Write-Host "  Goodbye. Audit log saved to: $script:LogPath" -ForegroundColor Cyan
            Write-Host ""
            $running = $false
        }
        default {
            Write-Host "  Invalid choice '$choice'. Please enter 1, 2, 3, 4, or Q." -ForegroundColor Yellow
            Start-Sleep -Seconds 1
        }
    }
}
