# Version: 1.0.0. Run in 64-bit Windows PowerShell 5.1 as Administrator (Windows 10 1809+).
# Installs Git and Microsoft Win32-OpenSSH directly; no winget or Windows Update required.
# Opens inbound TCP 22 and sets Git Bash as the SSH default shell.
# Sources: https://github.com/PowerShell/Win32-OpenSSH/wiki/Install-Win32-OpenSSH-Using-MSI
# https://gitforwindows.org/ (official Git installer)
& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run 64-bit Windows PowerShell as Administrator.'
    }
    $os = Get-CimInstance Win32_OperatingSystem
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt 17763 -or [int]$os.BuildNumber -ge 22000) {
        throw 'This installer supports Windows 10 version 1809 or later. Use install-ssh.ps1 on Windows 11.'
    }
    if (-not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
        throw 'This installer requires x64 Windows and 64-bit PowerShell; ARM and x86 are not supported.'
    }

    function Install-SignedPackage {
        param([string]$Url, [string]$Path, [string]$Arguments, [switch]$Msi)
        Write-Host "Downloading $(Split-Path $Path -Leaf)..."
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Path
        if ((Get-AuthenticodeSignature -FilePath $Path).Status -ne 'Valid') {
            throw "Installer signature verification failed: $Path. Nothing from this package was executed."
        }
        if ($Msi) {
            $process = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList "/i `"$Path`" $Arguments" -Wait -PassThru
        } else {
            $process = Start-Process -FilePath $Path -ArgumentList $Arguments -Wait -PassThru
        }
        if ($process.ExitCode -in @(3010, 1641)) { throw 'Installation requires a reboot. Restart Windows, then run this script again.' }
        if ($process.ExitCode -ne 0) { throw "Installer failed with exit code $($process.ExitCode). See logs in $(Split-Path $Path)." }
    }

    $work = Join-Path $env:TEMP "install-ssh-win10-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $work | Out-Null
    $previousTls = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = $previousTls -bor [Net.SecurityProtocolType]::Tls12
        $gitDir = Join-Path $env:ProgramFiles 'Git'
        $bash = Join-Path $gitDir 'bin\bash.exe'
        if (-not (Test-Path -LiteralPath $bash)) {
            Install-SignedPackage -Url 'https://github.com/git-for-windows/git/releases/download/v2.56.0.windows.1/Git-2.56.0-64-bit.exe' -Path "$work\git.exe" -Arguments "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /ALLUSERS /DIR=`"$gitDir`" /LOG=`"$work\git.log`""
        }
        if (-not (Test-Path -LiteralPath $bash)) { throw "Git installation did not create $bash." }
        & $bash --version
        if ($LASTEXITCODE -ne 0) { throw 'Git Bash failed its startup check.' }

        if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) {
            # Microsoft's GitHub MSI is labelled Preview; this bypasses the failing DISM path.
            Install-SignedPackage -Url 'https://github.com/PowerShell/Win32-OpenSSH/releases/download/10.0.0.0p2-Preview/OpenSSH-Win64-v10.0.0.0.msi' -Path "$work\openssh.msi" -Msi -Arguments "/qn /norestart ADDLOCAL=Server /L*v `"$work\openssh.log`""
            $sshDir = Join-Path $env:ProgramFiles 'OpenSSH'
            $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
            if ($machinePath.Split(';') -notcontains $sshDir) {
                [Environment]::SetEnvironmentVariable('Path', "$machinePath;$sshDir", 'Machine')
            }
        }
        $service = Get-Service sshd
        New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null
        New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value $bash -PropertyType String -Force | Out-Null
        New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShellCommandOption -Value '-c' -PropertyType String -Force | Out-Null
        if (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue) {
            Enable-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'
        } else {
            New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
        }
        Set-Service sshd -StartupType Automatic
        if ($service.Status -eq 'Running') { Restart-Service sshd } else { Start-Service sshd }
        (Get-Service sshd).WaitForStatus('Running', [TimeSpan]::FromSeconds(15))
        if (-not (Test-NetConnection -ComputerName 127.0.0.1 -Port 22 -InformationLevel Quiet)) {
            throw 'sshd started, but local TCP port 22 is not reachable. Check sshd_config and firewall policy.'
        }
        Remove-Item -LiteralPath $work -Recurse -Force
        Write-Host 'Verified: SSH service is running, TCP 22 is reachable locally, and Git Bash is configured.'
        Write-Host 'Remote access still depends on network/firewall policy. Use setup-windows-ssh.sh on Linux to install your key.'
    } catch {
        throw "SSH setup failed: $($_.Exception.Message) Logs/downloads retained in $work."
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $previousTls
    }
}
