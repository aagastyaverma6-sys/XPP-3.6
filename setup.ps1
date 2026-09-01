# ============================================================================
#  X++ v0.4.1 - COMPLETE ONE-CLICK SETUP (PowerShell / Windows)
#
#  Install everything automatically:
#    - Python 3.9+         (if missing)
#    - VS Code            (if missing)
#    - MSYS2 + g++/MinGW  (if missing)   <-- the piece everyone kept missing
#    - x / xpp / xite shims + PATH
#    - xppvm native VM
#    - VS Code extension + Code Runner + settings
#    - .xp file registration
#    Then VERIFY: x version, xppvm version
#
#  Run it:
#     powershell -ExecutionPolicy Bypass -File .\setup.ps1
#     or right-click setup.ps1 > Run with PowerShell
#     setup.bat now just calls this script.
# ============================================================================
$ErrorActionPreference = 'Stop'

# Repo root is the folder containing this script (this file lives in repo root).
$Root = $PSScriptRoot
if ([string]::IsNullOrEmpty($Root)) { $Root = (Get-Location).Path }

function Write-Step($msg) { Write-Host ""; Write-Host ("=" * 70); Write-Host "  X++ SETUP  *  $msg"; Write-Host ("=" * 70) }
function Write-Ok($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Info($msg) { Write-Host "  [i] $msg" -ForegroundColor Cyan }
function Write-WarnX($msg){ Write-Host "  [!] $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "  [X] $msg" -ForegroundColor Red }

function Get-PythonCmd {
    # Return a command that invokes a Python 3.9+ interpreter, or $null.
    $cands = @($env:PYTHON, "python", "py")
    foreach ($name in $cands) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        try {
            $ver = & $cmd.Name -c "import sys;print('.'.join(map(str,sys.version_info[:3])), sys.executable)" 2>$null
            if ($LASTEXITCODE -eq 0 -and $ver) {
                $parts = $ver -split " ", 2
                $v = $parts[0] -as [version]
                if ($v -and $v -ge [version]"3.9") {
                    return @{ Run = $cmd.Name; Version = $v; Exe = $parts[1] }
                }
            }
        } catch { }
    }
    return $null
}

function Install-Python {
    Write-Info "Python not found. Installing Python 3.12..."
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    winget install -e --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements --silent | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Info "winget failed. Downloading official Python installer..."
        $tmp = Join-Path $env:TEMP "xpp-python-setup.exe"
        try {
            Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe" -OutFile $tmp -UseBasicParsing
            Start-Process -FilePath $tmp -ArgumentList "/quiet InstallAllUsers=0 PrependPath=1 Include_launcher=1 Include_pip=1" -Wait
            Remove-Item $tmp -ErrorAction SilentlyContinue
        } catch {
            Write-Err "Could not download/install Python. Install it from https://www.python.org and rerun."
        }
    }
    $ErrorActionPreference = $old
}

function Install-VSCode {
    $code = Get-Command code -ErrorAction SilentlyContinue
    if ($code) { return $code.Name }
    $codeCmd = Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code\bin\code.cmd"
    if (Test-Path $codeCmd) { return $codeCmd }
    $codeCmd2 = Join-Path $env:ProgramFiles "Microsoft VS Code\bin\code.cmd"
    if (Test-Path $codeCmd2) { return $codeCmd2 }

    Write-Info "VS Code not found. Installing via winget..."
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    winget install -e --id Microsoft.VisualStudioCode --accept-package-agreements --accept-source-agreements --silent | Out-Null
    $ErrorActionPreference = $old
    if (Test-Path $codeCmd) { return $codeCmd }
    if (Test-Path $codeCmd2) { return $codeCmd2 }
    return $null
}

function Get-Gxx {
    $g = Get-Command g++ -ErrorAction SilentlyContinue
    if ($g) { return $g.Source }
    foreach ($p in @("C:\msys64\mingw64\bin\g++.exe", "C:\MinGW\bin\g++.exe", "C:\msys64\usr\bin\g++.exe")) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Install-Gxx {
    # Returns path to g++.exe or $null.
    $bash = "C:\msys64\usr\bin\bash.exe"
    if (-not (Test-Path $bash)) {
        Write-Info "Installing MSYS2... (trying winget)"
        $old = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        winget install -e --id MSYS2.MSYS2 --accept-package-agreements --accept-source-agreements --silent | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $bash)) {
            Write-Info "winget did not provide MSYS2. Downloading MSYS2 installer..."
            $tmp = Join-Path $env:TEMP "msys2-setup.exe"
            try {
                Invoke-WebRequest -Uri "https://github.com/msys2/msys2-installer/releases/download/2026-06-11/msys2-x86_64-20260611.exe" -OutFile $tmp -UseBasicParsing
                Write-Info "Running MSYS2 installer silently..."
                Start-Process -FilePath $tmp -ArgumentList "install --root C:\msys64 --confirm-command" -Wait
                Remove-Item $tmp -ErrorAction SilentlyContinue
            } catch {
                Write-Err "Could not download/install MSYS2 automatically."
            }
        }
        $ErrorActionPreference = $old
    }

    if (-not (Test-Path "C:\msys64\mingw64\bin\g++.exe")) {
        Write-Info "Installing mingw-w64 x86_64 gcc (one-time, may take a few minutes)..."
        if (Test-Path $bash) {
            & $bash -lc "pacman -Sy --noconfirm --needed mingw-w64-x86_64-gcc" | Out-Null
        }
    }

    $gxx = Get-Gxx
    # Add to process + user PATH so this setup and later terminals find it.
    $bin = "C:\msys64\mingw64\bin"
    $env:Path = $bin + ";" + $env:Path
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User") -split ";" | Where-Object { $_ -and $_.TrimEnd("\") -ne $bin.TrimEnd("\") }
    [Environment]::SetEnvironmentVariable("Path", ($bin + ";" + ($userPath -join ";")), "User")
    return $gxx
}

function Copy-XppVSCodeExt {
    $extRoot = Join-Path $HOME ".vscode\extensions"
    $dst = Join-Path $extRoot "atom-software.xpp-lang-0.4.1"
    $src = Join-Path $Root "vscode\xpp-vscode"
    if (-not (Test-Path $src)) {
        Write-WarnX "VS Code X++ extension folder missing: $src"
        return $false
    }
    New-Item -ItemType Directory -Force -Path $extRoot | Out-Null
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue }
    Copy-Item -Recurse -Force -Path $src -Destination $dst | Out-Null
    Write-Ok "VS Code X++ extension copied to $dst"
    return $true
}

function Update-VSCodeSettings {
    $userDir = Join-Path $HOME ".config\Code\User"
    if (Test-Path (Join-Path $HOME "AppData\Roaming\Code\User")) {
        $userDir = Join-Path $HOME "AppData\Roaming\Code\User"
    } elseif (Test-Path (Join-Path $HOME "Library\Application Support\Code\User")) {
        $userDir = Join-Path $HOME "Library\Application Support\Code\User"
    }
    if (-not (Test-Path $userDir)) { New-Item -ItemType Directory -Force -Path $userDir | Out-Null }
    $settings = Join-Path $userDir "settings.json"
    $data = @{}
    if (Test-Path $settings) {
        try { $data = Get-Content $settings -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $data = @{} }
    }
    if (-not $data.workbench) { $data | Add-Member -NotePropertyName workbench -NotePropertyValue (@{}) }
    $data.workbench.iconTheme = "xpp-file-icons"
    if (-not $data.files) { $data | Add-Member -NotePropertyName files -NotePropertyValue (@{}) }
    if (-not $data.files.associations) { $data.files | Add-Member -NotePropertyName associations -NotePropertyValue (@{}) }
    $data.files.associations."*.xp" = "xpp"
    if (-not $data."code-runner.executorMap") { $data | Add-Member -NotePropertyName "code-runner.executorMap" -NotePropertyValue (@{}) }
    $data."code-runner.executorMap".".xp" = 'x run "$fullFileName"'
    $data."code-runner.runInTerminal" = $true
    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $settings -Encoding UTF8
    Write-Ok "VS Code settings updated at $settings"
}

function Register-WinIcons {
    Write-Step "Windows file-type registration"
    $ico = Join-Path $Root "icons\xpp.ico"
    $pythonw = (Get-PythonCmd).Exe
    if (-not $pythonw -or -not (Test-Path $pythonw)) { $pythonw = "pythonw.exe" }
    $pyLauncher = Join-Path $Root "xite.py"
    foreach ($pair in @(
        @(".xp", "", "XppSourceFile"),
        @("XppSourceFile\DefaultIcon", "", $ico),
        @("XppSourceFile\shell\run", "", "Run with X++"),
        @("XppSourceFile\shell\run\command", "", 'cmd /c x run "%1"'),
        @("XppSourceFile\shell\edit", "", "Edit in Xite"),
        @("XppSourceFile\shell\edit\command", "", ('"' + $pythonw + '" "' + $pyLauncher + '" "%1"'))
    )) {
        $sub = "HKCU:\Software\Classes\" + $pair[0]
        New-Item -Path $sub -Force | Out-Null
        if ($pair[2]) { Set-ItemProperty -Path $sub -Name $pair[1] -Value $pair[2] -Force }
    }
    Write-Ok ".xp registration updated"
}

Write-Host ""
Write-Host ("=" * 70)
Write-Host "  X++ v0.4.1 - COMPLETE AUTO SETUP (PowerShell)"
Write-Host ("=" * 70)
Write-Host "  Repo: $Root"
Write-Host ""

# ---------------------------------------------------------------
# 0. Admin notice
# ---------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) { Write-Info "Administrator privileges detected." } else { Write-Info "Running without admin - OK." }

# ---------------------------------------------------------------
# 1. Python
# ---------------------------------------------------------------
Write-Step "Python 3.9+"
$py = Get-PythonCmd
if (-not $py) {
    Install-Python
    $py = Get-PythonCmd
}
if (-not $py) {
    Write-Err "Python not available. Install Python 3.9+ and rerun."
    exit 1
}
Write-Ok "Python: $($py.Exe)  (v$($py.Version))"

# ---------------------------------------------------------------
# 2. VS Code
# ---------------------------------------------------------------
Write-Step "VS Code"
$code = Install-VSCode
if ($code) { Write-Ok "VS Code: $code" } else { Write-WarnX "VS Code not available - rerun setup after installing it." }

# ---------------------------------------------------------------
# 3. g++ / MinGW  (THE BIG ONE - auto install)
# ---------------------------------------------------------------
Write-Step "C++ compiler (g++)"
$gxx = Get-Gxx
if ($gxx) {
    Write-Ok "g++ found: $gxx"
} else {
    Write-Info "g++ not found - installing MSYS2 + MinGW-w64 automatically..."
    $gxx = Install-Gxx
    if ($gxx) { Write-Ok "g++ installed: $gxx" } else { Write-WarnX "g++ could not be installed (network/winget blocked). Native X++ needs it; legacy X++ still works." }
}

# ---------------------------------------------------------------
# 4. Run the universal setup python (builds VM, shims, icons...)
# ---------------------------------------------------------------
Write-Step "Installing X++ engine / VM / commands / icons"
& $py.Run "tools\xpp_setup.py" "--all"
if ($LASTEXITCODE -ne 0) {
    Write-Err "xpp_setup.py reported an error."
}

# ---------------------------------------------------------------
# 5. VS Code integration (copy ext + settings)
# ---------------------------------------------------------------
Write-Step "VS Code integration"
if ($code) {
    $ok = Copy-XppVSCodeExt
    if ($ok) { Update-VSCodeSettings }
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $code --install-extension formulahendry.code-runner --force 2>$null | Out-Null
    $ErrorActionPreference = $old
}
Register-WinIcons

# ---------------------------------------------------------------
# 6. Verify
# ---------------------------------------------------------------
Write-Step "VERIFY"
$binDir = Join-Path $HOME ".xpp\bin"
$xFile = Join-Path $binDir "x.cmd"
$xppvmFile = Join-Path $binDir "xppvm.exe"
$repoXppvm = Join-Path $Root "build\xppvm.exe"

if (Test-Path $xFile) {
    Write-Ok "x.cmd: $xFile"
    & $xFile version
} else {
    Write-Err "x.cmd missing at $xFile"
}

if (Test-Path $xppvmFile) {
    Write-Ok "xppvm.exe: $xppvmFile"
    & $xppvmFile version
} elseif (Test-Path $repoXppvm) {
    Write-Ok "xppvm.exe: $repoXppvm"
    Write-Info "Tip: add $Root\build to PATH or run: set XPP_NATIVE_DIR=$Root\build"
    & $repoXppvm version
} else {
    Write-WarnX "xppvm.exe not built yet. If g++ is now installed, just rerun setup.ps1."
}

Write-Host ""
Write-Host ("=" * 70)
Write-Host "  DONE!"
Write-Host ""
Write-Host "  1. Open a NEW terminal."
Write-Host "  2. Run:  x version"
Write-Host "  3. Run:  x run examples\hello.xp"
Write-Host "  4. Fast: x run examples\fib_fast.xp --mode ZJIT"
Write-Host ("=" * 70)
Write-Host ""
Read-Host "Press Enter to close"
