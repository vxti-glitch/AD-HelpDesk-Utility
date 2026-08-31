@{
    Severity = @('Error', 'Warning')
    ExcludeRules = @(
        # Interactive menus intentionally use host colors and prompts.
        'PSAvoidUsingWriteHost'
        # AD cmdlets require SecureString; the plaintext exists only in memory,
        # is immediately converted, and is never logged or persisted.
        'PSAvoidUsingConvertToSecureStringWithPlainText'
        # These established local helper names are kept for compatibility.
        'PSUseApprovedVerbs'
        'PSUseSingularNouns'
        'PSAvoidOverwritingBuiltInCmdlets'
        # Password generation changes no external state despite the New verb.
        'PSUseShouldProcessForStateChangingFunctions'
        # Missing-OU creation deliberately requires a second confirmation.
        'PSAvoidShouldContinueWithoutForce'
        'PSPossibleIncorrectComparisonWithNull'
    )
}
