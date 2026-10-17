$script:CatalogBase = 'https://www.catalog.update.microsoft.com'
$script:CatalogUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) DriverDiag/1.0'
$script:CatalogSession = $null

function Get-DriverDiagCatalogSession {
    if ($null -eq $script:CatalogSession) {
        $script:CatalogSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        # cookie/warmup - catalog as vezes precisa de visita previa
        try {
            Invoke-WebRequest -Uri $script:CatalogBase -UseBasicParsing -TimeoutSec 30 `
                -WebSession $script:CatalogSession -Headers @{ 'User-Agent' = $script:CatalogUserAgent } | Out-Null
        }
        catch { }
    }
    return $script:CatalogSession
}

function Invoke-DriverDiagWebRequest {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [ValidateSet('GET', 'POST')][string]$Method = 'GET',
        [hashtable]$Body = $null,
        [int]$TimeoutSec = 90,
        [int]$Retries = 3
    )

    $session = Get-DriverDiagCatalogSession
    $attempt = 0
    $lastError = $null
    while ($attempt -lt $Retries) {
        $attempt++
        try {
            $params = @{
                Uri             = $Uri
                Method          = $Method
                UseBasicParsing = $true
                TimeoutSec      = $TimeoutSec
                WebSession      = $session
                Headers         = @{ 'User-Agent' = $script:CatalogUserAgent }
            }
            if ($Method -eq 'POST' -and $Body) {
                $params.Body = $Body
                $params.ContentType = 'application/x-www-form-urlencoded'
            }
            return Invoke-WebRequest @params
        }
        catch {
            $lastError = $_
            Write-Verbose "WebRequest falhou (tentativa $attempt/$Retries): $_"
            if ($attempt -lt $Retries) {
                Start-Sleep -Seconds ([Math]::Min(2 * $attempt, 8))
            }
        }
    }
    throw "Falha ao acessar $Uri apos $Retries tentativas: $lastError"
}

function Search-DriverDiagCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Query,
        [int]$MaxResults = 15
    )

    $encoded = [uri]::EscapeDataString($Query)
    $uri = "$script:CatalogBase/Search.aspx?q=$encoded"
    Write-Verbose "Catalog search: $uri"

    $response = Invoke-DriverDiagWebRequest -Uri $uri -Method GET
    $html = $response.Content
    $results = [System.Collections.Generic.List[object]]::new()

    # catalog agora usa id="{guid}_R0" nas linhas
    $rowRegex = [regex]::new(
        '<tr[^>]*id="(?<guid>[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})(?:_R\d+)?"[^>]*>(?<body>.*?)</tr>',
        [System.Text.RegularExpressions.RegexOptions]::Singleline -bor
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    $getTdText = {
        param([string]$tdHtml)
        $t = [regex]::Replace($tdHtml, '<[^>]+>', ' ')
        $t = [System.Net.WebUtility]::HtmlDecode($t)
        return ($t -replace '\s+', ' ').Trim()
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($m in $rowRegex.Matches($html)) {
        $guid = $m.Groups['guid'].Value
        if ($guid -eq '00000000-0000-0000-0000-000000000000') { continue }
        if (-not $seen.Add($guid)) { continue }
        $body = $m.Groups['body'].Value
        $tds = [regex]::Matches($body, '<td[^>]*>(.*?)</td>', 'Singleline, IgnoreCase')
        if ($tds.Count -lt 2) { continue }

        $title = & $getTdText $tds[1].Groups[1].Value
        if ([string]::IsNullOrWhiteSpace($title) -or $title -match '^(Title|Titulo)$') { continue }

        $products = if ($tds.Count -gt 2) { & $getTdText $tds[2].Groups[1].Value } else { '' }
        $classification = if ($tds.Count -gt 3) { & $getTdText $tds[3].Groups[1].Value } else { '' }
        $lastUpdated = if ($tds.Count -gt 4) { & $getTdText $tds[4].Groups[1].Value } else { '' }
        $version = if ($tds.Count -gt 5) { & $getTdText $tds[5].Groups[1].Value } else { '' }
        $size = if ($tds.Count -gt 6) { & $getTdText $tds[6].Groups[1].Value } else { '' }

        $score = 0
        if ($classification -match '(?i)driver' -or $title -match '(?i)driver') { $score += 10 }
        if ($title -match [regex]::Escape($Query)) { $score += 5 }
        if ($Query -match 'VEN_|VID_' -and $title -match '(?i)driver') { $score += 5 }

        $results.Add([pscustomobject]@{
            Source         = 'Catalog'
            SourceLabel    = 'Microsoft Update Catalog'
            Guid           = $guid
            Title          = $title
            Products       = $products
            Classification = $classification
            LastUpdated    = $lastUpdated
            Version        = $version
            Size           = $size
            Score          = $score
            Url            = "$script:CatalogBase/ScopedViewInline.aspx?updateid=$guid"
            DownloadUrl    = $null
            CanDownload    = $true
            SearchQuery    = $Query
        })

        if ($results.Count -ge ($MaxResults * 3)) { break }
    }

    if ($results.Count -eq 0) {
        foreach ($m in [regex]::Matches($html, "goToDetails\('(?<g>[0-9a-fA-F\-]{36})'\)", 'IgnoreCase')) {
            $g = $m.Groups['g'].Value
            if (-not $seen.Add($g)) { continue }
            if ($results.Count -ge $MaxResults) { break }
            $titleMatch = [regex]::Match($html, "goToDetails\('$g'\).*?</a>", 'Singleline, IgnoreCase')
            $title = if ($titleMatch.Success) {
                ([regex]::Replace($titleMatch.Value, '<[^>]+>', ' ') -replace '\s+', ' ').Trim()
            } else { "Update $g" }
            $results.Add([pscustomobject]@{
                Source         = 'Catalog'
                SourceLabel    = 'Microsoft Update Catalog'
                Guid           = $g
                Title          = $title
                Products       = ''
                Classification = 'Drivers'
                LastUpdated    = ''
                Version        = ''
                Size           = ''
                Score          = 1
                Url            = "$script:CatalogBase/ScopedViewInline.aspx?updateid=$g"
                DownloadUrl    = $null
                CanDownload    = $true
                SearchQuery    = $Query
            })
        }
    }

    return @($results | Sort-Object Score -Descending | Select-Object -First $MaxResults)
}

function Get-DriverDiagCatalogDownloadUrls {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Guid
    )

    # formato estavel usado pelo modulo OSD/MSCatalog
    $postJson = "{`"size`":0,`"languages`":`"`",`"uidInfo`":`"$Guid`",`"updateID`":`"$Guid`"}"
    $body = @{ updateIDs = "[$postJson]" }

    $response = Invoke-DriverDiagWebRequest `
        -Uri "$script:CatalogBase/DownloadDialog.aspx" `
        -Method POST `
        -Body $body

    $content = $response.Content.Replace('www.download.windowsupdate', 'download.windowsupdate')

    $urls = [System.Collections.Generic.List[string]]::new()
    $pattern = '(https?://(?:catalog\.s\.download\.windowsupdate\.com|dl\.delivery\.mp\.microsoft\.com|download\.windowsupdate\.com)/[^''"\s\\]+)'
    foreach ($m in [regex]::Matches($content, $pattern, 'IgnoreCase')) {
        $u = $m.Groups[1].Value.TrimEnd('\', ';', ',', ')', ']')
        $u = [System.Net.WebUtility]::HtmlDecode($u)
        if (-not $urls.Contains($u)) { $urls.Add($u) }
    }

    # fallback: url do downloadInformation.files
    if ($urls.Count -eq 0) {
        foreach ($m in [regex]::Matches($content, "url\s*=\s*'(https?://[^']+)'", 'IgnoreCase')) {
            $u = $m.Groups[1].Value
            if ($u -match 'windowsupdate|microsoft\.com' -and -not $urls.Contains($u)) {
                $urls.Add($u)
            }
        }
    }

    $rank = {
        param([string]$U)
        try {
            $e = [IO.Path]::GetExtension((([uri]$U).AbsolutePath)).ToLowerInvariant()
        }
        catch { return 4 }
        switch ($e) {
            '.cab' { 0 }
            '.msu' { 1 }
            '.zip' { 2 }
            '.exe' { 3 }
            default { 4 }
        }
    }
    $ordered = [System.Collections.Generic.List[string]]::new()
    foreach ($u in ($urls | Sort-Object { & $rank $_ })) {
        if ($u -match '^https?://\S{12,}') { $ordered.Add($u) }
    }
    # ToArray: caller deve usar Ensure-DriverDiagUrlList
    return $ordered.ToArray()
}

function Get-DriverDiagNormalizedUrls {
    # sempre devolve objecto com .Items (evita unwrap do PS em array de 1)
    param($Raw)
    $list = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Raw) {
        return [pscustomobject]@{ Items = @(); First = $null }
    }

    if ($Raw -is [string]) {
        if ($Raw -match '^https?://\S{12,}') { [void]$list.Add($Raw.Trim()) }
        return [pscustomobject]@{ Items = @($list.ToArray()); First = $(if ($list.Count) { $list[0] } else { $null }) }
    }

    if ($Raw -is [char]) {
        return [pscustomobject]@{ Items = @(); First = $null }
    }

    foreach ($item in @($Raw)) {
        if ($null -eq $item -or $item -is [char]) { continue }
        $s = [string]$item
        if ($s -match '^https?://\S{12,}') { [void]$list.Add($s.Trim()) }
    }

    return [pscustomobject]@{
        Items = @($list.ToArray())
        First = $(if ($list.Count) { $list[0] } else { $null })
    }
}

function Save-DriverDiagCatalogPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Guid,
        [Parameter(Mandatory)]
        [string]$Destination,
        [string]$PreferredTitle = 'catalog-package',
        [scriptblock]$ProgressCallback = $null
    )

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    if ($ProgressCallback) { & $ProgressCallback "Resolvendo download Catalog ($Guid)..." }

    $urlPack = Get-DriverDiagNormalizedUrls (Get-DriverDiagCatalogDownloadUrls -Guid $Guid)
    if (-not $urlPack.First) {
        return [pscustomobject]@{
            Success      = $false
            Files        = @()
            ErrorMessage = 'Catalog nao devolveu URL de download.'
            CatalogUrl   = "$script:CatalogBase/ScopedViewInline.aspx?updateid=$Guid"
        }
    }

    $url = [string]$urlPack.First
    $urls = @($urlPack.Items)
    $downloaded = [System.Collections.Generic.List[string]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()

    try {
        $fileName = [System.IO.Path]::GetFileName(([uri]$url).AbsolutePath)
        if ([string]::IsNullOrWhiteSpace($fileName)) {
            $ext = '.cab'
            if ($url -match '\.(msu|exe|zip|cab)(\?|$)') { $ext = ".$($Matches[1])" }
            $safe = ($PreferredTitle -replace '[^\w\.\-]+', '_')
            if ($safe.Length -gt 40) { $safe = $safe.Substring(0, 40) }
            if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'catalog-package' }
            $fileName = "${safe}$ext"
        }

        $target = Join-Path $Destination $fileName
        if ($ProgressCallback) { & $ProgressCallback "Baixando $fileName..." }

        $ok = $false
        for ($attempt = 1; $attempt -le 3 -and -not $ok; $attempt++) {
            try {
                if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue }
                # BITS as vezes falha com redirect do catalog; IWR mais confiavel aqui
                Invoke-WebRequest -Uri $url -OutFile $target -UseBasicParsing -TimeoutSec 600 `
                    -WebSession (Get-DriverDiagCatalogSession) `
                    -Headers @{ 'User-Agent' = $script:CatalogUserAgent }
                if ((Test-Path -LiteralPath $target) -and ((Get-Item -LiteralPath $target).Length -gt 1024)) {
                    $ok = $true
                    $downloaded.Add($target)
                }
            }
            catch {
                if ($attempt -ge 3) { $errors.Add("$_") }
                else { Start-Sleep -Seconds (2 * $attempt) }
            }
        }
        if (-not $ok -and $errors.Count -eq 0) { $errors.Add('Arquivo vazio ou muito pequeno.') }
    }
    catch {
        $errors.Add("$_")
    }

    return [pscustomobject]@{
        Success      = ($downloaded.Count -gt 0)
        Files        = @($downloaded)
        ErrorMessage = if ($downloaded.Count -eq 0) { ($errors -join '; ') } else { $null }
        CatalogUrl   = "$script:CatalogBase/ScopedViewInline.aspx?updateid=$Guid"
        SourceUrls   = @($urls)
    }
}

function Get-DriverDiagCatalogVendorShort {
    param($Device)

    $n = [string]$Device.VendorName
    if ($n -match '(?i)\bRealtek\b') { return 'Realtek' }
    if ($n -match '(?i)\bIntel\b') { return 'Intel' }
    if ($n -match '(?i)\bNVIDIA\b') { return 'NVIDIA' }
    if ($n -match '(?i)\bAMD\b|\bATI\b') { return 'AMD' }
    if ($n -match '(?i)\bBroadcom\b') { return 'Broadcom' }
    if ($n -match '(?i)\bQualcomm\b|\bAtheros\b') { return 'Qualcomm' }
    if ($n -match '(?i)\bMediaTek\b|\bRalink\b') { return 'MediaTek' }
    if ($n -match '(?i)\bMicrosoft\b') { return 'Microsoft' }
    if ($n -match '(?i)\bSynaptics\b') { return 'Synaptics' }
    if ($n -match '(?i)\bConexant\b') { return 'Conexant' }
    if ($n -match '(?i)\bCirrus\b') { return 'Cirrus' }
    if ($n -match '^\s*Fabricante') { return $null }

    # primeiro token util do nome
    if ($n -match '^([A-Za-z][A-Za-z0-9\+]+)') { return $Matches[1] }
    return $null
}

function Get-DriverDiagCatalogClassTerms {
    param($Device)

    $class = [string]$Device.Class
    $cat = [string]$Device.DeviceCategory
    $terms = [System.Collections.Generic.List[string]]::new()

    switch -Regex ("$class|$cat") {
        'Net|Network|Bluetooth|Modem' {
            foreach ($t in @('Net', 'LAN', 'Ethernet', 'Wireless', 'WiFi', 'WLAN', 'Networking')) { $terms.Add($t) }
        }
        'MEDIA|Audio' {
            foreach ($t in @('Audio', 'High Definition Audio', 'Sound')) { $terms.Add($t) }
        }
        'Display' {
            foreach ($t in @('Display', 'Graphics', 'Video')) { $terms.Add($t) }
        }
        'USB' {
            foreach ($t in @('USB', 'USBDevice')) { $terms.Add($t) }
        }
        'Image|Camera' {
            foreach ($t in @('Camera', 'Image', 'Imaging')) { $terms.Add($t) }
        }
        'HID|Keyboard|Mouse|Input' {
            foreach ($t in @('HID', 'Input')) { $terms.Add($t) }
        }
        'SCSI|HDC|Storage|Disk' {
            foreach ($t in @('Storage', 'SCSI', 'Disk')) { $terms.Add($t) }
        }
        default { }
    }
    return @($terms)
}

function Add-DriverDiagHwIdQueryVariants {
    param(
        [System.Collections.Generic.List[string]]$Queries,
        [string]$HardwareId
    )
    if ([string]::IsNullOrWhiteSpace($HardwareId)) { return }

    $add = {
        param($q)
        if ([string]::IsNullOrWhiteSpace($q)) { return }
        if (-not $Queries.Contains($q)) { $Queries.Add($q) }
    }

    $raw = $HardwareId.Trim()
    & $add $raw
    & $add $raw.ToLowerInvariant()

    # Catalog indexa bem pci\ven_xxxx&dev_yyyy (minusculo) e 4-part com SUBSYS
    if ($raw -match '(?i)(PCI\\VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}(?:&SUBSYS_[0-9A-F]{8})?(?:&REV_[0-9A-F]{2})?)') {
        $core = $Matches[1]
        & $add $core
        & $add $core.ToLowerInvariant()
        if ($core -match '(?i)PCI\\VEN_([0-9A-F]{4})&DEV_([0-9A-F]{4})') {
            $ven = $Matches[1]; $dev = $Matches[2]
            & $add ("VEN_${ven}&DEV_${dev}")
            & $add ("ven_$($ven.ToLowerInvariant())&dev_$($dev.ToLowerInvariant())")
            & $add ("pci\ven_$($ven.ToLowerInvariant())&dev_$($dev.ToLowerInvariant())")
        }
    }
    elseif ($raw -match '(?i)(USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4})') {
        $core = $Matches[1]
        & $add $core
        & $add $core.ToLowerInvariant()
    }
}

function Update-DriverDiagDeviceHardwareIds {
    # completa HWIDs reais antes da busca (scan rapido as vezes so tem InstanceId)
    param([Parameter(Mandatory)]$Device)

    $hasVen = $false
    foreach ($h in @($Device.HardwareIds)) {
        if ($h -match '(?i)VEN_|VID_') { $hasVen = $true; break }
    }
    if ($hasVen -and $Device.VendorId -and $Device.DeviceId) { return $Device }

    if (-not $Device.InstanceId) { return $Device }
    if (-not (Get-Command Get-DriverDiagDevicePropsBundle -ErrorAction SilentlyContinue)) { return $Device }

    try {
        $bundle = Get-DriverDiagDevicePropsBundle -InstanceId $Device.InstanceId -PnputilEntry $null
        $ids = [System.Collections.Generic.List[string]]::new()
        foreach ($h in @($Device.HardwareIds)) { if ($h) { $ids.Add($h) } }
        foreach ($h in @($bundle.HardwareIds)) {
            if ($h -and -not $ids.Contains($h)) { $ids.Add($h) }
        }
        $Device.HardwareIds = @($ids)
        $pref = Get-DriverDiagPreferredHardwareId -HardwareIds @($ids)
        if ($pref) { $Device.PreferredHardwareId = $pref }

        $vi = Get-DriverDiagVendorInfo -HardwareIds @($ids)
        if ($vi) {
            if ($vi.VendorId) { $Device.VendorId = $vi.VendorId }
            if ($vi.DeviceId) { $Device.DeviceId = $vi.DeviceId }
            if ($vi.VendorName) { $Device.VendorName = $vi.VendorName }
            if ($vi.SupportUrl) { $Device.SupportUrl = $vi.SupportUrl }
            if ($vi.DownloadHints) { $Device.DownloadHints = @($vi.DownloadHints) }
        }
        if ($bundle.DriverInfo) {
            if (-not $Device.DriverName -and $bundle.DriverInfo.DriverName) {
                $Device.DriverName = $bundle.DriverInfo.DriverName
            }
            if (-not $Device.DriverProvider -and $bundle.DriverInfo.DriverProvider) {
                $Device.DriverProvider = $bundle.DriverInfo.DriverProvider
            }
        }
    }
    catch {
        Write-Verbose "Update-DriverDiagDeviceHardwareIds: $_"
    }
    return $Device
}

function Get-DriverDiagCatalogSearchQueries {
    param([Parameter(Mandatory)]$Device)

    $queries = [System.Collections.Generic.List[string]]::new()
    $add = {
        param($q)
        if ([string]::IsNullOrWhiteSpace($q)) { return }
        $q = ($q -replace '\s+', ' ').Trim()
        if ($q.Length -lt 3) { return }
        # evita InstanceId longo tipo SWD\...
        if ($q -match '^(SWD\\|ROOT\\|HTREE\\|UEFI\\|ACPI\\)' -and $q -notmatch 'VEN_|VID_') { return }
        if (-not $queries.Contains($q)) { $queries.Add($q) }
    }

    $vendorShort = Get-DriverDiagCatalogVendorShort -Device $Device
    $classTerms = @(Get-DriverDiagCatalogClassTerms -Device $Device)
    $model = [string]$Device.Model
    $driverName = [string]$Device.DriverName

    # 1) NOME PRIMEIRO - e o que o Catalog indexa melhor (titulo do pacote)
    if ($model -and $model -notmatch '(?i)^Unknown|^Dispositivo desconhecido|^PCI\\|^USB\\') {
        & $add $model
        if ($vendorShort -and $model -notmatch [regex]::Escape($vendorShort)) {
            & $add "$vendorShort $model"
        }
    }
    if ($driverName -and $driverName -ne $model) {
        & $add $driverName
    }

    # 2) Fabricante + classe (ex: "Realtek Net", "Realtek Audio") - formato tipico do Catalog
    if ($vendorShort) {
        foreach ($t in $classTerms) {
            & $add "$vendorShort $t"
            & $add "$vendorShort - $t"
        }
        & $add $vendorShort
    }

    # 3) Padroes do vendors.json
    try {
        $vi = Get-DriverDiagVendorInfo -HardwareIds @($Device.HardwareIds)
        foreach ($pat in @($vi.SearchPatterns)) {
            if ([string]::IsNullOrWhiteSpace($pat)) { continue }
            if ($vendorShort -and $pat -notmatch [regex]::Escape($vendorShort)) {
                & $add "$vendorShort $pat"
            }
            else {
                & $add $pat
            }
        }
    }
    catch { }

    # 4) Hardware IDs (minusculo + maiusculo + 2/4 partes)
    if ($Device.PreferredHardwareId) {
        Add-DriverDiagHwIdQueryVariants -Queries $queries -HardwareId $Device.PreferredHardwareId
    }
    foreach ($hid in @($Device.HardwareIds | Select-Object -First 8)) {
        if ($hid -match '(?i)VEN_|VID_') {
            Add-DriverDiagHwIdQueryVariants -Queries $queries -HardwareId $hid
        }
    }
    if ($Device.VendorId -and $Device.DeviceId) {
        $v = $Device.VendorId; $d = $Device.DeviceId
        & $add ("PCI\VEN_${v}&DEV_${d}")
        & $add ("pci\ven_$($v.ToLowerInvariant())&dev_$($d.ToLowerInvariant())")
        & $add ("VEN_${v}&DEV_${d}")
        if ($vendorShort) {
            & $add "$vendorShort $d"
            & $add "$vendorShort DEV_$d"
        }
    }

    return @($queries)
}

function Find-DriverDiagCatalogCandidates {
    param(
        [Parameter(Mandatory)]$Device,
        [int]$MaxResults = 15,
        [scriptblock]$ProgressCallback = $null
    )

    # completa IDs se o scan veio fraco
    $Device = Update-DriverDiagDeviceHardwareIds -Device $Device

    $all = [System.Collections.Generic.List[object]]::new()
    $seenGuids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $os = $null
    if (Get-Command Get-DriverDiagOsHints -ErrorAction SilentlyContinue) {
        $os = Get-DriverDiagOsHints
    }

    $queryList = @(Get-DriverDiagCatalogSearchQueries -Device $Device)
    $qi = 0
    foreach ($q in $queryList) {
        $qi++
        if ($ProgressCallback) { & $ProgressCallback "Catalog [$qi/$($queryList.Count)]: $q" }
        try {
            $hits = Search-DriverDiagCatalog -Query $q -MaxResults 10
            foreach ($h in $hits) {
                if (-not $seenGuids.Add($h.Guid)) { continue }
                if ($os -and (Get-Command Get-DriverDiagCandidateScore -ErrorAction SilentlyContinue)) {
                    $h.Score = Get-DriverDiagCandidateScore -Candidate $h -Device $Device -OsHints $os
                }
                # bonus se titulo casa com fabricante curto
                $vs = Get-DriverDiagCatalogVendorShort -Device $Device
                if ($vs -and $h.Title -match [regex]::Escape($vs)) { $h.Score += 20 }
                $all.Add($h)
            }
        }
        catch {
            Write-Verbose "Catalog search falhou para '$q': $_"
        }
        # nao para cedo: nomes + HWID precisam rodar; so limita volume final
        if ($all.Count -ge 40) { break }
    }

    return @($all | Sort-Object Score -Descending | Select-Object -First $MaxResults)
}
