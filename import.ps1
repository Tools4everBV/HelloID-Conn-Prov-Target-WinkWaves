###########################################
# HelloID-Conn-Prov-Target-WinkWaves-Import
# PowerShell V2
###########################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-WinkWavesError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsMessage = ($httpErrorObj.ErrorDetails | ConvertFrom-Json).error
            $httpErrorObj.FriendlyMessage = $errorDetailsObject
        } catch {
            $httpErrorObj.FriendlyMessage = "Error: [$($errorDetailsMessage)] [$($_.Exception.Message)]"
        }
        Write-Output $httpErrorObj
    }
}

function ConvertTo-HelloIDAccountObject {
    param (
        [Parameter()]
        $Account
    )

    $obj = [PSCustomObject]@{
        userName    = $Account.userName
        displayName = $Account.displayName
        email       = ($Account.emails | Where-Object { $_.type -eq 'work' }).value
        active      = $Account.active
        id          = $Account.id
    }

    Write-Output $obj
}
#endregion

try {
    Write-Information 'Starting target account import'

    # Set headers
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add('Authorization', "Bearer $($actionContext.Configuration.Token)")

    $splatParams = @{
        Uri         = "$($($actionContext.configuration.BaseUrl))/scim/v2/Users"
        Headers     = $headers
        Method      = 'GET'
    }
    $existingAccounts = Invoke-RestMethod @splatParams

    foreach ($account in $existingAccounts.Resources){
        $helloIDAccountObject = ConvertTo-HelloIDAccountObject -Account $account

        Write-Output @{
            AccountReference = $helloIDAccountObject.id
            DisplayName      = $helloIDAccountObject.displayName
            UserName         = $helloIDAccountObject.userName
            Enabled          = $helloIDAccountObject.active
            Data             = $helloIDAccountObject
        }
    }
    Write-Information 'Target account import completed'
} catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-WinkWavesError -ErrorObject $ex
        Write-Error "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        Write-Error "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
}
