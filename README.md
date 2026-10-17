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

## Fluxo

1. Scan PnP (`Get-PnpDevice` + WMI + `pnputil /problem`)
2. Escolhe **Corrigir**
3. Catalog + OEM → candidatos
4. Download → extrai → `pnputil /add-driver /install`
5. Confirma extra em GPU/armazenamento

## Requisitos

Windows 10/11, PowerShell 5.1+, Admin, internet só no download.
