function Set-CWAAServerPassword {
    [CmdletBinding(SupportsShouldProcess = $True)]
    Param( 
        [Parameter(ParameterSetName = 'installertoken')]
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $True)]
        [string[]]$Server,

        [Parameter(ParameterSetName = 'password')]
        [Parameter(ValueFromPipelineByPropertyName = $True)]
        [AllowNull()]
        [SecureString]$ServerPassword,

        [Parameter(ParameterSetName = 'installertoken')]
        [ValidatePattern('(?s:^[0-9a-z]+$)')]
        [string]$InstallerToken
    )

    begin {
        Stop-CWAA
    }

    process {
        if ((Test-Path "${env:windir}\ltsvc" -EA 0)) {
            
            switch ($PSCmdlet.ParameterSetName) {
                'password' {
                    $Password = ConvertTo-CWAASecurity -InputString $ServerPassword
                }
                'installertoken' {
                    $Server = ForEach ($Svr in $Server) { if ($Svr -notmatch 'https?://.+') { "https://$($Svr)" }; $Svr }
                    ForEach ($Svr in $Server) {
                        if (-not ($GoodServer)) {
                            if ($Svr -match '^(https?://)?(([12]?[0-9]{1,2}\.){3}[12]?[0-9]{1,2}|[a-z0-9][a-z0-9_-]*(\.[a-z0-9][a-z0-9_-]*)*)$') {
                                if ($Svr -notmatch 'https?://.+') { $Svr = "http://$($Svr)" }
                                Try {
                                    Write-Debug "Line $(LINENUM): Skipping Server Version Check. Using Installer Token for download."
                                    $installer = "$($Svr)/LabTech/Deployment.aspx?InstallerToken=$InstallerToken"
                                    
                                    if ( $PSCmdlet.ShouldProcess($installer, 'DownloadFile') ) {
                                        Write-Debug "Line $(LINENUM): Downloading $InstallMSI from $installer"
                                        $Script:LTServiceNetWebClient.DownloadFile($installer, "$InstallBase\Installer\$InstallMSI")
                                        If ((Test-Path "$InstallBase\Installer\$InstallMSI") -and !((Get-Item "$InstallBase\Installer\$InstallMSI" -EA 0).length / 1KB -gt 1234)) {
                                            Write-Warning "WARNING: Line $(LINENUM): $InstallMSI size is below normal. Removing suspected corrupt file."
                                            Remove-Item "$InstallBase\Installer\$InstallMSI" -ErrorAction SilentlyContinue -Force -Confirm:$False
                                            Continue
                                        }
                                    }

                                    if ($WhatIfPreference -eq $True) {
                                        $GoodServer = $Svr
                                    }
                                    Elseif (Test-Path "$InstallBase\Installer\$InstallMSI") {
                                        $GoodServer = $Svr
                                        Write-Verbose "$InstallMSI downloaded successfully from server $($Svr)."
                                    }
                                    else {
                                        Write-Warning "WARNING: Line $(LINENUM): Error encountered downloading from $($Svr). No installation file was received."
                                        Continue
                                    }
                                }
                                Catch {
                                    Write-Warning "WARNING: Line $(LINENUM): Error encountered downloading from $($Svr)."
                                    Continue
                                }
                            }
                            else {
                                Write-Warning "WARNING: Line $(LINENUM): Server address $($Svr) is not formatted correctly. Example: https://lt.domain.com"
                            }
                        }
                        else {
                            Write-Debug "Line $(LINENUM): Server $($GoodServer) has been selected."
                            Write-Verbose "Server has already been selected - Skipping $($Svr)."
                        }
                    }

                    $MsiProperties = Read-MsiProperties -MsiPath "$InstallBase\Installer\$InstallMSI"
                    if ($MsiProperties.SERVERADDRESS -ne 'Enter the server address here.') {
                        $Password = ConvertTo-CWAASecurity -InputString $MsiProperties.SERVERADDRESS
                    }
                    else {
                        Write-Error 'Server password is not present in the MSI file, check the installer token'
                    }
                }
            }            
        }
    }
    end {
        if ($Password) {
            if ($PSCmdlet.ShouldProcess('[REDACTED]', 'Set server password')) {
                Set-ItemProperty -Path HKLM:\software\labtech\service -Name ServerPassword -Value $Password
            }
        }
        Start-CWAA
    }
}