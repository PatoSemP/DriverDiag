function Get-DriverDiagCategoryDefinitions {
    return @(
        [pscustomobject]@{
            Id          = 'Network'
            Title       = 'Rede'
            Subtitle    = 'Wi-Fi, Ethernet, Bluetooth, modem'
            IconGlyph   = [char]0xE839
            AccentArgb  = '#0B6E4F'
            Classes     = @('Net', 'NetClient', 'NetService', 'NetTrans', 'Bluetooth', 'Modem', 'SdHost', 'mtcbsd')
            Keywords    = @('wifi', 'wlan', 'ethernet', 'network', 'wireless', 'bluetooth', 'lan', 'adapter')
        }
        [pscustomobject]@{
            Id          = 'Audio'
            Title       = 'Som'
            Subtitle    = 'Audio, microfone, HDMI audio'
            IconGlyph   = [char]0xE767
            AccentArgb  = '#1B4F72'
            Classes     = @('MEDIA', 'AudioEndpoint', 'SoftwareDevice')
            Keywords    = @('audio', 'sound', 'realtek', 'headphones', 'microphone', 'speaker', 'hd audio')
        }
        [pscustomobject]@{
            Id          = 'Display'
            Title       = 'Video'
            Subtitle    = 'GPU, monitor, display'
            IconGlyph   = [char]0xE7F4
            AccentArgb  = '#6C3483'
            Classes     = @('Display', 'Monitor')
            Keywords    = @('graphics', 'gpu', 'radeon', 'geforce', 'display', 'vga', 'hdmi')
        }
        [pscustomobject]@{
            Id          = 'Storage'
            Title       = 'Armazenamento'
            Subtitle    = 'SATA, NVMe, RAID, discos'
            IconGlyph   = [char]0xEDA2
            AccentArgb  = '#922B21'
            Classes     = @('SCSIAdapter', 'HDC', 'DiskDrive', 'CDROM', 'FloppyDisk', 'Volume', 'VolumeSnapshot')
            Keywords    = @('storage', 'nvme', 'sata', 'raid', 'ahci', 'ssd', 'hdd')
        }
        [pscustomobject]@{
            Id          = 'Usb'
            Title       = 'USB'
            Subtitle    = 'Controladores e dispositivos USB'
            IconGlyph   = [char]0xE88E
            AccentArgb  = '#1A5276'
            Classes     = @('USB', 'USBDevice', 'WPD', 'USBPrint', 'UsbHub')
            Keywords    = @('usb', 'xhci', 'ehci', 'hub')
        }
        [pscustomobject]@{
            Id          = 'Chipset'
            Title       = 'Chipset'
            Subtitle    = 'Placa-mae, system, processador'
            IconGlyph   = [char]0xE950
            AccentArgb  = '#7D3C98'
            Classes     = @('System', 'Computer', 'Processor', 'SoftwareComponent', 'Firmware', 'SecurityDevices')
            Keywords    = @('chipset', 'motherboard', 'smbus', 'lpc', 'acpi')
        }
        [pscustomobject]@{
            Id          = 'Input'
            Title       = 'Entrada'
            Subtitle    = 'Teclado, mouse, touch, HID'
            IconGlyph   = [char]0xE765
            AccentArgb  = '#117A65'
            Classes     = @('HIDClass', 'Keyboard', 'Mouse', 'KeyboardHid', 'TouchScreen', 'Gesture')
            Keywords    = @('keyboard', 'mouse', 'touch', 'hid', 'trackpad')
        }
        [pscustomobject]@{
            Id          = 'Imaging'
            Title       = 'Imagem'
            Subtitle    = 'Camera, scanner, webcam'
            IconGlyph   = [char]0xE722
            AccentArgb  = '#B9770E'
            Classes     = @('Image', 'Camera', 'PrintQueue', 'Printer', 'Dot4', 'Sensor')
            Keywords    = @('camera', 'webcam', 'scanner', 'imaging')
        }
        [pscustomobject]@{
            Id          = 'Other'
            Title       = 'Outros'
            Subtitle    = 'Demais classes e dispositivos'
            IconGlyph   = [char]0xE8FD
            AccentArgb  = '#566573'
            Classes     = @()
            Keywords    = @()
        }
    )
}

function Get-DriverDiagDeviceCategoryId {
    param(
        [Parameter(Mandatory)]$Device
    )

    $defs = Get-DriverDiagCategoryDefinitions
    $class = [string]$Device.Class
    $model = ([string]$Device.Model + ' ' + [string]$Device.DriverName).ToLowerInvariant()

    foreach ($d in $defs) {
        if ($d.Id -eq 'Other') { continue }
        if ($class -and ($d.Classes -contains $class)) {
            # SoftwareDevice so conta como audio se o nome bater
            if ($d.Id -eq 'Audio' -and $class -eq 'SoftwareDevice') {
                $audioHit = $false
                foreach ($k in $d.Keywords) {
                    if ($model -like "*$k*") { $audioHit = $true; break }
                }
                if (-not $audioHit) { continue }
            }
            return $d.Id
        }
    }

    foreach ($d in $defs) {
        if ($d.Id -eq 'Other') { continue }
        foreach ($k in $d.Keywords) {
            if ($model -like "*$k*") { return $d.Id }
        }
    }

    return 'Other'
}

function Test-DriverDiagDeviceInCategories {
    param(
        [Parameter(Mandatory)]$Device,
        [string[]]$CategoryIds
    )

    if (-not $CategoryIds -or $CategoryIds.Count -eq 0) { return $true }
    if ($CategoryIds -contains 'All') { return $true }

    $id = if ($Device.PSObject.Properties.Name -contains 'DeviceCategory' -and $Device.DeviceCategory) {
        $Device.DeviceCategory
    }
    else {
        Get-DriverDiagDeviceCategoryId -Device $Device
    }

    return ($CategoryIds -contains $id)
}

function Get-DriverDiagCategoryTitle {
    param([string]$Id)
    if ($Id -eq 'All') { return 'Todos' }
    $d = Get-DriverDiagCategoryDefinitions | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if ($d) { return $d.Title }
    return $Id
}
