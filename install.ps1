<#
.SYNOPSIS
    PVM Installer - Sets up the Python Version Manager on your system.

.DESCRIPTION
    This script:
    1. Creates the ~/.pvm directory structure
    2. Copies pvm.ps1 and pvm.cmd into ~/.pvm/
    3. Adds ~/.pvm to the user PATH
    4. Creates a PowerShell profile hook so 'pvm' works as a command

.NOTES
    Run this script once after cloning or downloading PVM:
      powershell -ExecutionPolicy Bypass -File install.ps1
#>

param(
    [switch]$Uninstall
)

$PVM_DIR = Join-Path $env:USERPROFILE ".pvm"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ─── Colors ──────────────────────────────────────────────────────────────────────

function Write-Step {
    param([string]$Message)
    Write-Host "  -> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  [ERROR] $Message" -ForegroundColor Red
}

function Write-Attention {
    param([string]$Message)
    Write-Host "  [!] $Message" -ForegroundColor Yellow
}

# ─── Uninstall ───────────────────────────────────────────────────────────────────

if ($Uninstall) {
    Write-Host ""
    Write-Attention "Uninstalling PVM..."
    Write-Host ""

    # Remove from PATH
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath) {
        $pvmCurrent = Join-Path $PVM_DIR "current"
        $pvmScripts = Join-Path $pvmCurrent "Scripts"
        $pathParts = $userPath -split ";" | Where-Object {
            $part = $_.TrimEnd('\')
            ($part -ne $PVM_DIR.TrimEnd('\')) -and
            ($part -ne $pvmCurrent.TrimEnd('\')) -and
            ($part -ne $pvmScripts.TrimEnd('\')) -and
            ($_.Trim() -ne "")
        }
        [System.Environment]::SetEnvironmentVariable("Path", ($pathParts -join ";"), "User")
    }

    # Remove profile hook
    $profilePath = $PROFILE.CurrentUserCurrentHost
    if (Test-Path $profilePath) {
        $profileContent = Get-Content $profilePath -Raw
        $newContent = $profileContent -replace '(?m)^# PVM - Python Version Manager.*\r?\n.*pvm\.ps1.*\r?\n', ''
        Set-Content $profilePath $newContent
    }

    # Remove the current-user Start Menu app shortcut.
    $startMenuShortcut = Join-Path ([System.Environment]::GetFolderPath('Programs')) "PVM for Windows.lnk"
    if (Test-Path $startMenuShortcut) { Remove-Item -LiteralPath $startMenuShortcut -Force }

    Write-Ok "PVM removed from PATH and profile."
    Write-Attention "Python versions in $PVM_DIR\versions were NOT deleted."
    Write-Attention "Delete $PVM_DIR manually to fully remove everything."
    Write-Host ""
    return
}

# ─── Install ─────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  =========================================" -ForegroundColor Cyan
Write-Host "      PVM Installer - Python Version Manager" -ForegroundColor Cyan
Write-Host "  =========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Create directory structure
Write-Step "Creating directory structure..."
$dirsToCreate = @(
    $PVM_DIR,
    (Join-Path $PVM_DIR "versions"),
    (Join-Path $PVM_DIR "cache")
)
foreach ($dir in $dirsToCreate) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# 2. Copy PVM scripts
Write-Step "Copying PVM scripts..."
$filesToCopy = @("pvm.ps1", "pvm.cmd", "pvm.exe", "install.ps1")
foreach ($file in $filesToCopy) {
    $src = Join-Path $ScriptDir $file
    if ($file -eq "pvm.exe" -and -not (Test-Path $src)) {
        $src = Join-Path $ScriptDir "dist\pvm.exe"
    }
    $dst = Join-Path $PVM_DIR $file
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $dst -Force
        Write-Host "      Copied $file"
    }
    else {
        Write-Fail "Missing source file: $src"
    }
}

# 3. Default settings
$settingsFile = Join-Path $PVM_DIR "settings.json"
if (-not (Test-Path $settingsFile)) {
    @{ "enabled" = $true; "arch" = "amd64" } | ConvertTo-Json | Set-Content $settingsFile
}

# 4. Add ~/.pvm to user PATH (so pvm.cmd is findable from CMD)
Write-Step "Configuring PATH..."
$userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
$pathParts = @()
if ($userPath) {
    $pathParts = $userPath -split ";" | Where-Object { $_.Trim() -ne "" }
}

$pvmNormalized = $PVM_DIR.TrimEnd('\')
$alreadyInPath = $false
foreach ($part in $pathParts) {
    if ($part.TrimEnd('\') -eq $pvmNormalized) {
        $alreadyInPath = $true
        break
    }
}

if (-not $alreadyInPath) {
    $pathParts = @($PVM_DIR) + $pathParts
    [System.Environment]::SetEnvironmentVariable("Path", ($pathParts -join ";"), "User")
    Write-Host "      Added $PVM_DIR to user PATH"
}
else {
    Write-Host "      PATH already configured"
}

# 5. Add PowerShell function/alias to profile
Write-Step "Configuring PowerShell profile..."
$profilePath = $PROFILE.CurrentUserCurrentHost
$profileDir = Split-Path $profilePath -Parent

if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

$pvmScriptPath = Join-Path $PVM_DIR "pvm.ps1"
$pvmProfileBlock = @"

# PVM - Python Version Manager
function pvm { & "$pvmScriptPath" @args }
"@

if (Test-Path $profilePath) {
    $existingContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
    if ($existingContent -and $existingContent.Contains("# PVM - Python Version Manager")) {
        Write-Host "      Profile already configured"
    }
    else {
        Add-Content -Path $profilePath -Value $pvmProfileBlock
        Write-Host "      Added PVM function to profile"
    }
}
else {
    Set-Content -Path $profilePath -Value $pvmProfileBlock
    Write-Host "      Created profile with PVM function"
}

# 6. Add PVM to the current user's Start Menu with its embedded executable icon.
$pvmExePath = Join-Path $PVM_DIR "pvm.exe"
if (Test-Path $pvmExePath) {
    Write-Step "Adding PVM to the Start Menu..."
    $programsDir = [System.Environment]::GetFolderPath('Programs')
    if (-not (Test-Path $programsDir)) { New-Item -ItemType Directory -Path $programsDir -Force | Out-Null }
    $shortcutPath = Join-Path $programsDir "PVM for Windows.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $env:WINDIR "System32\cmd.exe"
    $shortcut.Arguments = '/K "title PVM for Windows & pvm.exe help"'
    $shortcut.WorkingDirectory = $PVM_DIR
    $shortcut.IconLocation = "$pvmExePath,0"
    $shortcut.Description = "Python Version Manager for Windows"
    $shortcut.Save()
    Write-Ok "Added PVM for Windows to the Start Menu."
}
else {
    Write-Attention "pvm.exe was not found; no Start Menu shortcut was created. Run build.ps1 and reinstall to add it."
}

# ─── Done ────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  =========================================" -ForegroundColor Green
Write-Host "      PVM installed successfully!" -ForegroundColor Green
Write-Host "  =========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Quick Start:" -ForegroundColor White
Write-Host ""
Write-Host "    1. Open a NEW terminal (to pick up PATH changes)"
Write-Host "    2. pvm list-remote          # see available Python versions"
Write-Host "    3. pvm install 3.12         # install Python 3.12"
Write-Host "    4. pvm use 3.12             # activate it"
Write-Host "    5. python --version         # verify!"
Write-Host ""
Write-Host "  PVM Home: $PVM_DIR" -ForegroundColor Gray
Write-Host ""
