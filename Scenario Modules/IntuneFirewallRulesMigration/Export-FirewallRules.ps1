#-------------------------------------------------------------------------------------------

param([switch]$includeDisabledRules, [switch]$includeLocalRules)
## check for running from correct folder location
if (-not ( Test-Path -Path ".\IntuneFirewallRulesMigration\Private\strings.ps1")) {
    Write-Host -ForegroundColor Red "Error:  Must run from script folder"
    Write-Host "No commands completed"
    return
  }
  
   
  
  ## check for elevation   
   $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
   $principal = New-Object Security.Principal.WindowsPrincipal $identity
  
   if (!$principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator))  {
    Write-Host -ForegroundColor Red "Error:  Must run elevated: run as administrator"
    Write-Host "No commands completed"
    return
   }



Import-Module .\FirewallRulesMigration.psm1
. "$PSScriptRoot\IntuneFirewallRulesMigration\Private\Strings.ps1"

$profileName = ""
try
{
    $json = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/intents?$filter=templateId%20eq%20%274b219836-f2b1-46c6-954d-4cd2f4128676%27%20or%20templateId%20eq%20%274356d05c-a4ab-4a07-9ece-739f7c792910%27%20or%20templateId%20eq%20%275340aa10-47a8-4e67-893f-690984e4d5da%27" -HttpMethod GET
    $profiles = $json.value
    $profileNameExist = $true
    $profileName = Read-Host -Prompt $Strings.EnterProfile
    while(-not($profileName))
    {
        $profileName = Read-Host -Prompt $Strings.ProfileCannotBeBlank
    }  
    while($profileNameExist)
    {
        foreach($display in $profiles)
        {
            $name = $display.displayName.Split("-")
            $profileNameExist = $false
            if($name[0] -eq $profileName)
            {
                $profileNameExist = $true
                $profileName = Read-Host -Prompt $Strings.ProfileExists
                while(-not($profileName))
                {
                    $profileName = Read-Host -Prompt $Strings.ProfileCannotBeBlank 
                }        
                break
            }
        }
    }
    $EnabledOnly = $true
    if($includeDisabledRules)
    {
        $EnabledOnly = $false
    }

    if($includeLocalRules)
    {
        Export-NetFirewallRule -ProfileName $profileName  -CheckProfileName $false -EnabledOnly:$EnabledOnly -PolicyStoreSource "All"
    }
    else
    {
        Export-NetFirewallRule -ProfileName $profileName -CheckProfileName $false -EnabledOnly:$EnabledOnly
    }
    
}
catch{
    $errorMessage = $_.ToString()
    Write-Host -ForegroundColor Red $errorMessage
    Write-Host "No commands completed"
}

    
                           