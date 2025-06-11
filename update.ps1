#################################################
# HelloID-Conn-Prov-Target-WinkWaves-Update
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
        $helloIDAccountObject = ConvertTo-HelloIDAccountObject -Account $correlatedAccount
        $outputContext.PreviousData = $helloIDAccountObject
    } catch {
        if ($_.Exception.Response.StatusCode -eq 404){
            Write-Information $_.Exception.Message
        } else {
            throw
        }
    }

    if ($null -ne $helloIDAccountObject) {
        $splatCompareProperties = @{
            ReferenceObject  = @($helloIDAccountObject.PSObject.Properties | Where-Object { $_.Name -ne 'active' })
            DifferenceObject = @($actionContext.Data.PSObject.Properties | Where-Object { $_.Name -ne 'active' })
        }
        $propertiesChanged = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
        if ($propertiesChanged) {
            $action = 'UpdateAccount'
        } else {
            $action = 'NoChanges'
        }
    } else {
        $action = 'NotFound'
    }

    # Process
    switch ($action) {
        'UpdateAccount' {
            Write-Information "Account property(s) required to update: $($propertiesChanged.Name -join ', ')"
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Updating WinkWaves account with accountReference: [$($actionContext.References.Account)]"
                [System.Collections.Generic.List[object]]$operations = @()
                foreach ($property in $propertiesChanged) {
                    switch ($property.Name) {
                        'email' {
                            $operations.Add(
                                [PSCustomObject]@{
                                    op    = 'Replace'
                                    path  = 'emails[type eq "work"].value'
                                    value = $property.Value
                                }
                            )
                        }
                        'displayName' {
                            $operations.Add(
                                [PSCustomObject]@{
                                    op    = 'Replace'
                                    path  = 'displayName'
                                    value = $property.Value
                                }
                            )
                        }
                        'userName' {
                            $operations.Add(
                                [PSCustomObject]@{
                                    op    = 'Replace'
                                    path  = 'userName'
                                    value = $property.Value
                                }
                            )
                        }
                    }
                }

                $splatParams = @{
                    Uri     = "$($actionContext.configuration.BaseUrl)/scim/v2/Users/$($actionContext.References.Account)"
                    Method  = 'Patch'
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
                Write-Information "[DryRun] Update WinkWaves account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.name -join ',')]"
                    IsError = $false
                })
            break
        }

        'NoChanges' {
            Write-Information "No changes to WinkWaves account with accountReference: [$($actionContext.References.Account)]"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'No changes will be made to the account during enforcement'
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "WinkWaves account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "WinkWaves account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
                    IsError = $true
                })
            break
        }
    }
} catch {
    $outputContext.Success  = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-WinkWavesError -ErrorObject $ex
        $auditMessage = "Could not update WinkWaves account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not update WinkWaves account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
