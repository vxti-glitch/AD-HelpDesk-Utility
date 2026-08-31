$modulePath = Join-Path $PSScriptRoot '..\modules\ADHelpDeskCore.psm1'
Import-Module $modulePath -Force

Describe 'New-ComplexPassword' {
    It 'returns the requested length' {
        (New-ComplexPassword -Length 24).Length | Should -Be 24
    }

    It 'contains each required character class' {
        $password = New-ComplexPassword -Length 32

        $password | Should -Match '[A-Z]'
        $password | Should -Match '[a-z]'
        $password | Should -Match '[0-9]'
        $password | Should -Match '[!@#$%^&*()_+=-]'
    }

    It 'generates different values across repeated calls' {
        $passwords = 1..10 | ForEach-Object { New-ComplexPassword -Length 20 }

        ($passwords | Sort-Object -Unique).Count | Should -Be 10
    }
}

Describe 'Directory input escaping' {
    It 'escapes single quotes in AD filter literals' {
        Escape-ADFilterLiteral -Value "O'Connor" | Should -Be "O''Connor"
    }

    It 'escapes distinguished-name separators' {
        Escape-ADDistinguishedNameValue -Value 'Finance, East' |
            Should -Be 'Finance\, East'
    }

    It 'escapes leading and trailing spaces in distinguished names' {
        Escape-ADDistinguishedNameValue -Value ' Team ' |
            Should -Be '\ Team\ '
    }
}

Describe 'Lookup outcomes fail closed' {
    It 'distinguishes confirmed missing from ambiguous and found results' {
        Get-ADLookupResultState -Items @() | Should -Be 'ConfirmedMissing'
        Get-ADLookupResultState -Items @([pscustomobject]@{ Name = 'one' }) | Should -Be 'Found'
        Get-ADLookupResultState -Items @(
            [pscustomobject]@{ Name = 'one' },
            [pscustomobject]@{ Name = 'two' }
        ) | Should -Be 'Ambiguous'
    }

    It 'classifies access denied' {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [UnauthorizedAccessException]::new('Access is denied'),
            'AccessDenied',
            [System.Management.Automation.ErrorCategory]::PermissionDenied,
            $null
        )
        Get-ADLookupFailureKind -ErrorRecord $errorRecord | Should -Be 'AccessDenied'
    }

    It 'classifies an unreachable directory service' {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [TimeoutException]::new('Domain controller timed out'),
            'ServerTimeout',
            [System.Management.Automation.ErrorCategory]::ConnectionError,
            $null
        )
        Get-ADLookupFailureKind -ErrorRecord $errorRecord | Should -Be 'Unavailable'
    }

    It 'classifies a confirmed identity absence' {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [InvalidOperationException]::new('Cannot find an object'),
            'IdentityNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $null
        )
        Get-ADLookupFailureKind -ErrorRecord $errorRecord | Should -Be 'NotFound'
    }
}

Describe 'OU safety boundary' {
    It 'allows a target under an approved base DN' {
        Test-AllowedOUPath -DistinguishedName 'OU=Finance,OU=Staff,DC=contoso,DC=com' `
            -AllowedBaseDN 'OU=Staff,DC=contoso,DC=com' | Should -BeTrue
    }

    It 'rejects a target outside the approved base DN' {
        Test-AllowedOUPath -DistinguishedName 'OU=Admins,DC=contoso,DC=com' `
            -AllowedBaseDN 'OU=Staff,DC=contoso,DC=com' | Should -BeFalse
    }
}

Describe 'Demo provisioning honors explicit OU creation and WhatIf' {
    BeforeEach {
        Initialize-ADHelpDeskCore -DemoMode $true -LogPath (Join-Path $TestDrive 'activity.log') `
            -DefaultOU 'OU=Staff,DC=contoso,DC=demo' -Domain 'contoso.demo' -ScriptName 'Pester'
        Mock Pause-AndReturn -ModuleName ADHelpDeskCore
    }

    It 'does not change demo state under WhatIf' {
        $csv = Join-Path $TestDrive 'whatif.csv'
        "FirstName,LastName,Department`nNoah,UniqueWhatIf,Finance" | Set-Content -Path $csv

        Invoke-BulkProvisioning -CsvPath $csv -ParentOU 'OU=Staff,DC=contoso,DC=demo' `
            -AllowedBaseDN 'OU=Staff,DC=contoso,DC=demo' -WhatIf

        InModuleScope ADHelpDeskCore {
            $script:DemoUsers.ContainsKey('nuniquewhatif') | Should -BeFalse
        }
    }

    It 'requires the explicit switch before simulating a missing OU creation' {
        $csv = Join-Path $TestDrive 'missing-ou.csv'
        "FirstName,LastName,Department`nRiley,MissingOU,Research" | Set-Content -Path $csv

        Invoke-BulkProvisioning -CsvPath $csv -ParentOU 'OU=Staff,DC=contoso,DC=demo' `
            -AllowedBaseDN 'OU=Staff,DC=contoso,DC=demo'

        InModuleScope ADHelpDeskCore {
            $script:DemoUsers.ContainsKey('rmissingou') | Should -BeFalse
        }
    }

    It 'allows explicit simulated OU creation and never logs a password' {
        $csv = Join-Path $TestDrive 'create-ou.csv'
        "FirstName,LastName,Department`nTaylor,ExplicitOU,Research" | Set-Content -Path $csv

        Invoke-BulkProvisioning -CsvPath $csv -ParentOU 'OU=Staff,DC=contoso,DC=demo' `
            -AllowedBaseDN 'OU=Staff,DC=contoso,DC=demo' -CreateMissingOUs

        InModuleScope ADHelpDeskCore {
            $script:DemoUsers.ContainsKey('texplicitou') | Should -BeTrue
        }
        (Get-Content (Join-Path $TestDrive 'activity.log') -Raw) | Should -Not -Match 'TempPassword|Auto-generated password'
    }

    It 'skips a pre-existing user' {
        $csv = Join-Path $TestDrive 'existing.csv'
        "FirstName,LastName,Department`nJane,Smith,Finance" | Set-Content -Path $csv

        Invoke-BulkProvisioning -CsvPath $csv -ParentOU 'OU=Staff,DC=contoso,DC=demo' `
            -AllowedBaseDN 'OU=Staff,DC=contoso,DC=demo'

        (Get-Content (Join-Path $TestDrive 'activity.log') -Raw) | Should -Match "User 'jsmith' already exists"
    }
}

