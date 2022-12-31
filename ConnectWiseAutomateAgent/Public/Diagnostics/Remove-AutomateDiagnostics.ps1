function Remove-AutomateDiagnostics {
    [cmdletbinding()]
    Param()
    $TaskName = 'CW Automate Diagnostics'
    $TaskPath = '\'

    $Task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue

    if ($Task) { 
        Write-Verbose 'Removing existing scheduled task'
        $Task | Unregister-ScheduledTask -Confirm $false 
    }
}