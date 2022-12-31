function Test-AutomateDiagnosticsErrors {
    [cmdletbinding()]
    Param()

    $TestErrors = [PSCustomObject]@{
        Crypto         = $false
        Janus          = $false
        Signup         = $false
        ServerPassword = $false
    }

    try {
        $AgentErrors = Get-CWAAError
        $ServerPassword = ConvertFrom-CWAASecurity (Get-ItemProperty hklm:\software\labtech\service).ServerPassword
        foreach ($AgentError in $AgentErrors) {
            $TestErrors.Crypto = ($AgentError.Message -match 'Unable to initialize remote agent security')
            $TestErrors.Janus = ($AgentError.Message -match 'Janus enabled')
            $TestErrors.Signup = ($AgentError.Message -match 'Failed Signup')
            $TestErrors.ServerPassword = ($ServerPassword -eq 'Enter the server password here.')
        }
    }
    catch {
        Write-Error 'Unable to get agent errors'
    }
    finally {
        $TestErrors
    }
}