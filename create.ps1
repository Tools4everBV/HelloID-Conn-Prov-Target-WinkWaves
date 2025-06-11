#################################################
# HelloID-Conn-Prov-Target-WinkWaves-Create
# PowerShell V2
#################################################

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
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    # Set headers
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add('Authorization', "Bearer $($actionContext.Configuration.Token)")

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        $splatGetParams = @{
            Uri     = "$($actionContext.configuration.BaseUrl)/scim/v2/Users?filter=$correlationField eq ""$($correlationValue)"""
            Method  = 'GET'
            Headers = $headers
        }
        $response = Invoke-RestMethod @splatGetParams
    }

    if ($response.Resources.Count -eq 0) {
        $action = 'CreateAccount'
    } elseif ($response.Resources.Count -eq 1) {
        $action = 'CorrelateAccount'
        $correlatedAccount = $response.Resources | Select-Object -First 1
    } elseif ($response.Count -gt 1) {
        throw "Multiple accounts found for person where $correlationField is: [$correlationValue]"
    }

    # Process
    switch ($action) {
        'CreateAccount' {
            $splatCreateParams = @{
                Uri    = "$($actionContext.Configuration.BaseUrl)/scim/v2/Users"
                Method = 'POST'
                Body   = @{
                    userName    = $actionContext.Data.userName
                    displayName = $actionContext.Data.displayName
                    active      = 'false'
                    emails     = @(@{
                        primary = $False
                        type    = 'work'
                        value   = $actionContext.Data.email
                    })
                } | ConvertTo-Json
                Headers = $headers
                ContentType = 'application/scim+json'
            }

            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information 'Creating and correlating WinkWaves account'
                $createdAccount = Invoke-RestMethod @splatCreateParams
                $helloIDAccountObject = ConvertTo-HelloIDAccountObject -Account $createdAccount
                $outputContext.Data = $helloIDAccountObject
                $outputContext.AccountReference = $helloIDAccountObject.id
            } else {
                Write-Information '[DryRun] Create and correlate WinkWaves account, will be executed during enforcement'
            }
            $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)]"
            break
        }

        'CorrelateAccount'{
            Write-Information 'Correlating WinkWaves account'
            $helloIDAccountObject = ConvertTo-HelloIDAccountObject -Account $correlatedAccount
            $outputContext.Data = $helloIDAccountObject
            $outputContext.AccountReference = $helloIDAccountObject.id
            $outputContext.AccountCorrelated = $true
            $auditLogMessage = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
            break
        }
    }

    $outputContext.success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = $action
            Message = $auditLogMessage
            IsError = $false
        })
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-WinkWavesError -ErrorObject $ex
        $auditMessage = "Could not create or correlate WinkWaves account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not create or correlate WinkWaves account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
