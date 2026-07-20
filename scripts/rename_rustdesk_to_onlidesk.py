#!/usr/bin/env python3
"""
Rename rustdesk → onlidesk no codebase OnliDesk.
Executar APENAS uma vez — não é idempotente.

Uso:
    python3 scripts/rename_rustdesk_to_onlidesk.py [--dry-run]
"""
import os
import re
import sys
import shutil
from pathlib import Path

DRY_RUN = "--dry-run" in sys.argv
ROOT = Path(__file__).parent.parent.resolve()

EXTENSIONS = {
    '.rs', '.toml', '.yaml', '.yml', '.cpp', '.h', '.m', '.mm',
    '.dart', '.cc', '.sh', '.ps1', '.bat', '.swift', '.swiftmodule',
    '.xcodeproj', '.wxs'
}

# Padrões de substituição (old → new)
REPLACEMENTS = [
    # Rust lib/crate names
    (r'\brustdesk\b', 'onlidesk'),        # geral
    (r'\blibrustdesk\b', 'libonlidesk'),  # nome da lib
    (r'\bRustDesk\b', 'OnliDesk'),         # branding no código
    (r'\brustdesk\.exe\b', 'OnliDesk.exe'),
    (r'\brustdesk-portable-packer\.exe\b', 'onlidesk-portable-packer.exe'),
    # Comments/docstrings
    (r'\bRustDesk core\b', 'OnliDesk core'),
    (r'\blibrustdesk core\b', 'OnliDesk core'),
]

# Arquivos que devem ser renomeados (não apenas editados)
RENAME_MAP = {
    'rustdesk': 'onlidesk',
    'RustDesk': 'OnliDesk',
    'rustdesk-portable-packer.exe': 'onlidesk-portable-packer.exe',
}

def should_process(path: Path, skip_dirs: set, skip_files: set) -> bool:
    # Não processar submódulos
    for skip in skip_dirs:
        if skip in path.parts:
            return False
    # Não processar arquivos específicos
    if path.name in skip_files:
        return False
    if path.suffix in EXTENSIONS:
        return True
    name = path.name.lower()
    # inclui arquivos de config sem extensão
    if name in {'cargo.lock', 'package.json'}:
        return True
    if name.endswith('.xcodeproj'):
        return True
    if name.endswith('.wxs'):
        return True
    return False

def process_file(path: Path) -> list[str]:
    """Retorna lista de (old, new, content_diff) para o arquivo."""
    changes = []
    try:
        content = path.read_text(encoding='utf-8', errors='replace')
    except Exception as e:
        print(f"  [SKIP] não consegui ler {path}: {e}")
        return changes

    new_content = content
    for pattern, repl in REPLACEMENTS:
        new_content = re.sub(pattern, repl, new_content)

    if new_content != content:
        changes.append((str(path), 'content_changed', f"{len(content)} → {len(new_content)} bytes"))
        if not DRY_RUN:
            path.write_text(new_content, encoding='utf-8')

    return changes

def process_rename(path: Path) -> list[str]:
    """Renomear arquivos."""
    changes = []
    for old_part, new_part in RENAME_MAP.items():
        if old_part in path.name:
            new_name = path.name.replace(old_part, new_part)
            new_path = path.parent / new_name
            if new_path.exists() and new_path != path:
                print(f"  [SKIP] já existe: {new_path}")
                return changes
            if not DRY_RUN:
                path.rename(new_path)
            changes.append((str(path), 'renamed', f"→ {new_name}"))
            return changes
    return changes

def walk_and_process(root: Path):
    all_changes = []
    skip_dirs = {
        '.git', 'target', 'node_modules', '.cargo', 'vcpkg_installed',
        'build', '.dart_tool', '.pub-cache', '.idea', '.vscode',
        # Não modificar submódulos — são dependências upstream
        'libs/hbb_common',
    }

    # NÃO renomear estes arquivos específicos
    skip_files = {
        '.github/workflows/third-party-RustDeskTempTopMostWindow.yml',  # teste upstream
        'README.md', 'docs/README-AR.md', 'docs/README-CS.md',
    }

    for path in root.rglob('*'):
        # Pula diretórios de build e dependências
        for skip in skip_dirs:
            if skip in path.parts:
                break
        else:
            if path.is_file() and should_process(path, skip_dirs, skip_files):
                changes = process_file(path)
                all_changes.extend(changes)

                # Renomear arquivos se o nome contém rustdesk (exceto submodule)
                if any(old in path.name for old in RENAME_MAP):
                    changes = process_rename(path)
                    all_changes.extend(changes)

    return all_changes

if __name__ == '__main__':
    print(f"{'[DRY RUN] ' if DRY_RUN else ''}Renomeando rustdesk → onlidesk em {ROOT}")
    print()

    changes = walk_and_process(ROOT)

    if DRY_RUN:
        print(f"Arquivos que seriam modificados ({len(changes)}):\n")
        for path, kind, detail in sorted(changes):
            print(f"  [{kind:20s}] {path}")
    else:
        print(f"Concluído: {len(changes)} alteração(ões)\n")
        for path, kind, detail in sorted(changes):
            print(f"  [{kind:20s}] {path} {detail}")

    print()
    if DRY_RUN:
        print("Execute sem --dry-run para aplicar as mudanças.")
    else:
        print("⚠️  IMPORTANTE:")
        print("  1. Rebuild completo: cargo clean && cargo build --release --features flutter")
        print("  2. Regenerar bridge: flutter_rust_bridge_codegen")
        print("  3. Rebuild Flutter: cd flutter && flutter pub get && flutter build")
        print("  4. Commit: git add -A && git commit -m 'refactor: rename rustdesk → onlidesk'")