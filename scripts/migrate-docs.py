#!/usr/bin/env python3
"""Migrate mkdocs-specific markdown syntax to Docusaurus-compatible syntax."""

import re
import sys
from pathlib import Path

ADMONITION_TYPE_MAP = {
    'note': 'note',
    'tip': 'tip',
    'info': 'info',
    'warning': 'warning',
    'danger': 'danger',
    'important': 'caution',
    'caution': 'caution',
    'abstract': 'info',
    'success': 'tip',
    'question': 'info',
    'failure': 'danger',
    'bug': 'danger',
    'example': 'note',
    'quote': 'note',
}


def convert_admonitions(content: str) -> str:
    lines = content.split('\n')
    result = []
    i = 0

    while i < len(lines):
        line = lines[i]
        m = re.match(r'^!!!\s+(\w+)(?:\s+"([^"]*)")?', line)
        if m:
            adm_type = m.group(1).lower()
            title = m.group(2)
            docusaurus_type = ADMONITION_TYPE_MAP.get(adm_type, adm_type)

            if title and title.strip().lower() != adm_type:
                result.append(f':::{docusaurus_type}[{title}]')
            else:
                result.append(f':::{docusaurus_type}')
            result.append('')

            i += 1
            body_lines = []

            while i < len(lines):
                if lines[i].startswith('    '):
                    body_lines.append(lines[i][4:])
                    i += 1
                elif lines[i] == '':
                    # Look ahead: keep blank line only if next non-blank line
                    # is still indented (still inside the admonition block)
                    j = i + 1
                    while j < len(lines) and lines[j] == '':
                        j += 1
                    if j < len(lines) and lines[j].startswith('    '):
                        body_lines.append('')
                        i += 1
                    else:
                        break
                else:
                    break

            # Trim trailing blank lines from body
            while body_lines and body_lines[-1] == '':
                body_lines.pop()

            result.extend(body_lines)
            result.append('')
            result.append(':::')
        else:
            result.append(line)
            i += 1

    return '\n'.join(result)


def convert_icons(content: str) -> str:
    # Strip octicons: :octicons-name-24:
    content = re.sub(r':octicons-[\w-]+-\d+:', '', content)
    # Strip material icons: :material-name:
    content = re.sub(r':material-[\w-]+:', '', content)
    # Strip simple icons: :simple/name:
    content = re.sub(r':simple/[\w-]+:', '', content)
    # Normalise heading whitespace after icon removal: "## <spaces>Text" -> "## Text"
    content = re.sub(r'^(#+) {2,}', lambda m: m.group(1) + ' ', content, flags=re.MULTILINE)
    content = re.sub(r'^(#+) $', r'\1 ', content, flags=re.MULTILINE)
    return content


def convert_figures(content: str) -> str:
    def _replace_figure(m: re.Match) -> str:
        alt = m.group(1)
        path = m.group(2)
        return (
            "<div style={{textAlign: 'center'}}>\n\n"
            f'![{alt}]({path})\n\n'
            '</div>'
        )

    # <figure markdown="span">\n  ![alt](path){ ... }\n</figure>
    pattern = r'<figure[^>]*>\s*!\[([^\]]*)\]\(([^)]+)\)\{[^}]*\}\s*</figure>'
    content = re.sub(pattern, _replace_figure, content, flags=re.DOTALL)

    # Standalone attribute list: ![alt](path){ ... }  (not inside figure)
    content = re.sub(r'(!\[[^\]]*\]\([^)]+\))\{[^}]*\}', r'\1', content)
    return content


def convert_image_paths(content: str) -> str:
    # Relative path from docs root: assets/images/
    content = content.replace('](assets/images/', '](/img/')
    # Relative path from subdirectory: ../assets/images/
    content = content.replace('](../assets/images/', '](/img/')
    # Absolute path from site root: /assets/images/
    content = content.replace('](/assets/images/', '](/img/')
    return content


def migrate_file(path: Path) -> None:
    original = path.read_text(encoding='utf-8')
    result = original
    result = convert_admonitions(result)
    result = convert_icons(result)
    result = convert_figures(result)
    result = convert_image_paths(result)
    if result != original:
        path.write_text(result, encoding='utf-8')
        print(f'  migrated: {path}')
    else:
        print(f'  unchanged: {path}')


def main() -> None:
    docs_dir = Path('docs/docs')
    if not docs_dir.is_dir():
        print(f'ERROR: {docs_dir} not found. Run from the repository root.', file=sys.stderr)
        sys.exit(1)

    md_files = sorted(docs_dir.rglob('*.md'))
    print(f'Migrating {len(md_files)} markdown files in {docs_dir}...')
    for f in md_files:
        migrate_file(f)
    print('Done.')


if __name__ == '__main__':
    main()
