# DriverDiag

Diagnóstico/correção de drivers no Windows (GUI ou console).

- Sem pasta `drivers\` no pendrive
- Download em `%USERPROFILE%\Downloads\DriverDiag\`
- Fontes: Microsoft Update Catalog + sites OEM oficiais
- Se o download falhar: só links oficiais

## Rodar

```bat
DriverDiag.cmd
```

Eleva admin e abre a GUI (escolhe categorias → varre → corrige).

```bat
DriverDiag.cmd -Console
```

## No kit

```bat
call "%~dp0DriverDiag\DriverDiag.cmd"
```

## Compartilhar (rede, sem instalar Git)

Estilo **executar da Internet** (como `irm christitus.com/win | iex`): nada de `git clone` nem pasta fixa em `%LOCALAPPDATA%`.

### Opcao 1 — so o `ferramenta.bat`

Envie `ferramenta.bat` (raiz deste repo ou pasta Genesis). Duplo clique ou:

```bat
ferramenta.bat
ferramenta.bat -Console
```

### Opcao 2 — uma linha PowerShell

```powershell
irm https://raw.githubusercontent.com/PatoSemP/DriverDiag/main/bootstrap.ps1 | iex
```

Com argumentos (modo consola):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/PatoSemP/DriverDiag/main/bootstrap.ps1))) -Console
```

### O que acontece

1. `bootstrap.ps1` transfere o ZIP do GitHub (`…/archive/refs/heads/main.zip`) para `%TEMP%\DriverDiag-run-<id>\`.
2. Extrai, executa `DriverDiag.ps1` e remove a pasta temporaria quando seguro (modo GUI sem admin pode deixar ficheiros ate fechar a janela elevada).

**Requisitos:** Windows 10/11, PowerShell 5.1+, Internet. **Nao** precisa de Git.

**Importante:** os URLs `raw.githubusercontent.com` so funcionam depois de `bootstrap.ps1` estar publicado na branch `main` do repositorio. Fork proprio: edite `BOOTSTRAP_URL` no `.bat` e as constantes no topo de `bootstrap.ps1`.

Elevacao de administrador continua a cargo do `DriverDiag.ps1`.

## Fluxo

1. Scan PnP (`Get-PnpDevice` + WMI + `pnputil /problem`)
2. Escolhe **Corrigir**
3. Catalog + OEM → candidatos
4. Download → extrai → `pnputil /add-driver /install`
5. Confirma extra em GPU/armazenamento

## Requisitos

Windows 10/11, PowerShell 5.1+, Admin, internet só no download.
