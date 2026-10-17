[CmdletBinding()]
param(
    [switch]$Console,
    [string[]]$Categories,
    [switch]$IncludeSuspicious,
    [switch]$IncludeDisconnected,
    [switch]$ScanOnly
)

$ErrorActionPreference = 'Stop'
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
}
catch { }

$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Test-DriverDiagAdminNow {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# UAC aqui (nao no .cmd) - caminho com acento/espaco quebrava o RunAs do bat
if (-not $ScanOnly -and -not (Test-DriverDiagAdminNow)) {
    $arg = "-NoProfile -STA -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($Console) { $arg += ' -Console' }
    try {
        Start-Process -FilePath $psExe -Verb RunAs -ArgumentList $arg | Out-Null
    }
    catch {
        Write-Host 'Elevacao cancelada ou falhou.' -ForegroundColor Yellow
        Write-Host $_
        Write-Host 'Enter para fechar...' -NoNewline
        [void](Read-Host)
        exit 1
    }
    exit 0
}

# WinForms precisa de STA; sem isso a janela abre e fecha na hora
if (-not $Console -and -not $ScanOnly) {
    $apt = [System.Threading.Thread]::CurrentThread.GetApartmentState()
    if ($apt -ne [System.Threading.ApartmentState]::STA) {
        $relaunch = "-NoProfile -STA -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        $p = Start-Process -FilePath $psExe -ArgumentList $relaunch -PassThru -Wait
        exit $p.ExitCode
    }
}

$root = $PSScriptRoot
$modules = @(
    'Categories.ps1',
    'Identify.ps1',
    'Scan.ps1',
    'Catalog.ps1',
    'Oem.ps1',
    'Fix.ps1',
    'AutoFix.ps1',
    'Ui.ps1',
    'Gui.ps1'
)

foreach ($m in $modules) {
    $path = Join-Path $root "modules\$m"
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Modulo ausente: $path"
    }
    . $path
}

if (-not $PSBoundParameters.ContainsKey('IncludeSuspicious')) {
    $IncludeSuspicious = $true
}

try {
    if ($ScanOnly) {
        $scanParams = @{
            IncludeSuspicious   = $IncludeSuspicious
            IncludeDisconnected = $IncludeDisconnected
        }
        if ($Categories -and $Categories.Count -gt 0) { $scanParams.Categories = $Categories }
        $devices = @(Invoke-DriverDiagScan @scanParams)
        $devices | Select-Object Category, DeviceCategoryTitle, Model, Class, ProblemCode, ProblemMessage, VendorName, DriverProvider, DriverVersion, PreferredHardwareId |
            Format-Table -AutoSize
        Write-Host ("Total: {0}" -f $devices.Count)
        return
    }

    if ($Console) {
        if ($Categories -and $Categories.Count -gt 0) {
            Write-Host 'DriverDiag (console) - escopo: ' -NoNewline
            Write-Host (($Categories | ForEach-Object { Get-DriverDiagCategoryTitle $_ }) -join ', ')
            $devices = @(Invoke-DriverDiagScan -Categories $Categories -IncludeSuspicious:$IncludeSuspicious -IncludeDisconnected:$IncludeDisconnected)
            if ($devices.Count -eq 0) {
                Write-Host 'Nenhum problema encontrado.' -ForegroundColor Green
                return
            }
            $i = 0
            foreach ($d in $devices) {
                $i++
                Show-DriverDiagDeviceConsole -Device $d -Index $i
                Write-Host ''
                Write-Host '  [C]orrigir  [P]ular  [D]etalhes  [S]air: ' -NoNewline
                $opt = Read-Host
                switch -Regex ($opt) {
                    '^[cC]' { Invoke-DriverDiagConsoleFix -Device $d }
                    '^[dD]' { Show-DriverDiagDeviceDetailsConsole -Device $d; $i--; continue }
                    '^[sS]' { return }
                }
            }
        }
        else {
            Start-DriverDiagConsole
        }
    }
    else {
        Start-DriverDiagGui
    }
}
catch {
    $msg = $_ | Out-String
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show($msg, 'DriverDiag - erro') | Out-Null
    }
    catch {
        Write-Host $msg -ForegroundColor Red
    }
    Write-Host $msg -ForegroundColor Red
    Write-Host 'Enter para fechar...' -NoNewline
    [void](Read-Host)
    exit 1
}
