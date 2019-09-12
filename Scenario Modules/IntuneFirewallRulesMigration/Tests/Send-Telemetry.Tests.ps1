. "$PSScriptRoot\..\IntuneFirewallRulesMigration\Private\Send-Telemetry.ps1"
. "$PSScriptRoot\..\IntuneFirewallRulesMigration\Private\Strings.ps1"

Describe "Send Telemetry Test Cases" {
    Context "Send-ConvertToIntuneFirewallRuleTelemetry" {
        It "Should call Send-FailureTelemetry with a 'ConvertToIntuneFirewallRule' category" {
            Mock Send-FailureTelemetry

            Send-ConvertToIntuneFirewallRuleTelemetry "foo"

            Assert-MockCalled Send-FailureTelemetry -ParameterFilter { $category -eq "ConvertToIntuneFirewallRule" } -Times 1 -Exactly
        }
    }

    Context "Send-IntuneFirewallRuleTelemetry" {
        It "Should call Send-FailureTelemetry with a 'IntuneFirewallRuleGraph' category" {
            Mock Send-FailureTelemetry

            Send-IntuneFirewallGraphTelemetry "foo"

            Assert-MockCalled Send-FailureTelemetry -ParameterFilter { $category -eq "IntuneFirewallRuleGraph" } -Times 1 -Exactly
        }
    }
}

Describe "Get-IntuneFirewallRuleErrorTelemetryChoice" {
    It "Should return 'Yes' if given the -sendErrorTelemetryInitialized is passed with a true value" {
        Get-IntuneFirewallRuleErrorTelemetryChoice -telemetryMessage "foo" -sendErrorTelemetryInitialized $true | Should -Be "Yes"
    }

    It "Should return 'Yes' if user selected 'Yes'" {
        Mock Get-UserPrompt -MockWith { return 0 }
        Get-IntuneFirewallRuleErrorTelemetryChoice -telemetryMessage "foo" | Should -Be $Strings.Yes
    }

    It "Should return 'No' if user selected 'No'" {
        Mock Get-UserPrompt -MockWith { return 1 }
        Get-IntuneFirewallRuleErrorTelemetryChoice -telemetryMessage "foo" | Should -Be $Strings.No
    }

    It "Should return 'Yes to All' if user selected 'Yes To All'" {
        Mock Get-UserPrompt -MockWith { return 2 }
        Get-IntuneFirewallRuleErrorTelemetryChoice -telemetryMessage "foo" | Should -Be $Strings.YesToAll
    }

    It "Should return 'Continue' if user selected 'Continue'" {
        Mock Get-UserPrompt -MockWith { return 3 }
        Get-IntuneFirewallRuleErrorTelemetryChoice -telemetryMessage "foo" | Should -Be $Strings.Continue
    }
}
