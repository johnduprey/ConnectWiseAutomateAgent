function Get-ServiceDetails {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$Service
    )
    Write-Verbose "Checking $service"
    Try {
        $svc_info = Get-WmiObject win32_service | Where-Object { $_.name -imatch $service }
        if ($null -ne $svc_info.State) { @{'Status' = $svc_info.State; 'Start Mode' = $svc_info.StartMode; 'User' = $svc_info.StartName } }
        else { @{'Status' = 'Not Detected'; 'Start Mode' = ''; 'User' = '' } }
    }
    Catch {
        Write-Verbose $Error[0].exception.GetType().fullname
        @{'Status' = 'WMI Error'; 'Start Mode' = ''; 'User' = '' }
    }
}