$_creator = "Mike Lu (lu.mike@inventec.com)"
$_version = '1.0'
$_changedate = 02/06/2026

# Set-ExecutionPolicy RemoteSigned


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
    Write-Host "** Windows Update Test " -NoNewline
    Write-Host "v$_version" -ForegroundColor 'DarkYellow' -NoNewline
    Write-Host " **"
    Write-Host "===================================="
    Write-Host " [1] Get XML file"
    Write-Host " [2] Add reg key (before testing)"
    Write-Host " [3] Check event ID (after testing)"
    Write-Host "===================================="
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

# Main
Show-Menu
do {
    $choice = Read-Host "Select a function"
} until ($choice -eq '1' -or $choice -eq '2' -or $choice -eq '3')

switch ($choice) {
    "1" { Invoke-GetXml }
    "2" { Invoke-AddTestRegistry }
    "3" { Invoke-CheckEvent307 }
}

Write-Host ""
Read-Host "Press Enter to exit..."
