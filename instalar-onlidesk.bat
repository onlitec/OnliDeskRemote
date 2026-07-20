@echo off
:: ================================================================
::  OnliDesk — Instalador Silencioso para Windows
::  Branding: OnliDesk by Onlitec
:: ================================================================
:: USO:
::   Execute este script como ADMINISTRADOR
::   Ele irá:
::   1. Validar a configuração do servidor
::   2. Baixar o cliente OnliDesk (fork)
::   3. Instalar silenciosamente
::   4. Aplicar a configuração
::   5. Iniciar o serviço
:: ================================================================
:: VARIÁVEIS DE AMBIENTE (suportam CI/CD e GPO):
::   ONLIDESK_SERVER   → servidor rendezvous/relay
::   ONLIDESK_KEY      → chave de autenticação
::   ONLIDESK_DOWNLOAD_URL → URL completa do .exe (opcional)
:: ================================================================

title OnliDesk — Instalacao

echo.
echo ============================================================
echo    OnliDesk - Instalando cliente de acesso remoto seguro
echo    Powered by Onlitec
echo ============================================================
echo.

:: ── Verificar Admin ──────────────────────────────────────────
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERRO] Execute este script como ADMINISTRADOR!
    echo Clique com o botao direito e "Executar como administrador"
    pause
    exit /b 1
)

:: ── Ler variáveis de ambiente (fallback para defaults) ────────
:: Se ONLIDESK_SERVER nao estiver definida, usa o default
if not defined ONLIDESK_SERVER (
    set "ONLIDESK_SERVER=100.72.185.126"
    set "ONLIDESK_KEY=CHANGE_ME_SET_ONLIDESK_KEY_ENV_VAR"
)

if "%ONLIDESK_KEY%"=="CHANGE_ME_SET_ONLIDESK_KEY_ENV_VAR" (
    echo [ERRO] Chave nao definida!
    echo Defina a variavel de ambiente ONLIDESK_KEY antes de executar.
    echo Ex: set ONLIDESK_KEY=sua-chave-aqui
    echo.
    echo Para CI/CD, exporte as variáveis:
    echo   set ONLIDESK_SERVER=seu-servidor.com
    echo   set ONLIDESK_KEY=sua-chave
    pause
    exit /b 1
)

echo [INFO] Servidor: %ONLIDESK_SERVER%
echo [INFO] Baixando cliente OnliDesk...

:: ── Etapa 1: Baixar do fork OnliDesk ──────────────────────────
:: Se ONLIDESK_DOWNLOAD_URL estiver definido, usa ele.
:: Caso contrário, tenta a API do GitHub do fork.
if defined ONLIDESK_DOWNLOAD_URL (
    echo [1/4] Baixando de URL customizada...
    for %%F in ("%ONLIDESK_DOWNLOAD_URL%") do set "FILENAME=%%~nxF"
    powershell -Command "& {[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%ONLIDESK_DOWNLOAD_URL%' -OutFile '%TEMP%\%FILENAME%' -Headers @{'User-Agent'='OnliDesk-Installer'} -TimeoutSec 120}"
    set "INSTALLER=%TEMP%\%FILENAME%"
) else (
    :: Tenta API do fork onlidesk — fallback para build local
    echo [1/4] Procurando release no fork onlidesk...
    for /f "delims=" %%R in ('powershell -Command "try { $r = Invoke-RestMethod -Uri 'https://api.github.com/repos/onlidesk/onlidesk/releases/latest' -Headers @{'User-Agent'='OnliDesk-Installer'} -TimeoutSec 10; $a = $r.assets ^| Where-Object { $_.name -match 'Setup\.exe$' -and $_.name -notmatch 'arm|debug|portable' } ^| Select-Object -First 1; if ($a) { $a.browser_download_url } else { '' } } catch { '' }"') do set "DOWNLOAD_URL=%%R"
    if defined DOWNLOAD_URL (
        echo [1/4] Baixando do fork...
        for %%F in ("%DOWNLOAD_URL%") do set "FILENAME=%%~nxF"
        powershell -Command "& {[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%DOWNLOAD_URL%' -OutFile '%TEMP%\%FILENAME%' -Headers @{'User-Agent'='OnliDesk-Installer'} -TimeoutSec 120}"
        set "INSTALLER=%TEMP%\%FILENAME%"
    ) else (
        :: Fallback: usa build local se existir
        if exist "OnliDesk-1.4.6-Setup.exe" (
            echo [1/4] Usando instalador local...
            copy "OnliDesk-1.4.6-Setup.exe" "%TEMP%\onlidesk-setup.exe" /Y
            set "INSTALLER=%TEMP%\onlidesk-setup.exe"
        ) else (
            echo [ERRO] Nenhum instalador encontrado!
            echo Defina ONLIDESK_DOWNLOAD_URL ou coloque o .exe na pasta.
            pause
            exit /b 1
        )
    )
)

if not exist "%INSTALLER%" (
    echo [ERRO] Falha no download. Verifique a URL.
    pause
    exit /b 1
)
echo        Download concluido!

:: ── Etapa 2: Instalar ─────────────────────────────────────────
echo [2/4] Instalando silenciosamente...
"%INSTALLER%" --silent-install
timeout /t 5 /nobreak >nul
echo        Instalacao concluida!

:: ── Etapa 3: Aplicar configuração ─────────────────────────────
echo [3/4] Aplicando configuracao do servidor...

set "RDCFG_USER=%APPDATA%\OnliDesk"
set "RDCFG_USER_NEW=%APPDATA%\OnliDesk\config"
set "RDCFG_SVC=C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\OnliDesk"
set "RDCFG_SVC_NEW=C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\OnliDesk\config"

if not exist "%RDCFG_USER%" mkdir "%RDCFG_USER%"
if not exist "%RDCFG_USER_NEW%" mkdir "%RDCFG_USER_NEW%"
if not exist "%RDCFG_SVC%" mkdir "%RDCFG_SVC%"
if not exist "%RDCFG_SVC_NEW%" mkdir "%RDCFG_SVC_NEW%"

for %%p in ("%RDCFG_USER%" "%RDCFG_USER_NEW%" "%RDCFG_SVC%" "%RDCFG_SVC_NEW%") do (
    if exist %%p (
        (
        echo [options]
        echo custom-rendezvous-server = '%ONLIDESK_SERVER%'
        echo relay-server = '%ONLIDESK_SERVER%'
        echo key = '%ONLIDESK_KEY%'
        echo approve-mode = 'both'
        echo direct-server = 'N'
        echo enable-audio = 'N'
        ) > "%%~p\OnliDesk2.toml"
    )
)
echo        Configuracao aplicada!

:: ── Etapa 4: Iniciar ──────────────────────────────────────────
echo [4/4] Iniciando o OnliDesk...
net stop "OnliDesk" >nul 2>&1
timeout /t 2 /nobreak >nul
net start "OnliDesk" >nul 2>&1

:: Tentar abrir — às vezes o serviço falha no primeiro start
start "" "C:\Program Files\OnliDesk\OnliDesk.exe"

echo.
echo ============================================================
echo    OnliDesk instalado e configurado com sucesso!
echo.
echo    Servidor: %ONLIDESK_SERVER%
echo    Status:   Aguarde o app abrir (status "Pronto")
echo ============================================================
echo.

:: Limpar
del /f /q "%INSTALLER%" >nul 2>&1

pause