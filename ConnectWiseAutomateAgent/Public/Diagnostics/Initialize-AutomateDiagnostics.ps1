function Initialize-AutomateDiagnostics {
    [cmdletbinding(DefaultParameterSetName = 'SetServer')]
    Param(
        [Parameter(ParameterSetName = 'SetServer', Mandatory = $true)]
        $Server,

        [Parameter(ParameterSetName = 'SetServer')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$LocationID = 1,

        [Parameter(ParameterSetName = 'UseDefault')]
        [switch]$UseAgentSettings,

        [Parameter(ParameterSetName = 'UseConfig')]
        [switch]$UseConfig,

        [switch]$EnableUpdates,

        [ValidateSet('Daily', 'Network', 'Startup')]
        [string[]]$TaskTriggers,

        [string]$DailyAt = '12pm',
        [string]$RandomDelayMinutes = 30
    )
    
    Begin {
        if ($UseAgentSettings) {
            $Info = Get-CWAAInfo
            $Server = $Info.Server | Select-Object -First 1
            $LocationID = $Info.LocationID
        }

        $DiagnosticsPath = Join-Path $env:ProgramData '\AutomateDiagnostics'
        $ConfigFile = "$DiagnosticsPath\config.json"

        if (-not (Test-Path $DiagnosticsPath)) {
            New-Item -ItemType Directory -Path $DiagnosticsPath | Out-Null
        }

        try {
            $Response = Invoke-WebRequest -UseBasicParsing -Uri "$Server/LabTech/agent.aspx"
            Write-Verbose $Response
        }
        catch {
            Write-Error "Exception connecting to $Server - $($_.Exception.Message)"
            return $false
        }
    }

    Process {
        $SetConfig = $true
        if ($UseConfig.IsPresent) {
            if (Test-Path -Path $ConfigFile) {
                $SetConfig = $false
            }
            else {
                Write-Error 'Configuration does not exist'
                return $false
            }
        }

        if ($SetConfig) {
            Write-Verbose 'Setting configuration file'
            [PSCustomObject]@{
                Server     = $Server
                LocationID = $LocationID
                Updates    = $EnableUpdates.IsPresent
            } | ConvertTo-Json | Out-File $ConfigFile -Force
        }

        Write-Verbose 'Setting scheduled task'
        $SchTask = @{
            TaskName = 'CW Automate Diagnostics'
            TaskPath = '\'
        }
        $ExistingTask = Get-ScheduledTask @SchTask -ErrorAction SilentlyContinue

        if ($ExistingTask) { 
            Write-Verbose 'Removing existing scheduled task'
            Unregister-ScheduledTask @SchTask -Confirm:$false 
        }

        $Triggers = [System.Collections.Generic.List[object]]::new()

        # Daily trigger
        if ($TaskTriggers -contains 'Daily') {
            Write-Verbose 'Adding Daily trigger'
            $DelaySpan = New-TimeSpan -Minutes $RandomDelayMinutes
            $Trigger = New-ScheduledTaskTrigger -Daily -At $DailyAt -RandomDelay $DelaySpan
            $Triggers.Add($Trigger) | Out-Null
        }

        # Network trigger
        if ($TaskTriggers -contains 'Network') {
            Write-Verbose 'Adding Network connection trigger'
            # Create ScheduledTask trigger for network connection events
            $Class = Get-CimClass MSFT_TaskEventTrigger root/Microsoft/Windows/TaskScheduler
            $Trigger = $Class | New-CimInstance -ClientOnly
            $Trigger.Enabled = $true
            $Trigger.Subscription = @'
<QueryList><Query Id="0" Path="Microsoft-Windows-NetworkProfile/Operational"><Select Path="Microsoft-Windows-NetworkProfile/Operational">*[System[Provider[@Name='Microsoft-Windows-NetworkProfile'] and EventID=10000]]</Select></Query></QueryList>
'@          
            $Triggers.Add($Trigger) | Out-Null
        }

        # Startup trigger
        if ($TaskTriggers -contains 'Startup') {
            Write-Verbose 'Adding Startup trigger'
            $Trigger = New-ScheduledTaskTrigger -AtStartup
            $Triggers.Add($Trigger) | Out-Null
        }

        $ActionParameters = @{
            Execute  = 'C:\Windows\system32\WindowsPowerShell\v1.0\powershell.exe'
            Argument = "-NoProfile -ExecutionPolicy Bypass -Command `"& { Import-Module ConnectWiseAutomateAgent; Invoke-AutomateDiagnostics }`""
        }

        $Action = New-ScheduledTaskAction @ActionParameters
        $Principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount
        $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries DontStopOnIdleEnd
        
        $RegSchTaskParameters = @{
            TaskName    = $TaskName
            Description = 'Runs Automate Diagnostics'
            TaskPath    = $TaskPath
            Action      = $Action
            Principal   = $Principal
            Settings    = $Settings
            Trigger     = $Triggers
        }
        Write-Verbose 'Creating scheduled task'
        Write-Verbose $RegSchTaskParameters

        $Task = Register-ScheduledTask @RegSchTaskParameters
        if ($Task.State -eq 'Ready') {
            Write-Host "Task '$TaskName' created successfully"
        }
        else {
            Write-Error 'Task creation failed'
        }
    }

    End {
        Write-Host 'Configuration set'
    }
}