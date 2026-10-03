# Mocked installer tests: no downloads, services, registry or firewall changes.
$ErrorActionPreference = 'Stop'
$source = Get-Content (Join-Path $PSScriptRoot '..\install-ssh-win10.ps1') -Raw
$tokens = $null; $errors = $null
[void][Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
# Exercise installation orchestration without Windows-only preflight or native Bash.
$body = $source.Substring($source.IndexOf('    function Install-SignedPackage')).TrimEnd()
$body = $body.Substring(0, $body.Length - 1).Replace('& $bash --version', 'Invoke-MockBash')
$body = $body.Replace("[Environment]::GetEnvironmentVariable('Path', 'Machine')", "'/programs/OpenSSH'")
$installer = [scriptblock]::Create($body)
$env:TEMP = '/tmp'; $env:ProgramFiles = '/programs'; $env:SystemRoot = '/windows'
$script:passed = 0
function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }; $script:passed++
}
function Reset {
    $script:git = $false; $script:ssh = $false; $script:signature = 'Valid'
    $script:exitCode = 0; $script:downloadFailure = $false; $script:port = $true
    $script:bashCode = 0; $script:firewall = $false; $script:events = @(); $script:messages = @()
}
function Write-Host { param($Object) $script:messages += [string]$Object }
function New-Item { param($Path, $ItemType, [switch]$Force) }
function Test-Path { param($LiteralPath) return $script:git }
function Invoke-WebRequest {
    param($Uri, $OutFile, [switch]$UseBasicParsing)
    $script:events += 'download'
    if ($script:downloadFailure) { throw 'Mock download failure' }
}
function Get-AuthenticodeSignature { param($FilePath) return @{ Status = $script:signature } }
function Start-Process {
    param($FilePath, $ArgumentList, [switch]$Wait, [switch]$PassThru)
    $script:events += 'execute'
    if ($script:exitCode -eq 0) {
        if ($FilePath -like '*msiexec.exe') { $script:ssh = $true } else { $script:git = $true }
    }
    return @{ ExitCode = $script:exitCode }
}
function Invoke-MockBash { $global:LASTEXITCODE = $script:bashCode }
function Get-Service {
    param($Name, $ErrorAction)
    if ($script:ssh) {
        $service = [pscustomobject]@{ Status = 'Running' }
        $service | Add-Member ScriptMethod WaitForStatus { param($Status, $Timeout) }
        return $service
    }
    if ($ErrorAction -eq 'SilentlyContinue') { return }
    throw 'Mock missing sshd service'
}
function New-ItemProperty { param($Path, $Name, $Value, $PropertyType, [switch]$Force) $script:events += 'registry' }
function Get-NetFirewallRule { param($Name, $ErrorAction) if ($script:firewall) { return @{ Name = $Name } } }
function New-NetFirewallRule { param($Name, $DisplayName, $Enabled, $Direction, $Protocol, $Action, $LocalPort) $script:events += 'firewall-create' }
function Enable-NetFirewallRule { param($Name) $script:events += 'firewall-enable' }
function Set-Service { param($Name, $StartupType) $script:events += 'service' }
function Restart-Service { param($Name) }
function Start-Service { param($Name) }
function Test-NetConnection { param($ComputerName, $Port, $InformationLevel) return $script:port }
function Remove-Item { param($LiteralPath, [switch]$Recurse, [switch]$Force) $script:events += 'cleanup' }
# Exercise the actual OS/architecture gate with mocked Windows version data.
$preflightStart = $source.IndexOf('    $os = Get-CimInstance')
$preflight = [scriptblock]::Create($source.Substring($preflightStart, $source.IndexOf('    function Install-SignedPackage') - $preflightStart))
function Get-CimInstance {
    param($ClassName)
    return @{ Caption = 'Mock Windows'; Version = $script:osVersion; BuildNumber = $script:build; ProductType = $script:productType }
}
$oldArchitecture = $env:PROCESSOR_ARCHITECTURE
try {
    $env:PROCESSOR_ARCHITECTURE = 'AMD64'
    foreach ($case in @(
        @{ build = 16299; version = '10.0.16299'; type = 1; allowed = $true },
        @{ build = 17763; version = '10.0.17763'; type = 1; allowed = $true },
        @{ build = 19045; version = '10.0.19045'; type = 1; allowed = $true },
        @{ build = 22000; version = '10.0.22000'; type = 1; allowed = $false },
        @{ build = 9600; version = '6.3.9600'; type = 1; allowed = $false },
        @{ build = 17763; version = '10.0.17763'; type = 3; allowed = $false }
    )) {
        $script:build = $case.build; $script:osVersion = $case.version; $script:productType = $case.type
        $threw = $false
        try { & $preflight } catch {
            $threw = $true
            Assert ($_.Exception.Message -match [string]$case.build) 'Rejection must identify detected build'
        }
        Assert ($threw -eq (-not $case.allowed)) "OS gate for build $($case.build), product type $($case.type)"
    }
} finally { $env:PROCESSOR_ARCHITECTURE = $oldArchitecture }

# Mocked machine PATH already contains OpenSSH; no real environment changes.
& {
    Reset
    & $installer
    Assert (($script:events | Where-Object { $_ -eq 'execute' }).Count -eq 2) 'Clean install runs both signed installers'
    Assert ($script:messages -match '^Verified:') 'Success only after checks'
    Assert ($script:events -contains 'firewall-create' -and $script:events -contains 'cleanup') 'Firewall and successful cleanup'
    Reset; $script:git = $true; $script:ssh = $true; $script:firewall = $true
    & $installer
    Assert ($script:events -notcontains 'download') 'Repeat run reuses existing installations'
    Assert ($script:events -contains 'firewall-enable') 'Existing firewall rule enabled'
    foreach ($case in @('signature', 'download', 'installer', 'reboot', 'bash', 'port')) {
        Reset
        switch ($case) {
            signature { $script:signature = 'NotSigned' }
            download { $script:downloadFailure = $true }
            installer { $script:exitCode = 1603 }
            reboot { $script:exitCode = 3010 }
            bash { $script:git = $true; $script:bashCode = 1 }
            port { $script:git = $true; $script:ssh = $true; $script:port = $false }
        }
        $tls = [Net.ServicePointManager]::SecurityProtocol
        $threw = $false
        try { & $installer } catch { $threw = $true }
        Assert $threw "$case must stop installation"
        Assert (-not ($script:messages -match '^Verified:')) "$case must not report success"
        Assert ($script:events -notcontains 'cleanup') "$case must retain diagnostics"
        Assert ([Net.ServicePointManager]::SecurityProtocol -eq $tls) 'TLS settings restored'
        if ($case -in @('signature', 'download')) {
            Assert ($script:events -notcontains 'execute') 'Unverified package must not execute'
        }
    }
}
Write-Output "Passed $script:passed assertions"
