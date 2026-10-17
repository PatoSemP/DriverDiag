function Get-DriverDiagDownloadRoot {
    $root = Join-Path $env:USERPROFILE 'Downloads\DriverDiag'
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }
    return $root
}

function Get-DriverDiagSanitizeName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return 'device' }
    $s = $Name -replace '[^\w\.\-]+', '_'
    if ($s.Length -gt 48) { $s = $s.Substring(0, 48) }
    return $s.Trim('_')
}

function Get-DriverDiagDeviceDownloadFolder {
    param([Parameter(Mandatory)]$Device)
    $name = Get-DriverDiagSanitizeName -Name $Device.Model
    $folder = Join-Path (Get-DriverDiagDownloadRoot) $name
    if (-not (Test-Path -LiteralPath $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
    return $folder
}

function Test-DriverDiagIsAdmin {
    try {
        $wi = [Security.Principal.WindowsIdentity]::GetCurrent()
        $wp = New-Object Security.Principal.WindowsPrincipal($wi)
        return $wp.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Test-DriverDiagNeedsExtraConfirm {
    param([Parameter(Mandatory)]$Device)
    $sensitiveClasses = @('Display', 'SCSIAdapter', 'HDC', 'DiskDrive')
    $sensitiveCats = @('Display', 'Storage')
    if ($Device.Class -and ($sensitiveClasses -contains $Device.Class)) { return $true }
    if ($Device.DeviceCategory -and ($sensitiveCats -contains $Device.DeviceCategory)) { return $true }
    return $false
}

function Get-DriverDiagCriticalConfirmMessage {
    param([Parameter(Mandatory)]$Device)
    return "Classe sensivel ($($Device.Class)): $($Device.Model)`r`n`r`nGPU/armazenamento - confirma instalacao?"
}

function Invoke-DriverDiagRescan {
    try { & pnputil.exe /scan-devices 2>$null | Out-Null } catch { }
}

function Expand-DriverDiagPackage {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    $ext = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    $extractDir = Join-Path $Destination ("extracted_" + [IO.Path]::GetFileNameWithoutExtension($FilePath))
    if (-not (Test-Path -LiteralPath $extractDir)) {
        New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
    }

    switch ($ext) {
        '.zip' {
            Expand-Archive -LiteralPath $FilePath -DestinationPath $extractDir -Force
            return $extractDir
        }
        '.cab' {
            & expand.exe $FilePath -F:* $extractDir 2>$null | Out-Null
            if (-not (Get-ChildItem -LiteralPath $extractDir -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)) {
                Copy-Item -LiteralPath $FilePath -Destination $extractDir -Force
            }
            return $extractDir
        }
        '.msu' {
            & expand.exe $FilePath -F:* $extractDir 2>$null | Out-Null
            return $extractDir
        }
        '.exe' {
            return $null
        }
        default {
            Copy-Item -LiteralPath $FilePath -Destination $extractDir -Force
            return $extractDir
        }
    }
}

function Find-DriverDiagInfFiles {
    param([string[]]$SearchRoots)
    $infs = [System.Collections.Generic.List[string]]::new()
    foreach ($root in $SearchRoots) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object { $infs.Add($_.FullName) }
    }
    return @($infs | Select-Object -Unique)
}

function Remove-DriverDiagOemPackage {
    param(
        [string]$InfName,
        [switch]$ForceGuiConfirm
    )

    if ([string]::IsNullOrWhiteSpace($InfName)) {
        return [pscustomobject]@{ Success = $false; Message = 'INF atual desconhecido.' }
    }

    $published = $InfName
    if ($InfName -notmatch '(?i)^oem\d+\.inf$') {
        return [pscustomobject]@{ Success = $false; Message = "Pacote nao e oemXX.inf ($InfName) - remocao automatica ignorada." }
    }

    try {
        $out = & pnputil.exe /delete-driver $published /uninstall /force 2>&1 | Out-String
        return [pscustomobject]@{
            Success = ($LASTEXITCODE -eq 0)
            Message = $out.Trim()
        }
    }
    catch {
        return [pscustomobject]@{ Success = $false; Message = "$_" }
    }
}

function Confirm-DriverDiagGui {
    param(
        [string]$Text,
        [string]$Title = 'DriverDiag'
    )
    if (-not ('System.Windows.Forms.MessageBox' -as [type])) {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    }
    $r = [System.Windows.Forms.MessageBox]::Show(
        $Text, $Title,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )
    return ($r -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Start-DriverDiagExeInstaller {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Start-Process -FilePath $Path
}

function Install-DriverDiagFromFiles {
    param(
        [Parameter(Mandatory)][string[]]$Files,
        [string]$WorkFolder,
        [switch]$Install,
        [scriptblock]$ProgressCallback = $null
    )

    if (-not $WorkFolder) {
        $WorkFolder = Join-Path (Get-DriverDiagDownloadRoot) '_install'
    }
    if (-not (Test-Path -LiteralPath $WorkFolder)) {
        New-Item -ItemType Directory -Path $WorkFolder -Force | Out-Null
    }

    $searchRoots = [System.Collections.Generic.List[string]]::new()
    $exeInstallers = [System.Collections.Generic.List[string]]::new()
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($f in $Files) {
        if (-not (Test-Path -LiteralPath $f)) { continue }
        $ext = [IO.Path]::GetExtension($f).ToLowerInvariant()
        if ($ext -eq '.exe') {
            $exeInstallers.Add($f)
            continue
        }
        if ($ProgressCallback) { & $ProgressCallback "Extraindo $(Split-Path $f -Leaf)..." }
        $extracted = Expand-DriverDiagPackage -FilePath $f -Destination $WorkFolder
        if ($extracted) { $searchRoots.Add($extracted) }
        $searchRoots.Add((Split-Path -Parent $f))
    }

    $infs = Find-DriverDiagInfFiles -SearchRoots @($searchRoots)

    if ($exeInstallers.Count -gt 0 -and $infs.Count -eq 0) {
        return [pscustomobject]@{
            Success      = $false
            NeedsExeRun  = $true
            ExeInstaller = $exeInstallers[0]
            Message      = 'Pacote e instalador .exe OEM.'
            Results      = @()
            InfFiles     = @()
        }
    }

    if (-not $Install) {
        return [pscustomobject]@{
            Success      = ($infs.Count -gt 0)
            NeedsExeRun  = $false
            ExeInstaller = $null
            Message      = if ($infs.Count -gt 0) { "$($infs.Count) INF(s) prontos." } else { 'Nenhum INF encontrado.' }
            Results      = @()
            InfFiles     = $infs
        }
    }

    if (-not (Test-DriverDiagIsAdmin)) {
        return [pscustomobject]@{
            Success      = $false
            NeedsExeRun  = $false
            ExeInstaller = $null
            Message      = 'Requer Administrador.'
            Results      = @()
            InfFiles     = $infs
        }
    }

    $installedAny = $false
    foreach ($inf in $infs) {
        if ($ProgressCallback) { & $ProgressCallback "pnputil: $(Split-Path $inf -Leaf)" }
        try {
            $out = & pnputil.exe /add-driver $inf /install 2>&1 | Out-String
            $ok = ($LASTEXITCODE -eq 0)
            if ($ok) { $installedAny = $true }
            $results.Add([pscustomobject]@{ Inf = $inf; Success = $ok; Output = $out.Trim() })
        }
        catch {
            $results.Add([pscustomobject]@{ Inf = $inf; Success = $false; Output = "$_" })
        }
    }

    Invoke-DriverDiagRescan

    return [pscustomobject]@{
        Success      = $installedAny
        NeedsExeRun  = $false
        ExeInstaller = $null
        Message      = if ($installedAny) { 'Driver instalado via pnputil.' } else { 'Falha ao instalar INF(s).' }
        Results      = @($results)
        InfFiles     = $infs
    }
}

function Install-DriverDiagPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Device,
        [Parameter(Mandatory)][string[]]$Files,
        [switch]$ConfirmDeleteWrong,
        [switch]$GuiMode
    )

    if (-not (Test-DriverDiagIsAdmin)) {
        return [pscustomobject]@{ Success = $false; Message = 'Requer Administrador.' }
    }

    $dest = Get-DriverDiagDeviceDownloadFolder -Device $Device
    $messages = [System.Collections.Generic.List[string]]::new()
    $searchRoots = [System.Collections.Generic.List[string]]::new()
    $exeInstallers = [System.Collections.Generic.List[string]]::new()

    foreach ($f in $Files) {
        if (-not (Test-Path -LiteralPath $f)) { continue }
        $ext = [IO.Path]::GetExtension($f).ToLowerInvariant()
        if ($ext -eq '.exe') {
            $exeInstallers.Add($f)
            continue
        }
        $extracted = Expand-DriverDiagPackage -FilePath $f -Destination $dest
        if ($extracted) { $searchRoots.Add($extracted) }
        $searchRoots.Add((Split-Path -Parent $f))
    }

    if ($ConfirmDeleteWrong -and $Device.InfName -match '(?i)^oem\d+\.inf$' -and $Device.Category -in @('Broken', 'Suspicious', 'Missing')) {
        $doDelete = $true
        if ($GuiMode) {
            $doDelete = Confirm-DriverDiagGui -Text (
                "Remover o pacote de driver atual ($($Device.InfName)) antes de instalar o novo?`r`n`r`n" +
                "Provedor atual: $($Device.DriverProvider)"
            ) -Title 'Remover driver antigo'
        }
        else {
            Write-Host "Remover pacote atual $($Device.InfName)? [S/N]" -ForegroundColor Yellow
            $a = Read-Host
            $doDelete = ($a -match '^[sSyY]')
        }
        if ($doDelete) {
            $rm = Remove-DriverDiagOemPackage -InfName $Device.InfName
            $messages.Add("Remocao: $($rm.Message)")
        }
    }

    $infs = Find-DriverDiagInfFiles -SearchRoots @($searchRoots)
    if ($infs.Count -gt 0) {
        $installedAny = $false
        foreach ($inf in $infs) {
            try {
                $out = & pnputil.exe /add-driver $inf /install 2>&1 | Out-String
                $messages.Add("pnputil $inf : $(($out -replace '\s+', ' ').Trim())")
                if ($LASTEXITCODE -eq 0) { $installedAny = $true }
            }
            catch {
                $messages.Add("Falha pnputil $inf : $_")
            }
        }

        Invoke-DriverDiagRescan

        return [pscustomobject]@{
            Success  = $installedAny
            Message  = ($messages -join "`r`n")
            InfFiles = $infs
        }
    }

    if ($exeInstallers.Count -gt 0) {
        $exe = $exeInstallers[0]
        $run = $true
        if ($GuiMode) {
            $run = Confirm-DriverDiagGui -Text "Nenhum INF encontrado. Executar instalador OEM?`r`n$exe" -Title 'Instalador OEM'
        }
        else {
            Write-Host "Executar instalador OEM?`n$exe`n[S/N]" -ForegroundColor Yellow
            $a = Read-Host
            $run = ($a -match '^[sSyY]')
        }
        if ($run) {
            Start-Process -FilePath $exe -Wait
            Invoke-DriverDiagRescan
            return [pscustomobject]@{
                Success  = $true
                Message  = "Instalador OEM executado: $exe"
                InfFiles = @()
            }
        }
        return [pscustomobject]@{ Success = $false; Message = 'Instalador OEM cancelado.'; InfFiles = @() }
    }

    return [pscustomobject]@{
        Success  = $false
        Message  = "Nenhum INF nem instalador EXE encontrado em: $($Files -join ', ')"
        InfFiles = @()
    }
}
