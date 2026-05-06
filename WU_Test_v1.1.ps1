$_creator = "Mike Lu (lu.mike@inventec.com)"
$_version = '1.1'
$_changedate = 05/06/2026


# Set-ExecutionPolicy Bypass


# Self-elevate to admin
$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)
$scriptPath = if ($PSCommandPath) {
    $PSCommandPath 
} else { 
    $MyInvocation.MyCommand.Path 
}
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process PowerShell `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" `
        -Verb RunAs
    exit
}


# Check if run as admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Please run this script with administrator privileges " -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit..."
    exit
}

# Show menu
function Show-Menu {
    Write-Host ""
    Write-Host "** Windows Update & Softpaq Test **"
    Write-Host "                v$_version" -ForegroundColor 'DarkYellow'
    Write-Host "======================================"
    Write-Host " [1] Get XML file"
    Write-Host " [2] Add reg key (before WU testing)"
    Write-Host " [3] Check event ID (after WU testing)"
    Write-Host " [4] Install and run SPTest"
    Write-Host " [5] Check SPTest log"
    Write-Host "======================================"
}

function Invoke-GetXml {
    Write-Host ""
    Write-Host "=== Get XML file ===" -ForegroundColor Cyan
    Push-Location $PSScriptRoot
    try {
        .\bin\systemmanifestgenerator.exe /output manifest.xml
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host "Done!" -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "Failed or systemmanifestgenerator.exe not found." -ForegroundColor Red
        }
    } finally {
        Pop-Location
    }
}

function Invoke-AddTestRegistry {
    Write-Host ""
    Write-Host "Adding test registry key...." -ForegroundColor Cyan
    New-Item -Path "HKLM:\Software\Microsoft\DriverFlighting\Partner" -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path "HKLM:\Software\Microsoft\DriverFlighting\Partner" -Name "TargetRing" -Value "Drivers" -Type String -Force
    Get-ItemProperty -Path "HKLM:\Software\Microsoft\DriverFlighting\Partner" -Name "TargetRing" -ErrorAction SilentlyContinue
    Write-Host ""
    Write-Host "Done!" -ForegroundColor Green
}

function Invoke-CheckEvent307 {
    Write-Host ""
    Write-Host "Checking event ID 307..." -ForegroundColor Cyan
    try {
        Get-WinEvent -LogName 'Microsoft-Windows-DeviceUpdateAgent/Operational' -FilterXPath '*[System[(EventID=307)]]' -MaxEvents 1 -ErrorAction Stop |
            Select-Object TimeCreated, Id, Message | Format-List
    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

function Invoke-StartSPTest {
    Write-Host ""
    Write-Host "=== Install and run SPTest ===" -ForegroundColor Cyan

    $spTestExe = "C:\HP Inc\SPTest\SPTest.exe"
    $spTestRoot = "C:\HP Inc\SPTest"
    $installerPath = Join-Path $PSScriptRoot "bin\SPTestInstaller.msi"
    $spqDir = Join-Path $PSScriptRoot "SPQ_files"

    # 1) Ensure SPTest installed
    if (-not (Test-Path -LiteralPath $spTestExe)) {
        if (-not (Test-Path -LiteralPath $installerPath)) {
            Write-Host "SPTest not installed, and installer not found: $installerPath" -ForegroundColor Red
            return
        }

        # Write-Host "SPTest not found. Installing..." -ForegroundColor Yellow
        $msiArgs = @("/i", "`"$installerPath`"", "/quiet")
        $p = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru
        if ($p.ExitCode -ne 0) {
            Write-Host "SPTest install failed. msiexec exit code: $($p.ExitCode)" -ForegroundColor Red
            return
        }

        if (-not (Test-Path -LiteralPath $spTestExe)) {
            Write-Host "SPTest install finished, but SPTest.exe still not found at $spTestExe" -ForegroundColor Red
            return
        }
        Write-Host "SPTest installed." -ForegroundColor Green
    } else {
        Write-Host "SPTest already installed. Skipping install." -ForegroundColor DarkGray
    }

    # 2) Validate SPQ_files contains exactly one matching pair (spXXXXXX.exe + spXXXXXX.cva)
    if (-not (Test-Path -LiteralPath $spqDir)) {
        Write-Host "Folder not found: $spqDir" -ForegroundColor Red
        return
    }

    $exeFiles = Get-ChildItem -LiteralPath $spqDir -File -Filter "sp*.exe" -ErrorAction SilentlyContinue
    $cvaFiles = @()
    $cvaFiles += Get-ChildItem -LiteralPath $spqDir -File -Filter "sp*.cva" -ErrorAction SilentlyContinue

    if (-not $exeFiles -or $exeFiles.Count -eq 0) {
        Write-Host "EXE file not found in $spqDir" -ForegroundColor Red
        return
    }
    if (-not $cvaFiles -or $cvaFiles.Count -eq 0) {
        Write-Host "CVA file not found in $spqDir" -ForegroundColor Red
        return
    }

    $exeBases = @($exeFiles | ForEach-Object { $_.BaseName.ToLowerInvariant() })
    $cvaBases = @($cvaFiles | ForEach-Object { $_.BaseName.ToLowerInvariant() })
    $pairs = @($exeBases | Where-Object { $cvaBases -contains $_ } | Select-Object -Unique)

    if ($pairs.Count -eq 0) {
        Write-Host "EXE and CVA file name do not match: need spXXXXXX.exe and spXXXXXX.cva (same name)." -ForegroundColor Red
        return
    }
    if ($pairs.Count -gt 1) {
        Write-Host "Found multiple SPQ files!" -ForegroundColor Red
        return
    }

    $spBase = $pairs | Select-Object -First 1
    $exe = $exeFiles | Where-Object { $_.BaseName.ToLowerInvariant() -eq $spBase } | Select-Object -First 1
    $cva = $cvaFiles | Where-Object { $_.BaseName.ToLowerInvariant() -eq $spBase } | Select-Object -First 1

    # Detect "extra" unmatched files that might confuse users (optional but strict)
    $unmatchedExe = $exeFiles | Where-Object { $pairs -notcontains $_.BaseName.ToLowerInvariant() }
    $unmatchedCva = $cvaFiles | Where-Object { $pairs -notcontains $_.BaseName.ToLowerInvariant() }
    if (($unmatchedExe.Count -gt 0) -or ($unmatchedCva.Count -gt 0)) {
        Write-Host "Found multiple SPQ files!" -ForegroundColor Red
        return
    }

    # 3) Create C:\HP Inc\SPTest\spXXXXXX and copy files (overwrite)
    $destDir = Join-Path $spTestRoot $spBase
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null

    Copy-Item -LiteralPath $exe.FullName -Destination (Join-Path $destDir $exe.Name) -Force
    Copy-Item -LiteralPath $cva.FullName -Destination (Join-Path $destDir $cva.Name) -Force

    Write-Host "Copied $($exe.Name) and $($cva.Name) to $destDir" -ForegroundColor Green

    # 4) Run SPTest
    Write-Host ""
    Write-Host "Launching SPTest..." -ForegroundColor Cyan
    Write-Host ""
    $p = Start-Process -FilePath $spTestExe -ArgumentList @("/spq", $spBase) -WorkingDirectory $spTestRoot -Wait -PassThru
}

function Invoke-CheckSPTestLog {
    Write-Host ""
    Write-Host "=== Check SPTest log ===" -ForegroundColor Cyan

    $spTestRoot = "C:\HP Inc\SPTest"
    if (-not (Test-Path -LiteralPath $spTestRoot)) {
        Write-Host "Folder not found: $spTestRoot" -ForegroundColor Red
        return
    }

    $spDirs = Get-ChildItem -LiteralPath $spTestRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^sp\d{6,}$' }

    if (-not $spDirs -or $spDirs.Count -eq 0) {
        Write-Host "No spXXXXXX folder found under $spTestRoot" -ForegroundColor Red
        return
    }
    if ($spDirs.Count -gt 1) {
        Write-Host "Found multiple spXXXXXX folders under $spTestRoot. Please keep only one for log checking." -ForegroundColor Red
        return
    }

    $spDir = $spDirs | Select-Object -First 1
    $logFile = Join-Path $spDir.FullName "$($spDir.Name).log"
    if (-not (Test-Path -LiteralPath $logFile)) {
        Write-Host "Log file not found: $logFile" -ForegroundColor Red
        return
    }

    $content = Get-Content -LiteralPath $logFile -ErrorAction Stop

    function Get-StatusLineValue([string[]]$lines, [string]$prefix) {
        $line = $lines | Where-Object { $_ -match ("^\s*" + [regex]::Escape($prefix) + "\s*") } | Select-Object -First 1
        if (-not $line) { return $null }
        return ($line -replace ("^\s*" + [regex]::Escape($prefix) + "\s*"), "").Trim()
    }

    $overall = Get-StatusLineValue -lines $content -prefix "Overall Status:"
    $cvaInt = Get-StatusLineValue -lines $content -prefix "CVA Integrity Check:"
    $target = Get-StatusLineValue -lines $content -prefix "Targeting Check:"
    $install = Get-StatusLineValue -lines $content -prefix "Installation Check:"

    $expectedOverall = "REBOOT REQUIRED & PASS"
    $expectedPass = "PASS"

    function Normalize([string]$s) {
        if ($null -eq $s) { return $null }
        return ($s.Trim().TrimEnd('.')).ToUpperInvariant()
    }

    function Write-CheckResult([string]$label, [string]$actual, [string]$expectedNorm) {
        $actualNorm = Normalize $actual
        $ok = ($actualNorm -eq $expectedNorm)
        $color = if ($ok) { "Green" } else { "Red" }
        $show = if ($null -eq $actual) { "<NOT FOUND>" } else { $actual.Trim() }
        Write-Host ($label + " ") -NoNewline
        Write-Host $show -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "Log file: $logFile" -ForegroundColor Yellow
    Write-Host ""
    Write-CheckResult -label "Overall Status:" -actual $overall -expectedNorm (Normalize $expectedOverall)
    Write-CheckResult -label "CVA Integrity Check:" -actual $cvaInt -expectedNorm (Normalize $expectedPass)
    Write-CheckResult -label "Targeting Check:" -actual $target -expectedNorm (Normalize $expectedPass)
    Write-CheckResult -label "Installation Check:" -actual $install -expectedNorm (Normalize $expectedPass)

    Write-Host ""
}


# Main
Show-Menu
do {
    $choice = Read-Host "Select a function"
} until ($choice -in @('1', '2', '3', '4', '5'))

switch ($choice) {
    "1" { Invoke-GetXml }
    "2" { Invoke-AddTestRegistry }
    "3" { Invoke-CheckEvent307 }
    "4" { Invoke-StartSPTest }
    "5" { Invoke-CheckSPTestLog }
}

Write-Host ""
Read-Host "Press Enter to exit..." 
[void][System.Console]::ReadLine()