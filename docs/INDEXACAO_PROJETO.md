# Indexacao do Projeto

## Visao Geral

Este repositorio contem o OnliDesk, uma aplicacao de acesso remoto multiplataforma.
O nucleo principal esta em Rust, enquanto a interface moderna esta em Flutter.

## Estrutura Principal

### `src/`

Nucleo Rust da aplicacao.

- `main.rs`: ponto de entrada principal do binario.
- `lib.rs`: indice central dos modulos do core.
- `core_main.rs`: bootstrap, argumentos e inicializacao da aplicacao.
- `client.rs`: logica do lado cliente da sessao remota.
- `server.rs`: agregacao dos servicos locais expostos na sessao.
- `rendezvous_mediator.rs`: comunicacao com servidor rendezvous e relay.
- `flutter_ffi.rs`: ponte entre Rust e Flutter.
- `ipc/`: comunicacao entre processos.
- `platform/`: implementacoes especificas por sistema operacional.
- `server/`: servicos remotos de audio, video, input, clipboard, terminal e impressao.
- `privacy_mode/`: recursos de privacidade.
- `plugin/`: infraestrutura de plugins nativos.
- `whiteboard/`: funcionalidades de quadro branco.
- `ui/`: interface Sciter legada, hoje secundaria.

### `flutter/`

Interface moderna desktop e mobile.

- `lib/main.dart`: entrada principal da aplicacao Flutter.
- `lib/common/`: widgets, estado compartilhado e componentes reutilizaveis.
- `lib/desktop/`: paginas e telas do fluxo desktop.
- `lib/mobile/`: paginas e telas do fluxo mobile.
- `lib/models/`: modelos de estado e integracao com a camada nativa.
- `lib/plugin/`: camada de plugin no lado Flutter.
- `lib/utils/`: utilitarios, platform channels e gerencia de janelas.
- `android/`, `ios/`, `linux/`, `macos/`, `windows/`: runners nativos por plataforma.

### `libs/`

Crates Rust internos e componentes de baixo nivel.

- `hbb_common/`: configuracao, proto, rede, utilitarios e tipos compartilhados.
- `scrap/`: captura de tela, camera, codecs e pipeline de video.
- `enigo/`: simulacao de teclado e mouse multiplataforma.
- `clipboard/`: clipboard remoto e transferencia de conteudo entre plataformas.
- `virtual_display/`: display virtual, principalmente no Windows.
- `remote_printer/`: suporte a impressao remota.
- `portable/`: empacotamento e execucao em modo portatil.
- `libxdo-sys-stub/`: stub para builds Linux sem dependencia real de `libxdo`.

### Outras Pastas Relevantes

- `docs/`: documentacao do projeto.
- `.github/`: workflows de CI/CD, automacoes e patches auxiliares.
- `res/`: scripts e recursos auxiliares de empacotamento.
- `appimage/`: configuracoes de distribuicao AppImage.
- `flatpak/`: configuracoes de distribuicao Flatpak.
- `fastlane/`: automacoes de release mobile.
- `examples/`: exemplos pequenos e experimentais.

## Arquivos-Chave

### Backend Rust

- `src/main.rs`: entrada principal da aplicacao.
- `src/lib.rs`: raiz dos modulos do core.
- `src/core_main.rs`: inicializacao do app e fluxos de startup.
- `src/client.rs`: conexao com peer remoto e fluxo de sessao.
- `src/server.rs`: inicializacao dos servicos do host.
- `src/rendezvous_mediator.rs`: descoberta, registro e relay.
- `src/flutter_ffi.rs`: API de integracao entre Flutter e Rust.

### Flutter

- `flutter/lib/main.dart`: bootstrap da UI Flutter.
- `flutter/lib/models/native_model.dart`: wrapper da biblioteca Rust no Dart.
- `flutter/lib/models/model.dart`: estado central da sessao remota na UI.
- `flutter/lib/desktop/pages/desktop_tab_page.dart`: shell principal da UI desktop.

### Bibliotecas Internas

- `libs/hbb_common/src/config.rs`: configuracao global do produto.
- `libs/hbb_common/src/lib.rs`: base compartilhada do ecossistema.
- `libs/scrap/src/lib.rs`: biblioteca de captura de tela e video.
- `libs/clipboard/src/lib.rs`: infraestrutura de clipboard remoto.
- `libs/enigo/src/lib.rs`: controle de input remoto.

## Areas Criticas

- Rede e sessao remota: `src/client.rs`, `src/server/`, `src/rendezvous_mediator.rs`
- Captura de tela e video: `libs/scrap/`
- Input remoto: `libs/enigo/`
- Clipboard e transferencia: `libs/clipboard/`
- Configuracao e protocolo compartilhado: `libs/hbb_common/`
- Interface desktop e mobile: `flutter/lib/desktop/`, `flutter/lib/mobile/`
- Integracao Flutter <-> Rust: `src/flutter_ffi.rs`, `flutter/lib/models/native_model.dart`

## Ordem Recomendada de Leitura

1. `src/lib.rs`
2. `src/core_main.rs`
3. `src/rendezvous_mediator.rs`
4. `src/server.rs`
5. `src/server/connection.rs`
6. `src/client.rs`
7. `src/flutter_ffi.rs`
8. `flutter/lib/main.dart`
9. `flutter/lib/models/native_model.dart`
10. `libs/hbb_common/src/config.rs`

## Mapa Mental Rapido

- Core do produto: `src/` + `libs/`
- Interface atual: `flutter/`
- Interface antiga: `src/ui/`
- Portabilidade por sistema: `src/platform/` + runners nativos do Flutter
- Funcionalidades de sessao remota: `server/`, `client.rs`, `rendezvous_mediator.rs`
- Distribuicao e release: `.github/`, `flatpak/`, `appimage/`, `fastlane/`
