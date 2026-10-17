$script:ProblemCodeMessages = @{
    1  = 'Configuracao incorreta do dispositivo (Codigo 1)'
    3  = 'Driver danificado ou incompleto (Codigo 3)'
    10 = 'Dispositivo nao inicia (Codigo 10)'
    12 = 'Recursos insuficientes (Codigo 12)'
    14 = 'Reinicie o computador (Codigo 14)'
    18 = 'Reinstale os drivers (Codigo 18)'
    19 = 'Registro danificado (Codigo 19)'
    21 = 'Dispositivo sendo removido (Codigo 21)'
    22 = 'Dispositivo desabilitado (Codigo 22)'
    24 = 'Dispositivo inexistente ou nao funcionando (Codigo 24)'
    28 = 'Drivers nao instalados (Codigo 28)'
    29 = 'Dispositivo desabilitado no firmware (Codigo 29)'
    31 = 'Windows nao determina as definicoes do dispositivo (Codigo 31)'
    32 = 'Servico do driver desabilitado (Codigo 32)'
    33 = 'Tradutor nao consegue traduzir recursos (Codigo 33)'
    34 = 'Windows nao determina a configuracao (Codigo 34)'
    35 = 'Firmware do sistema insuficiente (Codigo 35)'
    36 = 'IRQ interrompido (Codigo 36)'
    37 = 'Driver do dispositivo retornou falha (Codigo 37)'
    38 = 'Driver anterior ainda carregado (Codigo 38)'
    39 = 'Windows nao carrega o driver (Codigo 39)'
    40 = 'Informacoes de hardware ausentes no registro (Codigo 40)'
    41 = 'Dispositivo nao presente (Codigo 41)'
    42 = 'Ja existe uma instancia do dispositivo (Codigo 42)'
    43 = 'Windows parou este dispositivo (Codigo 43)'
    44 = 'Aplicativo ou servico encerrou o dispositivo (Codigo 44)'
    45 = 'Dispositivo nao conectado (Codigo 45)'
    46 = 'Windows nao acessa o dispositivo (Codigo 46)'
    47 = 'Seguranca do sistema removeu o dispositivo (Codigo 47)'
    48 = 'Software de suporte bloqueado (Codigo 48)'
    49 = 'Hive do sistema muito grande (Codigo 49)'
    50 = 'Windows nao aplica propriedades do dispositivo (Codigo 50)'
    51 = 'Dispositivo aguardando outro dispositivo (Codigo 51)'
    52 = 'Assinatura digital invalida no driver (Codigo 52)'
    53 = 'Dispositivo reservado para Windows Recovery (Codigo 53)'
    54 = 'Reinicie o computador (Codigo 54)'
}

# Classes worth checking for "Suspicious" (generic MS driver on OEM hardware)
$script:SuspiciousScanClasses = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
@(
    'Net', 'NetClient', 'NetService', 'NetTrans', 'Bluetooth', 'Modem',
    'MEDIA', 'AudioEndpoint',
    'Display', 'Monitor',
    'Image', 'Camera', 'Biometric', 'SmartCardReader',
    'SCSIAdapter', 'HDC',
    'USB', 'USBDevice'
) | ForEach-Object { [void]$script:SuspiciousScanClasses.Add($_) }

function Get-DriverDiagProblemMessage {
    param([int]$Code)
    if ($script:ProblemCodeMessages.ContainsKey($Code)) {
        return $script:ProblemCodeMessages[$Code]
    }
    if ($Code -gt 0) {
        return "Problema do dispositivo (Codigo $Code)"
    }
    return $null
}

function Get-DriverDiagClassCategoryMap {
    if ($script:ClassCategoryMap) { return $script:ClassCategoryMap }

    $map = @{}
    foreach ($d in @(Get-DriverDiagCategoryDefinitions)) {
        if ($d.Id -eq 'Other') { continue }
        foreach ($c in @($d.Classes)) {
            if ($c -and -not $map.ContainsKey($c)) {
                $map[$c] = $d.Id
            }
        }
    }
    $script:ClassCategoryMap = $map
    return $map
}

function Test-DriverDiagClassMayMatchCategories {
    param(
        [string]$Class,
        [string]$FriendlyName,
        [string[]]$FilterCategories
    )

    if (-not $FilterCategories -or $FilterCategories.Count -eq 0) { return $true }
    if ($FilterCategories -contains 'All') { return $true }
    if ($FilterCategories -contains 'Other') { return $true }

    # Unknown / empty class can still be Missing — keep them
    if ([string]::IsNullOrWhiteSpace($Class) -or $Class -eq 'Unknown') { return $true }

    $map = Get-DriverDiagClassCategoryMap
    if ($map.ContainsKey($Class)) {
        return ($FilterCategories -contains $map[$Class])
    }

    # Class not in map: may match via keywords later — only keep if name hints at filter
    if ($FriendlyName) {
        $model = $FriendlyName.ToLowerInvariant()
        foreach ($d in @(Get-DriverDiagCategoryDefinitions)) {
            if ($FilterCategories -notcontains $d.Id) { continue }
            foreach ($k in @($d.Keywords)) {
                if ($model -like "*$k*") { return $true }
            }
        }
    }

    return $false
}

function Get-DriverDiagPnputilProblemDevices {
    $map = @{}
    try {
        $output = & pnputil.exe /enum-devices /problem /deviceids 2>$null
        if (-not $output) { return $map }

        $current = $null
        foreach ($line in $output) {
            if ($line -match '^\s*Instance ID:\s*(.+)\s*$') {
                $id = $Matches[1].Trim()
                $current = [ordered]@{
                    InstanceId  = $id
                    DeviceIds   = [System.Collections.Generic.List[string]]::new()
                    ProblemCode = $null
                    Status      = $null
                }
                $map[$id] = $current
            }
            elseif ($current -and $line -match '^\s*Device ID:\s*(.+)\s*$') {
                $current.DeviceIds.Add($Matches[1].Trim())
            }
            elseif ($current -and $line -match '^\s*Problem Code:\s*(.+)\s*$') {
                $raw = $Matches[1].Trim()
                if ($raw -match '0x([0-9A-Fa-f]+)') {
                    $current.ProblemCode = [Convert]::ToInt32($Matches[1], 16)
                }
                elseif ($raw -match '(\d+)') {
                    $current.ProblemCode = [int]$Matches[1]
                }
            }
            elseif ($current -and $line -match '^\s*Status:\s*(.+)\s*$') {
                $current.Status = $Matches[1].Trim()
            }
        }
    }
    catch {
        Write-Verbose "pnputil /enum-devices falhou: $_"
    }
    return $map
}

function Get-DriverDiagWmiEntities {
    $byId = @{}
    try {
        $entities = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop
        foreach ($e in $entities) {
            if ($e.DeviceID) {
                $byId[$e.DeviceID] = $e
            }
        }
    }
    catch {
        Write-Verbose "Win32_PnPEntity falhou: $_"
    }
    return $byId
}

function Get-DriverDiagSignedDriverMap {
    # One CIM query (~1s) vs Get-PnpDeviceProperty (~1.5s each)
    $byId = @{}
    try {
        $rows = Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop
        foreach ($r in $rows) {
            if (-not $r.DeviceID) { continue }
            $byId[$r.DeviceID] = [pscustomobject]@{
                DriverName     = [string]$r.DeviceName
                DriverProvider = [string]$r.DriverProviderName
                DriverVersion  = [string]$r.DriverVersion
                DriverDate     = if ($r.DriverDate) { ([datetime]$r.DriverDate).ToString('yyyy-MM-dd') } else { $null }
                InfName        = [string]$r.InfName
            }
        }
    }
    catch {
        Write-Verbose "Win32_PnPSignedDriver falhou: $_"
    }
    return $byId
}

function Get-DriverDiagEmptyDriverInfo {
    return [pscustomobject]@{
        DriverName = $null; DriverProvider = $null; DriverVersion = $null; DriverDate = $null; InfName = $null
    }
}

function Get-DriverDiagHardwareIdsFast {
    param(
        [string]$InstanceId,
        $PnputilEntry,
        $WmiEntity
    )

    $ids = [System.Collections.Generic.List[string]]::new()

    if ($PnputilEntry -and $PnputilEntry.DeviceIds) {
        foreach ($d in $PnputilEntry.DeviceIds) {
            if ($d -and -not $ids.Contains($d)) { $ids.Add($d) }
        }
    }

    if ($WmiEntity -and $WmiEntity.HardwareID) {
        foreach ($h in @($WmiEntity.HardwareID)) {
            if ($h -and -not $ids.Contains([string]$h)) { $ids.Add([string]$h) }
        }
    }

    # InstanceId often embeds PCI\VEN_ / USB\VID_
    if ($InstanceId -match '(?i)(PCI\\VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}[^\\]*|USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}[^\\]*)') {
        $extracted = $Matches[1]
        if (-not $ids.Contains($extracted)) { $ids.Add($extracted) }
    }

    if ($InstanceId -and -not $ids.Contains($InstanceId)) {
        $ids.Add($InstanceId)
    }

    return @($ids)
}

function Get-DriverDiagDevicePropsBundle {
    <#
    .SYNOPSIS
      Fallback single Get-PnpDeviceProperty round-trip (slow — avoid in scan loops).
    #>
    param(
        [string]$InstanceId,
        $PnputilEntry
    )

    $info = [ordered]@{
        DriverName     = $null
        DriverProvider = $null
        DriverVersion  = $null
        DriverDate     = $null
        InfName        = $null
    }
    $ids = [System.Collections.Generic.List[string]]::new()

    if ($PnputilEntry -and $PnputilEntry.DeviceIds) {
        foreach ($d in $PnputilEntry.DeviceIds) {
            if ($d -and -not $ids.Contains($d)) { $ids.Add($d) }
        }
    }

    try {
        $props = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName @(
            'DEVPKEY_Device_DriverDesc',
            'DEVPKEY_Device_DriverProvider',
            'DEVPKEY_Device_DriverVersion',
            'DEVPKEY_Device_DriverDate',
            'DEVPKEY_Device_DriverInfPath',
            'DEVPKEY_Device_HardwareIds',
            'DEVPKEY_Device_CompatibleIds'
        ) -ErrorAction SilentlyContinue

        foreach ($p in @($props)) {
            switch ($p.KeyName) {
                'DEVPKEY_Device_DriverDesc'     { $info.DriverName = [string]$p.Data }
                'DEVPKEY_Device_DriverProvider' { $info.DriverProvider = [string]$p.Data }
                'DEVPKEY_Device_DriverVersion'  { $info.DriverVersion = [string]$p.Data }
                'DEVPKEY_Device_DriverDate'     {
                    if ($p.Data) { $info.DriverDate = ([datetime]$p.Data).ToString('yyyy-MM-dd') }
                }
                'DEVPKEY_Device_DriverInfPath'  { $info.InfName = [string]$p.Data }
                'DEVPKEY_Device_HardwareIds' {
                    foreach ($h in @($p.Data)) {
                        if ($h -and -not $ids.Contains([string]$h)) { $ids.Add([string]$h) }
                    }
                }
                'DEVPKEY_Device_CompatibleIds' {
                    foreach ($c in @($p.Data)) {
                        if ($c -and -not $ids.Contains([string]$c)) { $ids.Add([string]$c) }
                    }
                }
            }
        }
    }
    catch {
        Write-Verbose "Get-PnpDeviceProperty falhou para $InstanceId : $_"
    }

    if ($ids.Count -eq 0 -and $InstanceId) {
        $ids.Add($InstanceId)
    }

    return [pscustomobject]@{
        DriverInfo  = [pscustomobject]$info
        HardwareIds = @($ids)
    }
}

function Test-DriverDiagIsSuspicious {
    param(
        $Device,
        $VendorInfo,
        $DriverInfo
    )

    $reasons = [System.Collections.Generic.List[string]]::new()

    if ($VendorInfo -and $VendorInfo.Found -and $VendorInfo.VendorId) {
        $oemVen = $VendorInfo.VendorId -notin @('1414', '0000')
        $isGeneric = Test-DriverDiagGenericMicrosoftProvider -Provider $DriverInfo.DriverProvider
        if ($oemVen -and $isGeneric -and $Device.Class -notin @('Computer', 'System', 'SoftwareDevice', 'Volume', 'VolumeSnapshot')) {
            $expectedGeneric = $Device.Class -in @(
                'HIDClass', 'Keyboard', 'Mouse', 'DiskDrive', 'CDROM', 'FloppyDisk',
                'SCSIAdapter', 'HDC', 'USB', 'USBDevice', 'Net', 'Bluetooth', 'Processor'
            )
            if ($Device.Class -in @('Net', 'Media', 'MEDIA', 'Display', 'Image', 'Camera', 'Biometric', 'SmartCardReader')) {
                $reasons.Add('Driver generico Microsoft em dispositivo OEM (VEN conhecido)')
            }
            elseif (-not $expectedGeneric -and $DriverInfo.DriverProvider) {
                $reasons.Add('Provedor generico em hardware OEM')
            }
        }
    }

    if ($DriverInfo.DriverProvider -and $DriverInfo.DriverProvider -match '(?i)unknown|n/?a|null') {
        $reasons.Add('Provedor de driver estranho ou ausente')
    }

    if ($DriverInfo.DriverVersion -and $DriverInfo.DriverVersion -match '^(0\.0\.0\.0|1\.0\.0\.0)$') {
        $reasons.Add("Versao de driver incoerente ($($DriverInfo.DriverVersion))")
    }

    return , $reasons
}

function New-DriverDiagDeviceObject {
    param(
        [string]$InstanceId,
        [string]$FriendlyName,
        [string]$Class,
        [string]$Status,
        [Nullable[int]]$ProblemCode,
        [string]$Category,
        [string[]]$HardwareIds,
        $DriverInfo,
        $VendorInfo,
        [string[]]$SuspiciousReasons
    )

    $code = if ($null -ne $ProblemCode) { [int]$ProblemCode } else { 0 }
    $msg = Get-DriverDiagProblemMessage -Code $code
    if (-not $msg -and $Category -eq 'Missing') {
        $msg = 'Dispositivo sem driver instalado'
    }
    if (-not $msg -and $Category -eq 'Suspicious') {
        $msg = ($SuspiciousReasons -join '; ')
    }

    $preferredId = Get-DriverDiagPreferredHardwareId -HardwareIds $HardwareIds

    $obj = [pscustomobject]@{
        InstanceId          = $InstanceId
        Model               = if ($FriendlyName) { $FriendlyName } else { 'Dispositivo desconhecido' }
        Class               = $Class
        Status              = $Status
        ProblemCode         = $code
        ProblemMessage      = $msg
        Category            = $Category
        DeviceCategory      = $null
        DeviceCategoryTitle = $null
        HardwareIds         = @($HardwareIds)
        PreferredHardwareId = $preferredId
        DriverName          = $DriverInfo.DriverName
        DriverProvider      = $DriverInfo.DriverProvider
        DriverVersion       = $DriverInfo.DriverVersion
        DriverDate          = $DriverInfo.DriverDate
        InfName             = $DriverInfo.InfName
        VendorName          = if ($VendorInfo) { $VendorInfo.VendorName } else { $null }
        VendorId            = if ($VendorInfo) { $VendorInfo.VendorId } else { $null }
        DeviceId            = if ($VendorInfo) { $VendorInfo.DeviceId } else { $null }
        SupportUrl          = if ($VendorInfo) { $VendorInfo.SupportUrl } else { $null }
        DownloadHints       = if ($VendorInfo) { @($VendorInfo.DownloadHints) } else { @() }
        SuspiciousReasons   = @($SuspiciousReasons)
        Skipped             = $false
    }

    if (Get-Command Get-DriverDiagDeviceCategoryId -ErrorAction SilentlyContinue) {
        $obj.DeviceCategory = Get-DriverDiagDeviceCategoryId -Device $obj
        $obj.DeviceCategoryTitle = Get-DriverDiagCategoryTitle -Id $obj.DeviceCategory
    }

    return $obj
}

function Test-DriverDiagDeviceLooksProblem {
    param(
        $Dev,
        $PnputilEntry,
        [Nullable[int]]$ProblemCode
    )

    if ($PnputilEntry) { return $true }
    if ($null -ne $ProblemCode -and $ProblemCode -gt 0) { return $true }

    $status = [string]$Dev.Status
    # Error/Degraded are real problems. "Unknown" alone is common on healthy devices — do not treat as problem.
    if ($status -match '(?i)^(Error|Degraded)$') { return $true }

    $class = [string]$Dev.Class
    $classGuid = [string]$Dev.ClassGuid
    $friendly = [string]$Dev.FriendlyName
    $isOther = ($class -eq 'Unknown' -or [string]::IsNullOrWhiteSpace($class) -or $friendly -match '(?i)^Unknown device' -or $null -eq $Dev.Class)
    $emptyGuid = [string]::IsNullOrWhiteSpace($classGuid) -or $classGuid -eq '{00000000-0000-0000-0000-000000000000}'
    if ($isOther -and $emptyGuid) { return $true }
    if ($isOther -and $status -and $status -ne 'OK') { return $true }

    return $false
}

function Test-DriverDiagDeviceIsDisconnected {
    <#
    .SYNOPSIS
      Historical / phantom PnP entries (Code 45, Present=false, etc.).
    #>
    param(
        $Dev,
        $PnputilEntry,
        [Nullable[int]]$ProblemCode,
        $WmiEntity
    )

    # CM_PROB_PHANTOM / not connected
    if ($null -ne $ProblemCode -and [int]$ProblemCode -eq 45) { return $true }

    if ($null -ne $Dev) {
        $presentProp = $Dev.PSObject.Properties['Present']
        if ($presentProp -and $null -ne $Dev.Present -and -not [bool]$Dev.Present) { return $true }
    }

    if ($WmiEntity -and $null -ne $WmiEntity.ConfigManagerErrorCode) {
        try {
            if ([int]$WmiEntity.ConfigManagerErrorCode -eq 45) { return $true }
        }
        catch { }
    }

    if ($PnputilEntry -and $PnputilEntry.Status) {
        $st = [string]$PnputilEntry.Status
        if ($st -match '(?i)not\s*present|disconnected|nao\s*conectado|ausente|phantom') {
            return $true
        }
    }

    return $false
}

function Get-DriverDiagPnpDevicesForScan {
    param([switch]$IncludeDisconnected)

    if ($IncludeDisconnected) {
        return @(Get-PnpDevice -ErrorAction Stop)
    }

    # Prefer PresentOnly (Win10+) — drops Windows device history / ghosts
    $cmd = Get-Command Get-PnpDevice -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Parameters.ContainsKey('PresentOnly')) {
        try {
            return @(Get-PnpDevice -PresentOnly -ErrorAction Stop)
        }
        catch {
            Write-Verbose "Get-PnpDevice -PresentOnly falhou, filtrando Present: $_"
        }
    }

    $all = @(Get-PnpDevice -ErrorAction Stop)
    return @($all | Where-Object {
            $p = $_.PSObject.Properties['Present']
            if (-not $p -or $null -eq $_.Present) { $true } else { [bool]$_.Present }
        })
}

function Invoke-DriverDiagScan {
    [CmdletBinding()]
    param(
        [switch]$IncludeSuspicious,
        [switch]$IncludeDisconnected,
        [string[]]$Categories,
        [scriptblock]$ProgressCallback
    )

    if (-not $PSBoundParameters.ContainsKey('IncludeSuspicious')) {
        $IncludeSuspicious = $true
    }

    $filterCategories = @()
    if ($Categories -and $Categories.Count -gt 0 -and -not ($Categories -contains 'All')) {
        $filterCategories = @($Categories | Select-Object -Unique)
    }

    $report = {
        param([string]$Message)
        if ($ProgressCallback) {
            try { & $ProgressCallback $Message } catch { }
        }
    }

    & $report 'Consultando dispositivos com problema (pnputil)...'
    $pnputilMap = Get-DriverDiagPnputilProblemDevices

    # One Get-PnpDevice call (~1s); PresentOnly excludes historical/phantom devices by default
    if ($IncludeDisconnected) {
        & $report 'Listando dispositivos PnP (incluindo desconectados)...'
    }
    else {
        & $report 'Listando dispositivos PnP atuais...'
    }
    $pnpDevices = @()
    try {
        $pnpDevices = @(Get-DriverDiagPnpDevicesForScan -IncludeDisconnected:$IncludeDisconnected)
    }
    catch {
        Write-Warning "Get-PnpDevice falhou: $_"
    }

    $wmiMap = @{}
    & $report 'Carregando drivers assinados (WMI)...'
    $signedMap = Get-DriverDiagSignedDriverMap

    $results = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $total = $pnpDevices.Count
    $idx = 0

    foreach ($dev in $pnpDevices) {
        $idx++
        $instanceId = $dev.InstanceId
        if (-not $instanceId) { continue }
        [void]$seen.Add($instanceId)

        if (($idx % 25) -eq 0 -or $idx -eq 1) {
            & $report "Analisando $idx/$total..."
        }

        $class = [string]$dev.Class
        $friendly = [string]$dev.FriendlyName

        # Early category filter by Class — before expensive property lookups
        if ($filterCategories.Count -gt 0 -and -not (Test-DriverDiagClassMayMatchCategories -Class $class -FriendlyName $friendly -FilterCategories $filterCategories)) {
            continue
        }

        $pnpu = $null
        if ($pnputilMap.ContainsKey($instanceId)) { $pnpu = $pnputilMap[$instanceId] }

        $problemCode = $null
        if ($null -ne $dev.Problem) {
            try { $problemCode = [int]$dev.Problem } catch { }
        }
        if ($null -eq $problemCode -and $pnpu -and $null -ne $pnpu.ProblemCode) {
            $problemCode = [int]$pnpu.ProblemCode
        }

        $wmi = $null
        if ($wmiMap.Count -gt 0 -and $wmiMap.ContainsKey($instanceId)) {
            $wmi = $wmiMap[$instanceId]
            if ($null -eq $problemCode -and $null -ne $wmi.ConfigManagerErrorCode) {
                $problemCode = [int]$wmi.ConfigManagerErrorCode
            }
            if (-not $friendly) { $friendly = [string]$wmi.Name }
        }

        # Drop phantoms / history (Code 45, Present=false) unless power-user opt-in
        if (-not $IncludeDisconnected -and (Test-DriverDiagDeviceIsDisconnected -Dev $dev -PnputilEntry $pnpu -ProblemCode $problemCode -WmiEntity $wmi)) {
            continue
        }

        $looksProblem = Test-DriverDiagDeviceLooksProblem -Dev $dev -PnputilEntry $pnpu -ProblemCode $problemCode
        $classForSuspect = if ($class) { $class } else { '' }
        $mayBeSuspicious = $IncludeSuspicious -and $script:SuspiciousScanClasses.Contains($classForSuspect)

        # Skip healthy devices outside suspicious-relevant classes entirely
        if (-not $looksProblem -and -not $mayBeSuspicious) {
            continue
        }

        $status = [string]$dev.Status
        $classGuid = [string]$dev.ClassGuid

        # Prefer bulk WMI signed-driver map + InstanceId hardware IDs (never per-device Get-PnpDeviceProperty in scan)
        $needDriverProps = $looksProblem -or $mayBeSuspicious
        if ($needDriverProps) {
            $hardwareIds = Get-DriverDiagHardwareIdsFast -InstanceId $instanceId -PnputilEntry $pnpu -WmiEntity $wmi
            if ($signedMap.ContainsKey($instanceId)) {
                $driverInfo = $signedMap[$instanceId]
            }
            else {
                $driverInfo = Get-DriverDiagEmptyDriverInfo
            }
            $vendorInfo = Get-DriverDiagVendorInfo -HardwareIds $hardwareIds
        }
        else {
            $driverInfo = Get-DriverDiagEmptyDriverInfo
            $hardwareIds = Get-DriverDiagHardwareIdsFast -InstanceId $instanceId -PnputilEntry $pnpu -WmiEntity $null
            $vendorInfo = $null
        }

        $category = $null
        $isOther = ($class -eq 'Unknown' -or [string]::IsNullOrWhiteSpace($class) -or $friendly -match '(?i)^Unknown device' -or $null -eq $dev.Class)
        $emptyGuid = [string]::IsNullOrWhiteSpace($classGuid) -or $classGuid -eq '{00000000-0000-0000-0000-000000000000}'
        $code28 = ($null -ne $problemCode -and $problemCode -eq 28)
        $notOk = ($status -and $status -ne 'OK')

        if ($code28 -or ($isOther -and ($notOk -or $emptyGuid)) -or ($emptyGuid -and $notOk -and -not $driverInfo.InfName)) {
            $category = 'Missing'
        }
        elseif ($null -ne $problemCode -and $problemCode -gt 0 -and $problemCode -ne 28) {
            $category = 'Broken'
        }
        elseif ($notOk -and $status -match '(?i)Error|Degraded|Unknown') {
            $category = 'Broken'
        }

        $suspiciousReasons = @()
        if ($IncludeSuspicious -and -not $category -and $mayBeSuspicious) {
            $suspiciousReasons = @(Test-DriverDiagIsSuspicious -Device $dev -VendorInfo $vendorInfo -DriverInfo $driverInfo)
            if ($suspiciousReasons.Count -gt 0) {
                $category = 'Suspicious'
            }
        }

        if (-not $category) { continue }

        # Final category filter (handles SoftDevice audio keywords etc.)
        $obj = New-DriverDiagDeviceObject `
            -InstanceId $instanceId `
            -FriendlyName $friendly `
            -Class $class `
            -Status $status `
            -ProblemCode $problemCode `
            -Category $category `
            -HardwareIds $hardwareIds `
            -DriverInfo $driverInfo `
            -VendorInfo $vendorInfo `
            -SuspiciousReasons $suspiciousReasons

        if ($filterCategories.Count -gt 0 -and -not (Test-DriverDiagDeviceInCategories -Device $obj -CategoryIds $filterCategories)) {
            continue
        }

        $results.Add($obj)
    }

    # Orphans in pnputil but not in PresentOnly list are almost always historical — skip unless opted in
    foreach ($key in $pnputilMap.Keys) {
        if ($seen.Contains($key)) { continue }
        if (-not $IncludeDisconnected) { continue }

        if ($filterCategories.Count -gt 0 -and -not (Test-DriverDiagClassMayMatchCategories -Class 'Unknown' -FriendlyName $key -FilterCategories $filterCategories)) {
            continue
        }

        $pnpu = $pnputilMap[$key]
        $hardwareIds = @($pnpu.DeviceIds)
        if ($hardwareIds.Count -eq 0) { $hardwareIds = @($key) }
        $driverInfo = Get-DriverDiagEmptyDriverInfo
        $vendorInfo = Get-DriverDiagVendorInfo -HardwareIds $hardwareIds
        $code = $pnpu.ProblemCode
        $cat = if ($code -eq 28) { 'Missing' } else { 'Broken' }

        $obj = New-DriverDiagDeviceObject `
            -InstanceId $key `
            -FriendlyName $key `
            -Class 'Unknown' `
            -Status $(if ($pnpu.Status) { $pnpu.Status } else { 'Error' }) `
            -ProblemCode $code `
            -Category $cat `
            -HardwareIds $hardwareIds `
            -DriverInfo $driverInfo `
            -VendorInfo $vendorInfo `
            -SuspiciousReasons @()

        if ($filterCategories.Count -gt 0 -and -not (Test-DriverDiagDeviceInCategories -Device $obj -CategoryIds $filterCategories)) {
            continue
        }

        $results.Add($obj)
    }

    & $report 'Ordenando resultados...'

    $ordered = $results | Sort-Object @{
        Expression = {
            switch ($_.Category) {
                'Missing' { 0 }
                'Broken' { 1 }
                'Suspicious' { 2 }
                default { 3 }
            }
        }
    }, Model

    return @($ordered)
}
