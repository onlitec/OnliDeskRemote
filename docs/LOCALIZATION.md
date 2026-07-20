# OnliDesk — Estratégia de Localização

## Visão Geral

Este documento define a estratégia de suporte a idiomas para o fork **OnliDesk by Onlitec**,
focado no mercado corporativo brasileiro. O objetivo é manter apenas os idiomas críticos
com alta qualidade, reduzindo a carga de manutenção.

---

## Idiomas Prioritários

| Prioridade | Idioma       | Arquivo                | Status        | Notas                              |
| :--------- | :----------- | :--------------------- | :------------ | :--------------------------------- |
| 🥇 P1      | **Inglês**  | `src/lang/en.rs`       | ✅ Completo   | Idioma base — não remover          |
| 🥇 P1      | **Português (Brasil)** | `src/lang/ptbr.rs` | ⚠️ Parcial   | Foco atual — completar urgente     |
| 🥈 P2      | Espanhol    | `src/lang/es.rs`       | ⚠️ Parcial   | LatAm B2B (futuro)                 |
| 🥉 P3      | Alemão      | `src/lang/de.rs`       | ⚠️ Parcial   | Manter por agora                  |
| 🥉 P3      | Francês     | `src/lang/fr.rs`       | ⚠️ Parcial   | Manter por agora                  |
| 🗑️ P4      | ~47 outros  | `src/lang/*.rs`        | ⚠️ Parcial   | **Candidatos a remoção**          |

---

## Ações Recomendadas

### Curto prazo (agora)
- [ ] **Completar `ptbr.rs`** — o arquivo atual tem ~753 entries mas está incompleto
  em relação ao `en.rs`. Compare as chaves faltantes:
  ```bash
  # Encontrar chaves em en.rs que não existem em ptbr.rs
  python -c "
  import re
  def keys(f): return set(re.findall(r'\"(\w+)\".*:', open(f).read()))
  en = keys('src/lang/en.rs')
  pt = keys('src/lang/ptbr.rs')
  missing = en - pt
  for k in sorted(missing): print(k)
  "
  ```
- [ ] **Remover idiomas P4** — arquivos que nunca serão traduzidos:
  - `ge.rs`, `gu.rs`, `he.rs`, `ta.rs`, `ml.rs`, `lv.rs`, `lt.rs`, `kz.rs`,
    `nb.rs`, `sq.rs`, `sr.rs`, `sl.rs`, `sk.rs`, `bg.rs`, `be.rs`, `eo.rs`,
    `da.rs`, `fi.rs`, `ca.rs`, `uk.rs`, `vi.rs`, `th.rs`, `tr.rs`...
  - Para cada remoção: deletar o arquivo `src/lang/<code>.rs` e remover do
    `src/lang.rs` o `mod <code>;`.

### Médio prazo (próximos sprints)
- [ ] Completar `es.rs` para suporte LatAm
- [ ] Configurar CI para verificar completude de tradução:
  ```yaml
  # .github/workflows/translations-check.yml
  - name: Check translation coverage
    run: |
      MISSING=$(python scripts/check_translations.py)
      if [ -n "$MISSING" ]; then
        echo "Missing translations:"
        echo "$MISSING"
        exit 1
      fi
  ```
- [ ] Adicionar validação de JSON de tradução no pre-commit

### Longo prazo
- [ ] Migrar sistema de tradução para Gettext (.po/.mo) ou
  [Tolgee](https://tolgee.io/) para edição colaborativa por não-desenvolvedores
- [ ] Considerar Crowdin / Weblate para tradução crowdsourced com review

---

## Sistema de Tradução Atual

O OnliDesk usa um sistema de HashMap estático (Rust):

```
src/lang/
  en.rs      ← idioma de referência (sempre completo)
  ptbr.rs    ← português brasileiro
  *.rs       ← outros idiomas
src/lang.rs  ← mapeia código → módulo + nomes de arquivo .ftl
```

### Como adicionar novo idioma
1. Criar `src/lang/<code>.rs` copiando a estrutura de `en.rs`
2. Adicionar em `src/lang.rs`: `pub const <CODE>: &str = "..."`
3. Atualizar `flutter/lib/common.dart` com o nome traduzido
4. Rebuild: `cargo build --features inline`

---

## Notas Importantes

- **Não usar `TODO` ou `FIXME` em traduções** — strings de UI devem ser completas
- **Placeholders**: manter `%min%`, `%max%`, `%s` etc. — são substituídos em runtime
- **Tamanho de strings**: UI em português é ~20% maior que em inglês.
  Testar com `overflow: hidden` e text wrapping antes de commitar.
- **Data/hora**: usar `Intl` no Flutter, não formatos hardcoded (`dd/MM/yyyy` para BR)

---

## Referências
- [RustDesk Wiki: How to translate](https://github.com/rustdesk/rustdesk/wiki/Translation)
- [Flutter Internationalization](https://docs.flutter.dev/development/accessibility-and-localization/internationalization)