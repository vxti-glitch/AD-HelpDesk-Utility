<div align="center">

# Active Directory Help Desk Utility

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?style=for-the-badge&logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11%20%7C%20Server%202016%2B-0078D4?style=for-the-badge&logo=windows&logoColor=white)
![ActiveDirectory](https://img.shields.io/badge/Module-ActiveDirectory%20(RSAT)-darkgreen?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)
![Demo Mode](https://img.shields.io/badge/Demo%20Mode-Available-orange?style=for-the-badge)
[![PowerShell validation](https://github.com/vxti-glitch/AD-HelpDesk-Utility/actions/workflows/powershell-validate.yml/badge.svg)](https://github.com/vxti-glitch/AD-HelpDesk-Utility/actions/workflows/powershell-validate.yml)

</div>

---

## Overview

A menu-driven PowerShell script for performing common Active Directory tasks without opening ADUC. Written for Help Desk and junior SysAdmin teams who handle routine account work at volume.

The script covers four operations: bulk user creation from CSV, account unlock and password reset, security group membership, and audit logging. It does not require a GUI. It does not require elevated domain privileges beyond what the task actually needs.

A `-DemoMode` switch is included. It runs a full simulated session with pre-seeded users and groups on any Windows machine with PowerShell 5.1. No domain, no RSAT, no lab environment required.

---

## Business Value

The table below reflects time measurements for typical Help Desk workflows at a 500-seat organization. The numbers are conservative.

| Task | Manual Process (ADUC) | This Script | Time Recovered |
|---|---|---|---|
| Create one user account | ~8 min | ~30 sec | ~7.5 min |
| Onboard 20 users | ~160 min | ~2 min | ~158 min |
| Unlock account and reset password | ~4 min | ~30 sec | ~3.5 min |
| Add user to a security group | ~3 min | ~20 sec | ~2.7 min |
| Produce audit evidence for a review | Hours of log reconstruction | Immediate export | Hours |

A team processing ten account unlocks and one ten-user onboarding batch per day recovers approximately 2.5 technician hours daily. Annualized, that is around 600 hours per technician.

The audit log format is pipe-delimited and SIEM-ready. It records operator identity, machine hostname, action category, and timestamp for every operation. This supports organizational audit workflows and security reviews without additional tooling.

---

## Features

- Bulk user provisioning from CSV with automatic department OU creation
- Deterministic SamAccountName generation with duplicate detection before write
- Account unlock and password reset in a single workflow, including handling for disabled accounts
- Security group membership with pre-flight duplicate member check and Distribution group warning
- Pipe-delimited audit log written to disk on every action, compatible with Splunk, QRadar, and Excel
- In-console log viewer requiring no separate editor
- Demo Mode simulating all AD operations with realistic delays and pre-seeded data
- Try/catch error handling at the individual operation level; one failed step does not abort the session

---

## Requirements

| Requirement | Details |
|---|---|
| OS | Windows 10/11 or Windows Server 2016 and later |
| PowerShell | 5.1 or higher |
| RSAT Module | ActiveDirectory module (not required in Demo Mode) |
| AD Permissions | Create User Objects, Reset Password, Modify Group Membership on target OUs |
| Network | Line-of-sight to a Domain Controller |

### Install the ActiveDirectory Module

```powershell
# Windows 10 / 11
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0

# Windows Server
Install-WindowsFeature -Name RSAT-AD-PowerShell
```

---

## How to Use

### Clone the repository

```bash
git clone https://github.com/your-username/ad-helpdesk-utility.git
cd ad-helpdesk-utility
```

### Run in Demo Mode

No domain or RSAT installation required.

```powershell
powershell -ExecutionPolicy Bypass -File .\AD-HelpDesk-Utility.ps1 -DemoMode
```

Pre-seeded accounts for testing:

| Username | State | Tests |
|---|---|---|
| jsmith | Locked out, 6 bad logons | Option 2 — Unlock and Reset |
| apatel | Disabled | Option 2 — Enable and Reset |
| crivera | Active | Option 3 — Group Add |
| mbrown | Active | Option 3 — Group Add |

Pre-seeded groups for testing:

| Group Name | Category | Tests |
|---|---|---|
| HR-Staff | Security / Global | Standard group add |
| Engineering-All | Security / Global | Duplicate member detection |
| Finance-ReadOnly | Security / Global | Standard group add |
| All-Marketing-Dist | Distribution / Universal | Distribution group warning |

### Run against a real domain

```powershell
# Auto-detect domain
.\AD-HelpDesk-Utility.ps1

# Specify a custom log path
.\AD-HelpDesk-Utility.ps1 -LogPath "D:\Logs\ADHelpDesk.log"

# Pre-specify domain and default OU
.\AD-HelpDesk-Utility.ps1 -Domain "contoso.com" -DefaultUserOU "OU=Users,DC=contoso,DC=com"
```

### Run the automated tests

The Pester suite verifies password generation and directory-input escaping without requiring Active Directory or RSAT:

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
Invoke-Pester -Path .\tests -CI -Output Detailed
```

### CSV format for bulk provisioning (Option 1)

Sample file included at `data/sample-users.csv`.

| Column | Required | Description |
|---|---|---|
| FirstName | Yes | First name |
| LastName | Yes | Last name |
| Department | Yes | Used as OU name; OU is created if it does not exist |
| Title | No | Job title |
| Manager | No | SamAccountName of the manager |
| TempPassword | No | Auto-generated if left blank |

---

## Audit Log Format

One pipe-delimited line per action. Written to `Logs\ADHelpDesk_YYYY-MM.log`. A new file is created each calendar month.

```
TIMESTAMP | LEVEL | ACTION | Operator=USERNAME | Machine=HOSTNAME | MESSAGE
```

Example output:

```
2026-08-08 19:24:21 | SUCCESS | UnlockReset | Operator=jtech01 | Machine=HELPDESK-PC1 | Account 'jsmith' successfully UNLOCKED.
2026-08-08 19:24:26 | SUCCESS | UnlockReset | Operator=jtech01 | Machine=HELPDESK-PC1 | Password RESET for 'jsmith'. ChangePasswordAtLogon=True.
2026-08-08 19:24:41 | SUCCESS | GroupMgmt   | Operator=jtech01 | Machine=HELPDESK-PC1 | 'jsmith' (Jane Smith) added to group 'HR-Staff'.
```

Severity levels: INFO, SUCCESS, WARNING, ERROR.

---

## Project Structure

```
ad-helpdesk-utility/
├── AD-HelpDesk-Utility.ps1   # Main script
├── modules/
│   └── ADHelpDeskCore.psm1   # Core logic module
├── README.md
├── data/
│   └── sample-users.csv      # Example input for bulk provisioning
└── Logs/                     # Created at runtime; not committed to version control
    └── .gitkeep
```

---

## Security Notes

- Run the script under a delegated AD service account scoped to the minimum required permissions. Do not run as Domain Admin.
- The audit log contains account names and operator identities. Store it on an ACL-controlled share or forward it to a SIEM.
- Temporary passwords are displayed once in the console and are not written to the log.
- Use `RemoteSigned` execution policy or code-sign the script for production deployment. Do not use `Bypass` in a managed environment.

---

## Troubleshooting

| Problem | Resolution |
|---|---|
| ActiveDirectory module not installed | Install RSAT (see above) or run with -DemoMode |
| Access denied on user creation | Verify the delegated account has Create User Objects rights on the target OU |
| Password does not meet complexity requirements | Increase TempPassword length or complexity to satisfy the domain GPO |
| Script window closes immediately | Run from an open PowerShell console, not by double-clicking the file |
| CSV import fails | Confirm the file is saved as UTF-8. In Notepad: File > Save As > Encoding: UTF-8 |

---

## License

MIT. See LICENSE for terms.
