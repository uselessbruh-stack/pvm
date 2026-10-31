<#
.SYNOPSIS
    PVM - Python Version Manager for Windows
    A tool to manage multiple Python installations, inspired by nvm.

.DESCRIPTION
    PVM allows you to install, switch between, and manage multiple Python
    versions on Windows. It downloads official Python releases from python.org,
    installs them in an isolated directory, and lets you switch the active
    version globally via PATH manipulation.

.NOTES
    Author:  PVM Contributors
    License: MIT
#>

# ─── Configuration ──────────────────────────────────────────────────────────────

$PVM_DIR        = Join-Path $env:USERPROFILE ".pvm"
$PVM_VERSIONS   = Join-Path $PVM_DIR "versions"
$PVM_CURRENT    = Join-Path $PVM_DIR "current"       # symlink to active version
$PVM_CACHE      = Join-Path $PVM_DIR "cache"          # downloaded installers
$PVM_SETTINGS   = Join-Path $PVM_DIR "settings.json"  # persistent settings

# Color helpers (using native -ForegroundColor for PS 5.1+ compatibility)
function Write-Color {
    param([string]$Text, [string]$Color = "White")
    $colorMap = @{
        "Green"   = [System.ConsoleColor]::Green
        "Red"     = [System.ConsoleColor]::Red
        "Yellow"  = [System.ConsoleColor]::Yellow
        "Cyan"    = [System.ConsoleColor]::Cyan
        "Magenta" = [System.ConsoleColor]::Magenta
        "White"   = [System.ConsoleColor]::White
        "Gray"    = [System.ConsoleColor]::DarkGray
        "Bold"    = [System.ConsoleColor]::White
    }
    $fg = if ($colorMap.ContainsKey($Color)) { $colorMap[$Color] } else { [System.ConsoleColor]::White }
    Write-Host $Text -ForegroundColor $fg
}

function Write-Banner {
    Write-Host ""
    Write-Color "  +=========================================+" "Cyan"
    Write-Color "  |    PVM - Python Version Manager          |" "Cyan"
    Write-Color "  +=========================================+" "Cyan"
    Write-Host ""
}

function Write-Success  { param([string]$Msg) Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-Err      { param([string]$Msg) Write-Host "  [ERROR] $Msg" -ForegroundColor Red }
function Write-Warn     { param([string]$Msg) Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }
function Write-Info     { param([string]$Msg) Write-Host "  -> $Msg" -ForegroundColor Cyan }

# ─── Initialization ─────────────────────────────────────────────────────────────

function Initialize-Pvm {
    # Enforce TLS 1.2 for HTTPS connections (required on PS 5.1)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    foreach ($dir in @($PVM_DIR, $PVM_VERSIONS, $PVM_CACHE)) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
    # Default settings
    if (-not (Test-Path $PVM_SETTINGS)) {
        $defaultArch = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') { 'arm64' } elseif ([System.Environment]::Is64BitOperatingSystem) { 'amd64' } else { 'win32' }
        @{ "enabled" = $true; "arch" = $defaultArch } | ConvertTo-Json | Set-Content $PVM_SETTINGS
    }
}

function Get-PvmSettings {
    if (Test-Path $PVM_SETTINGS) {
        return Get-Content $PVM_SETTINGS | ConvertFrom-Json
    }
    return @{ "enabled" = $true; "arch" = "amd64" }
}

function Save-PvmSettings {
    param($Settings)
    $Settings | ConvertTo-Json | Set-Content $PVM_SETTINGS
}

# ─── Architecture Detection ─────────────────────────────────────────────────────

function Get-PythonArch {
    if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') { return "arm64" }
    $settings = Get-PvmSettings
    if ($settings.arch) { return $settings.arch }
    if ([System.Environment]::Is64BitOperatingSystem) { return "amd64" } else { return "win32" }
}

# ─── Version Resolution ─────────────────────────────────────────────────────────

function Test-WindowsInstallerExists {
    <#
    .SYNOPSIS
        Checks whether python.org publishes the matching official Windows installer.
    #>
    param([string]$Version, [string]$Arch)

    $installerUrl = "https://www.python.org/ftp/python/$Version/python-$Version-$Arch.exe"

    try {
        $null = Invoke-WebRequest -Uri $installerUrl -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        return $installerUrl
    }
    catch {}

    return $null
}

function Test-PythonInstallManagerAvailable {
    $launcher = Get-Command py.exe -ErrorAction SilentlyContinue
    if (-not $launcher) { return $false }
    try {
        $help = (& $launcher.Source help install 2>&1 | Out-String)
        return ($LASTEXITCODE -eq 0 -and $help -match '--target')
    }
    catch { return $false }
}

function Resolve-PythonVersion {
    <#
    .SYNOPSIS
        Resolves a partial version to the newest release supported by an
        official Windows installer or the Python install manager.
    #>
    param([string]$Requested)

    $arch = Get-PythonArch

    # Prefer the direct official installer; newer releases may use PyManager.
    if ($Requested -match '^\d+\.\d+\.\d+$') {
        if ((Test-WindowsInstallerExists -Version $Requested -Arch $arch) -or (Test-PythonInstallManagerAvailable)) { return $Requested }
        Write-Err "No official Windows installer was found for Python $Requested ($arch)."
        return $null
    }

    # Partial match — fetch remote and find best version with a Windows installer
    $remoteVersions = Get-RemoteVersions
    if (-not $remoteVersions) {
        Write-Err "Could not fetch remote versions to resolve '$Requested'"
        return $null
    }

    $candidates = $remoteVersions | Where-Object { $_ -like "$Requested*" }
    if (-not $candidates) {
        Write-Err "No version matching '$Requested' found remotely."
        return $null
    }

    Write-Info "Finding latest $Requested.x with an official Windows install source..."

    foreach ($ver in $candidates) {
        $result = Test-WindowsInstallerExists -Version $ver -Arch $arch
        if ($result) {
            Write-Info "Found: $ver (has $result installer)"
            return $ver
        }
    }

    if (Test-PythonInstallManagerAvailable) {
        Write-Info "Using the official Python install manager for $($candidates[0])."
        return $candidates[0]
    }

    Write-Err "No Windows installer found for any $Requested.x version."
    return $null
}

# ─── Remote Version Listing (scrapes python.org) ────────────────────────────────

function Get-RemoteVersions {
    <#
    .SYNOPSIS
        Fetches available Python release versions from python.org.
        Returns a sorted list of version strings (newest first).
    #>
    Write-Info "Fetching available versions from python.org..."

    try {
        $html = Invoke-WebRequest -Uri "https://www.python.org/downloads/" -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
        $versions = @()
        $matches_found = [regex]::Matches($html.Content, 'Python (\d+\.\d+\.\d+)')
        foreach ($m in $matches_found) {
            $versions += $m.Groups[1].Value
        }
        $versions = $versions | Select-Object -Unique | Sort-Object {
            $parts = $_ -split '\.'
            [int]$parts[0] * 10000 + [int]$parts[1] * 100 + [int]$parts[2]
        } -Descending
        return $versions
    }
    catch {
        Write-Err "Failed to fetch version list: $($_.Exception.Message)"
        return @()
    }
}

# ─── Install ─────────────────────────────────────────────────────────────────────

function Install-PythonVersion {
    <#
    .SYNOPSIS
        Downloads and installs a full Python runtime from the official source.
    #>
    param([string]$Version)

    if (-not $Version) {
        Write-Err "Usage: pvm install <version>  (e.g. pvm install 3.12.1)"
        return
    }

    # Resolve partial versions
    $resolved = Resolve-PythonVersion $Version
    if (-not $resolved) { return }
    $Version = $resolved

    $installPath = Join-Path $PVM_VERSIONS $Version

    if (Test-Path $installPath) {
        Write-Warn "Python $Version is already installed."
        Write-Info "Use 'pvm use $Version' to switch to it."
        return
    }

    $arch = Get-PythonArch
    $archLabel = $arch

    $installerUrl = Test-WindowsInstallerExists -Version $Version -Arch $archLabel
    if (-not $installerUrl) {
        if (-not (Test-PythonInstallManagerAvailable)) {
            Write-Err "No official Windows installer is published for Python $Version ($archLabel), and the Python install manager is not available."
            Write-Info "Install the official Python install manager from python.org, then retry."
            return
        }
        Write-Info "Installing Python $Version through the official Python install manager. Download progress is shown below."
        try {
            $manager = Get-Command py.exe -ErrorAction Stop
            & $manager.Source install "--target=$installPath" $Version
            if ($LASTEXITCODE -ne 0) { throw "Python install manager exited with code $LASTEXITCODE." }
            if (-not (Test-Path (Join-Path $installPath 'python.exe'))) { throw "Python was not found in $installPath after installation." }
            Write-Success "Python $Version installed successfully."
            if (-not (Test-Path $PVM_CURRENT)) { Set-ActiveVersion -Version $Version }
            else { Write-Info "Run 'pvm use $Version' to switch to this version." }
        }
        catch { Write-Err "Failed to install Python ${Version}: $($_.Exception.Message)" }
        return
    }

    Write-Host ""
    Write-Info "Installing Python $Version ($archLabel)..."
    Write-Host ""

    # Use the official full installer when published for this release.
    $installerFile = Join-Path $PVM_CACHE "python-$Version-$archLabel.exe"

    if (-not (Test-Path $installerFile) -or (Get-Item $installerFile).Length -lt 1000000) {
        if (Test-Path $installerFile) { Remove-Item $installerFile -Force }
        Write-Info "Downloading official installer from $installerUrl"
        $oldProgressPreference = $ProgressPreference
        try {
            $ProgressPreference = 'Continue'
            Invoke-WebRequest -Uri $installerUrl -OutFile $installerFile -UseBasicParsing -ErrorAction Stop

            $fileSize = (Get-Item $installerFile).Length
            if ($fileSize -lt 1000000) {
                throw "Downloaded installer is unexpectedly small ($fileSize bytes)."
            }
            Write-Success "Download complete ($([math]::Round($fileSize / 1MB, 1)) MB)."
        }
        catch {
            Write-Err "Failed to download official Python $Version installer."
            Write-Err "$($_.Exception.Message)"
            if (Test-Path $installerFile) { Remove-Item $installerFile -Force }
            return
        }
        finally { $ProgressPreference = $oldProgressPreference }
    }
    else {
        Write-Info "Using cached package."
    }

    Write-Info "Installing to $installPath ..."
    try {
        New-Item -ItemType Directory -Path $installPath -Force | Out-Null
        $installerArgs = @('/quiet', 'InstallAllUsers=0', "TargetDir=`"$installPath`"", 'Include_pip=1', 'Include_launcher=0', 'Include_test=0', 'PrependPath=0', 'AppendPath=0', 'Shortcuts=0')
        $process = Start-Process -FilePath $installerFile -ArgumentList $installerArgs -Wait -PassThru
        if ($process.ExitCode -ne 0) { throw "Python installer exited with code $($process.ExitCode)." }
    }
    catch {
        Write-Err "Failed to install Python: $($_.Exception.Message)"
        if (Test-Path $installPath) { Remove-Item $installPath -Recurse -Force }
        return
    }

    # Verify python.exe exists
    $pythonExe = Join-Path $installPath "python.exe"
    if (-not (Test-Path $pythonExe)) {
        Write-Err "Installation completed but python.exe not found in $installPath"
        return
    }
    Write-Success "Python $Version installed with pip."

    Write-Success "Python $Version installed successfully!"
    Write-Host ""

    # If no version is currently active, auto-activate this one
    if (-not (Test-Path $PVM_CURRENT)) {
        Set-ActiveVersion -Version $Version
    }
    else {
        Write-Info "Run 'pvm use $Version' to switch to this version."
    }
}

function Ensure-Pip {
    <#
    .SYNOPSIS
        Ensures pip is installed in the given Python installation.
    #>
    param([string]$InstallPath)

    $pythonExe = Join-Path $InstallPath "python.exe"
    $pipExe = Join-Path $InstallPath "Scripts\pip.exe"

    if (-not (Test-Path $pipExe)) {
        Write-Info "Installing pip..."
        try {
            $getPipUrl = "https://bootstrap.pypa.io/get-pip.py"
            $getPipPath = Join-Path $PVM_CACHE "get-pip.py"
            if (-not (Test-Path $getPipPath)) {
                $ProgressPreference = 'SilentlyContinue'
                Invoke-WebRequest -Uri $getPipUrl -OutFile $getPipPath -UseBasicParsing
                $ProgressPreference = 'Continue'
            }
            & $pythonExe $getPipPath --no-warn-script-location 2>$null | Out-Null
            if (Test-Path $pipExe) {
                Write-Success "pip installed."
            }
        }
        catch {
            Write-Warn "Could not install pip automatically."
        }
    }
}

# ─── Uninstall ───────────────────────────────────────────────────────────────────

function Uninstall-PythonVersion {
    param([string]$Version)

    if (-not $Version) {
        Write-Err "Usage: pvm uninstall <version>"
        return
    }

    $installPath = Join-Path $PVM_VERSIONS $Version

    if (-not (Test-Path $installPath)) {
        Write-Err "Python $Version is not installed."
        return
    }

    # Check if it's the currently active version
    $current = Get-CurrentVersion
    if ($current -eq $Version) {
        Write-Warn "Deactivating Python $Version first..."
        if (Test-Path $PVM_CURRENT) {
            # Remove the symlink/junction
            $item = Get-Item $PVM_CURRENT -Force
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                cmd.exe /c "rmdir `"$PVM_CURRENT`"" 2>$null
            }
            else {
                Remove-Item $PVM_CURRENT -Recurse -Force
            }
        }
    }

    Write-Info "Uninstalling Python $Version..."

    try {
        Remove-Item $installPath -Recurse -Force
        Write-Success "Python $Version uninstalled."
    }
    catch {
        Write-Err "Failed to remove $installPath : $_"
    }
}

# ─── Use / Switch Version ───────────────────────────────────────────────────────

function Set-ActiveVersion {
    param([string]$Version)

    if (-not $Version) {
        Write-Err "Usage: pvm use <version>"
        return
    }

    $installPath = Resolve-PythonInstallPath -Version $Version
    if (-not $installPath) {
        $match = Get-InstalledVersions | Where-Object { $_ -like "$Version*" } | Select-Object -First 1
        if ($match) { $Version = $match; $installPath = Resolve-PythonInstallPath -Version $Version }
    }
    if (-not $installPath) {
        Write-Err "Python $Version is not installed."
        Write-Info "Run 'pvm install $Version' first, or install Python from python.org."
        return
    }

    # Remove existing symlink/junction
    if (Test-Path $PVM_CURRENT) {
        $item = Get-Item $PVM_CURRENT -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            cmd.exe /c "rmdir `"$PVM_CURRENT`"" 2>$null
        }
        elseif ($item) {
            Remove-Item $PVM_CURRENT -Recurse -Force
        }
    }

    # Create directory junction (doesn't require admin, unlike symlinks)
    cmd.exe /c "mklink /J `"$PVM_CURRENT`" `"$installPath`"" 2>$null | Out-Null

    if (Test-Path $PVM_CURRENT) {
        # Ensure PVM current path is in the system PATH
        Update-SystemPath

        Write-Success "Now using Python $Version"

        # Show the version
        $pythonExe = Join-Path $PVM_CURRENT "python.exe"
        if (Test-Path $pythonExe) {
            $versionOutput = & $pythonExe --version 2>&1
            Write-Info "$versionOutput"
        }
    }
    else {
        Write-Err "Failed to create junction link."
        Write-Err "Try running as Administrator."
    }
}

function Update-SystemPath {
    <#
    .SYNOPSIS
        Ensures PVM's current directory and Scripts subdirectory are in the user PATH.
    #>
    $pvmPaths = @($PVM_CURRENT, (Join-Path $PVM_CURRENT "Scripts"))
    $currentPath = [System.Environment]::GetEnvironmentVariable("Path", "User")

    $pathParts = $currentPath -split ";" | Where-Object { $_.Trim() -ne "" }
    $changed = $false

    foreach ($p in $pvmPaths) {
        $normalizedP = $p.TrimEnd('\')
        $found = $pathParts | Where-Object { $_.TrimEnd('\') -eq $normalizedP }
        if (-not $found) {
            $pathParts = @($p) + $pathParts
            $changed = $true
        }
    }

    if ($changed) {
        $newPath = ($pathParts -join ";")
        [System.Environment]::SetEnvironmentVariable("Path", $newPath, "User")

        # Also update the current session
        $env:Path = "$($pvmPaths -join ';');$env:Path"

        Write-Info "Updated PATH. New terminal sessions will use Python from PVM."
    }
}

# ─── List Installed ──────────────────────────────────────────────────────────────

function Get-ExternalPythonInstallations {
    # Discover normal Windows installations without taking ownership of them.
    $executables = @()
    $launcher = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($launcher) {
        $launcherOutput = & $launcher.Source -0p 2>$null
        foreach ($line in $launcherOutput) {
            if ($line -match '([A-Za-z]:\\[^\r\n]*?python(?:w)?\.exe)\s*$') { $executables += $Matches[1] }
        }
    }

    foreach ($root in @('HKCU:\Software\Python\PythonCore', 'HKLM:\SOFTWARE\Python\PythonCore', 'HKLM:\SOFTWARE\WOW6432Node\Python\PythonCore')) {
        if (Test-Path $root) {
            foreach ($versionKey in (Get-ChildItem $root -ErrorAction SilentlyContinue)) {
                $installKey = Join-Path $versionKey.PSPath 'InstallPath'
                if (Test-Path $installKey) {
                    $props = Get-ItemProperty $installKey -ErrorAction SilentlyContinue
                    if ($props.ExecutablePath) { $executables += $props.ExecutablePath }
                    else {
                        $defaultDir = (Get-Item $installKey -ErrorAction SilentlyContinue).GetValue('')
                        if ($defaultDir) { $executables += (Join-Path $defaultDir 'python.exe') }
                    }
                }
            }
        }
    }

    foreach ($cmdName in @('python.exe', 'python3.exe')) {
        $commands = Get-Command $cmdName -All -ErrorAction SilentlyContinue
        foreach ($command in $commands) { if ($command.Source -and $command.Source -notmatch '\\WindowsApps\\') { $executables += $command.Source } }
    }

    $seen = @{}
    foreach ($exe in $executables) {
        if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { continue }
        $fullPath = [System.IO.Path]::GetFullPath($exe)
        $key = $fullPath.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        try {
            $output = & $fullPath --version 2>&1 | Out-String
            if ($output -match 'Python\s+(\d+\.\d+\.\d+)') {
                [PSCustomObject]@{ Version = $Matches[1]; Path = (Split-Path $fullPath -Parent) }
            }
        }
        catch { }
    }
}

function Resolve-PythonInstallPath {
    param([string]$Version)
    $managedPath = Join-Path $PVM_VERSIONS $Version
    if (Test-Path (Join-Path $managedPath 'python.exe')) { return $managedPath }
    $external = Get-ExternalPythonInstallations | Where-Object { $_.Version -eq $Version -or $_.Version -like "$Version*" } | Select-Object -First 1
    if ($external) { return $external.Path }
    return $null
}

function Get-InstalledVersions {
    $versions = @()
    if (Test-Path $PVM_VERSIONS) { $versions += Get-ChildItem -Path $PVM_VERSIONS -Directory | Select-Object -ExpandProperty Name }
    $versions += Get-ExternalPythonInstallations | Select-Object -ExpandProperty Version
    return $versions | Select-Object -Unique | Sort-Object {
        $parts = $_ -split '\.'
        [int]$parts[0] * 10000 + [int]$parts[1] * 100 + [int]$parts[2]
    } -Descending
}

function Show-InstalledVersions {
    $versions = Get-InstalledVersions
    $current = Get-CurrentVersion

    Write-Host ""

    if ($versions.Count -eq 0) {
        Write-Warn "No Python versions installed."
        Write-Info "Run 'pvm install <version>' to install one."
        Write-Info "Run 'pvm list-remote' to see available versions."
        return
    }

    Write-Color "  Python Versions (PVM and existing installs):" "Bold"
    Write-Host ""

    foreach ($v in $versions) {
        if ($v -eq $current) {
            Write-Color "   *  $v  (active)" "Green"
        }
        else {
            Write-Color "      $v" "White"
        }
    }
    Write-Host ""
}

# ─── List Remote ─────────────────────────────────────────────────────────────────

function Show-RemoteVersions {
    $versions = Get-RemoteVersions
    $installed = Get-InstalledVersions

    if ($versions.Count -eq 0) {
        Write-Err "Could not fetch available versions."
        return
    }

    Write-Host ""
    Write-Color "  Available Python Versions (latest 30):" "Bold"
    Write-Host ""

    $count = 0
    foreach ($v in $versions) {
        if ($count -ge 30) { break }

        $marker = ""
        if ($installed -contains $v) {
            $marker = "  [installed]"
        }

        if ($marker) {
            Write-Color "      $v$marker" "Green"
        }
        else {
            Write-Color "      $v" "White"
        }
        $count++
    }

    Write-Host ""
    Write-Info "Use 'pvm install <version>' to install a version."
    Write-Host ""
}

# ─── Current Version ────────────────────────────────────────────────────────────

function Get-CurrentVersion {
    if (-not (Test-Path $PVM_CURRENT)) { return $null }

    $item = Get-Item $PVM_CURRENT -Force -ErrorAction SilentlyContinue
    if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        $target = $item.Target
        if ($target) {
            # Target may be a list; take the first
            if ($target -is [System.Array]) { $target = $target[0] }
            $linkedPython = Join-Path $PVM_CURRENT 'python.exe'
            if (Test-Path $linkedPython) {
                $output = & $linkedPython --version 2>&1
                if ($output -match '(\d+\.\d+\.\d+)') { return $Matches[1] }
            }
            return Split-Path $target -Leaf
        }
    }

    # Fallback: check if python.exe exists and ask it
    $pythonExe = Join-Path $PVM_CURRENT "python.exe"
    if (Test-Path $pythonExe) {
        $output = & $pythonExe --version 2>&1
        if ($output -match '(\d+\.\d+\.\d+)') {
            return $Matches[1]
        }
    }

    return $null
}

function Show-CurrentVersion {
    $current = Get-CurrentVersion

    Write-Host ""
    if ($current) {
        Write-Success "Currently using Python $current"
        $pythonExe = Join-Path $PVM_CURRENT "python.exe"
        if (Test-Path $pythonExe) {
            $output = & $pythonExe --version 2>&1
            Write-Info "$output"
            $loc = (Get-Command python -ErrorAction SilentlyContinue).Source
            if ($loc) { Write-Info "Binary: $loc" }
        }
    }
    else {
        Write-Warn "No Python version is currently active."
        Write-Info "Run 'pvm use <version>' to activate one."
    }
    Write-Host ""
}

# ─── On / Off ────────────────────────────────────────────────────────────────────

function Enable-Pvm {
    $settings = Get-PvmSettings
    $settings.enabled = $true
    Save-PvmSettings $settings

    # Re-add to PATH
    Update-SystemPath

    Write-Host ""
    Write-Success "PVM enabled."
    $current = Get-CurrentVersion
    if ($current) {
        Write-Info "Active Python: $current"
    }
    Write-Host ""
}

function Disable-Pvm {
    $settings = Get-PvmSettings
    $settings.enabled = $false
    Save-PvmSettings $settings

    # Remove PVM paths from user PATH
    $pvmPaths = @($PVM_CURRENT, (Join-Path $PVM_CURRENT "Scripts"))
    $currentPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $pathParts = $currentPath -split ";" | Where-Object { $_.Trim() -ne "" }

    $newParts = $pathParts | Where-Object {
        $normalizedPart = $_.TrimEnd('\')
        $keep = $true
        foreach ($p in $pvmPaths) {
            if ($normalizedPart -eq $p.TrimEnd('\')) {
                $keep = $false
                break
            }
        }
        $keep
    }

    $newPath = ($newParts -join ";")
    [System.Environment]::SetEnvironmentVariable("Path", $newPath, "User")

    Write-Host ""
    Write-Success "PVM disabled. System Python (if any) will be used."
    Write-Info "Run 'pvm on' to re-enable."
    Write-Host ""
}

# ─── Help ────────────────────────────────────────────────────────────────────────

function Show-Help {
    Write-Banner
    Write-Host "  Usage: pvm <command> [arguments]"
    Write-Host ""
    Write-Color "  Commands:" "Bold"
    Write-Host ""
    Write-Host "    install <version>    Install a Python version        (e.g. pvm install 3.12)"
    Write-Host "    uninstall <version>  Remove an installed version     (e.g. pvm uninstall 3.11.5)"
    Write-Host "    use <version>        Switch the active Python        (e.g. pvm use 3.12)"
    Write-Host "    list                 List installed versions"
    Write-Host "    list-remote          List available versions online"
    Write-Host "    current              Show the currently active version"
    Write-Host "    on                   Enable PVM (add to PATH)"
    Write-Host "    off                  Disable PVM (remove from PATH)"
    Write-Host "    help                 Show this help message"
    Write-Host ""
    Write-Color "  Examples:" "Gray"
    Write-Host ""
    Write-Host "    pvm install 3.12          Install latest 3.12.x"
    Write-Host "    pvm install 3.11.5        Install exact version 3.11.5"
    Write-Host "    pvm use 3.12              Switch to Python 3.12.x"
    Write-Host "    pvm list                  See what's installed"
    Write-Host ""
    Write-Color "  Directories:" "Gray"
    Write-Host ""
    Write-Host "    Root:     $PVM_DIR"
    Write-Host "    Versions: $PVM_VERSIONS"
    Write-Host "    Active:   $PVM_CURRENT"
    Write-Host ""
}

# ─── Main Entry Point ───────────────────────────────────────────────────────────

function Main {
    Initialize-Pvm

    $command = if ($args.Count -gt 0) { $args[0] } else { "help" }
    $param   = if ($args.Count -gt 1) { $args[1] } else { $null }

    switch ($command.ToLower()) {
        "install"     { Install-PythonVersion -Version $param }
        "uninstall"   { Uninstall-PythonVersion -Version $param }
        "remove"      { Uninstall-PythonVersion -Version $param }
        "use"         { Set-ActiveVersion -Version $param }
        "list"        { Show-InstalledVersions }
        "ls"          { Show-InstalledVersions }
        "list-remote" { Show-RemoteVersions }
        "ls-remote"   { Show-RemoteVersions }
        "available"   { Show-RemoteVersions }
        "current"     { Show-CurrentVersion }
        "on"          { Enable-Pvm }
        "off"         { Disable-Pvm }
        "help"        { Show-Help }
        "--help"      { Show-Help }
        "-h"         { Show-Help }
        default {
            Write-Err "Unknown command: $command"
            Show-Help
        }
    }
}

# Invoke main with script arguments
Main @args
