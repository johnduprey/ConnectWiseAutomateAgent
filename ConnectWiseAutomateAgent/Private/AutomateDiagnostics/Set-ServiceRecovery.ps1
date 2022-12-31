function Set-ServiceRecovery {
    Param (
        [string] [Parameter(Mandatory = $true)] $ServiceName,
        [string] $action1 = 'restart',
        [int] $time1 = 30000, # in miliseconds
        [string] $action2 = 'restart',
        [int] $time2 = 30000, # in miliseconds
        [string] $actionLast = 'restart',
        [int] $timeLast = 30000, # in miliseconds
        [int] $resetCounter = 4000 # in seconds
    )
    $serverPath = '\\' + $server
    $services = Get-CimInstance -ClassName 'Win32_Service' | Where-Object { $_.ServiceName -imatch $ServiceName }
    $action = $action1 + '/' + $time1 + '/' + $action2 + '/' + $time2 + '/' + $actionLast + '/' + $timeLast
    foreach ($service in $services) {
        # https://technet.microsoft.com/en-us/library/cc742019.aspx
        $output = sc.exe $serverPath failure $($service.Name) actions= $action reset= $resetCounter
    }
}