function Get-DriverDiagOsHints {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $arch = $env:PROCESSOR_ARCHITECTURE
    $is64 = ($arch -eq 'AMD64') -or ([Environment]::Is64BitOperatingSystem)
    $caption = if ($os) { [string]$os.Caption } else { '' }
    $build = if ($os) { [int]$os.BuildNumber } else { 0 }
    $win11 = $build -ge 22000
    $win10 = ($build -ge 10240) -and (-not $win11)

    return [pscustomobject]@{
        Caption = $caption
        Build   = $build
        Is64    = $is64
        Win11   = $win11
        Win10   = $win10
        ArchToken = if ($is64) { 'x64' } else { 'x86' }
    }
}

function Get-DriverDiagCandidateScore {
    param(
        [Parameter(Mandatory)]$Candidate,
        [Parameter(Mandatory)]$Device,
        $OsHints = $null
    )

    if (-not $OsHints) { $OsHints = Get-DriverDiagOsHints }
    $score = 0
    $title = [string]$Candidate.Title
    $products = [string]$Candidate.Products
    $classif = [string]$Candidate.Classification
    $blob = "$title $products $classif"

    if ($Candidate.CanDownload) { $score += 100 }
    if ($Candidate.Source -eq 'Catalog') { $score += 40 }
    if ($classif -match '(?i)driver') { $score += 25 }
    if ($title -match '(?i)driver') { $score += 10 }

    if ($OsHints.Is64 -and $blob -match '(?i)x64|64[\-\s]?bit|amd64') { $score += 30 }
    if (-not $OsHints.Is64 -and $blob -match '(?i)x86|32[\-\s]?bit') { $score += 30 }
    if ($OsHints.Is64 -and $blob -match '(?i)\bx86\b' -and $blob -notmatch '(?i)x64') { $score -= 40 }

    if ($OsHints.Win11 -and $blob -match '(?i)Windows 11|Win11|W11') { $score += 35 }
    elseif ($OsHints.Win10 -and $blob -match '(?i)Windows 10|Win10|W10') { $score += 35 }
    elseif ($blob -match '(?i)Windows 1[01]') { $score += 15 }
    if ($blob -match '(?i)Windows 7|Windows 8|Windows Vista|Windows XP') { $score -= 25 }

    if ($Device.VendorId -and $blob -match [regex]::Escape($Device.VendorId)) { $score += 15 }
    if ($Device.DeviceId -and $blob -match [regex]::Escape($Device.DeviceId)) { $score += 20 }
    if ($Device.PreferredHardwareId) {
        $short = $null
        if ($Device.PreferredHardwareId -match '(VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4})') { $short = $Matches[1] }
        if ($short -and $blob -match [regex]::Escape($short)) { $score += 25 }
    }

    $class = [string]$Device.Class
    $cat = [string]$Device.DeviceCategory
    if ($class -eq 'Net' -or $cat -eq 'Network') {
        if ($blob -match '(?i)network|ethernet|wireless|wifi|wlan|lan|bluetooth') { $score += 20 }
    }
    if ($class -eq 'MEDIA' -or $cat -eq 'Audio') {
        if ($blob -match '(?i)audio|sound|hd audio|realtek') { $score += 20 }
    }
    if ($class -eq 'Display' -or $cat -eq 'Display') {
        if ($blob -match '(?i)display|graphics|video|radeon|geforce') { $score += 20 }
    }

    if ($Candidate.PSObject.Properties.Name -contains 'Score' -and $Candidate.Score) {
        $score += [int]$Candidate.Score
    }

    return $score
}

function Select-DriverDiagBestCandidate {
    param(
        [AllowEmptyCollection()]
        [object[]]$Candidates = @(),
        [Parameter(Mandatory)]$Device,
        [switch]$DownloadableOnly
    )

    if (-not $Candidates -or @($Candidates).Count -eq 0) { return $null }

    $os = Get-DriverDiagOsHints
    $pool = @($Candidates)
    if ($DownloadableOnly) {
        $pool = @($pool | Where-Object { $_.CanDownload -and $_.Source -eq 'Catalog' })
        if ($pool.Count -eq 0) {
            $pool = @($Candidates | Where-Object { $_.CanDownload })
        }
    }
    if ($pool.Count -eq 0) { return $null }

    $ranked = foreach ($c in $pool) {
        $s = Get-DriverDiagCandidateScore -Candidate $c -Device $Device -OsHints $os
        [pscustomobject]@{
            Candidate = $c
            RankScore = $s
        }
    }
    $best = $ranked | Sort-Object RankScore -Descending | Select-Object -First 1
    if (-not $best) { return $null }
    $pick = $best.Candidate
    $pick | Add-Member -NotePropertyName RankScore -NotePropertyValue $best.RankScore -Force
    return $pick
}

function Invoke-DriverDiagAutoFixDevice {
    <#
      Busca Catalog, escolhe o melhor, baixa e instala.
      Sem dialog de lista. So confirma GPU/storage se -ConfirmCritical.
    #>
    param(
        [Parameter(Mandatory)]$Device,
        [scriptblock]$ProgressCallback = $null,
        [switch]$ConfirmCritical,
        [switch]$SkipInstallConfirm,
        [System.Windows.Forms.Form]$Owner = $null
    )

    $say = {
        param($m)
        if ($ProgressCallback) { & $ProgressCallback $m }
    }

    if ($ConfirmCritical -and (Test-DriverDiagNeedsExtraConfirm -Device $Device)) {
        if ($Owner -and (Get-Command Confirm-DriverDiagGui -ErrorAction SilentlyContinue)) {
            $ok = Confirm-DriverDiagGui -Text (Get-DriverDiagCriticalConfirmMessage -Device $Device) -Title 'Confirmacao critica'
            if (-not $ok) {
                return [pscustomobject]@{
                    Success = $false; Skipped = $true; Device = $Device.Model
                    Message = 'Pulado (classe sensivel).'
                }
            }
        }
    }

    & $say "Preparando busca: $($Device.Model)..."
    $catalog = @()
    try {
        $catalog = @(Find-DriverDiagCatalogCandidates -Device $Device -MaxResults 15 -ProgressCallback $ProgressCallback)
    }
    catch {
        & $say "Catalog: $_"
    }

    $best = $null
    if (@($catalog).Count -gt 0) {
        $best = Select-DriverDiagBestCandidate -Candidates @($catalog) -Device $Device -DownloadableOnly
    }

    if (-not $best) {
        $oem = @()
        try { $oem = @(Find-DriverDiagOemCandidates -Device $Device -MaxResults 5) } catch { }
        $links = Get-DriverDiagFallbackLinks -Device $Device -CatalogCandidates $catalog -OemCandidates $oem
        return [pscustomobject]@{
            Success      = $false
            Skipped      = $false
            Device       = $Device.Model
            Message      = 'Sem pacote baixavel no Catalog para este dispositivo.'
            Links        = $links
            Candidate    = $null
            Files        = @()
        }
    }

    & $say "Baixando: $($best.Title)"
    $dest = Get-DriverDiagDeviceDownloadFolder -Device $Device
    $dl = Save-DriverDiagCandidatePackage -Candidate $best -Destination $dest -ProgressCallback $ProgressCallback

    if (-not $dl.Success) {
        $links = Get-DriverDiagFallbackLinks -Device $Device -CatalogCandidates $catalog
        return [pscustomobject]@{
            Success   = $false
            Skipped   = $false
            Device    = $Device.Model
            Message   = "Download falhou: $($dl.ErrorMessage)"
            Links     = $links
            Candidate = $best
            Files     = @()
        }
    }

    & $say "Instalando: $($Device.Model)..."
    $work = Join-Path $dest '_install'
    $install = Install-DriverDiagFromFiles -Files $dl.Files -WorkFolder $work -Install -ProgressCallback $ProgressCallback

    if ($install.NeedsExeRun -and $install.ExeInstaller) {
        Start-DriverDiagExeInstaller -Path $install.ExeInstaller
        return [pscustomobject]@{
            Success   = $true
            Skipped   = $false
            Device    = $Device.Model
            Message   = "Instalador OEM iniciado: $($best.Title)"
            Links     = @()
            Candidate = $best
            Files     = $dl.Files
        }
    }

    if ($install.Success) {
        return [pscustomobject]@{
            Success   = $true
            Skipped   = $false
            Device    = $Device.Model
            Message   = "OK: $($best.Title)"
            Links     = @()
            Candidate = $best
            Files     = $dl.Files
        }
    }

    return [pscustomobject]@{
        Success   = $false
        Skipped   = $false
        Device    = $Device.Model
        Message   = "Instalacao falhou: $($install.Message)"
        Links     = @()
        Candidate = $best
        Files     = $dl.Files
    }
}

function Invoke-DriverDiagAutoFixBatch {
    param(
        [AllowEmptyCollection()]
        [object[]]$Devices = @(),
        [scriptblock]$ProgressCallback = $null,
        [switch]$ConfirmCritical,
        [System.Windows.Forms.Form]$Owner = $null
    )

    $results = [System.Collections.Generic.List[object]]::new()
    if (-not $Devices -or @($Devices).Count -eq 0) {
        return [pscustomobject]@{
            Results = @()
            Ok = 0; Fail = 0; Skip = 0; Total = 0
            Summary = 'Nenhum dispositivo na lista.'
        }
    }

    $i = 0
    $total = @($Devices | Where-Object { -not $_.Skipped }).Count
    foreach ($d in $Devices) {
        if ($d.Skipped) { continue }
        $i++
        if ($ProgressCallback) {
            & $ProgressCallback "[$i/$total] $($d.Model)"
        }
        $r = Invoke-DriverDiagAutoFixDevice -Device $d -ProgressCallback $ProgressCallback `
            -ConfirmCritical:$ConfirmCritical -Owner $Owner -SkipInstallConfirm
        $results.Add($r)
    }

    try { Invoke-DriverDiagRescan } catch { }

    $ok = @($results | Where-Object { $_.Success }).Count
    $fail = @($results | Where-Object { -not $_.Success -and -not $_.Skipped }).Count
    $skip = @($results | Where-Object { $_.Skipped }).Count

    return [pscustomobject]@{
        Results = @($results)
        Ok      = $ok
        Fail    = $fail
        Skip    = $skip
        Total   = $results.Count
        Summary = "Concluidos: $ok ok, $fail falha, $skip pulados (de $($results.Count))"
    }
}
