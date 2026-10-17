$script:DriverDiagVendors = $null

function Get-DriverDiagVendors {
    if ($null -ne $script:DriverDiagVendors) {
        return $script:DriverDiagVendors
    }
    $path = Join-Path $PSScriptRoot '..\data\vendors.json'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Arquivo de vendors nao encontrado: $path"
    }
    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $script:DriverDiagVendors = $raw | ConvertFrom-Json
    return $script:DriverDiagVendors
}

function ConvertFrom-DriverDiagHardwareId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$HardwareId
    )
    process {
        $result = [ordered]@{
            Bus      = $null
            VendorId = $null
            DeviceId = $null
            Subsys   = $null
            Rev      = $null
            Raw      = $HardwareId
        }

        if ([string]::IsNullOrWhiteSpace($HardwareId)) {
            return [pscustomobject]$result
        }

        $id = $HardwareId.Trim().ToUpperInvariant()

        if ($id -match 'PCI\\VEN_([0-9A-F]{4})&DEV_([0-9A-F]{4})') {
            $result.Bus = 'PCI'
            $result.VendorId = $Matches[1]
            $result.DeviceId = $Matches[2]
            if ($id -match 'SUBSYS_([0-9A-F]{8})') { $result.Subsys = $Matches[1] }
            if ($id -match 'REV_([0-9A-F]{2})') { $result.Rev = $Matches[1] }
        }
        elseif ($id -match 'USB\\VID_([0-9A-F]{4})&PID_([0-9A-F]{4})') {
            $result.Bus = 'USB'
            $result.VendorId = $Matches[1]
            $result.DeviceId = $Matches[2]
        }
        elseif ($id -match 'ACPI\\([A-Z0-9_]+)') {
            $result.Bus = 'ACPI'
            $result.VendorId = $Matches[1]
        }

        return [pscustomobject]$result
    }
}

function Get-DriverDiagVendorInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$HardwareIds
    )

    $vendors = Get-DriverDiagVendors
    $decoded = $null

    foreach ($hid in $HardwareIds) {
        $d = ConvertFrom-DriverDiagHardwareId -HardwareId $hid
        if ($d.Bus -in @('PCI', 'USB') -and $d.VendorId) {
            $decoded = $d
            break
        }
    }

    if (-not $decoded) {
        return [pscustomobject]@{
            Found          = $false
            Bus            = $null
            VendorId       = $null
            DeviceId       = $null
            VendorName     = 'Desconhecido'
            SupportUrl     = $null
            DownloadHints  = @()
            SearchPatterns = @()
            Decoded        = $null
        }
    }

    $table = if ($decoded.Bus -eq 'USB') { $vendors.usb } else { $vendors.pci }
    $key = $decoded.VendorId
    $entry = $null

    if ($table.PSObject.Properties.Name -contains $key) {
        $entry = $table.$key
    }
    elseif ($decoded.Bus -eq 'USB' -and $vendors.pci.PSObject.Properties.Name -contains $key) {
        $entry = $vendors.pci.$key
    }

    if ($entry) {
        return [pscustomobject]@{
            Found          = $true
            Bus            = $decoded.Bus
            VendorId       = $decoded.VendorId
            DeviceId       = $decoded.DeviceId
            VendorName     = $entry.name
            SupportUrl     = $entry.supportUrl
            DownloadHints  = @($entry.downloadHints)
            SearchPatterns = @($entry.searchPatterns)
            Decoded        = $decoded
        }
    }

    return [pscustomobject]@{
        Found          = $false
        Bus            = $decoded.Bus
        VendorId       = $decoded.VendorId
        DeviceId       = $decoded.DeviceId
        VendorName     = "Fabricante $key (nao mapeado)"
        SupportUrl     = $null
        DownloadHints  = @()
        SearchPatterns = @()
        Decoded        = $decoded
    }
}

function Test-DriverDiagGenericMicrosoftProvider {
    param([string]$Provider)
    if ([string]::IsNullOrWhiteSpace($Provider)) { return $false }
    $vendors = Get-DriverDiagVendors
    $p = $Provider.Trim()
    foreach ($g in $vendors.genericMicrosoftProviders) {
        if ($p -eq $g -or $p -like "*$g*") { return $true }
    }
    return $false
}

function Get-DriverDiagPreferredHardwareId {
    param([string[]]$HardwareIds)
    if (-not $HardwareIds) { return $null }
    $pci = $HardwareIds | Where-Object { $_ -match '^PCI\\VEN_' } | Select-Object -First 1
    if ($pci) { return $pci }
    $usb = $HardwareIds | Where-Object { $_ -match '^USB\\VID_' } | Select-Object -First 1
    if ($usb) { return $usb }
    return ($HardwareIds | Select-Object -First 1)
}
