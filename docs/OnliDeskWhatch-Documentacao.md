# OnliDeskWhatch — Documentação Técnica Completa

> Sistema corporativo de **acesso remoto + monitoramento** de colaboradores.
> Fork do RustDesk (marca **OnliDesk**) com um módulo de auditoria embutido
> (**OnliDeskWhatch**) e uma plataforma web ("cockpit") para o administrador.

Última atualização: 2026-07-22.

---

## 1. Visão geral

O OnliDeskWhatch tem **duas metades**:

1. **Cliente Windows** (Rust + Flutter) — instalado nas máquinas dos colaboradores.
   Faz **acesso remoto** (herdado do RustDesk) e **monitoramento**: sites acessados,
   eventos de arquivos em pastas monitoradas e **evidências** (captura de tela +
   janela ativa + processo) em acessos sensíveis.
2. **Servidor de monitoramento** (Node.js + SQLite) — recebe os dados, categoriza
   (regras + IA local + RDAP), gera relatórios inteligentes e serve o **painel web**
   onde o administrador acompanha tudo.

Separação por servidor (decisão de infraestrutura):

| Função | Servidor | Endereço |
|---|---|---|
| **Acesso remoto** (hbbs/hbbr) | Brasil | `onlideskremotesvr.onlitec.com.br` / Tailscale `100.72.185.126` |
| **Monitoramento** (Node + painel + IA) | Finlândia (Hetzner) | `https://onlideskwatch.onlitec.com.br` |

---

## 2. Arquitetura

```
┌──────────────────────── Máquina do colaborador (Windows) ────────────────────────┐
│  OnliDesk.exe (Flutter) ── carrega ──> librustdesk.dll (Rust)                     │
│    ├─ Serviço Windows  "OnliDesk"  (sessão 0, SYSTEM, start=auto)                 │
│    │     └─ lança o processo  --server  (sessão do usuário)                       │
│    │            └─ onlidesk-watch::start_monitoring()                             │
│    │                 ├─ sni.rs      (captura de domínios via WinDivert)           │
│    │                 ├─ evidence.rs (janela + processo + screenshot)              │
│    │                 ├─ watcher.rs  (eventos de arquivos)                         │
│    │                 └─ mikrotik.rs (fallback via API do roteador)               │
│    └─ --tray  (icone na bandeja)                                                  │
│  Config: C:\ProgramData\OnliDeskWhatch\watch_config.json                          │
└───────────────────────────────────────────────────────────────────────────────────┘
                │  HTTPS (Bearer = token do dispositivo)
                ▼
┌──────────────────────── Servidor Finlândia (Docker) ─────────────────────────────┐
│  nginx-proxy-manager (TLS) ──> container onlidesk-watch-server (172.17.0.1:4460) │
│    Node.js + Express + SQLite                                                     │
│      ├─ /api/logs, /api/evidence, /api/devices/*  (ingestão + pareamento)        │
│      ├─ enriquecimento: regra -> IA -> RDAP -> reverse-DNS  (domain_meta)         │
│      ├─ worker de relatório IA (a cada 3 min)                                     │
│      └─ painel web (SPA) em /public                                               │
│  IA local: container onlifin-ollama (modelo qwen2.5:3b) via rede onlifin-network │
└───────────────────────────────────────────────────────────────────────────────────┘
```

- **Repositórios:** o app fica em `onlitec/OnliDeskRemote` (fork RustDesk); o módulo
  de monitoramento é o submódulo `OnliDeskWhatch/` = `onlitec/OnliDeskWatch`.
- **Feature Cargo `watch`** (padrão OFF): o build padrão é OnliDesk puro (só acesso
  remoto); com `--watch` vira o produto OnliDeskWhatch (remoto + monitoramento).

---

## 3. Cliente (Rust) — `OnliDeskWhatch/src/`

Crate `onlidesk-watch`, integrado ao workspace do app. Disparado em
`src/server.rs` (do app) dentro do bloco `#[cfg(feature = "watch")]`, no processo
`--server` (sessão interativa do usuário — por isso enxerga a tela).

### 3.1 `lib.rs` — supervisor
- `start_monitoring()` inicializa tudo; sobe a captura SNI (Windows) e um
  **loop supervisor** que faz o pareamento e sobe os monitores.
- Ciclo: `pair_until_approved()` → sobe watcher, flush do spool, loop de política de
  captura e (se SNI desligado) o monitor Mikrotik; reinicia se o dispositivo for
  bloqueado no painel (HTTP 403).

### 3.2 `sni.rs` — identificação de sites (a fonte principal de dados)
- Lê o **domínio** direto do tráfego de saída via **WinDivert** (driver de sniff em
  modo read-only): SNI do handshake TLS (HTTPS/443) e cabeçalho **Host** (HTTP/80).
- Independe do roteador, funciona com DoH e CDN, é **por máquina**. Só metadado
  (domínio), nunca payload.
- **Filtro de ruído** (`NOISE`): descarta CDN/telemetria (akamai, fastly, gstatic,
  doubleclick, telemetry, ocsp, etc.). `valid_domain()` também rejeita IP e infra.
- Dedup por domínio numa janela de 5 min (`first_time`).
- Ao detectar um domínio válido: grava `site_access` e, se a **política de captura**
  marcar (`evidence::wants_capture`), dispara a evidência.

### 3.3 `evidence.rs` — provas (captura de tela)
- **Categorias** (chave → palavras-chave do domínio): `bancos`, `redes_sociais`,
  `streaming`, `adulto`, `apostas`, `odio`, `drogas`.
- **Política** (`Policy { enabled, categories, custom }`) buscada do servidor a cada
  ~60s por `start_policy_loop()` (endpoint `/api/devices/policy`).
- `wants_capture(domain)` → captura se a política está ativa **e** (a categoria do
  domínio está habilitada **ou** o domínio contém uma palavra-chave extra do admin).
- `report(domain, category, force)`:
  1. Dedup: no máx. 1 captura por domínio a cada 10 min (`force=true` ignora — usado
     na captura imediata).
  2. Coleta (em `spawn_blocking`, pois é GDI bloqueante): **janela ativa** +
     **processo** (Win32) e **screenshot** do desktop virtual (todos os monitores),
     reduzido p/ máx. 1366 px, JPEG qualidade ~55.
  3. POST em `/api/evidence` com `Authorization: Bearer <device_token>` (imagem em
     base64 `data:image/jpeg`).
- **Captura imediata:** o loop de política, ao receber `capture_now=true`, chama
  `report("captura-imediata", "Captura imediata (admin)", true)`.
- Detecção de janela/processo: `GetForegroundWindow`/`GetWindowTextW`/
  `GetWindowThreadProcessId` + `QueryFullProcessImageNameW`. Screenshot: GDI
  (`GetDC`/`BitBlt`/`GetDIBits`) → `image` (feature jpeg).

### 3.4 `watcher.rs` — auditoria de arquivos
- Observa as **pastas monitoradas** (crate `notify`, recursivo): eventos
  `file_created/modified/moved/deleted`.
- **Recarrega os caminhos da config a cada ~20s** — uma pasta cadastrada no painel
  passa a ser monitorada sem reiniciar o serviço.

### 3.5 `mikrotik.rs` — fallback por roteador
- Coleta IPs acessados via **API REST do Mikrotik** (RouterOS 7+:
  `/rest/ip/firewall/connection` + cache DNS). **Desligado quando o SNI está ativo**
  (evita ruído de IP). RouterOS v6 não tem REST (só API binária 8728/8729).

### 3.6 `config.rs` / `crypto.rs` / `logger.rs`
- **`config.rs`**: `C:\ProgramData\OnliDeskWhatch\watch_config.json` — `mikrotik_*`,
  `monitored_paths`, `webhook_url`, `webhook_token`, `device_token`, `device_status`,
  `admin_password_hash`, `sni_capture` (padrão true).
- **`crypto.rs`**: hash admin `sha256$salt$hash`; senha do Mikrotik cifrada
  `enc:v1:` (AES-256-CBC, chave embutida). Interopera com o Node e o Dart.
- **`logger.rs`**: `log_event()` grava local (JSON Lines) e envia ao servidor;
  **spool** `pending_logs.jsonl` para resiliência offline; sinaliza bloqueio no 403.

### 3.7 `build.rs` + `vendor/windivert/`
- Linka `WinDivert.lib` → `WinDivert.dll`; `vendor/windivert/` traz `WinDivert.dll`,
  `WinDivert64.sys` (assinado) e o header.

---

## 4. Servidor (Node.js) — `OnliDeskWhatch/server/`

Express + SQLite (`sqlite3`). Porta 4460, publicada em `172.17.0.1:4460` (bridge
Docker) atrás do nginx-proxy-manager (TLS).

### 4.1 Banco de dados — `src/database.js`

| Tabela | Colunas | Função |
|---|---|---|
| `devices` | mac (PK), hostname, ip, user, token, status, last_seen, created_at, **capture_now** | Máquinas + pareamento + comando de captura imediata |
| `audit_logs` | id, mac, timestamp, event_type, target, details | Eventos (site_access, file_*) |
| `domain_meta` | domain (PK), category, label, platform, productive, risk, source, updated_at | Cache de enriquecimento (regra/ia/rdap/rdns) |
| `ai_reports` | key (PK), scope, content, generated_at | Cache dos relatórios/insights de IA |
| `evidence` | id, mac, user, target, category, window_title, process, screenshot, timestamp | Provas (screenshot em `/data/evidence`) |
| `settings` | key (PK), value | Config do painel (ex.: `capture_policy` em JSON) |

### 4.2 `src/index.js` — API e workers
- Auth do **painel**: `POST /api/admin/login` (bcrypt de `WATCH_ADMIN_PASSWORD_HASH`)
  → token de sessão em memória (TTL 8h). Middleware `adminAuthMiddleware`.
- Auth do **dispositivo**: `Authorization: Bearer <device.token>` + `mac`, validado
  contra `devices` (status `approved`).
- **Worker de enriquecimento** (`enrichBatch`, a cada 45s): para cada alvo novo,
  `regra (categories.js) → IA (ai.js) → RDAP (rdap.js) → reverse-DNS`; grava em
  `domain_meta`. **Backfill**: reprocessa "Outros" antigos com RDAP (1x cada).
- **Worker de relatório IA** (`refreshAiCache`, a cada 3 min): gera e cacheia o
  relatório e os insights do dia (para o painel abrir instantâneo).
- **Filtro de visões** (`hideFromSites`): esconde ruído (CDN/telemetria) e IP não
  identificado; mostra IP já resolvido por organização (ex.: "Microsoft (IP)").
  `?raw=1` mostra tudo (auditoria).

### 4.3 `src/categories.js`
- `categorize(target)` — categoriza por palavra-chave (Redes sociais, Streaming,
  Trabalho, E-mail, Compras, Notícias, IA/Chat, Bancos, Governo, Downloads/CDN).
- `platformOf` (Instagram/Facebook/TikTok/…), `isProductiveCat`, `isNoise`,
  `isRawIp`, `isMeaninglessSite`, `hideFromSites(target, category)`.

### 4.4 `src/rdap.js` — identificação por registro oficial
- Consulta **RDAP** (sucessor do WHOIS) via `rdap.org`: organização dona de um
  **domínio** (`lookupDomain`) ou **IP** (`lookupIp`). Grátis, sem chave. Só
  metadado. `registrable()` reduz subdomínio ao domínio registrável (trata
  `.com.br` etc.). Melhor para **IPs** (não redigidos): `8.8.8.8 → Google LLC`.

### 4.5 `public/app.js` + `public/style.css` — painel (SPA)
Cockpit em JS puro: roteador por hash, gráficos Chart.js (vendorizado), toasts,
tooltips, tema claro/escuro, auto-refresh 15s, export CSV.

---

## 5. Uso do modelo de IA

- **Modelo:** `qwen2.5:3b` via **Ollama** (container `onlifin-ollama`), **local** no
  servidor da Finlândia. Sem internet, sem custo, privado.
- **Cliente Ollama:** `server/src/ai.js` — `POST {OLLAMA_URL}/api/generate`
  (`stream:false`; `format:"json"` na classificação). Env: `OLLAMA_URL`
  (`http://onlifin-ollama:11434`), `OLLAMA_MODEL` (`qwen2.5:3b`), `AI_ENABLED`.

A IA é usada em **duas frentes** (nunca recebe payload — só domínios/agregados):

1. **Classificação da cauda longa** — `classifyDomain(domain, categorias)` devolve
   JSON validado `{category, label, platform, productive, risk}` para domínios que
   as regras não cobriram. Cacheado em `domain_meta` (`source='ai'`).
2. **Relatórios em linguagem natural** — `generateReport(hint, dadosJSON)`:
   - **Relatório executivo** (`/api/ai/report`): seções fixas (Resumo, Onde foi o
     tempo, Destaques por colaborador, Pontos de atenção), fundamentado **somente
     nos dados** (prompt proíbe inventar).
   - **Insights/alertas** (`/api/ai/insights`): sites de risco, acessos fora do
     horário comercial, padrões do dia.
   - Ambos **cacheados** (`ai_reports`) e regenerados pelo worker a cada 3 min.

**O que a IA NÃO faz:** ela não "identifica" o dono de um IP puro (isso é dado, não
inferência) — para isso usamos **RDAP + reverse-DNS**. A IA agrega valor em
categorizar e em escrever os relatórios. O modelo é local: **nenhum dado de
colaborador sai da rede** (apenas o nome de domínio vai ao RDAP público quando
necessário).

---

## 6. Funcionalidades (painel)

| Página | O que mostra |
|---|---|
| **Dashboard** | KPIs, donut "onde vai o tempo" (categorias), timeline, top destinos, atividade por máquina/usuário |
| **Sites** | Sites acessados agrupados por domínio (accordion), com categoria/rótulo/risco (enriquecidos por IA/RDAP) |
| **Redes Sociais** | Uso por plataforma (Instagram/TikTok/…), ranking de colaboradores, linha do tempo |
| **Provas** | Grade de evidências (screenshot + janela + processo + horário); **critérios de captura** (retraídos) e **captura imediata** |
| **Relatório IA** | Relatório executivo + insights (automáticos, com botão "Atualizar agora") |
| **Registros** | Auditoria bruta (site_access, file_*), filtrável e exportável (a prova crua) |
| **Máquinas / Usuários** | Detalhe por computador/colaborador, com páginas dedicadas |
| **Relatórios** | Exportação CSV filtrável (máquina/usuário/tipo/período; BOM UTF-8) |

### 6.1 Provas e critérios de captura
- O admin escolhe, por **categorias agrupadas**, o que dispara a captura:
  - **Financeiro:** Bancos / Finanças
  - **Redes e entretenimento:** Redes sociais · Streaming/Vídeo
  - **Conteúdo sensível:** Pornografia/Adulto · Apostas/Jogos de azar · Discurso de
    ódio/Racismo · Drogas/Armas
  - **+ palavras-chave extras** (campo livre) e **toggle mestre** "Captura ativa".
- A seção vem **retraída** por padrão (cabeçalho clicável, chevron, badge de ativos).
- **Captura imediata:** seletor de máquina + botão "Capturar agora" → o cliente
  captura na próxima verificação (~1 min).
- **Limite:** 1 captura por domínio a cada 10 min (a imediata ignora o limite).

> **Limites honestos de detecção:** bancos/redes/adulto/apostas têm ótima detecção
> por nome de domínio; **ódio/racismo e drogas** têm detecção limitada (é conteúdo,
> não domínio) — por isso o campo de palavras-chave. **CSAM (pedofilia)** não é
> detectável por domínio e é matéria criminal para autoridades.

---

## 7. Referência da API

**Painel (sessão admin — `Bearer <session token>`):**
```
POST /api/admin/login | /api/admin/logout
GET  /api/clients | /api/logs | /api/stats
POST /api/devices/approve | /api/devices/block
GET  /api/analytics/{overview,timeline,top-targets,by-device,by-user,
                     by-category,site-visits,user-summary,categories,social}
GET  /api/ai/{status,report,insights}
GET  /api/evidence | /api/evidence/:id/image (aceita ?token=)
GET  /api/settings/capture   PUT /api/settings/capture
POST /api/devices/capture-now
GET  /api/export  (CSV)
```
**Dispositivo (cliente — `Bearer <device token>` + mac):**
```
POST /api/devices/register        (pareamento; retorna status/token)
GET  /api/devices/status
POST /api/logs                    (site_access, file_*)
POST /api/evidence                (janela + processo + screenshot)
GET  /api/devices/policy?mac=...  (política de captura + comando imediato)
```

---

## 8. Fluxos principais

1. **Pareamento:** cliente `POST /api/devices/register` → fica `pending` no painel →
   admin aprova → servidor devolve `device_token` → cliente passa a enviar dados.
2. **Sites:** SNI capta domínio → `POST /api/logs` (`site_access`) → worker
   enriquece (`domain_meta`) → painel mostra categorizado.
3. **Evidência (automática):** SNI capta domínio sensível → `wants_capture` (política)
   → screenshot+janela+processo → `POST /api/evidence`.
4. **Captura imediata:** admin clica "Capturar agora" → `capture_now` no device →
   cliente vê em `/api/devices/policy` (one-shot) → captura → `POST /api/evidence`.
5. **Relatório IA:** worker (3 min) monta agregados filtrados → Ollama gera texto →
   cache `ai_reports` → painel abre instantâneo.

---

## 9. Segurança e privacidade

- **Painel:** senha bcrypt (`WATCH_ADMIN_PASSWORD_HASH`) + token de sessão; endpoints
  de leitura/gestão protegidos.
- **Dispositivo:** token único por máquina; bloqueio remoto (403 → re-pareamento).
- **Config local:** `C:\ProgramData\OnliDeskWhatch` com permissão `users-modify`
  (o painel de admin, não elevado, grava a config); a **fonte de verdade** dos
  registros é o **servidor** (adulterar a config local no máximo faz o dispositivo
  parar de reportar, o que é visível no painel).
- **IA local:** os dados ficam no servidor; nada vai a provedores externos.
- **LGPD:** o monitoramento — em especial a **captura de tela** — exige **aviso
  formal aos colaboradores** (política interna/termo de ciência). Responsabilidade
  do empregador. Só metadado de rede (domínio) sai para o RDAP público.

---

## 10. Deploy e build

### 10.1 Servidor (Finlândia)
- `OnliDeskWhatch/server/`: `Dockerfile` + `docker-compose.yml` (bind
  `172.17.0.1:4460`, rede `onlifin-network` p/ o Ollama, volume `watch-data`).
- Senha do painel: `node server/src/hash-password.js "<senha>"` →
  `WATCH_ADMIN_PASSWORD_HASH` no `.env` → `docker compose up -d`.
- Deploy (SSH WireGuard `10.10.10.1:4450`):
  ```
  cd server && tar -cf - <arquivos> | ssh -p 4450 alfreire@10.10.10.1 \
    'cd ~/onlideskwhatch && tar -xf - && docker compose up -d --build'
  ```
- Testar sempre por `http://172.17.0.1:4460` (NÃO 127.0.0.1). NPM: proxy host id 15
  → `onlideskwatch.onlitec.com.br`; `proxy_read_timeout 300s` em
  `/data/nginx/custom/server_proxy.conf` (relatório IA leva ~25s).

### 10.2 Cliente (Windows)
1. `cargo build --features flutter,watch --lib --release` → `librustdesk.dll`
   (env: `VCPKG_ROOT`, `LIBCLANG_PATH`, `CARGO_PROFILE_RELEASE_LTO=false`; use
   `-j 2` e `CODEGEN_UNITS=4` em máquinas com pouca RAM p/ evitar OOM/swap lento).
2. `flutter build windows --release` (Flutter 3.24.5) → bundle em
   `flutter/build/windows/x64/runner/Release/`.
3. Copiar `librustdesk.dll` + WinDivert ao bundle.
4. `ISCC.exe OnliDeskWhatch/installer.iss` → `OnliDesk-1.4.6-Watch-Setup.exe`.
- **Instalador:** cria o serviço `OnliDesk` direto via `sc` (start=auto, com
  auto-restart), atalho de bandeja na pasta Inicializar, ajusta a permissão do
  config (`icacls`), e na desinstalação **para o WinDivert antes** de matar os
  processos (evita o travamento do broker).
- Publicado em `https://onlideskremotesvr.onlitec.com.br/downloads/`.

---

## 11. Estrutura de arquivos (resumo)

```
OnliDeskRemote/                      (app OnliDesk — fork RustDesk)
├─ src/tray.rs                       (ícone da bandeja — carregamento robusto)
├─ src/server.rs                     (dispara o monitoramento no --server)
├─ res/tray-icon.png                 (ícone do tray)
├─ docs/OnliDeskWhatch-Documentacao.md   (este documento)
└─ OnliDeskWhatch/                   (submódulo = onlitec/OnliDeskWatch)
   ├─ src/                           (crate onlidesk-watch)
   │  ├─ lib.rs  sni.rs  evidence.rs  watcher.rs  mikrotik.rs
   │  ├─ config.rs  crypto.rs  logger.rs  build.rs
   │  └─ vendor/windivert/
   ├─ installer.iss                  (instalador InnoSetup)
   └─ server/                        (plataforma Node)
      ├─ src/index.js  database.js  ai.js  categories.js  rdap.js
      ├─ public/app.js  style.css
      ├─ Dockerfile  docker-compose.yml
      └─ data/  (evidence/ + database.sqlite no volume)
```

---

## 12. Histórico de decisões relevantes

- **SNI em vez de só Mikrotik:** o painel mostrava só IPs (DoH/CDN furam o DNS do
  roteador). A captura SNI no cliente resolve — domínios reais, por máquina.
- **RDAP para IPs:** a IA não resolve IP puro; RDAP identifica a organização dona
  (Microsoft/Google/Cloudflare), tornando as visões legíveis.
- **Relatório automático:** o modelo local leva ~25s; um worker mantém o cache
  quente (o painel nunca espera) e corrigiu a corrida do auto-refresh de 15s.
- **Provas no processo `--server`:** roda na sessão do usuário, por isso a captura
  de tela funciona (a restrição de "serviço não vê a tela" não se aplica).
- **Serviço criado direto no instalador:** o `--install-service` do RustDesk falhava
  por `runas` oculto; o InnoSetup cria o serviço via `sc` (já elevado).
