Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function New-DriverDiagColor {
    param([int]$R, [int]$G, [int]$B)
    return [System.Drawing.Color]::FromArgb($R, $G, $B)
}

function Initialize-DriverDiagGuiTheme {
    $script:GuiTheme = @{
        Bg        = (New-DriverDiagColor 28 30 34)
        Panel     = (New-DriverDiagColor 36 39 46)
        PanelAlt  = (New-DriverDiagColor 42 46 54)
        Border    = (New-DriverDiagColor 58 63 72)
        Text      = (New-DriverDiagColor 230 232 236)
        Muted     = (New-DriverDiagColor 150 156 168)
        Accent    = (New-DriverDiagColor 70 140 180)
        AccentHot = (New-DriverDiagColor 90 160 200)
        Danger    = (New-DriverDiagColor 200 80 70)
        Warn      = (New-DriverDiagColor 200 150 60)
        Ok        = (New-DriverDiagColor 80 170 110)
        FontUi    = New-Object System.Drawing.Font('Segoe UI', 9.5)
        FontTitle = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
        FontMono  = New-Object System.Drawing.Font('Consolas', 9)
        FontSmall = New-Object System.Drawing.Font('Segoe UI', 8.5)
    }
}

function Set-DriverDiagControlDark {
    param($Control)
    $Control.BackColor = $script:GuiTheme.Bg
    $Control.ForeColor = $script:GuiTheme.Text
    $Control.Font = $script:GuiTheme.FontUi
}

function New-DriverDiagButton {
    param(
        [string]$Text,
        [System.Drawing.Color]$Back,
        [int]$Width = 120,
        [int]$Height = 32
    )
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Width = $Width
    $btn.Height = $Height
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0
    $btn.BackColor = $Back
    $btn.ForeColor = [System.Drawing.Color]::White
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.Font = $script:GuiTheme.FontUi
    return $btn
}

function Get-DriverDiagCategoryBadgeText {
    param([string]$Category)
    switch ($Category) {
        'Missing' { return 'AUSENTE' }
        'Broken' { return 'QUEBRADO' }
        'Suspicious' { return 'SUSPEITO' }
        default { return $Category }
    }
}

function Get-DriverDiagCategoryColor {
    param([string]$Category)
    switch ($Category) {
        'Missing' { return $script:GuiTheme.Warn }
        'Broken' { return $script:GuiTheme.Danger }
        'Suspicious' { return (New-DriverDiagColor 180 140 60) }
        default { return $script:GuiTheme.Muted }
    }
}

function Show-DriverDiagCandidateDialog {
    param(
        [System.Windows.Forms.Form]$Owner,
        [AllowEmptyCollection()]
        [object[]]$Candidates = @()
    )

    if (-not $Candidates -or @($Candidates).Count -eq 0) {
        return $null
    }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Escolher candidato de driver'
    $dlg.Size = New-Object System.Drawing.Size(720, 480)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    Set-DriverDiagControlDark $dlg
    $dlg.BackColor = $script:GuiTheme.Panel

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = 'Selecione um pacote do Catalog ou pagina OEM oficial:'
    $lbl.AutoSize = $true
    $lbl.Location = New-Object System.Drawing.Point(16, 14)
    $lbl.ForeColor = $script:GuiTheme.Text
    $dlg.Controls.Add($lbl)

    $list = New-Object System.Windows.Forms.ListView
    $list.View = 'Details'
    $list.FullRowSelect = $true
    $list.MultiSelect = $false
    $list.HideSelection = $false
    $list.Location = New-Object System.Drawing.Point(16, 42)
    $list.Size = New-Object System.Drawing.Size(672, 340)
    $list.BackColor = $script:GuiTheme.PanelAlt
    $list.ForeColor = $script:GuiTheme.Text
    $list.Font = $script:GuiTheme.FontSmall
    [void]$list.Columns.Add('Fonte', 160)
    [void]$list.Columns.Add('Download', 90)
    [void]$list.Columns.Add('Titulo', 400)
    $dlg.Controls.Add($list)

    for ($i = 0; $i -lt $Candidates.Count; $i++) {
        $c = $Candidates[$i]
        $dl = if ($c.CanDownload) { 'Sim' } else { 'Link' }
        $item = New-Object System.Windows.Forms.ListViewItem($c.SourceLabel)
        [void]$item.SubItems.Add($dl)
        [void]$item.SubItems.Add($c.Title)
        $item.Tag = $i
        [void]$list.Items.Add($item)
    }
    if ($list.Items.Count -gt 0) { $list.Items[0].Selected = $true }

    $script:CandidateDialogResult = $null

    $btnOk = New-DriverDiagButton -Text 'Selecionar' -Back $script:GuiTheme.Accent -Width 110
    $btnOk.Location = New-Object System.Drawing.Point(460, 400)
    $btnOk.Add_Click({
        if ($list.SelectedItems.Count -gt 0) {
            $idx = [int]$list.SelectedItems[0].Tag
            $script:CandidateDialogResult = $Candidates[$idx]
            $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $dlg.Close()
        }
    })
    $dlg.Controls.Add($btnOk)

    $btnCancel = New-DriverDiagButton -Text 'Cancelar' -Back $script:GuiTheme.Border -Width 110
    $btnCancel.Location = New-Object System.Drawing.Point(580, 400)
    $btnCancel.Add_Click({
        $script:CandidateDialogResult = $null
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dlg.Close()
    })
    $dlg.Controls.Add($btnCancel)

    [void]$dlg.ShowDialog($Owner)
    return $script:CandidateDialogResult
}

function Show-DriverDiagLinksDialog {
    param(
        [System.Windows.Forms.Form]$Owner,
        [object[]]$Links,
        [string]$Message = 'Nao foi possivel baixar automaticamente. Use apenas estes links oficiais:'
    )

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Links oficiais'
    $dlg.Size = New-Object System.Drawing.Size(700, 420)
    $dlg.StartPosition = 'CenterParent'
    Set-DriverDiagControlDark $dlg
    $dlg.BackColor = $script:GuiTheme.Panel

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Message
    $lbl.AutoSize = $false
    $lbl.Size = New-Object System.Drawing.Size(660, 40)
    $lbl.Location = New-Object System.Drawing.Point(16, 12)
    $lbl.ForeColor = $script:GuiTheme.Warn
    $dlg.Controls.Add($lbl)

    $box = New-Object System.Windows.Forms.TextBox
    $box.Multiline = $true
    $box.ReadOnly = $true
    $box.ScrollBars = 'Vertical'
    $box.Location = New-Object System.Drawing.Point(16, 56)
    $box.Size = New-Object System.Drawing.Size(650, 260)
    $box.BackColor = $script:GuiTheme.PanelAlt
    $box.ForeColor = $script:GuiTheme.Text
    $box.Font = $script:GuiTheme.FontMono
    $text = ($Links | ForEach-Object { "$($_.Label)`r`n$($_.Url)`r`n" }) -join "`r`n"
    $box.Text = $text + "`r`nNUNCA use Softpedia, DriverPack ou mirrors de terceiros."
    $dlg.Controls.Add($box)

    $btnOpen = New-DriverDiagButton -Text 'Abrir 1o link' -Back $script:GuiTheme.Accent -Width 130
    $btnOpen.Location = New-Object System.Drawing.Point(16, 330)
    $btnOpen.Add_Click({
        if ($Links -and $Links.Count -gt 0) {
            Start-Process $Links[0].Url
        }
    })
    $dlg.Controls.Add($btnOpen)

    $btnClose = New-DriverDiagButton -Text 'Fechar' -Back $script:GuiTheme.Border -Width 100
    $btnClose.Location = New-Object System.Drawing.Point(566, 330)
    $btnClose.Add_Click({ $dlg.Close() })
    $dlg.Controls.Add($btnClose)

    [void]$dlg.ShowDialog($Owner)
}

function Update-DriverDiagDetailPane {
    param(
        $Labels,
        $Device
    )

    if (-not $Device) {
        $Labels.Model.Text = '-'
        $Labels.Ids.Text = '-'
        $Labels.Driver.Text = '-'
        $Labels.Provider.Text = '-'
        $Labels.Version.Text = '-'
        $Labels.Class.Text = '-'
        $Labels.Error.Text = '-'
        $Labels.Vendor.Text = '-'
        return
    }

    $Labels.Model.Text = [string]$Device.Model
    $ids = @($Device.HardwareIds | Select-Object -First 6) -join "`r`n"
    $Labels.Ids.Text = $ids
    $Labels.Driver.Text = if ($Device.DriverName) { $Device.DriverName } else { '(nenhum)' }
    $Labels.Provider.Text = if ($Device.DriverProvider) { $Device.DriverProvider } else { '-' }
    $Labels.Version.Text = "$(if ($Device.DriverVersion) { $Device.DriverVersion } else { '-' })  $(if ($Device.DriverDate) { $Device.DriverDate } else { '' })"
    $Labels.Class.Text = "$($Device.Class)  |  $($Device.Status)"
    $Labels.Error.Text = "Codigo $($Device.ProblemCode) - $($Device.ProblemMessage)"
    $Labels.Vendor.Text = "$($Device.VendorName)  (VEN $($Device.VendorId) DEV $($Device.DeviceId))"
}

function Invoke-DriverDiagGuiFix {
    param(
        [System.Windows.Forms.Form]$Form,
        $Device,
        [System.Windows.Forms.Label]$StatusLabel,
        [System.Windows.Forms.ProgressBar]$Progress,
        [switch]$ManualPick
    )

    if (-not $Device) {
        [System.Windows.Forms.MessageBox]::Show('Selecione um dispositivo.', 'DriverDiag') | Out-Null
        return
    }

    $progressCb = {
        param($m)
        $StatusLabel.Text = $m
        [System.Windows.Forms.Application]::DoEvents()
    }

    if ($ManualPick) {
        $StatusLabel.Text = 'Buscando candidatos...'
        $Progress.Style = 'Marquee'
        $Form.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
        $catalog = @(); $oem = @()
        try { $catalog = @(Find-DriverDiagCatalogCandidates -Device $Device -MaxResults 12) } catch { }
        try { $oem = @(Find-DriverDiagOemCandidates -Device $Device) } catch { }
        $Progress.Style = 'Blocks'
        $candidates = @($catalog) + @($oem)
        if ($candidates.Count -eq 0) {
            Show-DriverDiagLinksDialog -Owner $Form -Links (Get-DriverDiagFallbackLinks -Device $Device)
            return
        }
        $chosen = Show-DriverDiagCandidateDialog -Owner $Form -Candidates $candidates
        if (-not $chosen) { return }
        $dest = Get-DriverDiagDeviceDownloadFolder -Device $Device
        $dl = Save-DriverDiagCandidatePackage -Candidate $chosen -Destination $dest -ProgressCallback $progressCb
        if (-not $dl.Success) {
            Show-DriverDiagLinksDialog -Owner $Form -Links (Get-DriverDiagFallbackLinks -Device $Device -CatalogCandidates $catalog) `
                -Message "Download falhou: $($dl.ErrorMessage)"
            return
        }
        $work = Join-Path $dest '_install'
        $install = Install-DriverDiagFromFiles -Files $dl.Files -WorkFolder $work -Install -ProgressCallback $progressCb
        if ($install.Success) {
            Invoke-DriverDiagRescan
            $StatusLabel.Text = 'Instalacao concluida.'
        }
        else {
            $StatusLabel.Text = "Falha: $($install.Message)"
        }
        $Progress.Value = 100
        return
    }

    # automatico: escolhe melhor do Catalog, baixa e instala
    $Progress.Style = 'Marquee'
    $Form.Refresh()
    $r = Invoke-DriverDiagAutoFixDevice -Device $Device -ProgressCallback $progressCb -ConfirmCritical -Owner $Form
    $Progress.Style = 'Blocks'
    $Progress.Value = 100

    if ($r.Success) {
        $StatusLabel.Text = $r.Message
    }
    elseif ($r.Skipped) {
        $StatusLabel.Text = $r.Message
    }
    else {
        $StatusLabel.Text = $r.Message
        if ($r.Links -and $r.Links.Count -gt 0) {
            Show-DriverDiagLinksDialog -Owner $Form -Links $r.Links -Message $r.Message
        }
    }
}

function Invoke-DriverDiagGuiFixAll {
    param(
        [System.Windows.Forms.Form]$Form,
        [object[]]$Devices,
        [System.Windows.Forms.Label]$StatusLabel,
        [System.Windows.Forms.ProgressBar]$Progress
    )

    $todo = @($Devices | Where-Object { $_ -and -not $_.Skipped })
    if ($todo.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('Nada para corrigir.', 'DriverDiag') | Out-Null
        return
    }

    $r = [System.Windows.Forms.MessageBox]::Show(
        "Corrigir automaticamente $($todo.Count) dispositivo(s)?`n`nBusca no Catalog, baixa o melhor pacote e instala. GPU/storage pedem confirmacao.",
        'Corrigir todos',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $Progress.Style = 'Marquee'
    $batch = Invoke-DriverDiagAutoFixBatch -Devices $todo -ConfirmCritical -Owner $Form -ProgressCallback {
        param($m)
        $StatusLabel.Text = $m
        [System.Windows.Forms.Application]::DoEvents()
    }
    $Progress.Style = 'Blocks'
    $Progress.Value = 100

    $failLines = @(
        $batch.Results |
            Where-Object { -not $_.Success -and -not $_.Skipped } |
            ForEach-Object { "- $($_.Device): $($_.Message)" }
    )
    $msg = $batch.Summary
    if ($failLines.Count -gt 0) {
        $msg += "`n`nFalhas:`n" + ($failLines -join "`n")
    }
    [System.Windows.Forms.MessageBox]::Show($msg, 'Corrigir todos',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $(if ($batch.Fail -eq 0) { [System.Windows.Forms.MessageBoxIcon]::Information } else { [System.Windows.Forms.MessageBoxIcon]::Warning })
    ) | Out-Null
    $StatusLabel.Text = $batch.Summary
}

# Set while Gui.ps1 is dot-sourced (PSScriptRoot = modules\)
$script:DriverDiagAppRoot = if ((Split-Path -Leaf $PSScriptRoot) -eq 'modules') {
    Split-Path -Parent $PSScriptRoot
}
else {
    $PSScriptRoot
}

function Start-DriverDiagGui {
    param([switch]$IncludeSuspicious)

    Initialize-DriverDiagGuiTheme
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'DriverDiag - Diagnostico de drivers'
    $form.Size = New-Object System.Drawing.Size(1100, 700)
    $form.StartPosition = 'CenterScreen'
    $form.MinimumSize = New-Object System.Drawing.Size(900, 560)
    Set-DriverDiagControlDark $form

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = 'Top'
    $header.Height = 56
    $header.BackColor = $script:GuiTheme.Panel
    $form.Controls.Add($header)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'DriverDiag'
    $title.Font = $script:GuiTheme.FontTitle
    $title.ForeColor = $script:GuiTheme.AccentHot
    $title.AutoSize = $true
    $title.Location = New-Object System.Drawing.Point(16, 14)
    $header.Controls.Add($title)

    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Text = 'Diagnostico e reparo de drivers (Catalog + OEM oficial)'
    $subtitle.ForeColor = $script:GuiTheme.Muted
    $subtitle.AutoSize = $true
    $subtitle.Location = New-Object System.Drawing.Point(140, 20)
    $header.Controls.Add($subtitle)

    $statusPanel = New-Object System.Windows.Forms.Panel
    $statusPanel.Dock = 'Bottom'
    $statusPanel.Height = 48
    $statusPanel.BackColor = $script:GuiTheme.Panel
    $form.Controls.Add($statusPanel)

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = 'Escolha o escopo e clique em Varrer.'
    $statusLabel.ForeColor = $script:GuiTheme.Muted
    $statusLabel.AutoSize = $false
    $statusLabel.Location = New-Object System.Drawing.Point(12, 6)
    $statusLabel.Size = New-Object System.Drawing.Size(700, 18)
    $statusPanel.Controls.Add($statusLabel)

    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Location = New-Object System.Drawing.Point(12, 26)
    $progress.Size = New-Object System.Drawing.Size(700, 12)
    $progress.Minimum = 0
    $progress.Maximum = 100
    $statusPanel.Controls.Add($progress)

    $toolbar = New-Object System.Windows.Forms.Panel
    $toolbar.Dock = 'Top'
    $toolbar.Height = 48
    $toolbar.BackColor = $script:GuiTheme.Bg

    $btnCorrigirTodos = New-DriverDiagButton -Text 'Corrigir todos' -Back $script:GuiTheme.AccentHot -Width 120
    $btnCorrigir = New-DriverDiagButton -Text 'Corrigir' -Back $script:GuiTheme.Accent -Width 90
    $btnManual = New-DriverDiagButton -Text 'Manual' -Back $script:GuiTheme.Border -Width 80
    $btnPular = New-DriverDiagButton -Text 'Pular' -Back $script:GuiTheme.Border -Width 70
    $btnDetalhes = New-DriverDiagButton -Text 'Detalhes' -Back $script:GuiTheme.Border -Width 80
    $btnRescan = New-DriverDiagButton -Text 'Rescan' -Back $script:GuiTheme.Ok -Width 80
    $btnEscopo = New-DriverDiagButton -Text 'Escopo' -Back $script:GuiTheme.Border -Width 80
    $btnPasta = New-DriverDiagButton -Text 'Downloads' -Back $script:GuiTheme.PanelAlt -Width 100

    $x = 12
    foreach ($b in @($btnCorrigirTodos, $btnCorrigir, $btnManual, $btnPular, $btnDetalhes, $btnRescan, $btnEscopo, $btnPasta)) {
        $b.Location = New-Object System.Drawing.Point($x, 8)
        $toolbar.Controls.Add($b)
        $x += $b.Width + 8
    }

    # tela inicial: escolha de categorias
    $catPanel = New-Object System.Windows.Forms.Panel
    $catPanel.Dock = 'Fill'
    $catPanel.BackColor = $script:GuiTheme.Bg
    $catPanel.Padding = New-Object System.Windows.Forms.Padding(24)
    $form.Controls.Add($catPanel)
    $catPanel.BringToFront()

    $catTitle = New-Object System.Windows.Forms.Label
    $catTitle.Text = 'O que varrer?'
    $catTitle.Font = $script:GuiTheme.FontTitle
    $catTitle.ForeColor = $script:GuiTheme.Text
    $catTitle.AutoSize = $true
    $catTitle.Location = New-Object System.Drawing.Point(28, 24)
    $catPanel.Controls.Add($catTitle)

    $catHint = New-Object System.Windows.Forms.Label
    $catHint.Text = 'Marque as categorias (ou Todos) e depois Varrer. So dispositivos conectados agora.'
    $catHint.ForeColor = $script:GuiTheme.Muted
    $catHint.AutoSize = $true
    $catHint.Location = New-Object System.Drawing.Point(28, 56)
    $catPanel.Controls.Add($catHint)

    $chkAll = New-Object System.Windows.Forms.CheckBox
    $chkAll.Text = 'Todos'
    $chkAll.Checked = $true
    $chkAll.AutoSize = $true
    $chkAll.ForeColor = $script:GuiTheme.Text
    $chkAll.Font = $script:GuiTheme.FontUi
    $chkAll.Location = New-Object System.Drawing.Point(28, 96)
    $catPanel.Controls.Add($chkAll)

    $chkSuspect = New-Object System.Windows.Forms.CheckBox
    $chkSuspect.Text = 'Incluir suspeitos (driver generico em OEM)'
    $chkSuspect.Checked = $true
    $chkSuspect.AutoSize = $true
    $chkSuspect.ForeColor = $script:GuiTheme.Muted
    $chkSuspect.Font = $script:GuiTheme.FontSmall
    $chkSuspect.Location = New-Object System.Drawing.Point(120, 98)
    $catPanel.Controls.Add($chkSuspect)

    $catChecks = [System.Collections.Generic.List[object]]::new()
    $defs = @(Get-DriverDiagCategoryDefinitions)
    $col = 0
    $row = 0
    foreach ($d in $defs) {
        $chk = New-Object System.Windows.Forms.CheckBox
        $chk.Text = "$($d.Title)  -  $($d.Subtitle)"
        $chk.Tag = $d.Id
        $chk.Checked = $false
        $chk.Enabled = $false
        $chk.AutoSize = $true
        $chk.ForeColor = $script:GuiTheme.Text
        $chk.Font = $script:GuiTheme.FontUi
        $x = 28 + ($col * 480)
        $y = 140 + ($row * 36)
        $chk.Location = New-Object System.Drawing.Point($x, $y)
        $catPanel.Controls.Add($chk)
        $catChecks.Add($chk)
        $row++
        if ($row -ge 5) { $row = 0; $col++ }
    }

    $chkAll.Add_CheckedChanged({
        foreach ($c in $catChecks) {
            $c.Enabled = -not $chkAll.Checked
            if ($chkAll.Checked) { $c.Checked = $false }
        }
    })

    $btnScan = New-DriverDiagButton -Text 'Varrer' -Back $script:GuiTheme.Accent -Width 140 -Height 36
    $btnScan.Location = New-Object System.Drawing.Point(28, 340)
    $catPanel.Controls.Add($btnScan)

    $mainPanel = New-Object System.Windows.Forms.Panel
    $mainPanel.Dock = 'Fill'
    $mainPanel.Visible = $false
    $form.Controls.Add($mainPanel)

    $split = New-Object System.Windows.Forms.SplitContainer
    $split.Dock = 'Fill'
    $split.BackColor = $script:GuiTheme.Border
    $split.SplitterWidth = 3
    $split.Orientation = 'Vertical'
    $mainPanel.Controls.Add($split)

    # Toolbar inside mainPanel (Dock Top); add after split so Top docks before Fill and the list stays below the buttons.
    $mainPanel.Controls.Add($toolbar)

    $listView = New-Object System.Windows.Forms.ListView
    $listView.Dock = 'Fill'
    $listView.View = 'Details'
    $listView.FullRowSelect = $true
    $listView.MultiSelect = $false
    $listView.HideSelection = $false
    $listView.BackColor = $script:GuiTheme.PanelAlt
    $listView.ForeColor = $script:GuiTheme.Text
    $listView.Font = $script:GuiTheme.FontSmall
    $listView.BorderStyle = 'None'
    [void]$listView.Columns.Add('Status', 90)
    [void]$listView.Columns.Add('Modelo', 260)
    [void]$listView.Columns.Add('Classe', 100)
    [void]$listView.Columns.Add('Codigo', 60)
    $split.Panel1.Controls.Add($listView)

    $detailPanel = New-Object System.Windows.Forms.Panel
    $detailPanel.Dock = 'Fill'
    $detailPanel.BackColor = $script:GuiTheme.Panel
    $detailPanel.Padding = New-Object System.Windows.Forms.Padding(16)
    $split.Panel2.Controls.Add($detailPanel)
    $split.Panel2.BackColor = $script:GuiTheme.Panel

    function New-DetailLabel([string]$caption, [int]$y) {
        $cap = New-Object System.Windows.Forms.Label
        $cap.Text = $caption
        $cap.ForeColor = $script:GuiTheme.Muted
        $cap.Location = New-Object System.Drawing.Point(16, $y)
        $cap.AutoSize = $true
        $cap.Font = $script:GuiTheme.FontSmall
        $detailPanel.Controls.Add($cap)

        $val = New-Object System.Windows.Forms.Label
        $val.ForeColor = $script:GuiTheme.Text
        $val.Location = New-Object System.Drawing.Point(16, ($y + 18))
        $val.Size = New-Object System.Drawing.Size(480, 36)
        $val.Font = $script:GuiTheme.FontUi
        $detailPanel.Controls.Add($val)
        return $val
    }

    $detailTitle = New-Object System.Windows.Forms.Label
    $detailTitle.Text = 'Detalhes'
    $detailTitle.Font = $script:GuiTheme.FontTitle
    $detailTitle.ForeColor = $script:GuiTheme.Text
    $detailTitle.Location = New-Object System.Drawing.Point(16, 12)
    $detailTitle.AutoSize = $true
    $detailPanel.Controls.Add($detailTitle)

    $labels = @{
        Model    = (New-DetailLabel 'Modelo' 50)
        Vendor   = (New-DetailLabel 'Fabricante' 100)
        Class    = (New-DetailLabel 'Classe / Status' 150)
        Error    = (New-DetailLabel 'Codigo de erro' 200)
        Driver   = (New-DetailLabel 'Driver atual' 250)
        Provider = (New-DetailLabel 'Provedor' 300)
        Version  = (New-DetailLabel 'Versao / Data' 350)
        Ids      = (New-DetailLabel 'Hardware IDs' 400)
    }
    $labels.Ids.Height = 120
    $labels.Ids.Font = $script:GuiTheme.FontMono
    $labels.Error.ForeColor = $script:GuiTheme.Warn

    $script:GuiDevices = @()
    $script:SelectedCategories = @('All')
    $script:IncludeSuspiciousGui = $true
    $script:ScanBusy = $false

    $getSelectedCats = {
        if ($chkAll.Checked) { return @('All') }
        $ids = @($catChecks | Where-Object { $_.Checked } | ForEach-Object { [string]$_.Tag })
        if ($ids.Count -eq 0) { return @('All') }
        return $ids
    }

    $setScanUiBusy = {
        param([bool]$Busy)
        $script:ScanBusy = $Busy
        foreach ($b in @($btnScan, $btnRescan, $btnEscopo, $btnCorrigirTodos, $btnCorrigir, $btnManual, $btnPular, $btnDetalhes, $btnPasta)) {
            $b.Enabled = -not $Busy
        }
        $chkAll.Enabled = -not $Busy
        $chkSuspect.Enabled = -not $Busy
        if (-not $Busy) {
            foreach ($c in $catChecks) {
                $c.Enabled = -not $chkAll.Checked
            }
        }
        else {
            foreach ($c in $catChecks) { $c.Enabled = $false }
        }
    }

    $showResults = {
        $catPanel.Visible = $false
        $mainPanel.Visible = $true
        $mainPanel.BringToFront()
        $mainPanel.PerformLayout()
        if ($split.Width -gt 100) {
            $split.SplitterDistance = [Math]::Max(380, [int]($form.ClientSize.Width * 0.48))
        }
    }

    $showScope = {
        if ($script:ScanBusy) { return }
        $mainPanel.Visible = $false
        $catPanel.Visible = $true
        $catPanel.BringToFront()
        $listView.Items.Clear()
        $script:GuiDevices = @()
        Update-DriverDiagDetailPane -Labels $labels -Device $null
        $statusLabel.Text = 'Escolha o escopo e clique em Varrer.'
        $progress.Style = 'Blocks'
        $progress.Value = 0
    }

    $loadList = {
        if ($script:ScanBusy) { return }

        $listView.Items.Clear()
        $script:SelectedCategories = @(& $getSelectedCats)
        $script:IncludeSuspiciousGui = $chkSuspect.Checked

        $statusLabel.Text = 'Varrendo...'
        $statusLabel.ForeColor = $script:GuiTheme.Muted
        $progress.Style = 'Marquee'
        & $setScanUiBusy $true
        $form.Refresh()
        [System.Windows.Forms.Application]::DoEvents()

        $script:GuiDevices = @()
        $scanError = $null
        try {
            $scanParams = @{
                IncludeSuspicious = $script:IncludeSuspiciousGui
                ProgressCallback  = {
                    param($m)
                    if ($m) { $statusLabel.Text = [string]$m }
                    [System.Windows.Forms.Application]::DoEvents()
                }
            }
            if (-not ($script:SelectedCategories -contains 'All')) {
                $scanParams.Categories = $script:SelectedCategories
            }
            $script:GuiDevices = @(Invoke-DriverDiagScan @scanParams)
        }
        catch {
            $scanError = "$_"
            $script:GuiDevices = @()
        }

        $progress.Style = 'Blocks'
        $progress.Value = 0
        & $setScanUiBusy $false

        if ($scanError) {
            [System.Windows.Forms.MessageBox]::Show("Erro na varredura:`n$scanError", 'DriverDiag') | Out-Null
            $statusLabel.Text = 'Varredura falhou.'
            return
        }

        foreach ($d in $script:GuiDevices) {
            $item = New-Object System.Windows.Forms.ListViewItem((Get-DriverDiagCategoryBadgeText $d.Category))
            $item.ForeColor = Get-DriverDiagCategoryColor $d.Category
            [void]$item.SubItems.Add($d.Model)
            [void]$item.SubItems.Add($d.Class)
            [void]$item.SubItems.Add([string]$d.ProblemCode)
            $item.Tag = $d
            [void]$listView.Items.Add($item)
        }

        & $showResults

        $scopeTxt = if ($script:SelectedCategories -contains 'All') {
            'Todos'
        }
        else {
            ($script:SelectedCategories | ForEach-Object { Get-DriverDiagCategoryTitle $_ }) -join ', '
        }

        if ($script:GuiDevices.Count -eq 0) {
            $statusLabel.Text = "Nenhum problema nos dispositivos atuais: $scopeTxt"
            Update-DriverDiagDetailPane -Labels $labels -Device $null
        }
        else {
            $statusLabel.Text = "$($script:GuiDevices.Count) dispositivo(s) atuais - escopo: $scopeTxt"
            $listView.Items[0].Selected = $true
        }
    }

    $getSelected = {
        if ($listView.SelectedItems.Count -eq 0) { return $null }
        return $listView.SelectedItems[0].Tag
    }

    $listView.Add_SelectedIndexChanged({
        $dev = & $getSelected
        Update-DriverDiagDetailPane -Labels $labels -Device $dev
    })

    $btnScan.Add_Click({ & $loadList })

    $btnRescan.Add_Click({
        if ($script:ScanBusy) { return }
        Invoke-DriverDiagRescan
        & $loadList
    })

    $btnEscopo.Add_Click({ & $showScope })

    $btnPasta.Add_Click({
        $root = Get-DriverDiagDownloadRoot
        Start-Process explorer.exe -ArgumentList $root
    })

    $btnPular.Add_Click({
        $dev = & $getSelected
        if (-not $dev) { return }
        $dev.Skipped = $true
        $idx = $listView.SelectedIndices[0]
        $listView.Items[$idx].ForeColor = $script:GuiTheme.Muted
        $listView.Items[$idx].SubItems[0].Text = 'PULADO'
        $statusLabel.Text = "Pulado: $($dev.Model)"
        if ($idx + 1 -lt $listView.Items.Count) {
            $listView.Items[$idx + 1].Selected = $true
            $listView.EnsureVisible($idx + 1)
        }
    })

    $btnDetalhes.Add_Click({
        $dev = & $getSelected
        if (-not $dev) { return }
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("Modelo: $($dev.Model)")
        [void]$sb.AppendLine("Categoria: $($dev.Category)")
        [void]$sb.AppendLine("Classe: $($dev.Class)")
        [void]$sb.AppendLine("Status: $($dev.Status)")
        [void]$sb.AppendLine("Codigo: $($dev.ProblemCode) - $($dev.ProblemMessage)")
        [void]$sb.AppendLine("Fabricante: $($dev.VendorName)")
        [void]$sb.AppendLine("VEN/DEV: $($dev.VendorId)/$($dev.DeviceId)")
        [void]$sb.AppendLine("Driver: $($dev.DriverName)")
        [void]$sb.AppendLine("Provedor: $($dev.DriverProvider)")
        [void]$sb.AppendLine("Versao: $($dev.DriverVersion)")
        [void]$sb.AppendLine("INF: $($dev.InfName)")
        [void]$sb.AppendLine("InstanceId: $($dev.InstanceId)")
        [void]$sb.AppendLine('Hardware IDs:')
        foreach ($h in $dev.HardwareIds) { [void]$sb.AppendLine("  $h") }
        if ($dev.SupportUrl) { [void]$sb.AppendLine("Suporte: $($dev.SupportUrl)") }
        [System.Windows.Forms.MessageBox]::Show($sb.ToString(), 'Detalhes',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    })

    $btnCorrigir.Add_Click({
        try {
            $dev = & $getSelected
            Invoke-DriverDiagGuiFix -Form $form -Device $dev -StatusLabel $statusLabel -Progress $progress
            & $loadList
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("$_", 'DriverDiag - erro') | Out-Null
            $statusLabel.Text = 'Erro ao corrigir.'
            $progress.Style = 'Blocks'
            $progress.Value = 0
        }
    })

    $btnManual.Add_Click({
        try {
            $dev = & $getSelected
            Invoke-DriverDiagGuiFix -Form $form -Device $dev -StatusLabel $statusLabel -Progress $progress -ManualPick
            & $loadList
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("$_", 'DriverDiag - erro') | Out-Null
            $statusLabel.Text = 'Erro no modo manual.'
            $progress.Style = 'Blocks'
            $progress.Value = 0
        }
    })

    $btnCorrigirTodos.Add_Click({
        try {
            Invoke-DriverDiagGuiFixAll -Form $form -Devices @($script:GuiDevices) -StatusLabel $statusLabel -Progress $progress
            & $loadList
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("$_", 'DriverDiag - erro') | Out-Null
            $statusLabel.Text = 'Erro em Corrigir todos.'
            $progress.Style = 'Blocks'
            $progress.Value = 0
        }
    })

    $form.Add_Shown({
        if ($split.Width -gt 100) {
            $split.SplitterDistance = [Math]::Max(380, [int]($form.ClientSize.Width * 0.48))
        }
    })

    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $statusLabel.Text = 'AVISO: sem Admin - instalacao pode falhar. Escolha o escopo e Varrer.'
        $statusLabel.ForeColor = $script:GuiTheme.Warn
    }

    [void]$form.ShowDialog()
}
