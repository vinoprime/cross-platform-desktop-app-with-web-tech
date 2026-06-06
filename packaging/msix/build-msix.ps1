param(
    [string]$Version = "1.0.0.0",
    [string]$PackageName = "DesktopHost",
    [string]$DisplayName = "MyApp",
    [string]$Publisher = "CN=ViRa",
    [string]$Architecture = "x64",
    [switch]$SkipSign,
    [string]$CertPassword = "MyAppDevCert!"

)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"


function Get-ToolPath {
    param([string]$ToolName)


    $command = Get-Command $ToolName -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $kitsPaths = @(
        (Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"),
        (Join-Path ${env:ProgramFiles} "Windows Kits\10\bin")
    )


    foreach ($kitsPath in $kitsPaths) {
        if (-not (Test-Path $kitsPath)) {
            continue
        }

        $tool = Get-ChildItem -Path $kitsPath -Directory |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName ("x64\{0}.exe" -f $ToolName) } |
        Where-Object { Test-Path $_ } |
        Select-Object -First 1

        if ($tool) {
            return $tool
        }
    }

    throw "Required tool '$ToolName' was not found. Install Windows 10/11 SDK to get makeappx.exe and signtool.exe."
}

function New-PngAsset {
    param(
        [string]$Path,
        [int]$Width,
        [int]$Height,
        [string]$Label,
        [string]$BackgroundColor = "#BB5C2D",
        [string]$ForegroundColor = "#FFF7F0"
    )

    Add-Type -AssemblyName System.Drawing

    $bitmap = New-Object System.Drawing.Bitmap $Width, $Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $backgroundBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($BackgroundColor))
    $foregroundBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($ForegroundColor))
    $borderPen = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml("#E39E63"), [Math]::Max(2, [int]($Width * 0.04)))
    $fontSize = [Math]::Max(14, [int]([Math]::Min($Width, $Height) * 0.34))
    $font = New-Object System.Drawing.Font("Segoe UI", $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $textFormat = New-Object System.Drawing.StringFormat
    $textFormat.Alignment = [System.Drawing.StringAlignment]::Center
    $textFormat.LineAlignment = [System.Drawing.StringAlignment]::Center

    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.FillRectangle($backgroundBrush, 0, 0, $Width, $Height)

        $circleSize = [Math]::Min($Width, $Height) * 0.72
        $circleX = ($Width - $circleSize) / 2
        $circleY = ($Height - $circleSize) / 2
        $graphics.FillEllipse($foregroundBrush, $circleX, $circleY, $circleSize, $circleSize)
        $graphics.DrawEllipse($borderPen, $circleX, $circleY, $circleSize, $circleSize)

        $labelBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($BackgroundColor))
        try {
            $textBounds = New-Object System.Drawing.RectangleF -ArgumentList @([single]0, [single]0, [single]$Width, [single]$Height)
            $graphics.DrawString($Label, $font, $labelBrush, $textBounds, $textFormat)
        }
        finally {
            $labelBrush.Dispose()
        }

        $parentDir = Split-Path -Path $Path -Parent
        if (-not (Test-Path $parentDir)) {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        }

        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $textFormat.Dispose()
        $font.Dispose()
        $borderPen.Dispose()
        $foregroundBrush.Dispose()
        $backgroundBrush.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Get-IdentityName {
    param([string]$Name)

    $identityName = ($Name -replace "[^A-Za-z0-9\.]", "").Trim('.')
    if ([string]::IsNullOrWhiteSpace($identityName)) {
        throw "PackageName '$Name' does not produce a valid MSIX identity name."
    }

    return $identityName
}

function Get-PublisherDisplayName {
    param([string]$PublisherName)

    if ($PublisherName -match "CN=([^,]+)") {
        return $matches[1]
    }

    return $PublisherName
}

function Escape-Xml {
    param([string]$Value)

    return [System.Security.SecurityElement]::Escape($Value)
}

function New-AppxManifest {
    param(
        [string]$Path,
        [string]$IdentityName,
        [string]$PublisherName,
        [string]$PackageVersion,
        [string]$PackageArchitecture,
        [string]$AppDisplayName,
        [string]$PublisherDisplayName,
        [string]$ExecutableName
    )

    $manifestXml = @"
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
    xmlns:desktop="http://schemas.microsoft.com/appx/manifest/desktop/windows10"
    xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
    IgnorableNamespaces="uap desktop rescap">
  <Identity Name="$(Escape-Xml $IdentityName)" Publisher="$(Escape-Xml $PublisherName)" Version="$(Escape-Xml $PackageVersion)" ProcessorArchitecture="$(Escape-Xml $PackageArchitecture)" />
  <Properties>
    <DisplayName>$(Escape-Xml $AppDisplayName)</DisplayName>
    <PublisherDisplayName>$(Escape-Xml $PublisherDisplayName)</PublisherDisplayName>
    <Description>$(Escape-Xml $AppDisplayName)</Description>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.22621.0" />
  </Dependencies>
  <Resources>
    <Resource Language="en-us" />
  </Resources>
    <Capabilities>
        <rescap:Capability Name="runFullTrust" />
    </Capabilities>
  <Applications>
    <Application Id="App" Executable="$(Escape-Xml $ExecutableName)" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements
        DisplayName="$(Escape-Xml $AppDisplayName)"
        Description="$(Escape-Xml $AppDisplayName)"
        BackgroundColor="#FFF9F2"
        Square150x150Logo="Assets\Square150x150Logo.png"
        Square44x44Logo="Assets\Square44x44Logo.png">
        <uap:DefaultTile
          Wide310x150Logo="Assets\Wide310x150Logo.png"
          Square310x310Logo="Assets\LargeTile.png" />
        <uap:SplashScreen Image="Assets\SplashScreen.png" BackgroundColor="#FFF9F2" />
      </uap:VisualElements>
      <Extensions>
                <desktop:Extension Category="windows.fullTrustProcess" Executable="$(Escape-Xml $ExecutableName)" />
      </Extensions>
    </Application>
  </Applications>
</Package>
"@

    Set-Content -Path $Path -Value $manifestXml -Encoding UTF8
}

function New-AppAssets {
    param(
        [string]$AssetsPath,
        [string]$AppDisplayName
    )

    $labelChars = ($AppDisplayName -replace "[^A-Za-z0-9]", "")
    if ([string]::IsNullOrWhiteSpace($labelChars)) {
        $labelChars = "APP"
    }

    $label = $labelChars.Substring(0, [Math]::Min(2, $labelChars.Length)).ToUpperInvariant()

    New-PngAsset -Path (Join-Path $AssetsPath "StoreLogo.png") -Width 50 -Height 50 -Label $label
    New-PngAsset -Path (Join-Path $AssetsPath "Square44x44Logo.png") -Width 44 -Height 44 -Label $label
    New-PngAsset -Path (Join-Path $AssetsPath "Square150x150Logo.png") -Width 150 -Height 150 -Label $label
    New-PngAsset -Path (Join-Path $AssetsPath "Wide310x150Logo.png") -Width 310 -Height 150 -Label $label
    New-PngAsset -Path (Join-Path $AssetsPath "LargeTile.png") -Width 310 -Height 310 -Label $label
    New-PngAsset -Path (Join-Path $AssetsPath "SplashScreen.png") -Width 620 -Height 300 -Label $label
}

function Get-OrCreateDevCertificate {
    param(
        [string]$PublisherName,
        [string]$PfxPath,
        [string]$CerPath,
        [string]$Password
    )

    if ((Test-Path $PfxPath) -and (Test-Path $CerPath)) {
        return
    }

    $existingCert = Get-ChildItem -Path Cert:\CurrentUser\My |
    Where-Object { $_.Subject -eq $PublisherName } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1

    if (-not $existingCert) {
        $existingCert = New-SelfSignedCertificate -Type CodeSigningCert `
            -Subject $PublisherName `
            -CertStoreLocation "Cert:\CurrentUser\My" `
            -KeyExportPolicy Exportable `
            -HashAlgorithm "SHA256" `
            -KeyAlgorithm "RSA" `
            -KeyLength 2048 `
            -NotAfter (Get-Date).AddYears(3)
    }

    $securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
    Export-PfxCertificate -Cert $existingCert -FilePath $PfxPath -Password $securePassword | Out-Null
    Export-Certificate -Cert $existingCert -FilePath $CerPath | Out-Null
}

function Invoke-NativeCommand {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $FilePath $($Arguments -join ' ')"
    }
}


$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$webAppRoot = Join-Path $repoRoot "web-app"
$hostProject = Join-Path $repoRoot "DesktopHost\DesktopHost\DesktopHost.csproj"

# Auto-detect version from web-app/package.json when the caller has not pinned a version.
# After resolving major.minor.patch from package.json, the 4th build segment is auto-incremented
# by scanning existing MSIX artifacts so every build produces a unique, monotonically increasing version.
if ($Version -eq "1.0.0.0") {
    $pkgJsonPath = Join-Path $webAppRoot "package.json"
    if (Test-Path $pkgJsonPath) {
        $pkgVersion = (Get-Content $pkgJsonPath -Raw | ConvertFrom-Json).version
        if ($pkgVersion -match '^(\d+)\.(\d+)\.(\d+)') {
            $majorMinorPatch = "{0}.{1}.{2}" -f $Matches[1], $Matches[2], $Matches[3]

            # Find the highest build number already used for this major.minor.patch in the msix output folder.
            $existingMsixRoot = Join-Path $repoRoot "artifacts\msix"
            $highestBuild = -1
            if (Test-Path $existingMsixRoot) {
                Get-ChildItem -Path $existingMsixRoot -Filter "*.msix" -File |
                Where-Object { $_.Name -match "^$([regex]::Escape($PackageName))_$([regex]::Escape($majorMinorPatch))\.(\d+)_" } |
                ForEach-Object {
                    if ($_.Name -match "$([regex]::Escape($majorMinorPatch))\.(\d+)_") {
                        $build = [int]$Matches[1]
                        if ($build -gt $highestBuild) { $highestBuild = $build }
                    }
                }
            }

            $nextBuild = $highestBuild + 1
            $Version = "{0}.{1}" -f $majorMinorPatch, $nextBuild
        }
    }
}
Write-Host "Package version: $Version"

$artifactRoot = Join-Path $repoRoot "artifacts"
$publishRoot = Join-Path $artifactRoot "desktop"
$msixRoot = Join-Path $artifactRoot "msix"
$distRoot = Join-Path $artifactRoot "dist"
$layoutRoot = Join-Path $msixRoot "layout"
$assetsRoot = Join-Path $layoutRoot "Assets"


$packageFile = Join-Path $msixRoot ("{0}_{1}_{2}.msix" -f $PackageName, $Version, $Architecture)
$certFile = Join-Path $msixRoot "dev-signing-cert.pfx"
$certPublicFile = Join-Path $msixRoot "dev-signing-cert.cer"
$bundleName = "{0}_{1}" -f $PackageName, $Version
$bundleRoot = Join-Path $distRoot $bundleName
$bundlePackageFile = Join-Path $bundleRoot ("{0}_{1}_{2}.msix" -f $PackageName, $Version, $Architecture)
$bundleCertFile = Join-Path $bundleRoot "MyApp-cert.cer"
$bundleInstallerTemplate = Join-Path $PSScriptRoot "Install.ps1"
$bundleInstallerFile = Join-Path $bundleRoot "Install.ps1"

$identityName = Get-IdentityName -Name $PackageName
$publisherDisplayName = Get-PublisherDisplayName -PublisherName $Publisher
$makeAppx = Get-ToolPath -ToolName "makeappx"
$signTool = $null

if (-not $SkipSign) {
    $signTool = Get-ToolPath -ToolName "signtool"
}

New-Item -Path $artifactRoot -ItemType Directory -Force | Out-Null
New-Item -Path $publishRoot -ItemType Directory -Force | Out-Null
New-Item -Path $msixRoot -ItemType Directory -Force | Out-Null
New-Item -Path $distRoot -ItemType Directory -Force | Out-Null


Write-Host "[1/7] Building Web-App prod bundle"
Push-Location $webAppRoot
try {
    & npm.cmd run build:prod
}
finally {
    Pop-Location
} 

Write-Host "[2/7] Publishing Desktop Host for $Architecture"
dotnet publish $hostProject -c Release -r win-$Architecture --self-contained true -o $publishRoot

$entryExecutable = Join-Path $publishRoot "DesktopHost.exe"
if (-not (Test-Path $entryExecutable)) {
    throw "Published host exe not found at $entryExecutable"
}

$entryExecutableName = Split-Path -Path $entryExecutable -Leaf

Write-Host "[3/7] Copying Web-App dist into wwwroot/ alongside host app"

# Discover the most recently modified dist folder so we always pick the latest build output.
$webDistRoot = Join-Path $webAppRoot "dist"
if (-not (Test-Path $webDistRoot)) {
    throw "Web-App dist root not found at '$webDistRoot'. Run 'npm run build:prod' from the web-app folder first."
}

$latestDistFolder = Get-ChildItem -Path $webDistRoot -Directory |
Sort-Object LastWriteTime -Descending |
Select-Object -First 1

if (-not $latestDistFolder) {
    throw "No dist sub-folder found inside '$webDistRoot'. Run 'npm run build:prod' from the web-app folder first."
}

$webAppDist = $latestDistFolder.FullName
Write-Host "Using web dist: $webAppDist"

if (-not (Test-Path $webAppDist)) {
    throw "WebApp dist not found at $webAppDist"
}

$wwwrootTarget = Join-Path $publishRoot "wwwroot"
if (Test-Path $wwwrootTarget ) {
    Remove-Item -Path $wwwrootTarget -Recurse -Force

}
Copy-Item -Path $webAppDist -Destination $wwwrootTarget -Recurse -Force

Write-Host "[4/7] Preparing MSIX layout"
if (Test-Path $layoutRoot) {
    Remove-Item -Path $layoutRoot -Recurse -Force
}

New-Item -Path $layoutRoot -ItemType Directory -Force | Out-Null
Copy-Item -Path (Join-Path $publishRoot "*") -Destination $layoutRoot -Recurse -Force

Write-Host "[5/7] Generating app manifest and assets"
New-AppAssets -AssetsPath $assetsRoot -AppDisplayName $DisplayName
New-AppxManifest `
    -Path (Join-Path $layoutRoot "AppxManifest.xml") `
    -IdentityName $identityName `
    -PublisherName $Publisher `
    -PackageVersion $Version `
    -PackageArchitecture $Architecture `
    -AppDisplayName $DisplayName `
    -PublisherDisplayName $publisherDisplayName `
    -ExecutableName $entryExecutableName

Write-Host "[6/7] Packing MSIX"
if (Test-Path $packageFile) {
    Remove-Item -Path $packageFile -Force
}

Invoke-NativeCommand -FilePath $makeAppx -Arguments @(
    "pack",
    "/d", $layoutRoot,
    "/p", $packageFile,
    "/o"
)

if (-not $SkipSign) {
    Write-Host "[7/7] Signing MSIX"
    Get-OrCreateDevCertificate -PublisherName $Publisher -PfxPath $certFile -CerPath $certPublicFile -Password $CertPassword
    Invoke-NativeCommand -FilePath $signTool -Arguments @(
        "sign",
        "/fd", "SHA256",
        "/f", $certFile,
        "/p", $CertPassword,
        $packageFile
    )

    Write-Host "Certificate exported to $certPublicFile"
    Write-Host "Use the generated artifacts/dist/.../Install.ps1 script to install on other machines."
}
else {
    Write-Host "[7/7] Skipping signing"
}

Write-Host "MSIX package created: $packageFile"

Write-Host "[8/8] Creating distribution bundle"
if (Test-Path $bundleRoot) {
    Remove-Item -Path $bundleRoot -Recurse -Force
}

New-Item -Path $bundleRoot -ItemType Directory -Force | Out-Null
Copy-Item -Path $packageFile -Destination $bundlePackageFile -Force

if (-not (Test-Path $certPublicFile)) {
    throw "Certificate file not found at $certPublicFile. Build signed package first without -SkipSign."
}
Copy-Item -Path $certPublicFile -Destination $bundleCertFile -Force

if (-not (Test-Path $bundleInstallerTemplate)) {
    throw "Installer template not found at $bundleInstallerTemplate"
}
Copy-Item -Path $bundleInstallerTemplate -Destination $bundleInstallerFile -Force

Write-Host "Distribution bundle created: $bundleRoot"
Write-Host "Share this folder with users. They only need to run Install.ps1"


