function Read-MsiProperties {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$MsiPath
    )

    if (Test-Path $MsiPath) {
        try {
            $MsiFile = (Get-Item $MsiPath).FullName

            $WindowsInstaller = New-Object -ComObject WindowsInstaller.Installer
            $MSIDatabase = $WindowsInstaller.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $Null, $WindowsInstaller, @($MsiFile, 0))
            $Query = 'SELECT * FROM Property'
            $View = $MSIDatabase.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $MSIDatabase, ($Query))
            $View.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $View, $null)

            $hash = @{}
            while ($Record = $View.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $View, $null)) {
                $name = $Record.GetType().InvokeMember('StringData', 'GetProperty', $null, $Record, 1)
                $value = $Record.GetType().InvokeMember('StringData', 'GetProperty', $null, $Record, 2)
                $hash.Add($name, $value)
            }
            [pscustomobject]$hash
           
            $MSIDatabase.GetType().InvokeMember('Commit', 'InvokeMethod', $null, $MSIDatabase, $null)
            $View.GetType().InvokeMember('Close', 'InvokeMethod', $null, $View, $null)   
            $MSIDatabase = $null
            $View = $Null        
        }
        catch {
            Write-Error ('Unable to retrieve MSI properties: {0}' -f $_.Exception.Message)
        }
        finally {
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($WindowsInstaller) | Out-Null
            [System.GC]::Collect()
        }
    }
    else {
        Write-Error 'MSI path does not exist'
    }
}
