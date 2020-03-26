<#

.COPYRIGHT
Copyright (c) Microsoft Corporation. All rights reserved. Licensed under the MIT license.
See LICENSE in the project root for license information.

#>

####################################################

$IntuneModule = Get-Module -Name "Microsoft.Graph.Intune" -ListAvailable

if (!$IntuneModule){

    write-host "Microsoft.Graph.Intune Powershell module not installed..." -f Red
    write-host "Install by running 'Install-Module Microsoft.Graph.Intune' from an elevated PowerShell prompt" -f Yellow
    write-host "Script can't continue..." -f Red
    write-host
    exit

}

####################################################

if(!(Connect-MSGraph)){

    Connect-MSGraph

}

####################################################

Update-MSGraphEnvironment -SchemaVersion beta -Quiet

####################################################

$properties = @{

    reportName = 'Devices'
    select = @('DeviceId',"DeviceName","OSVersion", "HasUnlockToken")
    filter = "((DeviceType eq '9') or (DeviceType eq '8') or (DeviceType eq '10'))"
    
}

$psObj = New-Object -TypeName psobject -Property $properties

$Json = ConvertTo-Json -InputObject $psObj

####################################################

$uri = "https://graph.microsoft.com/beta/deviceManagement/reports/exportJobs"
$result = (Invoke-MSGraphRequest -Url $uri -HttpMethod Post -Content $JSON.toString())

$id = $result.id

write-host "Export Job id is '$id'" -ForegroundColor Cyan

Write-Host

while($true){

    $pollingUri = "$uri('$id')"
    write-host "Polling uri = '$pollingUri'"

    $result = (Invoke-MSGraphRequest -Url $pollingUri -HttpMethod Get)
    $status = $result.status

    if ($status -eq 'completed'){

        Write-Host "Export Job Complete..." -ForegroundColor Green
        Write-Host

        $fileName = (Split-Path -Path $result.url -Leaf).split('?')[0]

        Invoke-WebRequest -Uri $result.url -OutFile $env:temp\$fileName

        Write-host "Downloaded Export to local disk as '$env:temp\$fileName'..." -ForegroundColor Green
        Write-Host
        break;

    }

    else {

        Write-Host "In progress, waiting..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        Write-Host
        
    }

}

    