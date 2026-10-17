$script:OemUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) DriverDiag/1.0'

function Get-DriverDiagOemHandlers {
    return @{
        '8086' = 'Intel'
        '10DE' = 'NVIDIA'
        '1002' = 'AMD'
        '1022' = 'AMD'
        '10EC' = 'Realtek'
        '14E4' = 'Broadcom'
        '168C' = 'Qualcomm'
        '17CB' = 'Qualcomm'
        '1969' = 'Qualcomm'
        '14C3' = 'MediaTek'
        '0BDA' = 'Realtek'
    }
}

function New-DriverDiagOemCandidate {
    param(
        [string]$VendorName,
        [string]$Title,
        [string]$Url,
        [bool]$CanDownload = $false,
        [string]$DownloadUrl = $null,
        [string]$Version = '',
        [string]$Size = '',
        [string]$LastUpdated = '',
        [int]$Score = 5
    )

    return [pscustomobject]@{
        Source         = "OEM:$VendorName"
        SourceLabel    = "OEM - $VendorName"
        Guid           = [guid]::NewGuid().ToString()
        Title          = $Title
        Products       = $VendorName
        Classification = 'OEM Driver'
        LastUpdated    = $LastUpdated
        Version        = $Version
        Size           = $Size
        Score          = $Score
        Url            = $Url
        DownloadUrl    = $DownloadUrl
        CanDownload    = $CanDownload
    }
}

function Find-DriverDiagOemCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Device,
        [int]$MaxResults = 8
    )

    $list = [System.Collections.Generic.List[object]]::new()
    $ven = $Device.VendorId
    $handlers = Get-DriverDiagOemHandlers
    $vendorName = if ($Device.VendorName) { $Device.VendorName } else { 'OEM' }

    $handlerKey = $null
    if ($ven -and $handlers.ContainsKey($ven.ToUpperInvariant())) {
        $handlerKey = $handlers[$ven.ToUpperInvariant()]
    }

    if ($Device.SupportUrl) {
        $list.Add((New-DriverDiagOemCandidate `
            -VendorName $vendorName `
            -Title "Pagina oficial de suporte - $vendorName" `
            -Url $Device.SupportUrl `
            -CanDownload $false `
            -Score 3))
    }

    foreach ($hint in @($Device.DownloadHints)) {
        if ([string]::IsNullOrWhiteSpace($hint)) { continue }
        if ($list | Where-Object { $_.Url -eq $hint }) { continue }
        $list.Add((New-DriverDiagOemCandidate `
            -VendorName $vendorName `
            -Title "Download center oficial - $vendorName" `
            -Url $hint `
            -CanDownload $false `
            -Score 4))
    }

    switch ($handlerKey) {
        'Intel' {
            $list.Add((New-DriverDiagOemCandidate `
                -VendorName 'Intel' `
                -Title 'Intel Download Center (detectar automaticamente)' `
                -Url 'https://www.intel.com/content/www/us/en/support/detect.html' `
                -CanDownload $false `
                -Score 8))
            $list.Add((New-DriverDiagOemCandidate `
                -VendorName 'Intel' `
                -Title 'Intel Driver & Support Assistant' `
                -Url 'https://www.intel.com/content/www/us/en/download-center/home.html' `
                -CanDownload $false `
                -Score 7))
            if ($Device.PreferredHardwareId) {
                $q = [uri]::EscapeDataString($Device.PreferredHardwareId)
                $list.Add((New-DriverDiagOemCandidate `
                    -VendorName 'Intel' `
                    -Title 'Busca Intel por Hardware ID' `
                    -Url "https://www.intel.com/content/www/us/en/search.html?q=$q" `
                    -CanDownload $false `
                    -Score 6))
            }
        }
        'AMD' {
            $list.Add((New-DriverDiagOemCandidate `
                -VendorName 'AMD' `
                -Title 'AMD Drivers & Support' `
                -Url 'https://www.amd.com/en/support/download/drivers.html' `
                -CanDownload $false `
                -Score 8))
            $list.Add((New-DriverDiagOemCandidate `
                -VendorName 'AMD' `
                -Title 'AMD Auto-Detect and Install' `
                -Url 'https://www.amd.com/en/support/download/auto-detect-tool.html' `
                -CanDownload $false `
                -Score 7))
        }
        'NVIDIA' {
            $list.Add((New-DriverDiagOemCandidate `
                -VendorName 'NVIDIA' `
                -Title 'NVIDIA Driver Downloads' `
                -Url 'https://www.nvidia.com/Download/index.aspx' `
                -CanDownload $false `
                -Score 8))
            $list.Add((New-DriverDiagOemCandidate `
                -VendorName 'NVIDIA' `
                -Title 'NVIDIA App / GeForce drivers' `
                -Url 'https://www.nvidia.com/en-us/geforce/geforce-experience/' `
                -CanDownload $false `
                -Score 6))
        }
        'Realtek' {
            $list.Add((New-DriverDiagOemCandidate `
                -VendorName 'Realtek' `
                -Title 'Realtek Download Center' `
                -Url 'https://www.realtek.com/Download/Index?lang=en' `
                -CanDownload $false `
                -Score 8))
            if ($Device.DeviceCategory -eq 'Audio' -or $Device.Class -eq 'MEDIA') {
                $list.Add((New-DriverDiagOemCandidate `
                    -VendorName 'Realtek' `
                    -Title 'Realtek Audio / Codec (oficial)' `
                    -Url 'https://www.realtek.com/Download/List?cate_id=585' `
                    -CanDownload $false `
                    -Score 9))
            }
            if ($Device.DeviceCategory -eq 'Network' -or $Device.Class -eq 'Net') {
                $list.Add((New-DriverDiagOemCandidate `
                    -VendorName 'Realtek' `
                    -Title 'Realtek PCIe / USB Ethernet (oficial)' `
                    -Url 'https://www.realtek.com/Download/List?cate_id=584' `
                    -CanDownload $false `
                    -Score 9))
            }
        }
        'Broadcom' {
            $list.Add((New-DriverDiagOemCandidate `
                -VendorName 'Broadcom' `
                -Title 'Broadcom Support Download Search' `
                -Url 'https://www.broadcom.com/support/download-search' `
                -CanDownload $false `
                -Score 7))
        }
        'Qualcomm' {
            $list.Add((New-DriverDiagOemCandidate `
                -VendorName 'Qualcomm' `
                -Title 'Qualcomm Support' `
                -Url 'https://www.qualcomm.com/support' `
                -CanDownload $false `
                -Score 6))
        }
        'MediaTek' {
            $list.Add((New-DriverDiagOemCandidate `
                -VendorName 'MediaTek' `
                -Title 'MediaTek Support' `
                -Url 'https://www.mediatek.com/products' `
                -CanDownload $false `
                -Score 5))
        }
    }

    if ($Device.PreferredHardwareId) {
        $cq = [uri]::EscapeDataString($Device.PreferredHardwareId)
        $list.Add((New-DriverDiagOemCandidate `
            -VendorName 'Microsoft Catalog' `
            -Title 'Abrir busca no Microsoft Update Catalog' `
            -Url "https://www.catalog.update.microsoft.com/Search.aspx?q=$cq" `
            -CanDownload $false `
            -Score 2))
    }

    $unique = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($c in ($list | Sort-Object Score -Descending)) {
        $key = if ($c.DownloadUrl) { $c.DownloadUrl } else { $c.Url }
        if ($seen.Add($key)) { $unique.Add($c) }
        if ($unique.Count -ge $MaxResults) { break }
    }

    return @($unique)
}

function Save-DriverDiagOemPackage {
    param(
        [Parameter(Mandatory)]$Candidate,
        [Parameter(Mandatory)][string]$Destination,
        [scriptblock]$ProgressCallback = $null
    )

    if (-not $Candidate.CanDownload -or [string]::IsNullOrWhiteSpace($Candidate.DownloadUrl)) {
        return [pscustomobject]@{
            Success      = $false
            Files        = @()
            ErrorMessage = 'Este candidato OEM nao possui URL direta de arquivo. Abra a pagina oficial.'
            OemUrl       = $Candidate.Url
        }
    }

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    try {
        $fileName = [System.IO.Path]::GetFileName(([uri]$Candidate.DownloadUrl).AbsolutePath)
        if ([string]::IsNullOrWhiteSpace($fileName)) { $fileName = 'oem-driver.bin' }
        $target = Join-Path $Destination $fileName
        if ($ProgressCallback) { & $ProgressCallback "Baixando OEM: $fileName..." }

        if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
            Start-BitsTransfer -Source $Candidate.DownloadUrl -Destination $target -ErrorAction Stop
        }
        else {
            Invoke-WebRequest -Uri $Candidate.DownloadUrl -OutFile $target -UseBasicParsing -TimeoutSec 600 -Headers @{
                'User-Agent' = $script:OemUserAgent
            }
        }

        if ((Test-Path -LiteralPath $target) -and ((Get-Item $target).Length -gt 0)) {
            return [pscustomobject]@{
                Success      = $true
                Files        = @($target)
                ErrorMessage = $null
                OemUrl       = $Candidate.Url
            }
        }
        return [pscustomobject]@{
            Success      = $false
            Files        = @()
            ErrorMessage = 'Arquivo baixado esta vazio.'
            OemUrl       = $Candidate.Url
        }
    }
    catch {
        return [pscustomobject]@{
            Success      = $false
            Files        = @()
            ErrorMessage = "$_"
            OemUrl       = $Candidate.Url
        }
    }
}

function Find-DriverDiagAllCandidates {
    param(
        [Parameter(Mandatory)]$Device,
        [int]$MaxCatalog = 10,
        [int]$MaxOem = 8
    )

    $all = [System.Collections.Generic.List[object]]::new()

    try {
        $catalog = @(Find-DriverDiagCatalogCandidates -Device $Device -MaxResults $MaxCatalog)
        foreach ($c in $catalog) { $all.Add($c) }
    }
    catch {
        Write-Verbose "Catalog falhou: $_"
    }

    try {
        $oem = @(Find-DriverDiagOemCandidates -Device $Device -MaxResults $MaxOem)
        foreach ($c in $oem) { $all.Add($c) }
    }
    catch {
        Write-Verbose "OEM falhou: $_"
    }

    return @($all | Sort-Object @{ Expression = { if ($_.CanDownload) { 0 } else { 1 } } }, @{ Expression = 'Score'; Descending = $true })
}

function Get-DriverDiagFallbackLinks {
    param(
        [Parameter(Mandatory)]$Device,
        [object[]]$CatalogCandidates = @(),
        [object[]]$OemCandidates = @()
    )

    $links = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    $add = {
        param($Label, $Url)
        if ([string]::IsNullOrWhiteSpace($Url)) { return }
        if ($seen.Add($Url)) {
            $links.Add([pscustomobject]@{ Label = $Label; Url = $Url })
        }
    }

    if ($Device.PreferredHardwareId) {
        $q = [uri]::EscapeDataString($Device.PreferredHardwareId)
        & $add 'Microsoft Update Catalog' "https://www.catalog.update.microsoft.com/Search.aspx?q=$q"
    }

    if ($Device.SupportUrl) {
        & $add "OEM - $($Device.VendorName)" $Device.SupportUrl
    }

    foreach ($h in @($Device.DownloadHints | Select-Object -First 2)) {
        & $add "OEM download - $($Device.VendorName)" $h
    }

    foreach ($c in @($CatalogCandidates | Select-Object -First 3)) {
        if ($c.Url) { & $add $c.Title $c.Url }
    }
    foreach ($c in @($OemCandidates | Select-Object -First 5)) {
        if ($c.Url) { & $add $c.Title $c.Url }
    }

    return @($links)
}

function Save-DriverDiagCandidatePackage {
    param(
        [Parameter(Mandatory)]$Candidate,
        [Parameter(Mandatory)][string]$Destination,
        [scriptblock]$ProgressCallback = $null
    )

    if ($Candidate.Source -eq 'Catalog' -or $Candidate.SourceLabel -match 'Catalog') {
        return Save-DriverDiagCatalogPackage `
            -Guid $Candidate.Guid `
            -Destination $Destination `
            -PreferredTitle $Candidate.Title `
            -ProgressCallback $ProgressCallback
    }

    if ($Candidate.CanDownload -and $Candidate.DownloadUrl) {
        return Save-DriverDiagOemPackage -Candidate $Candidate -Destination $Destination -ProgressCallback $ProgressCallback
    }

    return [pscustomobject]@{
        Success      = $false
        Files        = @()
        ErrorMessage = 'Candidato sem download automatico - use o link oficial.'
        CatalogUrl   = $Candidate.Url
        OemUrl       = $Candidate.Url
    }
}
