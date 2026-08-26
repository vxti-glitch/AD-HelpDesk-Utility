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

