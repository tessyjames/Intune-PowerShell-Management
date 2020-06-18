<#
.Synopsis
  IntunePolicyAnalyticsClient - Implementation of Group Policy Object import into Intune.
.DESCRIPTION
   Implementation of Group Policy Object import into Intune.
#>

#region Cmdlets
Function Get-GPOMigrationReportCollection
{
<#
.Synopsis
   Get-GPOMigrationReportCollection Generates Migration reports from previously updated Group Policy Objects
.DESCRIPTION
   Gets Migration report for previously uploaded GPOs from Intune.
.PARAMETER TenantAdminUPN
    AAD User Principal Name of the Intune Tenant Administrator which is required to upload the GPOs.
.PARAMETER ExpandSettings
    Switch if set, expands the SettingsMap
.OUTPUT
    GPO Migration Report based on the previously updated Group Policy Objects
.EXAMPLE
    Get-GPOMigrationReportCollection -TenantAdminUPN "admin@IPASHAMSUA01MSIT.onmicrosoft.com"
        Gets the MigrationReports from Intune
#>
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TenantAdminUPN,
        [Switch]$ExpandSettings = $false
    )

    Try
    {
        # Initialize Module
        $IPAClientConfiguration = Initialize-IPAClientConfiguration -TenantAdminUPN $TenantAdminUPN

        # Fetch the migration report
        $sw = [Diagnostics.Stopwatch]::StartNew()

        # Initialize Module
        $IPAClientConfiguration = Initialize-IPAClientConfiguration -TenantAdminUPN  $TenantAdminUPN

        # Make the Graph call to fetch the GroupPolicyMigrationReport collection
        $collectionUri = ""
        $nextUrl = $null

        # Iterate through nextlinks to get the complete set of reports
        Do
        {
            $result = Get-IntuneEntityCollection -CollectionPath $collectionUri `
                                     -Uri $nextUrl `
                                     -GraphConfiguration $script:GraphConfiguration
            $migrationReportCollection += $result.Value
            $nextUrl = $result.'@odata.nextLink'            
        }
        While ($nextUrl)

        Write-Log -Message "Get-GPOMigrationReportCollection Found $($migrationReportCollection.Count) MigrationReports.."

        # Instantiate a new collection for the GPO Migration Reports to be fetched from Intune
        $GPOMigrationReportCollection = @{}

        # Populate the groupPolicyMigrationReports collection
        ForEach ($migrationReport in $migrationReportCollection)
        {
            Try
            {
                # Get the groupPolicySettingMappings for each migrationReport
                $groupPolicyObjectId = $migrationReport.groupPolicyObjectId
                $ou = [System.Web.HTTPUtility]::UrlDecode($migrationReport.ouDistinguishedName)

                If ($ExpandSettings)
                {
                    $collectionUri = "('$($groupPolicyObjectId)_$($ou)')?`$expand=groupPolicySettingMappings"
                    Write-Log -Message "Get-GPOMigrationReportCollection: collectionUri=$($collectionUri)"

                    $groupPolicySettingMappingCollection = Get-IntuneEntityCollection -CollectionPath $collectionUri `
                                                                          -Uri $null `
                                                                          -GraphConfiguration $script:GraphConfiguration
                }
                Else
                {
                    $groupPolicySettingMappingCollection = $null
                }

                If ($null -eq $groupPolicySettingMappingCollection)
                {
                    $GPOMigrationReportCollection.Add("$($groupPolicyObjectId)_$($ou)", [PSCustomObject]@{MigrationReport = $migrationReport; `
                                                                                SettingMappings = $null})
                }
                Else
                {
                    $GPOMigrationReportCollection.Add("$($groupPolicyObjectId)_$($ou)", [PSCustomObject]@{MigrationReport = $migrationReport; `
                                                                                SettingMappings = ($groupPolicySettingMappingCollection.groupPolicySettingMappings)})
                }
            }
            Catch
            {
                $exception  = $_
                Write-Log -Message "Get-GPOMigrationReportCollection: Failure: $($exception)" -Level "Warn"
            }
        }
    }
    Catch
    {
        $exception  = $_
        Write-Log -Message "Get-GPOMigrationReportCollection: Failure: $($exception)" -Level "Error"
        Write-Log -Message "Get-GPOMigrationReportCollection: IPAGlobalSettingBag: $($IPAClientConfiguration)"
        Write-Log -Message "Get-GPOMigrationReportCollection: graphConfiguration: $($graphConfiguration)"
        throw
    }
    Finally
    {
        $IPAClientConfiguration | ConvertTo-Json | Out-File -FilePath "$($IPAClientConfiguration.ConfigurationFolderPath)\IPAGlobalSettingBag.json"
        $GPOMigrationReportCollection | ConvertTo-Json | Out-File -FilePath "$($IPAClientConfiguration.StatePath)\GroupPolicyMigrationReportCollection.json"
        $sw.Stop()
        Write-Log -Message "Get-GPOMigrationReportCollection: Elapsed time = $($sw.Elapsed.ToString())"
    }

    Write-Log -Message "Get-GPOMigrationReportCollection: GPOMigrationReports returned=$($GPOMigrationReportCollection.Count)"
    return $GPOMigrationReportCollection
}

Function Get-MigrationReadinessReport
{
<#
.Synopsis
   Get-MigrationReadinessReport Gets the Migration Readiness Report for previously uploaded GPOs.
.DESCRIPTION
   Gets the Migration Readiness Report for previously uploaded GPOs.
.PARAMETER TenantAdminUPN
    AAD User Principal Name of the Intune Tenant Administrator which is required to upload the GPOs.
.EXAMPLE
     Get-MigrationReadinessReport -TenantAdminUPN "admin@IPASHAMSUA01MSIT.onmicrosoft.com"
       Gets the Migration Readiness Report for previously uploaded GPOs.
#>
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TenantAdminUPN
    )

    Try
    {
        # Initialize Module
        $IPAClientConfiguration = Initialize-IPAClientConfiguration -TenantAdminUPN $TenantAdminUPN

        # Fetch the migration report
        $sw = [Diagnostics.Stopwatch]::StartNew()

        # Headers for the Graph call
        $clonedHeaders = CloneObject (Get-AuthHeader $graphConfiguration);
        $clonedHeaders["api-version"] = "$($script:ApiVersion)";        

        <#
            1. Ask to create the report
            Post https://graph.microsoft-ppe.com/testppebeta_intune_onedf/deviceManagement/reports/cachedReportConfigurations
            Payload: {"id":"GPAnalyticsMigrationReadiness_00000000-0000-0000-0000-000000000001","filter":"","orderBy":[],"select":["SettingName","MigrationReadiness","OSVersion","Scope","ProfileType","SettingCategory"],"metadata":""}
        #>
        $uri = "$($script:GraphConfiguration.GraphBaseAddress)/$($script:GraphConfiguration.SchemaVersion)/deviceManagement/reports/cachedReportConfigurations";        
        $Body = "{            
            `"id`":`"GPAnalyticsMigrationReadiness_00000000-0000-0000-0000-000000000001`",
            `"filter`": `"`",`
            `"select`": [`
            `"SettingName`",`"MigrationReadiness`",`"OSVersion`",`"Scope`",`"ProfileType`",`"SettingCategory`"
            ],`
            `"orderBy`": [`
                `"SettingCategory`"
            ]`
          }"
        $clonedHeaders["content-length"] = $Body.Length;

        Try
        {        
            Write-Log -Message "Get-MigrationReadinessReport: Creating MigrationReadiness Report..."           
            $response = Invoke-RestMethod $uri -Method Post -Headers $clonedHeaders -Body $body;
        }
        Catch
        {
            $exception  = $_
            Write-Log -Message "Get-MigrationReadinessReport: Invoke-RestMethod $uri -Method Post. Size=$($Body.Length). Failure: $($exception)" -Level "Warn"
            throw
        }
            
        <#    
            2. Query, over and over, until the report is complete (you will see 'completed' in the response
            get: https://graph.microsoft-ppe.com/testppebeta_intune_onedf/deviceManagement/reports/cachedReportConfigurations('GPAnalyticsMigrationReadiness_00000000-0000-0000-0000-000000000001')            
        #>
        $uri = "$($script:GraphConfiguration.GraphBaseAddress)/$($script:GraphConfiguration.SchemaVersion)/deviceManagement/reports/cachedReportConfigurations(`'GPAnalyticsMigrationReadiness_00000000-0000-0000-0000-000000000001`')"
        Try
        {
            $Counter = 0
            Write-Log -Message "Get-MigrationReadinessReport: Getting MigrationReadinessReport..."       
            Do
            {                
                $response = (Invoke-RestMethod $uri -Method Get -Headers $clonedHeaders)
                $Counter++
                Write-Log -Message "Get-MigrationReadinessReport: Report creation Status: $($response.Status),  Attempt: $($Counter)"
                Start-Sleep -Seconds 1
            } While (($response.Status -contains "inProgress") -and ($Counter -lt 100))
        }
        Catch
        {
            $exception  = $_
            Write-Log -Message "Get-MigrationReadinessReport: Invoke-RestMethod $uri -Method Get. Failure: $($exception)" -Level "Warn"
            throw
        }

        <#
            3. Get the actual report: (you may want to increase 'top')
            Post: https://graph.microsoft-ppe.com/testppebeta_intune_onedf/deviceManagement/reports/getCachedReport
            Payload: {"Id":"GPAnalyticsMigrationReadiness_00000000-0000-0000-0000-000000000001","Skip":0,"Top":50,"Search":"","OrderBy":[],"Select":["SettingName","MigrationReadiness","OSVersion","Scope","ProfileType","SettingCategory"]}
        #>
        $uri = "$($script:GraphConfiguration.GraphBaseAddress)/$($script:GraphConfiguration.SchemaVersion)/deviceManagement/reports/getCachedReport";        
        $Body = "{            
            `"id`":`"GPAnalyticsMigrationReadiness_00000000-0000-0000-0000-000000000001`",
            `"skip`": `"0`",`
            `"Search`": `"`",`
            `"select`": [`
            `"SettingName`",`"MigrationReadiness`",`"OSVersion`",`"Scope`",`"ProfileType`",`"SettingCategory`"
            ],`
            `"orderBy`": [`
                `"SettingCategory`"`
            ]`
          }"
        $clonedHeaders["content-length"] = $Body.Length;

        Try
        {
            Write-Log -Message "Get-MigrationReadinessReport: Get the created report..."                       
            $response = Invoke-RestMethod $uri -Method Post -Headers $clonedHeaders -Body $body;

            Write-Log -Message "Get-MigrationReadinessReport: $($response.TotalRowCount) records found."
            Write-Log -Message "Get-MigrationReadinessReport: $($response.Values.Count) records downloaded."
        }
        Catch
        {
            $exception  = $_
            Write-Log -Message "Get-MigrationReadinessReport: Invoke-RestMethod $uri -Method Post. Size=$($Body.Length). Failure: $($exception)" -Level "Warn"
            throw
        }     
    }
    Catch
    {
        $exception  = $_
        Write-Log -Message "Get-MigrationReadinessReport: Failure: $($exception)" -Level "Error"
        Write-Log -Message "Get-MigrationReadinessReport: IPAGlobalSettingBag: $($IPAClientConfiguration)"
        Write-Log -Message "Get-MigrationReadinessReport: graphConfiguration: $($graphConfiguration)"
        throw
    }
    Finally
    {
        $IPAClientConfiguration | ConvertTo-Json | Out-File -FilePath "$($IPAClientConfiguration.ConfigurationFolderPath)\IPAGlobalSettingBag.json"
        $GPOMigrationReportCollection | ConvertTo-Json | Out-File -FilePath "$($IPAClientConfiguration.StatePath)\GroupPolicyMigrationReportCollection.json"
        $sw.Stop()
        Write-Log -Message "Get-MigrationReadinessReport Elapsed time = $($sw.Elapsed.ToString())"
    }
    
    return  $response
}

Function Update-MigrationReadinessReport
{
<#
.Synopsis
   Update-MigrationReadinessReport Updates the Migration Readiness Report for previously uploaded GPOs.
.DESCRIPTION
   Updates the Migration Readiness Report for previously uploaded GPOs.
.PARAMETER TenantAdminUPN
    AAD User Principal Name of the Intune Tenant Administrator which is required to upload the GPOs.
.EXAMPLE
     Update-MigrationReadinessReport -TenantAdminUPN "admin@IPASHAMSUA01MSIT.onmicrosoft.com"
       Updates the Migration Readiness Report for previously uploaded GPOs.
#>
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TenantAdminUPN
    )

    Try
    {
        # Initialize Module
        $IPAClientConfiguration = Initialize-IPAClientConfiguration -TenantAdminUPN $TenantAdminUPN

        # Fetch the migration report
        $sw = [Diagnostics.Stopwatch]::StartNew()

        # Make the Graph call to fetch the GroupPolicyMigrationReport collection        
        $nextUrl = "$($script:GraphConfiguration.GraphBaseAddress)/$($script:GraphConfiguration.SchemaVersion)/deviceManagement/GroupPolicyObjectFiles"

        # Iterate through nextlinks to get the complete set of reports
        Do
        {
            $result = Get-IntuneEntityCollection -Uri $nextUrl `
                                     -GraphConfiguration $script:GraphConfiguration `
                                     -CollectionPath ""
            $GroupPolicyObjectFileCollection += $result.Value       
            $nextUrl = $result.'@odata.nextLink'            
        }
        While ($nextUrl)

        Write-Log -Message "Update-MigrationReadinessReport: Found $($GroupPolicyObjectFileCollection.Count) GPO files.."
        
        # Upload GroupPolicyObjectFile back to Intune
        ForEach ($GroupPolicyObjectFile in $GroupPolicyObjectFileCollection)
        {                     
            $ouDistinguishedName = [System.Web.HTTPUtility]::UrlDecode($GroupPolicyObjectFile.ouDistinguishedName)
            $content = $GroupPolicyObjectFile.content
            $GroupPolicyObjectFileToUpload = [PSCustomObject]@{groupPolicyObjectFile = ([PSCustomObject]@{ouDistinguishedName = $ouDistinguishedName; content = $content})}               
            
            # Upload GroupPolicyObjectFile to Intune
            Try
            {
                Write-Log "Update-MigrationReadinessReport: Updating $($GroupPolicyObjectFile.id)..." 
                $MigrationReportCreated = Add-IntuneEntityCollection "createMigrationReport" ($GroupPolicyObjectFileToUpload |ConvertTo-Json) $script:GraphConfiguration
                Write-Log "Update-MigrationReadinessReport: $($MigrationReportCreated.Value) updated."                                
            }
            Catch
            {
                $exception  = $_
                Write-Log -Message "Update-MigrationReadinessReport: Failure: $($exception)"
            }            
        }
    }
    Catch
    {
        $exception  = $_
        Write-Log -Message "Update-MigrationReadinessReport: Failure: $($exception)" -Level "Error"
        Write-Log -Message "Update-MigrationReadinessReport: IPAGlobalSettingBag: $($IPAClientConfiguration)"
        Write-Log -Message "Update-MigrationReadinessReport: graphConfiguration: $($graphConfiguration)"
        throw
    }
    Finally
    {
        $IPAClientConfiguration | ConvertTo-Json | Out-File -FilePath "$($IPAClientConfiguration.ConfigurationFolderPath)\IPAGlobalSettingBag.json"
        $GPOMigrationReportCollection | ConvertTo-Json | Out-File -FilePath "$($IPAClientConfiguration.StatePath)\GroupPolicyMigrationReportCollection.json"
        $sw.Stop()
        Write-Log -Message "Update-MigrationReadinessReport Elapsed time = $($sw.Elapsed.ToString())"
    }
}

Function Import-GPOCollection
{
<#
.Synopsis
    Import-GPOCollection Gets all the Group Policy Object collection for a given domain, uploads it to Intune and determines what settings are supported.
.DESCRIPTION
    IntunePolicyAnalyticsClient uses the Group Policy cmdlets to get all the Group Policy Objects
    for a given domain, uploads it to Intune and determines what settings are supported.
.PARAMETER Domain
    The local AD Domain for which the GPO collection is fetched.
    Defaults to the local AD Domain for the client on which this script is run on.
.PARAMETER TenantAdminUPN
    AAD User Principal Name of the Intune Tenant Administrator which is required to upload the GPOs.
.PARAMETER OUFilter
    Use OUFilter to constrain the GP Objects to the OU in consideration.
    Specifies a query string that retrieves Active Directory objects. This string uses the PowerShell Expression Language syntax. The PowerShell Expression Language syntax provides rich type-conversion support for value types received by the OUFilter parameter. The syntax uses an in-order representation, which means that the operator is placed between the operand and the value. For more information about the OUFilter parameter, type Get-Help about_ActiveDirectory_Filter.
    Syntax:
        The following syntax uses Backus-Naur form to show how to use the PowerShell Expression Language for this parameter.
        <OUFilter> ::= "{" <FilterComponentList> "}"
        <FilterComponentList> ::= <FilterComponent> | <FilterComponent> <JoinOperator> <FilterComponent> | <NotOperator> <FilterComponent>
        <FilterComponent> ::= <attr> <FilterOperator> <value> | "(" <FilterComponent> ")"
        <FilterOperator> ::= "-eq" | "-le" | "-ge" | "-ne" | "-lt" | "-gt"| "-approx" | "-bor" | "-band" | "-recursivematch" | "-like" | "-notlike"
        <JoinOperator> ::= "-and" | "-or"
        <NotOperator> ::= "-not"
        <attr> ::= <PropertyName> | <LDAPDisplayName of the attribute>
        <value>::= <compare this value with an <attr> by using the specified <FilterOperator>>
        For a list of supported types for <value>, type Get-Help about_ActiveDirectory_ObjectModel.
.OUTPUT
    GPO Collection collected from the local AD domain and sent to Intune
.EXAMPLE
    Import-GPOCollection -Domain "redmond.corp.microsoft.com" -TenantAdminUPN "admin@IPASHAMSUA01MSIT.onmicrosoft.com"
        Gets all the GPOs in the domain "redmond.corp.microsoft.com" and back them up on disk.
.EXAMPLE
    Import-GPOCollection -Domain "redmond.corp.microsoft.com" -OUFilter 'DistinguishedName -like "OU=CoreIdentity,OU=ITServices,DC=redmond,DC=corp,DC=microsoft,DC=com"' -TenantAdminUPN "admin@IPASHAMSUA01MSIT.onmicrosoft.com"
        Gets all the GPOs in a specific OU for the given domain, back them up on disk and upload to Intune.
#>
    [cmdletbinding()]
    param(
        [Alias("Domain")]
        [Parameter(Mandatory=$true)]
        [String]$ADDomain,
        [Parameter(Mandatory=$true)]
        [string]$TenantAdminUPN,
        [String]$OUFilter = 'Name -like "*"'
    )

    Try
    {
        # Start timer
        $sw = [Diagnostics.Stopwatch]::StartNew()

        # Initialize Module
        $IPAClientConfiguration = Initialize-IPAClientConfiguration -TenantAdminUPN $TenantAdminUPN

        # Fetch GPO Xml Reports from local AD Domain
        $gpoReportXmlCollection = @{}
        Try
        {
            Write-Log -Message "Import-GPOCollection: Get GPO backups from ADDomain=$($ADDomain) with OUFilter=$($OUFilter)..."
            $gpoReportXmlCollection = Get-GPOReportXmlCollectionFromAD -ADDomain $($ADDomain) -OUFilter $($OUFilter)
        }
        Catch
        {
            $exception  = $_

            # For non-domain joined loadgens
            Switch ($exception)
            {
                'Unable to contact the server. This may be because this server does not exist, it is currently down, or it does not have the Active Directory Web Services running.'
                {
                    If (($IPAClientConfiguration.Environment -ne "pe") -and (Test-Path -Path "$($IPAClientConfiguration.StatePath)\GPOReportXmlCollection.json"))
                    {
                        (Get-Content -Path "$($IPAClientConfiguration.StatePath)\GPOReportXmlCollection.json" `
                            | ConvertFrom-JSon).psobject.properties | ForEach-Object { $gpoReportXmlCollection[$_.Name] = $_.Value }
                        Write-Log -Message "Import-GPOCollection: Read GPOReportXmlCollection from: $($IPAClientConfiguration.StatePath)\GPOReportXmlCollection.json"
                    }
                    Else
                    {
                        Write-Log -Message "Import-GPOCollection:: Get-GPOReportXmlCollectionFromAD -ADDomain $($ADDomain) -OUFilter $($OUFilter) failed. Failure: $($exception)" -Level "Error"
                        throw
                    }
                }
            }
        }

        # Upload GPOs to Intune
        If ($null -ne $gpoReportXmlCollection)
        {
            Write-Log -Message "Import-GPOCollection: Number of GPOs to upload to Intune=$($gpoReportXmlCollection.Count)"
            $gpoReportXmlCollection.GetEnumerator() | ForEach-Object `
            {
                Try
                {
                    $key = $_.key

                    # Create GroupPolicyObjectFile entity in memory
                    $GroupPolicyObjectFile = [PSCustomObject]@{groupPolicyObjectFile = $_.value}

                    # Upload GroupPolicyObjectFile to Intune
                    $MigrationReportCreated = Add-IntuneEntityCollection "createMigrationReport" ($GroupPolicyObjectFile |ConvertTo-Json) $script:GraphConfiguration
                    Write-Log -Message "Import-GPOCollection: $($MigrationReportCreated.value) uploaded to Intune"
                }
                Catch
                {
                    $exception  = $_
                    Write-Log -Message "Add-IntuneEntityCollection "createMigrationReport" for id: $($key) failed. Failure: $($exception)"
                }
            }
        }
    }
    catch
    {
        # Log error
        $exception  = $_
        Write-Log -Message "Import-GPOCollection: Failure: $($exception)" -Level "Error"
        Write-Log -Message "Import-GPOCollection: IPAGlobalSettingBag: $($IPAClientConfiguration)"
        throw
    }
    Finally
    {
        # Save Configuration Bag
        $IPAClientConfiguration | ConvertTo-Json | Out-File -FilePath "$($IPAClientConfiguration.ConfigurationFolderPath)\IPAGlobalSettingBag.json"

        If (($IPAClientConfiguration.Environment -ne "pe") -and `
            !(Test-Path "$($IPAClientConfiguration.StatePath)\GPOReportXmlCollection.json"))
        {
            # Save GPOReportXmlCollection for non-PE environments
            $gpoReportXmlCollection | ConvertTo-Json -Depth 10 | Set-Content -Path "$($IPAClientConfiguration.StatePath)\GPOReportXmlCollection.json"
        }

        $sw.Stop()
        Write-Log -Message "Import-GPOCollection: Elapsed time: $($sw.Elapsed.ToString())"
    }

    return $gpoReportXmlCollection
}

# Global Configuration settings
$script:IPAClientConfiguration = $null
$script:GraphConfiguration = $null

Function Initialize-IPAClientConfiguration
{
<#
.Synopsis
  Initialize-IPAClientConfiguration - Initializes the Global settings for Intune Policy Analytics Client
.DESCRIPTION
   Initializes the Global settings for Intune Policy Analytics Client
.PARAMETER TenantAdminUPN
    AAD User Principal Name of the Intune Tenant Administrator which is required to upload the GPOs.
.PARAMETER Environment
    Type of Intune environment. Supported values:
        local
        dogfood
        selfhost
        ctip
        pe
.PARAMETER DeltaUpdate
    If set, checks if GPO already uploaded to Intune
#>
    param
    (
        [Parameter(Mandatory=$true)]
        $TenantAdminUPN,
        [Parameter(Mandatory=$false)]
        [String]$Environment = "dogfood",
        [Parameter(Mandatory=$false)]
        [Switch]$DeltaUpdate = $false
    )

    If ($null -eq $script:IPAClientConfiguration)
    {
        $GpoBackupDateTime = Get-Date -UFormat "%Y.%m.%d.%H%M"
        $IPAWorkingFolderPath = "$($env:APPDATA)\IPA"
        $LogFolderPath = "$($IPAWorkingFolderPath)\Logs"
        $script:IPAClientConfiguration = @(
            [PSCustomObject]@{`
                ConfigurationFolderPath = "$($IPAWorkingFolderPath)\Configuration"; `
                Environment = "$($Environment)"; `
                GpoBackupFolderPath = "$($IPAWorkingFolderPath)\GPO\GPOBackup"; `
                LogFilePath = "$($LogFolderPath)\IPAClient.$($TenantAdminUPN).$($Environment).$($GpoBackupDateTime).log"; `
                StatePath = "$($IPAWorkingFolderPath)\State"; `
                TenantAdminUPN = "$($TenantAdminUPN)"; `
                DeltaUpdate = "$($DeltaUpdate)"
            }
        )

        # Initialize logging
        If(!(Test-Path -Path "$($LogFolderPath)" ))
        {
            (New-Item -ItemType directory -Path $LogFolderPath) | Out-Null
        }

        If(!(Test-Path -Path "$($script:IPAClientConfiguration.LogFilePath)"))
        {
            (New-Item -Path $script:IPAClientConfiguration.LogFilePath -Force -ItemType File) | Out-Null
            Write-Log -Message "Initializing IPAClient"
        }

        # Create Configuration Folder path if necessary
        If(!(Test-Path -Path "$($script:IPAClientConfiguration.ConfigurationFolderPath)" ))
        {
            (New-Item -ItemType directory -Path $script:IPAClientConfiguration.ConfigurationFolderPath) | Out-Null
        }

        # Create State Folder path if necessary
        If(!(Test-Path -Path "$($script:IPAClientConfiguration.StatePath)" ))
        {
            (New-Item -ItemType directory -Path $script:IPAClientConfiguration.StatePath) | Out-Null
        }

        # Import pre-requisite modules
        Import-PreRequisiteModuleList

        # Initialize Graph
        $script:GraphConfiguration = Initialize-GraphConfiguration -Environment $Environment -TenantAdminUPN $TenantAdminUPN

        # Connect to Intune
        Connect-Intune $script:GraphConfiguration
    }

    return $script:IPAClientConfiguration
}

Function Remove-GPOMigrationReportCollection
{
<#
.Synopsis
   Remove-GPOMigrationReportCollection Removes Migration Report Collection from Intune
.DESCRIPTION
   Removes Migration reports for previously updated GPOs from Intune.
.PARAMETER TenantAdminUPN
    AAD User Principal Name of the Intune Tenant Administrator which is required to upload the GPOs.
.EXAMPLE
    Remove-GPOMigrationReportCollection -TenantAdminUPN "admin@IPASHAMSUA01MSIT.onmicrosoft.com"
        Removes the MigrationReports from Intune
#>
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TenantAdminUPN
    )

    Try
    {
        # Initialize Module
        $IPAClientConfiguration = Initialize-IPAClientConfiguration -TenantAdminUPN $TenantAdminUPN

        # Fetch the migration report
        $sw = [Diagnostics.Stopwatch]::StartNew()

        # Initialize Module
        $IPAClientConfiguration = Initialize-IPAClientConfiguration -TenantAdminUPN  $TenantAdminUPN

        # Make the Graph call to fetch the GroupPolicyMigrationReport collection
        $collectionUri = ""
        $nextUrl = $null

        # Iterate through nextlinks to get the complete set of reports
        Do
        {
            $result = Get-IntuneEntityCollection -CollectionPath $collectionUri `
                                     -Uri $nextUrl `
                                     -GraphConfiguration $script:GraphConfiguration
            $migrationReportCollection += $result.Value
            $nextUrl = $result.'@odata.nextLink'
        }
        While ($nextUrl)

        Write-Log -Message "Remove-GPOMigrationReportCollection: Found $($migrationReportCollection.Count) MigrationReports to delete.."

        # Populate the groupPolicyMigrationReports collection
        ForEach ($migrationReport in $migrationReportCollection)
        {
            Try
            {
                # Get the groupPolicySettingMappings for each migrationReport
                $groupPolicyObjectId = $migrationReport.groupPolicyObjectId
                $ou = [System.Web.HTTPUtility]::UrlDecode($migrationReport.ouDistinguishedName)
                $collectionUri = "('$($groupPolicyObjectId)_$($ou)')"
                Write-Log -Message "Remove-GPOMigrationReportCollection: collectionUri=$($collectionUri)"
                (Remove-IntuneEntityCollection -CollectionPath $collectionUri -Uri $null -GraphConfiguration $script:GraphConfiguration) | Out-Null
            }
            Catch
            {
                $exception  = $_
                Write-Log -Message "Remove-GPOMigrationReportCollection: Failure: $($exception)" -Level "Warn"
            }
        }
    }
    Catch
    {
        $exception  = $_
        Write-Log -Message "Remove-GPOMigrationReportCollection: Failure: $($exception)" -Level "Error"
        Write-Log -Message "Remove-GPOMigrationReportCollection: IPAGlobalSettingBag: $($IPAClientConfiguration)"
        Write-Log -Message "Remove-GPOMigrationReportCollection: graphConfiguration: $($graphConfiguration)"
        throw
    }
    Finally
    {
        $IPAClientConfiguration | ConvertTo-Json | Out-File -FilePath "$($IPAClientConfiguration.ConfigurationFolderPath)\IPAGlobalSettingBag.json"
        $sw.Stop()
        Write-Log -Message "Remove-GPOMigrationReportCollection: Elapsed time = $($sw.Elapsed.ToString())"
    }
}

Export-ModuleMember -Function Get-GPOMigrationReportCollection
Export-ModuleMember -Function Get-MigrationReadinessReport
Export-ModuleMember -Function Update-MigrationReadinessReport
Export-ModuleMember -Function Import-GPOCollection
Export-ModuleMember -Function Initialize-IPAClientConfiguration
Export-ModuleMember -Function Remove-GPOMigrationReportCollection
#endregion Cmdlets

#region Configuration Utilities
<#
.Synopsis
  Import-PreRequisiteModuleList - Checks if RSAT is installed or not. If not, prompts user to install.
.DESCRIPTION
   Checks if RSAT is installed or not. If not, prompts user to install.
#>
Function Import-PreRequisiteModuleList
{
    Try
    {
        If (!(Get-module -ListAvailable -Name GroupPolicy))
        {
            $ShouldInstallRSATModule = "Y"
            $ShouldInstallRSATModule = Read-Host -Prompt "RSAT Module not installed. Install it? Y/N Default:[$($ShouldInstallRSATModule)]"

            # Install RSAT only if consented
            If ($ShouldInstallRSATModule -eq "Y")
            {
                # Check for Windows10
                $osVersion =[System.Environment]::OSVersion.Version
                If ($osVersion.Major -ge 10)
                {
                    $RSATx86 = 'https://download.microsoft.com/download/1/D/8/1D8B5022-5477-4B9A-8104-6A71FF9D98AB/WindowsTH-RSAT_WS2016-x86.msu'
                    $RSATx64 = 'https://download.microsoft.com/download/1/D/8/1D8B5022-5477-4B9A-8104-6A71FF9D98AB/WindowsTH-RSAT_WS2016-x64.msu'

                    switch ($env:PROCESSOR_ARCHITECTURE)
                    {
                        'x86' {$RSATDownloadUri = $RSATx86}
                        'AMD64' {$RSATDownloadUri = $RSATx64}
                    }

                    $RSATKBDownloadFileName = $RSATDownloadUri.Split('/')[-1]

                    Write-Log -Message "Downloading RSAT from $($RSATDownloadUri) to $($RSATKBDownloadFileName)"
                    Invoke-WebRequest -Uri $RSATDownloadUri -UseBasicParsing -OutFile "$env:TEMP\$RSATKBDownloadFileName"

                    Write-Log -Message "Start-Process -FilePath wusa.exe -ArgumentList $env:TEMP\$($RSATKBDownloadFileName) /quiet /promptrestart /log"
                    Start-Process -FilePath wusa.exe -ArgumentList "$env:TEMP\$($RSATKBDownloadFileName) /quiet /promptrestart /log" -Wait -Verbose
                }
                Else
                {
                    Write-Log -Message "RSAT install is supported only on Windows 10 and above" -Level "Error"
                    throw
                }
            }
        }

        Import-Module ActiveDirectory
        Import-Module GroupPolicy
    }
    Catch
    {
        $exception  = $_
        Write-Log -Message "Import-PreRequisiteModuleList failed. Failure: $($exception)" -Level "Error"
        throw
    }
}
#endregion

#region Logging Utilities
function Write-Log
{
    Param
    (
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        [Parameter(Mandatory=$false)]
        [string]$Level="Info",
        [Parameter(Mandatory=$false)]
        [string]$LogPath = "$($script:IPAClientConfiguration.LogFilePath)"
    )

    # Format Date for our Log File
    $currentDateTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Write message to error, warning, or verbose pipeline and specify $LevelText
    switch ($Level)
    {
        'Error'
        {
            $logLine = "[$($currentDateTime)] ERROR: $($Message)"
            Write-Error $logLine
        }       
        Default
        {
            $logLine = "[$($currentDateTime)] INFO: $($Message)"
            Write-Progress -Activity "IntunePolicyAnalytics" -PercentComplete -1 -Status $logLine
        }
    }

    # Write log entry to $Path
    $logLine | Out-File -FilePath $LogPath -Append
}
#endregion

#region Graph Utilities
function Initialize-GraphConfiguration
{
<#
.Synopsis
    Put-GraphConfiguration: Initializes the Graph settings
.PARAMETER Environment
    Type of Intune environment. Supported values:
        local
        dogfood
        selfhost
        ctip
        pe
.PARAMETER TenantUPN
    UPN of the Intune Tenant Admin
#>
    param
    (
        [Parameter(Mandatory=$true)]
        [String]$Environment,
        [Parameter(Mandatory=$true)]
        $TenantAdminUPN
    )

    # Graph AuthHeader primitives
    $userUpn = New-Object "System.Net.Mail.MailAddress" -ArgumentList $TenantAdminUPN
    $tenant = $userUpn.Host

    # App IDs to use
    $IntunePowerShellclientId = "d1ddf0e4-d672-4dae-b554-9d5bdfd93547" # Official PowerShell App
    $IntunePolicyAnalyticsClientId = "a1357584-810b-42e6-a9e6-4e7237ccbcea" # PPE IPA PowerShell App

    # RedirectUri to use
    $IntunePowerShellRedirectUri = "urn:ietf:wg:oauth:2.0:oob"
    $IntunePolicyAnalyticsRedirectUri = "https://login.microsoftonline.com/common/oauth2/nativeclient"

    # Graph configuration settings per environment
    $GraphConfiguration = @(       
        [PSCustomObject]@{Environment = "dogfood"; `
            AuthUrl = "https://login.windows-ppe.net/$($tenant)"; `
            ResourceId = "https://graph.microsoft-ppe.com"; `
            GraphBaseAddress = "https://graph.microsoft-ppe.com"; `
            IPARoute = "deviceManagement/groupPolicyMigrationReports"; `
            AppId = "$($IntunePolicyAnalyticsClientId)"; `
            RedirectLink = "$($IntunePolicyAnalyticsRedirectUri)"; `
            SchemaVersion = "testppebeta_intune_onedf"; `
            TenantAdminUPN = "$($TenantAdminUPN)";
            AuthHeader = $null;
            platformParameters = $null;
            userId = $null;
            authContext = $null}
        [PSCustomObject]@{Environment = "selfhost"; `
            AuthUrl = "https://login.microsoftonline.com/$($tenant)"; `
            ResourceId = "https://canary.graph.microsoft.com"; `
            GraphBaseAddress = "https://canary.graph.microsoft.com"; `
            IPARoute = "deviceManagement/groupPolicyMigrationReports"; `
            AppId = "$($IntunePowerShellclientId)"; `
            RedirectLink = "$($IntunePowerShellRedirectUri)"; `
            SchemaVersion = "testprodbeta_intune_sh"; `
            TenantAdminUPN = "$($TenantAdminUPN)";
            AuthHeader = $null;
            platformParameters = $null;
            userId = $null;
            authContext = $null}
        [PSCustomObject]@{Environment = "ctip"; `
            AuthUrl = "https://login.microsoftonline.com/$($tenant)"; `
            ResourceId = "https://canary.graph.microsoft.com"; `
            GraphBaseAddress = "https://canary.graph.microsoft.com"; `
            IPARoute = "deviceManagement/groupPolicyMigrationReports"; `
            AppId = "$($IntunePowerShellclientId)"; `
            RedirectLink = "$($IntunePowerShellRedirectUri)"; `
            SchemaVersion = "testprodbeta_intune_ctip"; `
            TenantAdminUPN = "$($TenantAdminUPN)";
            AuthHeader = $null;
            platformParameters = $null;
            userId = $null;
            authContext = $null}
        [PSCustomObject]@{Environment = "pe_canary"; `
            AuthUrl = "https://login.microsoftonline.com/$($tenant)"; `
            ResourceId = "https://canary.graph.microsoft.com"; `
            GraphBaseAddress = "https://canary.graph.microsoft.com"; `
            IPARoute = "deviceManagement/groupPolicyMigrationReports"; `
            AppId = "$($IntunePowerShellclientId)"; `
            RedirectLink = "$($IntunePowerShellRedirectUri)"; `
            SchemaVersion = "testprodbeta_intune_ctip"; `
            TenantAdminUPN = "$($TenantAdminUPN)";
            AuthHeader = $null;
            platformParameters = $null;
            userId = $null;
            authContext = $null}
        [PSCustomObject]@{Environment = "pe"; `
            AuthUrl = "https://login.microsoftonline.com/$($tenant)"; `
            ResourceId = "https://graph.microsoft.com"; `
            GraphBaseAddress = "https://graph.microsoft.com"; `
            IPARoute = "deviceManagement/groupPolicyMigrationReports"; `
            AppId = "$($IntunePowerShellclientId)"; `
            RedirectLink = "$($IntunePowerShellRedirectUri)"; `
            SchemaVersion = "stagingbeta"; `
            TenantAdminUPN = "$($TenantAdminUPN)";
            AuthHeader = $null;
            platformParameters = $null;
            userId = $null;
            authContext = $null}
        [PSCustomObject]@{Environment = "pe_fxp"; `
            AuthUrl = "https://login.microsoftonline.us/$($tenant)"; `
            ResourceId = "https://graph.microsoft.us"; `
            GraphBaseAddress = "https://graph.microsoft.us"; `
            IPARoute = "deviceManagement/groupPolicyMigrationReports"; `
            AppId = "$($IntunePowerShellclientId)"; `
            RedirectLink = "$($IntunePowerShellRedirectUri)"; `
            SchemaVersion = "beta"; `
            TenantAdminUPN = "$($TenantAdminUPN)";
            AuthHeader = $null;
            platformParameters = $null;
            userId = $null;
            authContext = $null}
        [PSCustomObject]@{Environment = "pe_cnb"; `
            AuthUrl = "https://login.partner.microsoftonline.cn/$($tenant)"; `
            ResourceId = "https://microsoftgraph.chinacloud.cn"; `
            GraphBaseAddress = "https://microsoftgraph.chinacloud.cn"; `
            IPARoute = "deviceManagement/groupPolicyMigrationReports"; `
            AppId = "$($IntunePowerShellclientId)"; `
            RedirectLink = "$($IntunePowerShellRedirectUri)"; `
            SchemaVersion = "beta"; `
            TenantAdminUPN = "$($TenantAdminUPN)";
            AuthHeader = $null;
            platformParameters = $null;
            userId = $null;
            authContext = $null}     
    )

    $graphConfiguration = ($GraphConfiguration | Where-Object {$_.Environment -eq "$($Environment)"})

#region AAD configurations
    $AadModule = Get-Module -Name "AzureAD" -ListAvailable

    If ($null -eq $AadModule)
    {
        Write-Log -Message "AzureAD PowerShell module not found, looking for AzureADPreview"
        $AadModule = Get-Module -Name "AzureADPreview" -ListAvailable
    }

    If ($null -eq $AadModule)
    {
        Install-Module AzureADPreview
    }

    $adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
    $adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"

    # Load ADAL types
    [System.Reflection.Assembly]::LoadFrom($adal) | Out-Null
    [System.Reflection.Assembly]::LoadFrom($adalforms) | Out-Null

    $graphConfiguration.platformParameters = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters" -ArgumentList "Auto"
    $graphConfiguration.userId = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.UserIdentifier" -ArgumentList ($graphConfiguration.TenantAdminUPN, "OptionalDisplayableId")
    $graphConfiguration.authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $graphConfiguration.AuthUrl
#endregion

    return $graphConfiguration
}

<#
.Synopsis
  Connect-Intune - Connect to Microsoft Intune
.DESCRIPTION
   Get an auth token from AAD.
.PARAMETER GraphConfiguration
   The UPN of the user that shall be used to get an auth token for.
#>
Function Connect-Intune
{
    param
    (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$graphConfiguration
    )

    Try
    {
        # BUGBUG: We are directly doing auth via ADAL till we figure how to call
        # Connect-MSGraph correctly
        (Get-AuthHeader -graphConfiguration $graphConfiguration) | Out-Null
    }
    Catch
    {
        $exception  = $_
        Write-Log -Message "Connect-Intune Failed. Failure: $($exception)" -Level "Error"
        throw
    }
}

#
# CloneObject: Clones the input object
#
function CloneObject($object)
{
	$stream = New-Object IO.MemoryStream;
	$formatter = New-Object Runtime.Serialization.Formatters.Binary.BinaryFormatter;
	$formatter.Serialize($stream, $object);
	$stream.Position = 0;
	$formatter.Deserialize($stream);
}

<#
.Synopsis
  Get-AuthHeader - Get an auth token from AAD.
.DESCRIPTION
   Get an auth token from AAD.
.PARAMETER GraphConfiguration
   The UPN of the user that shall be used to get an auth token for.
#>
Function Get-AuthHeader
{
    param
    (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$graphConfiguration
    )

    # Get the AuthToken from AAD
    $currentDateTime = (Get-Date).ToUniversalTime()
    $tokenExpiresOn = ($graphConfiguration.AuthHeader.ExpiresOn.datetime - $currentDateTime).Minutes

    If ($tokenExpiresOn -le 0)
    {        
        $authResult = $graphConfiguration.authContext.AcquireTokenAsync($graphConfiguration.ResourceId,`
                                                        $graphConfiguration.AppId, `
                                                        $graphConfiguration.RedirectLink, `
                                                        $graphConfiguration.platformParameters, `
                                                        $graphConfiguration.userId).Result

        # Creating header for Authorization token
        $graphConfiguration.AuthHeader = @{
            'Content-Type'='application/json'
            'Authorization'="Bearer " + $authResult.AccessToken
            'ExpiresOn'=$authResult.ExpiresOn
            }
    }

    return $graphConfiguration.AuthHeader
}

<#
.Synopsis
  Add-IntuneEntityCollection - Makes a POST request to Intune
.DESCRIPTION
   Make a HTTP POST request to Intune
.PARAMETER CollectionPath
   The Collection path to the Graph Entitie that needs to be fetched.
.PARAMETER Body
   The Json serialized Body of the HTTP POST call
#>
function Add-IntuneEntityCollection
{
    param
    (
        [Parameter(Mandatory=$true)]
        $CollectionPath,
        [Parameter(Mandatory=$true)]
        $Body,
        [Parameter(Mandatory=$true)]
        $GraphConfiguration
    )

    $uri = "$($GraphConfiguration.GraphBaseAddress)/$($GraphConfiguration.SchemaVersion)/$($GraphConfiguration.IPARoute)/$($collectionPath)";
    $clonedHeaders = CloneObject (Get-AuthHeader $graphConfiguration);
	$clonedHeaders["content-length"] = $Body.Length;
    $clonedHeaders["api-version"] = "$($script:ApiVersion)";

	Try
	{        
        $response = Invoke-RestMethod $uri -Method Post -Headers $clonedHeaders -Body $body;
    }
    Catch
	{
        $exception  = $_
        Write-Log -Message "Add-IntuneEntityCollection: Failed. CollectionPath:$($CollectionPath). Size=$($Body.Length). Failure: $($exception)" -Level "Warn"
        throw
	}

    return $response;
}

<#
.Synopsis
  Get-IntuneEntityCollection - Makes a GET request to Intune
.DESCRIPTION
   Make a HTTP GET request to Intune
.PARAMETER CollectionPath
   The Collection path to the Graph Entitie that needs to be fetched.
#>
Function Get-IntuneEntityCollection
{
    param
    (
        [Parameter(Mandatory=$true)]
        $CollectionPath,
        [Parameter(Mandatory=$false)]
        $Uri,
        [Parameter(Mandatory=$true)]
        $GraphConfiguration
    )

    If ($null -eq $Uri)
    {
        $uri = "$($GraphConfiguration.GraphBaseAddress)/$($GraphConfiguration.SchemaVersion)/$($GraphConfiguration.IPARoute)$($collectionPath)";
    }

    $clonedHeaders = CloneObject (Get-AuthHeader $graphConfiguration);
    $clonedHeaders["api-version"] = "$($script:ApiVersion)";

	Try
	{
        $response = Invoke-RestMethod $uri -Method Get -Headers $clonedHeaders
	}
	Catch
	{
        $exception  = $_
        Switch ($exception)
        {
            'not found'
            {
                $response = $null
                Write-Log -Message "Get-IntuneEntityCollection: GET $($uri) Failed. Failure: $($exception)"
            }
            Default
            {
                $response = $exception
                Write-Log -Message "Get-IntuneEntityCollection: GET $($uri) Failed. Failure: $($exception)" -Level "Warn"
                throw
            }
        }
	}

    return $response;
}

<#
.Synopsis
  Remove-IntuneEntityCollection - Makes a DELETE request to Intune
.DESCRIPTION
   Make a HTTP DELETE request to Intune
.PARAMETER CollectionPath
   The Collection path to the Graph Entitie that needs to be fetched.
#>
Function Remove-IntuneEntityCollection
{
    param
    (
        [Parameter(Mandatory=$true)]
        $CollectionPath,
        [Parameter(Mandatory=$false)]
        $Uri,
        [Parameter(Mandatory=$true)]
        $GraphConfiguration
    )

    If ($null -eq $Uri)
    {
        $uri = "$($GraphConfiguration.GraphBaseAddress)/$($GraphConfiguration.SchemaVersion)/$($GraphConfiguration.IPARoute)$($collectionPath)";
    }

    $clonedHeaders = CloneObject (Get-AuthHeader $graphConfiguration);
    $clonedHeaders["api-version"] = "$($script:ApiVersion)";

	Try
	{
        $response = Invoke-RestMethod $uri -Method Delete -Headers $clonedHeaders
	}
	Catch
	{
        $exception  = $_
        Write-Log -Message "Remove-IntuneEntityCollection: DELETE $($uri) Failed. Failure: $($exception)" -Level "Warn"
        throw
	}

    return $response;
}
#endregion

#region AD Utilities
<#
.Synopsis
 Get-GPOReportXmlCollectionFromAD: Calls Get-GPOReport for all GPO discovered for the given domain.
.DESCRIPTION
   Calls Get-GPOReport for all GPO discovered for the given domain and returns the Xml report collection.
.PARAMETER ADDomain
   The local AD Domain for which the GPO collection is fetched.
   Defaults to the local AD Domain for the client on which this script is run on.
.PARAMETER OUFilter
   Use OUFilter to constrain the GP Objects to the OU in consideration.
   Specifies a query string that retrieves Active Directory objects. This string uses the PowerShell Expression Language syntax.
#>
Function Get-GPOReportXmlCollectionFromAD
{
    param
    (
        [Parameter(Mandatory=$true)]
        [String]$ADDomain,
        [Parameter(Mandatory=$true)]
        [String]$OUFilter
    )

    $gpoReportXmlCollection = @{}
    $gpoMigrationReportCollection = @{}

    If ($script:IPAClientConfiguration.DeltaUpdate -eq $true)
    {
        # If set, check Intune before posting GPOReportXml
        $gpoMigrationReportCollection = Get-GPOMigrationReportCollection -TenantAdminUPN $script:IPAClientConfiguration.TenantAdminUPN
    }

    Try
    {
        # Get the OU collection for the given AD Domain
        $ouCollection = Get-ADOrganizationalUnit -Filter $OUFilter -Server $ADDomain `
            | Select-Object Name,DistinguishedName,LinkedGroupPolicyObjects `
            | Where-Object {$_.LinkedGroupPolicyObjects -ne '{}'}

        # Get GPO backups for each OU
        ForEach ($ou in $ouCollection)
        {
            # Get the GPO collection linked to this ou
            # Each element in $gpoCollection is a fully qualified LDAP name of the Linked GPOs.
            # For example: "cn={A7A7EA17-BF74-4120-ADC3-14FD1DE01B34},cn=policies,cn=system,DC=redmond,DC=corp,DC=microsoft,DC=com"
            $GUIDRegex = "[a-zA-Z0-9]{8}[-][a-zA-Z0-9]{4}[-][a-zA-Z0-9]{4}[-][a-zA-Z0-9]{4}[-][a-zA-Z0-9]{12}"
            $gpoCollection = $ou | Select-Object -ExpandProperty LinkedGroupPolicyObjects
            Write-Log -Message "Get-GPOReportXmlCollectionFromAD: $($ou.DistinguishedName). GPO Count=$($gpoCollection.Count)"

            # Backup GPO from LinkedGroupPolicyObjects
            ForEach ($gpo in $gpoCollection)
            {
                $result = [Regex]::Match($gpo,$GUIDRegex);
                If ($result.Success)
                {
                    # Assign the GPO Guid
                    $gpoGuid = $result.Value

                    Try
                    {
                        # Backup a GPO as Xml in memory if not previously uploaded
                        $gpoReportXmlKey = "$($gpoGuid)_$($ou.DistinguishedName)"

                        If (!$gpoMigrationReportCollection.Contains($gpoReportXmlKey))
                        {
                            [Xml]$gpoReportXml = (Get-GPOReport -Guid $gpoGuid -ReportType Xml -Domain $ADDomain -ErrorAction Stop)
                            $bytes = [System.Text.Encoding]::UNICODE.GetBytes($gpoReportXml.InnerXml)
                            $encodedText = [Convert]::ToBase64String($bytes)
                            $gpoReportXmlCollection.Add($gpoReportXmlKey, [PSCustomObject]@{ouDistinguishedName = $ou.DistinguishedName; content = $encodedText})
                            Write-Log -Message "Get-GPOReportXmlCollectionFromAD:  Backed up GPO Guid=$($gpoGuid), $($ou.DistinguishedName)"
                        }
                        Else
                        {
                            Write-Log -Message "Get-GPOReportXmlCollectionFromAD:  GPO Guid=$($gpoGuid), $($ou.DistinguishedName) previously uploaded"
                        }
                    }
                    Catch
                    {
                        $exception  = $_
                        Write-Log -Message "Get-GPOReportXmlCollectionFromAD:Unable to get $($gpo) xml backup in memory. Failure: $($exception)" -Level "Warn"
                        # We continue to next GPO
                    }
                }
            }
        }

        Write-Log -Message "Get-GPOReportXmlCollectionFromAD: $($gpoReportXmlCollection.Count) GPOs found"
    }
    catch
    {
        # Log error
        $exception  = $_
        Write-Log -Message "Get-GPOReportXmlCollectionFromAD: Failure: ($exception)" -Level "Error"
        throw
    }

    return $gpoReportXmlCollection
}
#endregion AD Utilities
# SIG # Begin signature block
# MIIjhwYJKoZIhvcNAQcCoIIjeDCCI3QCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBRB7QsuihBVgFu
# F3SiANo6r2t6JSunSLs3hXfL9d4TQaCCDXYwggX0MIID3KADAgECAhMzAAABhk0h
# daDZB74sAAAAAAGGMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjAwMzA0MTgzOTQ2WhcNMjEwMzAzMTgzOTQ2WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQC49eyyaaieg3Xb7ew+/hA34gqzRuReb9svBF6N3+iLD5A0iMddtunnmbFVQ+lN
# Wphf/xOGef5vXMMMk744txo/kT6CKq0GzV+IhAqDytjH3UgGhLBNZ/UWuQPgrnhw
# afQ3ZclsXo1lto4pyps4+X3RyQfnxCwqtjRxjCQ+AwIzk0vSVFnId6AwbB73w2lJ
# +MC+E6nVmyvikp7DT2swTF05JkfMUtzDosktz/pvvMWY1IUOZ71XqWUXcwfzWDJ+
# 96WxBH6LpDQ1fCQ3POA3jCBu3mMiB1kSsMihH+eq1EzD0Es7iIT1MlKERPQmC+xl
# K+9pPAw6j+rP2guYfKrMFr39AgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUhTFTFHuCaUCdTgZXja/OAQ9xOm4w
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwMDEyKzQ1ODM4NDAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzci
# tW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEG
# CCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0
# MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBAEDkLXWKDtJ8rLh3d7XP
# 1xU1s6Gt0jDqeHoIpTvnsREt9MsKriVGKdVVGSJow1Lz9+9bINmPZo7ZdMhNhWGQ
# QnEF7z/3czh0MLO0z48cxCrjLch0P2sxvtcaT57LBmEy+tbhlUB6iz72KWavxuhP
# 5zxKEChtLp8gHkp5/1YTPlvRYFrZr/iup2jzc/Oo5N4/q+yhOsRT3KJu62ekQUUP
# sPU2bWsaF/hUPW/L2O1Fecf+6OOJLT2bHaAzr+EBAn0KAUiwdM+AUvasG9kHLX+I
# XXlEZvfsXGzzxFlWzNbpM99umWWMQPTGZPpSCTDDs/1Ci0Br2/oXcgayYLaZCWsj
# 1m/a0V8OHZGbppP1RrBeLQKfATjtAl0xrhMr4kgfvJ6ntChg9dxy4DiGWnsj//Qy
# wUs1UxVchRR7eFaP3M8/BV0eeMotXwTNIwzSd3uAzAI+NSrN5pVlQeC0XXTueeDu
# xDch3S5UUdDOvdlOdlRAa+85Si6HmEUgx3j0YYSC1RWBdEhwsAdH6nXtXEshAAxf
# 8PWh2wCsczMe/F4vTg4cmDsBTZwwrHqL5krX++s61sLWA67Yn4Db6rXV9Imcf5UM
# Cq09wJj5H93KH9qc1yCiJzDCtbtgyHYXAkSHQNpoj7tDX6ko9gE8vXqZIGj82mwD
# TAY9ofRH0RSMLJqpgLrBPCKNMIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkq
# hkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
# IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5WjB+MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQg
# Q29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4BjgaBEm6f8MMHt03
# a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe0t+bU7IKLMOv2akr
# rnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpcoRb0Rrrg
# OGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v++MrWhAfTVYoonpy
# 4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLTswM9
# sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN91/w0FK/jJSHvMAh
# dCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8k
# A/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmhD+kjSbwYuER8ReTB
# w3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmn
# Eyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8HhhUSJxAlMxdSlQy90
# lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0w
# ggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXTgqoXNzcitW2o
# ynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx0SOJNDBa
# BgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4GCCsG
# AQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNV
# HSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcCARYzaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsG
# AQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5AF8AcwB0AGEAdABl
# AG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKb
# C5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0epo/Np22O/IjWll11l
# hJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6
# I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWluWpiW5IP0
# wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInWH8MyGOLwxS3OW560
# STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNABQam
# ASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMdYzaXht/a8/jyFqGa
# J+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ah
# XJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKfenoi+kiVH6v7RyOA
# 9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33Vt
# Y5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZOSEXAQsmbdlsKgEhr
# /Xmfwb1tbWrJUnMTDXpQzTGCFWcwghVjAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAAGGTSF1oNkHviwAAAAAAYYwDQYJYIZIAWUDBAIB
# BQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEII+hwwEQxq2Vg6Mt28kC3E5f
# xeqSMGv/MW9SANodd6QgMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8A
# cwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
# BQAEggEAcagKsuqUIK7Aoy9Lvwdnv6o4J9Vi6gLFUvCEO6mBWLzZkwvGjg9T/63L
# sf+QZMHIasbng3Sf4X/hhCoqQD4Yg8bZem3/bEYWj/jY9i7ewvHPn943MIe3OJzt
# FOKmXl141HpvLnTRWfvjwNbqi273YZzW7NIHUp4DR32gJE7vP4PpaSb/V5QkKMp2
# zc5Whj7MVk/HhcPa0rWa6RnCy3wXb/O5IC8lV0QXQDjxWuxeoaTOaU6re83ppUdL
# cz/TtQe4YMs77KYGlYYvJdK8rnRsQPcbbh348lKWc8U19EITmSXp0amQq20sTevv
# PRJxGT7ndOP9dieq9F4WBxzZlGtz16GCEvEwghLtBgorBgEEAYI3AwMBMYIS3TCC
# EtkGCSqGSIb3DQEHAqCCEsowghLGAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFVBgsq
# hkiG9w0BCRABBKCCAUQEggFAMIIBPAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFl
# AwQCAQUABCAa5snGWsMhxQbHUdyIhuKoVjSjaDwv/Vfz2vAcJc7tUAIGXtVI9vbP
# GBMyMDIwMDYxODA5NTA1NS40ODhaMASAAgH0oIHUpIHRMIHOMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3Bl
# cmF0aW9ucyBQdWVydG8gUmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046Rjc3
# Ri1FMzU2LTVCQUUxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZp
# Y2Wggg5EMIIE9TCCA92gAwIBAgITMwAAASroF5b4hqfvowAAAAABKjANBgkqhkiG
# 9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYw
# JAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0xOTEyMTkw
# MTE1MDJaFw0yMTAzMTcwMTE1MDJaMIHOMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0aW9ucyBQdWVy
# dG8gUmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046Rjc3Ri1FMzU2LTVCQUUx
# JTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggEiMA0GCSqG
# SIb3DQEBAQUAA4IBDwAwggEKAoIBAQCf35WBpIXSbcUrBwbvZZlxf1F8Txey+OZx
# IZrXdNSg6LFm2PMueATe/pPQzL86k6D9/b/P2fjbRMyo/AX+REKBtf6SX6cwiXvN
# B2asqjKNKEPRLoFWOmDVTWtk9budXfeqtYRZrtXYMbfLg9oOyKQUHYUtraXN49xx
# Myr1f78BK+/wXE7sKlB6q6wYB3Pe9XqVUeKOWzSrI4pGsJjMPQ/7cq03IstxfRqv
# aRIJPBKiXznQGm5Gp7gFk45ZgYWbUYjvVtahacJ7vRualb3TSkSsUHbcTAtOKVhn
# 58cw2nO/oyKped9iBAuUEp72POLMxKccN9UFvy2n0og5gLWFh6ZvAgMBAAGjggEb
# MIIBFzAdBgNVHQ4EFgQUcPTFLXQrP64TdsvRJBOmSPTvE2kwHwYDVR0jBBgwFoAU
# 1WM6XIoxkPNDe3xGG8UzaFqFbVUwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2Ny
# bC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljVGltU3RhUENBXzIw
# MTAtMDctMDEuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNUaW1TdGFQQ0FfMjAxMC0w
# Ny0wMS5jcnQwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcDCDANBgkq
# hkiG9w0BAQsFAAOCAQEAisA09Apx1aOOjlslG6zyI/ECHH/j04wVWKSoNStg9eWe
# sRLr5n/orOjfII/X9Z5BSAC74fohpMfBoBmv6APSIVzRBWDzRWh8B2p/1BMNT+k4
# 3Wqst3LywvH/MxNQkdS4VzaH6usX6E/RyxhUoPbJDyzNU0PkQEF/TIoBJvBRZYYb
# ENYhgdd/fcfHfdofSrKahg5zvemfQI+zmw7XVOkaGa7GZIkUDZ15p19SPkbsLS7v
# DDfF4SS0pecKqhzN66mmjL0gCElbSskqcyQuWYfuZCZahXUoiB1vEPvEehFhvCC2
# /T3/sPz8ncit2U5FV1KRQPiYVo3Ms6YVRsPX349GCjCCBnEwggRZoAMCAQICCmEJ
# gSoAAAAAAAIwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmlj
# YXRlIEF1dGhvcml0eSAyMDEwMB4XDTEwMDcwMTIxMzY1NVoXDTI1MDcwMTIxNDY1
# NVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggEiMA0GCSqGSIb3DQEB
# AQUAA4IBDwAwggEKAoIBAQCpHQ28dxGKOiDs/BOX9fp/aZRrdFQQ1aUKAIKF++18
# aEssX8XD5WHCdrc+Zitb8BVTJwQxH0EbGpUdzgkTjnxhMFmxMEQP8WCIhFRDDNdN
# uDgIs0Ldk6zWczBXJoKjRQ3Q6vVHgc2/JGAyWGBG8lhHhjKEHnRhZ5FfgVSxz5NM
# ksHEpl3RYRNuKMYa+YaAu99h/EbBJx0kZxJyGiGKr0tkiVBisV39dx898Fd1rL2K
# Qk1AUdEPnAY+Z3/1ZsADlkR+79BL/W7lmsqxqPJ6Kgox8NpOBpG2iAg16HgcsOmZ
# zTznL0S6p/TcZL2kAcEgCZN4zfy8wMlEXV4WnAEFTyJNAgMBAAGjggHmMIIB4jAQ
# BgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4EFgQU1WM6XIoxkPNDe3xGG8UzaFqFbVUw
# GQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB
# /wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0f
# BE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJv
# ZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4w
# TDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0
# cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwgaAGA1UdIAEB/wSBlTCBkjCB
# jwYJKwYBBAGCNy4DMIGBMD0GCCsGAQUFBwIBFjFodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vUEtJL2RvY3MvQ1BTL2RlZmF1bHQuaHRtMEAGCCsGAQUFBwICMDQeMiAd
# AEwAZQBnAGEAbABfAFAAbwBsAGkAYwB5AF8AUwB0AGEAdABlAG0AZQBuAHQALiAd
# MA0GCSqGSIb3DQEBCwUAA4ICAQAH5ohRDeLG4Jg/gXEDPZ2joSFvs+umzPUxvs8F
# 4qn++ldtGTCzwsVmyWrf9efweL3HqJ4l4/m87WtUVwgrUYJEEvu5U4zM9GASinbM
# QEBBm9xcF/9c+V4XNZgkVkt070IQyK+/f8Z/8jd9Wj8c8pl5SpFSAK84Dxf1L3mB
# ZdmptWvkx872ynoAb0swRCQiPM/tA6WWj1kpvLb9BOFwnzJKJ/1Vry/+tuWOM7ti
# X5rbV0Dp8c6ZZpCM/2pif93FSguRJuI57BlKcWOdeyFtw5yjojz6f32WapB4pm3S
# 4Zz5Hfw42JT0xqUKloakvZ4argRCg7i1gJsiOCC1JeVk7Pf0v35jWSUPei45V3ai
# caoGig+JFrphpxHLmtgOR5qAxdDNp9DvfYPw4TtxCd9ddJgiCGHasFAeb73x4QDf
# 5zEHpJM692VHeOj4qEir995yfmFrb3epgcunCaw5u+zGy9iCtHLNHfS4hQEegPsb
# iSpUObJb2sgNVZl6h3M7COaYLeqN4DMuEin1wC9UJyH3yKxO2ii4sanblrKnQqLJ
# zxlBTeCG+SqaoxFmMNO7dDJL32N79ZmKLxvHIa9Zta7cRDyXUHHXodLFVeNp3lfB
# 0d4wwP3M5k37Db9dT+mdHhk4L7zPWAUu7w2gUDXa7wknHNWzfjUeCLraNtvTX4/e
# dIhJEqGCAtIwggI7AgEBMIH8oYHUpIHRMIHOMQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSkwJwYDVQQLEyBNaWNyb3NvZnQgT3BlcmF0aW9ucyBQ
# dWVydG8gUmljbzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046Rjc3Ri1FMzU2LTVC
# QUUxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiIwoBATAH
# BgUrDgMCGgMVAOqy5qyh8iDD++nj5d9tcSlCd2F/oIGDMIGApH4wfDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZIhvcNAQEFBQACBQDilYe6MCIYDzIw
# MjAwNjE4MTAyNzA2WhgPMjAyMDA2MTkxMDI3MDZaMHcwPQYKKwYBBAGEWQoEATEv
# MC0wCgIFAOKVh7oCAQAwCgIBAAICJNQCAf8wBwIBAAICEaYwCgIFAOKW2ToCAQAw
# NgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEKMAgC
# AQACAwGGoDANBgkqhkiG9w0BAQUFAAOBgQBM6zKMp1ZvIwWdqx5J+1DSzAqgRF6u
# Y4dJkdjdycG2DaTHKdvjnn9u8s1gsS6S5hVp3lE3Uzkvx6+AttI03/r9oRbrdQat
# eU6XeYc5UFMPFHcIZ5cCP7LXekH09IUeutw1Cm9755mkNWqPoXE022rt9QyE1ooQ
# HSdxicamTahCHDGCAw0wggMJAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAABKugXlviGp++jAAAAAAEqMA0GCWCGSAFlAwQCAQUAoIIBSjAa
# BgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIArboNeJ
# y7W7g3BDBF8W0kPSKuRgAppDVhQjJx4/SbIoMIH6BgsqhkiG9w0BCRACLzGB6jCB
# 5zCB5DCBvQQgQ5g1hFr3On4bObeFqKOUPhTBQnGiIFeMlD+AqbgZi5kwgZgwgYCk
# fjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQD
# Ex1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAASroF5b4hqfvowAA
# AAABKjAiBCCONmvni8sIpSUVJx+juf90BvnoVDWYtbUNfZn56EPPrTANBgkqhkiG
# 9w0BAQsFAASCAQAUqEJkObReVaVeXHT68FHE1VCSEgxVUkFpCTkM7enw4W1xpL7A
# WrpHkILfGvR3DcxoBT1kaa5qvXrqnTstsQyaY3mmvn3FDO6LGZSz81wfvkyCkZHK
# ua4cb5RXNeZ8oXveCCCVIkzNsRUkN9psPsJxYbvmys8UDbhnRyu/4V4hSScW65Ke
# upBJko+9MRVqtmeYY06NQUeBUGl6ac1VBxC4N6ZhBAz2//aEhmYrO0UZhVO+XmIE
# L5VHXCz/aIVau4bgzMKCVaWdyn19B8vRBnGci481Fjwvd6VOmwY0Wl/dgqxZd7lv
# 4S7y7mpbUrbwKqpBg5ZPrZt5L4UXhfoncGmP
# SIG # End signature block
