param(
    [string]$CertificateFile = "MyApp-cert.cer",
    [string]$PackageFile,
    [string]$LogFile = "Install.log",
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Elevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin) {
        return
    }

    Write-Host "Restarting with administrator rights..."
    $scriptPath = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        $scriptPath = $MyInvocation.PSCommandPath
    }
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        throw "Unable to determine installer script path for elevation restart."
    }

    $argumentList = @(
        "-ExecutionPolicy", "Bypass",
        "-File", $scriptPath,
        "-CertificateFile", $CertificateFile,
        "-LogFile", $LogFile
    )

    if (-not [string]::IsNullOrWhiteSpace($PackageFile)) {
        $argumentList += @("-PackageFile", $PackageFile)
    }

    if ($NoPause) {
        $argumentList += "-NoPause"
    }

    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argumentList | Out-Null
    exit
}

function Resolve-RequiredFile {
    param(
        [string]$FileName,
        [string]$Label
    )

    $filePath = Join-Path $PSScriptRoot $FileName
    if (-not (Test-Path $filePath)) {
        throw "$Label not found: $filePath"
    }

    return $filePath
}

function Resolve-PackageFile {
    param([string]$ExplicitPackageFile)

    if ($ExplicitPackageFile) {
        return Resolve-RequiredFile -FileName $ExplicitPackageFile -Label "MSIX package"
    }

    $packageCandidates = @(Get-ChildItem -Path $PSScriptRoot -Filter "*.msix" -File)
    if ($packageCandidates.Count -eq 0) {
        throw "MSIX package not found in $PSScriptRoot"
    }

    if ($packageCandidates.Count -gt 1) {
        throw "Multiple MSIX packages found. Pass -PackageFile explicitly."
    }

    return $packageCandidates[0].FullName
}

function Ensure-CertificateInstalled {
    param(
        [string]$CertificatePath,
        [string]$StorePath
    )

    $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertificatePath)
    $existing = Get-ChildItem -Path $StorePath -ErrorAction SilentlyContinue |
    Where-Object { $_.Thumbprint -eq $certificate.Thumbprint } |
    Select-Object -First 1

    if (-not $existing) {
        Import-Certificate -FilePath $CertificatePath -CertStoreLocation $StorePath | Out-Null
        Write-Host "Installed certificate in $StorePath"
    }
    else {
        Write-Host "Certificate already present in $StorePath"
    }
}

Ensure-Elevated

$logPath = Join-Path $PSScriptRoot $LogFile
$transcriptStarted = $false

try {
    Start-Transcript -Path $logPath -Append -ErrorAction Stop | Out-Null
    $transcriptStarted = $true
}
catch {
    Write-Host "Warning: Could not start transcript log at $logPath"
}

try {
    $certPath = Resolve-RequiredFile -FileName $CertificateFile -Label "Certificate file"
    $msixPath = Resolve-PackageFile -ExplicitPackageFile $PackageFile

    Write-Host "Installing certificate trust chain..."
    Ensure-CertificateInstalled -CertificatePath $certPath -StorePath "Cert:\LocalMachine\TrustedPeople"
    Ensure-CertificateInstalled -CertificatePath $certPath -StorePath "Cert:\LocalMachine\Root"

    Write-Host "Installing application package..."
    Add-AppxPackage -Path $msixPath -ForceApplicationShutdown

    Write-Host "Install completed successfully. Open Start menu and launch MyApp."
}
catch {
    Write-Host "Installation failed: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
        Write-Host "Installer log: $logPath"
    }

    if (-not $NoPause) {
        try {
            Read-Host "Press Enter to close"
        }
        catch {
            # Ignore pause errors in non-interactive hosts.
        }
    }
}
