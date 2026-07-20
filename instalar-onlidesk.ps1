# ================================================================
#  OnliDesk — Script PowerShell de Instalação e Configuração
#  Branding: OnliDesk by Onlitec
#  Servidor: 100.72.185.126 (VPN Tailscale — servidor Brasil)
#  Autor:    Onlitec DevOps Team
# ================================================================
#
# EXECUÇÃO:
#   Execute no PowerShell como ADMINISTRADOR:
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\instalar-onlidesk.ps1
#
# Para uso em GPO/RMM (completamente silencioso):
#   powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File instalar-onlidesk.ps1 -Silent
#
# COM VARIÁVEIS DE AMBIENTE (recomendado para CI/CD):
#   $env:ONLIDESK_SERVER = "100.72.185.126"
#   $env:ONLIDESK_KEY    = "your-key-here"
#   .\instalar-onlidesk.ps1
#
# ================================================================

param (
    [switch]$Silent
)

# ── Configurações do Servidor OnliDesk ──────────────────────────
# PRIORIDADE: variáveis de ambiente > parâmetros > defaults
$SERVIDOR = if ($env:ONLIDESK_SERVER) { $env:ONLIDESK_SERVER } else { "100.72.185.126" }
$CHAVE    = if ($env:ONLIDESK_KEY)    { $env:ONLIDESK_KEY }    else { "" }
$VERSAO   = if ($env:ONLIDESK_VERSION) { $env:ONLIDESK_VERSION } else { "latest" }

# ── URL do instalador (fork OnliDesk) ──────────────────────────
# ATENÇÃO: publique releases no repositório onlidesk/onlidesk
# e atualize esta URL para apontar para o seu release.
# Formato: https://github.com/<owner>/<repo>/releases/latest/download/<asset>
$DOWNLOAD_URL = if ($env:ONLIDESK_DOWNLOAD_URL) {
    $env:ONLIDESK_DOWNLOAD_URL
} else {
    # Fallback: releases do fork onlidesk
    # Substitua pelo URL real do seu asset de release:
    #   https://github.com/onlidesk/onlidesk/releases/latest/download/OnliDesk-Setup.exe
    $apiUrl = "https://api.github.com/repos/onlidesk/onlidesk/releases/latest"
    try {
        $release = Invoke-RestMethod -Uri $apiUrl -Headers @{"User-Agent" = "OnliDesk-Installer"} -TimeoutSec 15
        $asset = $release.assets | Where-Object { $_.name -match "Setup\.exe$|\.exe$" -and $_.name -notmatch "arm|debug|portable" } | Select-Object -First 1
        if ($asset) { $asset.browser_download_url } else { $null }
    } catch { $null }
}
# ────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"

function Write-Step {
    param($Num, $Total, $Msg)
    if (-not $Silent) {
        Write-Host "[$Num/$Total] $Msg" -ForegroundColor Cyan
    }
}

function Write-OK   { if (-not $Silent) { Write-Host "        OK!" -ForegroundColor Green } }
function Write-Info { param($M) if (-not $Silent) { Write-Host "        $M" -ForegroundColor Yellow } }
function Write-Err  { param($M) Write-Host "[ERRO] $M" -ForegroundColor Red; exit 1 }

if (-not $Silent) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host "   OnliDesk — Instalacao do Cliente de Acesso Remoto" -ForegroundColor White
    Write-Host "   Powered by Onlitec" -ForegroundColor DarkCyan
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host ""
}

# Verificar privilégios de administrador
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")
if (-not $isAdmin) { Write-Err "Execute como Administrador!" }

# ── Etapa 1: Validar configuração ─────────────────────────────
Write-Step 1 5 "Validando configuracao do servidor..."
if ([string]::IsNullOrWhiteSpace($SERVIDOR)) {
    Write-Err "Servidor nao definido. Defina \$env:ONLIDESK_SERVER ou edite o script."
}
if ([string]::IsNullOrWhiteSpace($CHAVE)) {
    Write-Err "Chave nao definida. Defina \$env:ONLIDESK_KEY ou edite o script."
}
Write-Info "Servidor: $SERVIDOR"
Write-OK

# ── Etapa 2: Baixar OnliDesk (fork) ───────────────────────────
Write-Step 2 5 "Baixando cliente OnliDesk..."

$installerPath = "$env:TEMP\onlidesk-setup.exe"

if ($DOWNLOAD_URL) {
    try {
        Write-Info "Baixando de: $DOWNLOAD_URL"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $DOWNLOAD_URL -OutFile $installerPath -Headers @{"User-Agent" = "OnliDesk-Installer"} -TimeoutSec 120
        Write-OK
    } catch {
        Write-Err "Falha ao baixar: $_"
    }
} else {
    # Fallback: procurar instalador local (para build interno)
    $localInstaller = "OnliDesk-1.4.6-Setup.exe"
    if (Test-Path $localInstaller) {
        Write-Info "Usando instalador local: $localInstaller"
        Copy-Item $localInstaller $installerPath -Force
        Write-OK
    } else {
        Write-Err "Nenhum instalador encontrado. Defina ONLIDESK_DOWNLOAD_URL ou coloque o .exe na pasta do script."
    }
}

# ── Etapa 3: Instalar silenciosamente ─────────────────────────
Write-Step 3 5 "Instalando o cliente..."
try {
    Start-Process -FilePath $installerPath -ArgumentList "--silent-install" -Wait -NoNewWindow
    Start-Sleep -Seconds 5
    Write-OK
} catch {
    Write-Err "Falha na instalacao: $_"
}

# ── Etapa 4: Aplicar configuração do servidor ─────────────────
Write-Step 4 5 "Configurando servidor OnliDesk..."

$configContent = @"
[options]
custom-rendezvous-server = '$SERVIDOR'
relay-server = '$SERVIDOR'
key = '$CHAVE'
approve-mode = 'both'
direct-server = 'N'
enable-audio = 'N'
"@

$configPaths = @(
    "$env:APPDATA\OnliDesk",
    "$env:APPDATA\OnliDesk\config",
    "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\OnliDesk",
    "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\OnliDesk\config"
)

foreach ($path in $configPaths) {
    if (-not (Test-Path $path)) {
        try {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        } catch {}
    }
    if (Test-Path $path) {
        $configContent | Out-File -FilePath "$path\OnliDesk2.toml" -Encoding UTF8 -Force
    }
}

Write-Info "Servidor: $SERVIDOR"
Write-OK

# ── Etapa 5: Reiniciar o serviço ──────────────────────────────
Write-Step 5 5 "Iniciando servico OnliDesk..."
try {
    $svc = Get-Service -Name "OnliDesk" -ErrorAction SilentlyContinue
    if ($svc) {
        Restart-Service -Name "OnliDesk" -Force
    } else {
        $exePath = "C:\Program Files\OnliDesk\OnliDesk.exe"
        if (Test-Path $exePath) {
            Start-Process -FilePath $exePath -ArgumentList "--install-service" -Wait -NoNewWindow
            Start-Service -Name "OnliDesk" -ErrorAction SilentlyContinue
        }
    }
    Write-OK
} catch {
    Write-Info "Servico iniciado via app."
}

# ── Resultado Final ───────────────────────────────────────────
if (-not $Silent) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "   OnliDesk instalado e configurado com SUCESSO!" -ForegroundColor White
    Write-Host ""
    Write-Host "   Servidor: $SERVIDOR" -ForegroundColor Cyan
    Write-Host "   Status:   Abra o OnliDesk e aguarde status 'Pronto'" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   Para usar em CI/CD, exporte as variáveis:" -ForegroundColor White
    Write-Host "   \$env:ONLIDESK_SERVER = '$SERVIDOR'" -ForegroundColor Gray
    Write-Host "   \$env:ONLIDESK_KEY    = '<sua-chave>'" -ForegroundColor Gray
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
}

# Limpar instalador
Remove-Item $installerPath -Force -ErrorAction SilentlyContinue