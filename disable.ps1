##################################################
# HelloID-Conn-Prov-Target-WinkWaves-Disable
# PowerShell V2
##################################################

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
            $errorDetailsMessage = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            if ($null -ne $errorDetailsMessage.details) {
                $errorDetailsMessage = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
                $messages = [System.Collections.Generic.List[string]]::new()
                foreach ($key in $errorDetailsMessage.details.PSObject.Properties.Name) {
                    $value = $errorDetailsMessage.details."$key"
                    if ($value.errors) {
                        $messages.Add($value.errors)
                    }
                }
                $httpErrorObj.FriendlyMessage = ($messages | ConvertTo-Json)
            } else {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject
            }
        } catch {
            $httpErrorObj.FriendlyMessage = "Error: [$($errorDetailsMessage)] [$($_.Exception.Message)]"
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    # Set headers
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add('Authorization', "Bearer $($actionContext.Configuration.Token)")

    Write-Information 'Verifying if a WinkWaves account exists'
    try {
        $splatParams = @{
            Uri         = "$($actionContext.configuration.BaseUrl)/scim/v2/Users/$($actionContext.References.Account)"
            Headers     = $headers
            Method      = 'GET'
        }
        $correlatedAccount = Invoke-RestMethod @splatParams
    } catch {
        if ($_.Exception.Response.StatusCode -eq 404){
            Write-Information $_.Exception.Message
        } else {
            throw
        }
    }

    if ($null -ne $correlatedAccount) {
        $action = 'DisableAccount'
    } else {
        $action = 'NotFound'
    }

    # Process
    switch ($action) {
        'DisableAccount' {
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Disabling WinkWaves account with accountReference: [$($actionContext.References.Account)]"
                [System.Collections.Generic.List[object]]$operations = @()

                $operations.Add(
                    [PSCustomObject]@{
                        op    = 'Replace'
                        path  = 'active'
                        value = 'false'
                    }
                )

                $splatParams = @{
                    Uri     = "$($actionContext.configuration.BaseUrl)/scim/v2/Users/$($actionContext.References.Account)"
                    Method  = 'PATCH'
                    Body    = [ordered]@{
                        schemas    = @(
                            'urn:ietf:params:scim:api:messages:2.0:PatchOp'
                        )
                        Operations = $operations
                    } | ConvertTo-Json
                    Headers = $headers
                    ContentType = 'application/scim+json'
                }
                $null = Invoke-RestMethod @splatParams
            } else {
                Write-Information "[DryRun] Disable WinkWaves account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'Disable account was successful'
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "WinkWaves account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "WinkWaves account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
                    IsError = $false
                })
            break
        }
    }
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-WinkWavesError -ErrorObject $ex
        $auditMessage = "Could not disable WinkWaves account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not disable WinkWaves account. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
        Message = $auditMessage
        IsError = $true
    })
}
