# Active Directory Help Desk Utility

I built this small PowerShell utility to practice safe, routine Active Directory support workflows: CSV-based user creation, account unlock and temporary-password reset, and security-group membership. The repository includes a clearly simulated demo mode so I can exercise the control flow without claiming access to a live organization or production directory.

The current CI suite uses mocks, pure guard functions, and offline demo paths. It does not prove behavior against a real domain, delegated permissions, replication, password policy, or domain-controller failures; an authorized AD lab is still required for that evidence.

## Safety behavior

- Directory lookup errors are not treated as “not found.” Access denied, unreachable directory services, ambiguous results, and unexpected failures stop the affected change.
- User creation requires a confirmed-missing account and exactly one existing target OU.
- Target OUs must be within `-AllowedBaseDN`. The default boundary is the configured parent/default OU.
- Missing department OUs are not created by default. `-CreateMissingOUs` is explicit, has its own `ShouldProcess` and interactive confirmation boundary, and requires delegated OU-creation permission.
- `-WhatIf` performs no user, OU, password, unlock, enable, or group writes and reports planned/skipped actions as such.
- Temporary passwords use `RandomNumberGenerator`, are marked `ChangePasswordAtLogon`, and are never written to the local activity log. The interactive console may display an auto-generated password once so the operator can transfer it through an approved channel.

## Local activity log boundary

The pipe-delimited file is a structured local activity log. It is editable and is not tamper-evident, compliance-grade, or a security audit trail. A real audit design would require access controls, centralized forwarding, retention policy, monitoring, clock controls, and integrity protections appropriate to the organization.

The log includes operator and machine identifiers, so store and share it carefully.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7 for offline/demo checks
- ActiveDirectory RSAT module and authorized domain connectivity for real mode
- Only the delegated permissions required for the selected operation
- Pester 5 for the documented tests
- PSScriptAnalyzer for static analysis

Do not run the utility as Domain Admin merely for convenience.

## Run the simulated path

```powershell
git clone https://github.com/vxti-glitch/AD-HelpDesk-Utility.git
cd AD-HelpDesk-Utility
.\AD-HelpDesk-Utility.ps1 -DemoMode
```

Demo users and groups are synthetic. Demo-mode actions are in-memory simulations plus the editable local log; they are not live AD evidence.

## Run against an authorized lab

```powershell
.\AD-HelpDesk-Utility.ps1 `
  -Domain 'lab.example' `
  -DefaultUserOU 'OU=Staff,DC=lab,DC=example' `
  -AllowedBaseDN 'OU=Staff,DC=lab,DC=example'
```

To permit a separate OU-creation confirmation:

```powershell
.\AD-HelpDesk-Utility.ps1 `
  -Domain 'lab.example' `
  -DefaultUserOU 'OU=Staff,DC=lab,DC=example' `
  -AllowedBaseDN 'OU=Staff,DC=lab,DC=example' `
  -CreateMissingOUs
```

Preview writes first:

```powershell
.\AD-HelpDesk-Utility.ps1 -WhatIf -Domain 'lab.example' `
  -DefaultUserOU 'OU=Staff,DC=lab,DC=example' `
  -AllowedBaseDN 'OU=Staff,DC=lab,DC=example'
```

The CSV columns are `FirstName`, `LastName`, and `Department`, with optional `Title`, `Manager`, and `TempPassword`. Prefer leaving `TempPassword` blank so the cryptographic generator is used. `data/sample-users.csv` is synthetic.

## Verification

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse
Invoke-Pester .\tests -CI -Output Detailed
```

The tests cover cryptographic password shape, input escaping, confirmed absence, access denied, unreachable service, ambiguous/pre-existing lookup states, allowed/disallowed OU paths, explicit OU creation in demo mode, and `WhatIf` no-change behavior. They do not print or persist temporary passwords.

## Current evidence boundary

What is demonstrated here: PowerShell guard logic, offline/demo control flow, local logging behavior, static analysis, and mock/unit tests.

What is not yet demonstrated: live AD object creation, delegated-permission behavior, domain-controller failover, replication, organization-specific password policy, or production operation.

MIT licensed. See `LICENSE`.
