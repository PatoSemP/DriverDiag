function Write-DriverDiagHeader {
    Clear-Host
    Write-Host ''
    Write-Host '  DriverDiag' -ForegroundColor Cyan
    Write-Host '  Diagnostico e correcao de drivers (Catalog automatico)' -ForegroundColor DarkGray
    Write-Host ('  ' + ('-' * 60)) -ForegroundColor DarkGray
    Write-Host ''
}

function Read-DriverDiagCategories {
    Write-Host '  Selecione o escopo da varredura:' -ForegroundColor White
    Write-Host '    [0] Todos'
    $defs = @(Get-DriverDiagCategoryDefinitions)
    $i = 1
    foreach ($d in $defs) {
        Write-Host ("    [{0}] {1} - {2}" -f $i, $d.Title, $d.Subtitle)
        $i++
    }
    Write-Host ''
    Write-Host '  Numeros separados por virgula (ex: 1,2) ou 0: ' -NoNewline
    $raw = Read-Host
    if ([string]::IsNullOrWhiteSpace($raw) -or $raw.Trim() -eq '0') {
        return @('All')
    }
    $selected = [System.Collections.Generic.List[string]]::new()
    foreach ($part in ($raw -split '[,;\s]+')) {
        $n = 0
        if ([int]::TryParse($part, [ref]$n)) {
            if ($n -eq 0) { return @('All') }
            if ($n -ge 1 -and $n -le $defs.Count) {
                $selected.Add($defs[$n - 1].Id)
            }
        }
    }
    if ($selected.Count -eq 0) { return @('All') }
    return @($selected | Select-Object -Unique)
}

function Show-DriverDiagDeviceConsole {
    param($Device, [int]$Index)
    $badge = switch ($Device.Category) {
        'Missing' { 'FALTANDO' }
        'Broken' { 'QUEBRADO' }
        'Suspicious' { 'SUSPEITO' }
        default { $Device.Category }
    }
    $color = switch ($Device.Category) {
        'Missing' { 'Red' }
        'Broken' { 'Yellow' }
        default { 'DarkYellow' }
    }
    Write-Host ("  [{0}] " -f $Index) -NoNewline
    Write-Host $badge -ForegroundColor $color -NoNewline
    Write-Host ("  {0}" -f $Device.Model) -ForegroundColor White
    Write-Host ("       Categoria: {0}  |  Classe: {1}  |  Codigo: {2}" -f `
        $Device.DeviceCategoryTitle, $Device.Class, $Device.ProblemCode) -ForegroundColor DarkGray
    Write-Host ("       {0}" -f $Device.ProblemMessage) -ForegroundColor Gray
}

function Show-DriverDiagDeviceDetailsConsole {
    param($Device)
    Write-Host ''
    Write-Host '  --- Detalhes ---' -ForegroundColor Cyan
    Write-Host "  Modelo:     $($Device.Model)"
    Write-Host "  Categoria:  $($Device.DeviceCategoryTitle)"
    Write-Host "  Classe:     $($Device.Class)"
    Write-Host "  Status:     $($Device.Status) / $($Device.Category)"
    Write-Host "  Codigo:     $($Device.ProblemCode) - $($Device.ProblemMessage)"
    Write-Host "  Fabricante: $($Device.VendorName)"
    Write-Host "  Driver:     $($Device.DriverName)"
    Write-Host "  Provedor:   $($Device.DriverProvider)"
    Write-Host "  Versao:     $($Device.DriverVersion)"
    Write-Host "  INF:        $($Device.InfName)"
    Write-Host "  HW ID:      $($Device.PreferredHardwareId)"
    Write-Host ''
}

function Start-DriverDiagConsole {
    Write-DriverDiagHeader

    if (-not (Test-DriverDiagIsAdmin)) {
        Write-Host '  AVISO: sem elevacao - instalacao de drivers pode falhar.' -ForegroundColor Yellow
        Write-Host ''
    }

    $cats = Read-DriverDiagCategories
    Write-Host ''
    Write-Host '  Incluir suspeitos? [S/n]: ' -NoNewline
    $susp = Read-Host
    $includeSuspicious = -not ($susp -match '^[nN]')

    Write-Host ''
    Write-Host '  Varrendo dispositivos atuais...' -ForegroundColor Cyan
    $scanParams = @{ IncludeSuspicious = $includeSuspicious }
    if (-not ($cats -contains 'All')) { $scanParams.Categories = $cats }
    $devices = @(Invoke-DriverDiagScan @scanParams)

    if ($devices.Count -eq 0) {
        Write-Host '  Nenhum problema nos dispositivos atuais.' -ForegroundColor Green
        Write-Host ''
        Write-Host '  Pressione Enter para sair...' -NoNewline
        [void](Read-Host)
        return
    }

    $i = 0
    foreach ($d in $devices) {
        $i++
        Show-DriverDiagDeviceConsole -Device $d -Index $i
    }

    Write-Host ''
    Write-Host '  [A]uto todos  [C]orrigir um  [S]air: ' -NoNewline
    $mode = Read-Host

    if ($mode -match '^[aA]') {
        Write-Host '  Corrigindo automaticamente...' -ForegroundColor Cyan
        $batch = Invoke-DriverDiagAutoFixBatch -Devices $devices -ConfirmCritical -ProgressCallback {
            param($m) Write-Host "  $m" -ForegroundColor DarkGray
        }
        Write-Host "  $($batch.Summary)" -ForegroundColor Green
        foreach ($r in $batch.Results) {
            $col = if ($r.Success) { 'Green' } elseif ($r.Skipped) { 'DarkYellow' } else { 'Red' }
            Write-Host ("    {0}: {1}" -f $r.Device, $r.Message) -ForegroundColor $col
        }
    }
    elseif ($mode -match '^[cC]') {
        Write-Host '  Numero do dispositivo: ' -NoNewline
        $n = 0
        $raw = Read-Host
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $devices.Count) {
            Invoke-DriverDiagConsoleFix -Device $devices[$n - 1]
        }
    }

    Write-Host ''
    Write-Host '  Pressione Enter...' -NoNewline
    [void](Read-Host)
}

function Invoke-DriverDiagConsoleFix {
    param($Device)

    Write-Host "  Auto-fix: $($Device.Model)" -ForegroundColor Cyan
    $r = Invoke-DriverDiagAutoFixDevice -Device $Device -ConfirmCritical -ProgressCallback {
        param($m) Write-Host "  $m" -ForegroundColor DarkGray
    }
    if ($r.Success) {
        Write-Host "  OK: $($r.Message)" -ForegroundColor Green
    }
    else {
        Write-Host "  $($r.Message)" -ForegroundColor Yellow
        foreach ($l in @($r.Links)) {
            Write-Host "    $($l.Url)" -ForegroundColor DarkCyan
        }
    }
}
