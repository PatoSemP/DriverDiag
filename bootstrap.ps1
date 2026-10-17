[CmdletBinding()]
param(
    [switch]$Console,
    [string[]]$Categories,
    [switch]$IncludeSuspicious,
    [switch]$IncludeDisconnected,
    [switch]$ScanOnly
)

$ErrorActionPreference = 'Stop'

$RepoOwner = 'PatoSemP'
$RepoName  = 'DriverDiag'
$Branch    = 'main'
$ZipUrl    = "https://github.com/$RepoOwner/$RepoName/archive/refs/heads/$Branch.zip"

function Test-DriverDiagBootstrapAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-BootstrapFail {
    param([string]$Message)
    Write-Host ''
    Write-Host "[DriverDiag] $Message" -ForegroundColor Red
    Write-Host ''
    Write-Host 'Verifique a ligacao à Internet e se o repositorio esta acessivel.' -ForegroundColor Yellow
    Write-Host "URL: $ZipUrl" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host 'Enter para fechar...' -NoNewline
    try { [void](Read-Host) } catch { }
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}
catch { }

$script:BootstrapAdminAtStart = Test-DriverDiagBootstrapAdmin
$runDir = $null
$exitCode = 0

try {
    $suffix = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $runDir = Join-Path $env:TEMP "DriverDiag-run-$suffix"
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null

    $zipPath = Join-Path $runDir 'DriverDiag.zip'
    Write-Host '[DriverDiag] A transferir a versao mais recente...' -ForegroundColor Cyan

    try {
        Invoke-WebRequest -Uri $ZipUrl -OutFile $zipPath -UseBasicParsing
    }
    catch {
        if ($_.Exception.Message -match '404') {
            throw 'Arquivo nao encontrado (404). Confirme que bootstrap.ps1 e o repositorio ja foram publicados no GitHub (branch main).'
        }
        throw "Falha ao transferir: $($_.Exception.Message)"
    }

    if (-not (Test-Path -LiteralPath $zipPath) -or (Get-Item -LiteralPath $zipPath).Length -lt 100) {
        throw 'Transferencia incompleta ou resposta invalida do servidor.'
    }

    Write-Host '[DriverDiag] A extrair...' -ForegroundColor Cyan
    Expand-Archive -LiteralPath $zipPath -DestinationPath $runDir -Force
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue

    $extracted = Get-ChildItem -LiteralPath $runDir -Directory |
        Where-Object { $_.Name -like "$RepoName-*" } |
        Select-Object -First 1

    if (-not $extracted) {
        throw 'Estrutura do arquivo ZIP inesperada (pasta DriverDiag-* nao encontrada).'
    }

    $ps1 = Join-Path $extracted.FullName 'DriverDiag.ps1'
    if (-not (Test-Path -LiteralPath $ps1)) {
        throw "DriverDiag.ps1 nao encontrado em: $($extracted.FullName)"
    }

    $invokeParams = @{}
    if ($Console) { $invokeParams['Console'] = $true }
    if ($ScanOnly) { $invokeParams['ScanOnly'] = $true }
    if ($PSBoundParameters.ContainsKey('IncludeSuspicious')) {
        $invokeParams['IncludeSuspicious'] = [bool]$IncludeSuspicious
    }
    if ($PSBoundParameters.ContainsKey('IncludeDisconnected')) {
        $invokeParams['IncludeDisconnected'] = [bool]$IncludeDisconnected
    }
    if ($Categories -and $Categories.Count -gt 0) {
        $invokeParams['Categories'] = $Categories
    }

    Write-Host '[DriverDiag] A iniciar...' -ForegroundColor Cyan
    & $ps1 @invokeParams
    if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        $exitCode = $LASTEXITCODE
    }
}
catch {
    Write-BootstrapFail -Message $_.Exception.Message
    exit 1
}
finally {
    # Sem admin, DriverDiag.ps1 relanca elevado e sai logo; nao apagar TEMP ate o utilizador fechar a instancia elevada.
    $elevationHandoff = (-not $script:BootstrapAdminAtStart) -and (-not $ScanOnly)

    if (-not $elevationHandoff -and $runDir -and (Test-Path -LiteralPath $runDir)) {
        try {
            Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction Stop
        }
        catch {
            Write-Host '[DriverDiag] Aviso: nao foi possivel remover a pasta temporaria.' -ForegroundColor DarkYellow
        }
    }
    elseif ($elevationHandoff -and $runDir) {
        Write-Host "[DriverDiag] Ficheiros temporarios em: $runDir" -ForegroundColor DarkGray
        Write-Host '(A instancia elevada pode precisar desta pasta; pode apagar depois de fechar o DriverDiag.)' -ForegroundColor DarkGray
    }
}

exit $exitCode
