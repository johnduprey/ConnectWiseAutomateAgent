function Invoke-AutomateDiagnostics {
    [cmdletbinding(DefaultParameterSetName = 'DiagnosticTask')]
    Param(
        [Parameter(ParameterSetName = 'OnDemand')]
        [switch]$RunTask,

        [Parameter(ParameterSetName = 'OnDemand')]
        [switch]$UpdateAgent,

        [Parameter(ParameterSetName = 'OutputResults')]
        [switch]$GetResults,

        [Parameter(ParameterSetName = 'OutputResults')]
        [switch]$AsJson
    )

    $DiagnosticsPath = Join-Path $env:ProgramData '\AutomateDiagnostics'
    $ConfigFile = "$DiagnosticsPath\config.json"
    $StatusFile = "$DiagnosticsPath\status.json"
    $OnDemandFile = "$DiagnosticsPath\ondemand.json"
    $RunningFile = "$DiagnosticsPath\running.json"
    $DiagnosticLog = "$DiagnosticsPath\diagnostics.log"

    if (-not (Test-Path $DiagnosticsPath)) {
        New-Item -ItemType Directory -Path $DiagnosticsPath
    }

    if (Test-Path $ConfigFile) {
        try {
            $Config = Get-Content -Raw $ConfigFile | ConvertFrom-Json
        }
        catch {
            Write-Error "Exception reading configuration: $($_.Exception.Message)"
            return $false
        }
    }
    else {
        Write-Verbose 'Setting default diagnostic settings'
        Initialize-AutomateDiagnostics -UseAgentSettings -TaskTriggers @('Daily', 'Network', 'Startup') -EnableUpdates
        $Config = Get-Content -Raw $ConfigFile | ConvertFrom-Json
    }

    $TaskName = 'CW Automate Diagnostics'
    $TaskPath = '\'
    $Task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue

    if (!$Task) {
        Initialize-AutomateDiagnostics -UseConfig -TaskTriggers @('Daily', 'Network', 'Startup')
    }

    Write-Verbose $PSCmdlet.ParameterSetName
    switch ($PSCmdlet.ParameterSetName) {
        'DiagnosticTask' {
            try {
                if (Test-Path $RunningFile) {
                    Write-Host 'Diagnostics already running'
                    return
                }

                if (Test-Path $OnDemandFile) {
                    $OnDemandActions = Get-Content -Path $OnDemandFile | ConvertFrom-Json
                    Remove-Item $OnDemandFile
                }

                Start-Transcript -Path $DiagnosticLog
                Write-Host 'Starting diagnostics...'
                
                $Started = Get-Date
                $Running = [PSCustomObject]@{
                    Started = $Started
                }
                $Running | ConvertTo-Json | Out-File -FilePath $RunningFile

                $Services = @('LTService', 'LTSVCMon', 'ScreenConnect Client')
                $ServiceInfo = @{}
                foreach ($Service in $Services) {
                    $ServiceInfo.$Service = Get-ServiceDetails -Service $Service
                    Set-ServiceRecovery -ServiceName $Service
                }

                try { 
                    Invoke-CWAACommand -Command 'Send Status'
                    
                    Write-Host 'Waiting 5 seconds for agent checkin to update'
                    Start-Sleep -Seconds 5

                    Write-Host 'Getting agent information'
                    $AgentInfo = Get-CWAAInfo
                }
                catch {
                    Write-Host "Exception caught getting agent info: $($_.Exception.Message)"
                }

                Write-Host 'Checking agent health'
                if ($AgentInfo.ID -gt 0 -and $AgentInfo.LastSuccessStatus -gt (Get-Date).AddDays(-1) -and $AgentInfo.Server -contains $Config.Server) {
                    $Healthy = $true
                }
                else {
                    $Healthy = $false
                }

                $UpdateNeeded = $false
                try { 
                    Write-Host 'Getting server version'
                    $AgentPage = $Script:LTServiceNetWebClient.DownloadString("$($Config.Server)/labtech/agent.aspx")
                    $ServerVersion = $AgentPage.Split('|')[6]
                    
                    if ([System.Version]$AgentInfo.Version -lt [System.Version]$ServerVersion) {
                        $UpdateNeeded = $true
                    }
                }
                catch {
                    Write-Host "Update check failed: $($_.Exception.Message)"
                }

                # Run updates
                if ($UpdateNeeded) {
                    Write-Host 'Updates are needed'
                    if ((!$OnDemandActions -and $Config.Updates) -or $OnDemandActions.UpdateNow) {
                        Write-Host 'Starting update...'
                        taskkill /im ltsvc.exe /f
                        taskkill /im ltsvcmon.exe /f
                        taskkill /im lttray.exe /f
                        Try {
                            Update-CWAA
                            Start-Sleep -Seconds 30
                            Try { Restart-CWAA -Confirm:$false } Catch {}
                            Invoke-CWAACommand -Command 'Send Status'
                            Start-Sleep -Seconds 30
                            $UpdateInfo = Get-CWAAInfo
                        
                            if ([version]$UpdateInfo.Version -gt [version]$AgentInfo.Version ) {
                                $UpdateText = 'Updated from {1} to {0}' -f $AgentInfo.Version, $UpdateInfo.Version
                            }
                            else {
                                $UpdateText = 'Error updating, still on {0}' -f $AgentInfo.Version
                            }
                        }
                        Catch {
                            $UpdateText = 'Error: Update-CWAA failed to run'
                        }
                    }
                    else {
                        $UpdateText = 'Version {0} is available and not installed' -f $ServerVersion
                    }
                }
                else {
                    $UpdateText = 'No update required'
                }

                # Get checkin / heartbeat times to DateTime
                Write-Host 'Getting check-in times'
                $LastSuccess = try { Get-Date $AgentInfo.LastSuccessStatus } catch { $null }
                $LastHBSent = try { Get-Date $AgentInfo.HeartbeatLastSent } catch { $null }
                $LastHBRcv = try { Get-Date $AgentInfo.HeartbeatLastReceived } catch { $null }

                # Check online and heartbeat statuses
                $OnlineThreshold = (Get-Date).AddMinutes(-5)
                $Online = $LastSuccess -ge $OnlineThreshold
                $HeartbeatRcv = $LastHBRcv -ge $OnlineThreshold 
                $HeartbeatSnd = $LastHBSent -ge $OnlineThreshold
                $HeartbeatStatus = $HeartbeatRcv -or $HeartbeatSnd

                Write-Host 'Writing status to file'
                $Status = [PSCustomObject]@{
                    Server          = $AgentInfo.Server | Select-Object -First 1
                    ClientID        = $AgentInfo.ClientID
                    LocationID      = $AgentInfo.LocationID
                    AgentID         = $AgentInfo.ID
                    Online          = $Online
                    Healthy         = $Healthy
                    LastContact     = $LastSuccess
                    HeartbeatSent   = $LastHBSent
                    HeartbeatRecv   = $LastHBRcv
                    HeartbeatStatus = $HeartbeatStatus
                    AgentVersion    = $AgentInfo.Version
                    ServerVersion   = $ServerVersion
                    UpdateNeeded    = $UpdateNeeded
                    UpdateText      = $UpdateText
                    ServiceInfo     = $ServiceInfo
                    LastRun         = $Started
                }

                $Status | ConvertTo-Json | Out-File -FilePath $StatusFile
            }
            catch {
                Write-Host "Exception: $($_.Exception.Message)"
            }
            finally {
                Write-Host 'Done.'
                if (Test-Path $RunningFile) { Remove-Item $RunningFile }
                Stop-Transcript
            }
        }
        'OutputResults' {
            if (Test-Path -Path $DiagnosticLog) {
                $LogMessages = Get-Content -Path $DiagnosticLog
                $Logs = foreach ($LogMessage in $LogMessages) {
                    $LogMessage.ToString()
                }
            }
            
            if (Test-Path $RunningFile) {
                $Message = 'Diagnostics are currently running...'
            }

            if (Test-Path -Path $StatusFile) {
                $Status = Get-Content -Path $StatusFile | ConvertFrom-Json
            }
            else {
                if (-not (Test-Path -Path $DiagnosticLog)) { 
                    $Message = 'Diagnostics have not yet run' 
                }
            }
            $CWAErrors = Get-CWAAError | Select-Object -Last 30
            $TestErrors = Test-AutomateDiagnosticsErrors

            $Results = [PSCustomObject]@{
                Status     = $Status
                Message    = $Message
                Logs       = $Logs
                CWAErrors  = $CWAErrors
                TestErrors = $TestErrors
            }

            if ($AsJson.IsPresent) {
                $Results | ConvertTo-Json -Depth 10
            }
            else {
                $Results                
            }
        }
        'OnDemand' {
            [PSCustomObject]@{
                UpdateNow = $UpdateAgent.IsPresent
            } | ConvertTo-Json | Out-File -FilePath $OnDemandFile
            
            $Task | Start-ScheduledTask
            [PSCustomObject]@{ 
                Message = 'Diagnostics started...'
            }
        }
    }
}