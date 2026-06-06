# MkDocs → Docusaurus Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the MkDocs/Material build pipeline with Docusaurus while keeping all content, navigation structure, dark/light theme, admonitions, mermaid diagrams, and visual presentation identical.

**Architecture:** Docusaurus is scaffolded inside the existing `docs/` directory, which already contains `docs/docs/` (the markdown source). The Docusaurus project root is `docs/` with `docs.path: 'docs'` (its default), so markdown files do not move. Static images move from `docs/docs/assets/images/` to `docs/static/img/`. A Python script converts mkdocs-specific markdown syntax (admonitions, icon shortcodes, `<figure>` wrappers, image path prefixes) across all source files.

**Tech Stack:** Docusaurus 3.7.0, React 18, Node.js ≥18, `@docusaurus/theme-mermaid`, `peaceiris/actions-gh-pages@v3`

---

## File Map

| Action | Path | Purpose |
|---|---|---|
| Create | `docs/package.json` | Docusaurus Node.js project |
| Create | `docs/docusaurus.config.js` | Site config: title, baseUrl, theme, plugins |
| Create | `docs/sidebars.js` | Navigation sidebar (mirrors mkdocs.yml nav) |
| Create | `docs/src/css/custom.css` | Indigo primary color vars, image-center utility |
| Create | `scripts/migrate-docs.py` | Converts mkdocs syntax in-place across all md files |
| Modify | `docs/docs/index.md` | Add `slug: /` frontmatter (makes it the root page) |
| Copy | `docs/site/assets/images/favicon.png` → `docs/static/img/favicon.png` | Favicon |
| Copy | `docs/docs/assets/images/*.{png,webp}` → `docs/static/img/` | All 4 images |
| Modify | `Makefile` | Update `serve-docs` target |
| Modify | `.github/workflows/ci.yml` | Replace `publish-docs` job |
| Modify | `.gitignore` | Add `docs/node_modules/`, `docs/build/`, `docs/.docusaurus/` |
| Delete | `docs/mkdocs.yml` | Replaced by docusaurus.config.js + sidebars.js |

---

## Task 1: Create `docs/package.json`

**Files:**
- Create: `docs/package.json`

- [ ] **Step 1: Create the file**

```json
{
  "name": "kubernetes-platform-docs",
  "version": "0.0.0",
  "private": true,
  "scripts": {
    "docusaurus": "docusaurus",
    "start": "docusaurus start",
    "build": "docusaurus build",
    "swizzle": "docusaurus swizzle",
    "deploy": "docusaurus deploy",
    "clear": "docusaurus clear",
    "serve": "docusaurus serve",
    "write-translations": "docusaurus write-translations",
    "write-heading-ids": "docusaurus write-heading-ids"
  },
  "dependencies": {
    "@docusaurus/core": "3.7.0",
    "@docusaurus/preset-classic": "3.7.0",
    "@docusaurus/theme-mermaid": "3.7.0",
    "@mdx-js/react": "^3.0.0",
    "clsx": "^2.0.0",
    "prism-react-renderer": "^2.3.0",
    "react": "^18.0.0",
    "react-dom": "^18.0.0"
  },
  "devDependencies": {
    "@docusaurus/module-type-aliases": "3.7.0",
    "@docusaurus/types": "3.7.0"
  },
  "engines": {
    "node": ">=18.0"
  },
  "browserslist": {
    "production": [">0.5%", "not dead", "not op_mini all"],
    "development": [
      "last 3 chrome version",
      "last 3 firefox version",
      "last 3 safari version"
    ]
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add docs/package.json
git commit -m "chore: add docusaurus package.json"
```

---

## Task 2: Create `docs/docusaurus.config.js`

**Files:**
- Create: `docs/docusaurus.config.js`

> **Note on baseUrl:** The current mkdocs CI deploys to the `gh-pages` branch of `appvia/kubernetes-platform`, giving URL `https://appvia.github.io/kubernetes-platform/`. Verify this against the repo's GitHub Pages settings (`Settings → Pages`) before merging and update `baseUrl` if the site lives at a custom domain (set `baseUrl: '/'`).

- [ ] **Step 1: Create the file**

```js
// @ts-check
const {themes: prismThemes} = require('prism-react-renderer');

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'Kubernetes Platform',
  tagline: 'Built for DevOps, Platform Engineers, and SREs',
  url: 'https://appvia.github.io',
  baseUrl: '/kubernetes-platform/',
  onBrokenLinks: 'throw',
  onBrokenMarkdownLinks: 'warn',
  favicon: 'img/favicon.png',
  organizationName: 'appvia',
  projectName: 'kubernetes-platform',
  trailingSlash: false,

  themes: ['@docusaurus/theme-mermaid'],

  markdown: {
    mermaid: true,
  },

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          sidebarPath: './sidebars.js',
          routeBasePath: '/',
          editUrl:
            'https://github.com/appvia/kubernetes-platform/edit/main/docs/',
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      colorMode: {
        defaultMode: 'light',
        disableSwitch: false,
        respectPrefersColorScheme: true,
      },
      navbar: {
        title: 'Kubernetes Platform',
        logo: {
          alt: 'Kubernetes Platform Logo',
          src: 'img/favicon.png',
        },
        items: [
          {
            type: 'docSidebar',
            sidebarId: 'docs',
            position: 'left',
            label: 'Documentation',
          },
          {
            href: 'https://github.com/appvia/kubernetes-platform',
            label: 'GitHub',
            position: 'right',
          },
        ],
      },
      footer: {
        style: 'dark',
        links: [
          {
            label: 'GitHub',
            href: 'https://github.com/appvia',
          },
        ],
        copyright: `Copyright © ${new Date().getFullYear()} Appvia Ltd.`,
      },
      prism: {
        theme: prismThemes.github,
        darkTheme: prismThemes.dracula,
        additionalLanguages: ['yaml', 'bash', 'shell-session'],
      },
    }),
};

module.exports = config;
```

- [ ] **Step 2: Commit**

```bash
git add docs/docusaurus.config.js
git commit -m "chore: add docusaurus site configuration"
```

---

## Task 3: Create `docs/sidebars.js`

**Files:**
- Create: `docs/sidebars.js`

This mirrors the `nav:` block from `docs/mkdocs.yml` exactly, plus adds the orphaned `getting-started/standalone-aws` page that exists in source but was missing from the mkdocs nav.

- [ ] **Step 1: Create the file**

```js
/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  docs: [
    {
      type: 'doc',
      id: 'index',
      label: 'Overview',
    },
    {
      type: 'category',
      label: 'Architecture',
      items: [
        'architecture/overview',
        'architecture/setup',
        'architecture/system-appsets',
        'architecture/tenant-appsets',
        'architecture/tenant-namespace',
      ],
    },
    {
      type: 'category',
      label: 'Getting Started',
      items: [
        'getting-started/standalone',
        'getting-started/standalone-aws',
        'getting-started/central',
      ],
    },
    {
      type: 'category',
      label: 'Development',
      items: [
        'development/local',
        'development/validation',
        {
          type: 'category',
          label: 'Remote',
          items: [
            'development/overview',
            'development/standalone',
            'development/hub',
          ],
        },
      ],
    },
    {
      type: 'category',
      label: 'Platform',
      items: [
        'platform/overview',
        {
          type: 'category',
          label: 'Addons',
          items: ['catalog/overview', 'catalog/features'],
        },
        {
          type: 'category',
          label: 'Node Pools',
          items: [
            'platform/nodepools/overview',
            'platform/nodepools/karpenter',
          ],
        },
        {
          type: 'category',
          label: 'Notifications',
          items: [
            'platform/notifications/overview',
            'platform/notifications/slack',
          ],
        },
        {
          type: 'category',
          label: 'Security',
          items: [
            {
              type: 'category',
              label: 'Network Security',
              items: [
                'platform/security/cilium',
                'platform/security/cilium-examples',
              ],
            },
            {
              type: 'category',
              label: 'Admission Policy',
              items: [
                'platform/security/kyverno',
                'platform/security/kyverno-policies',
                'platform/security/pod-security',
              ],
            },
            'platform/security/cluster-roles',
            'platform/security/external-secrets',
          ],
        },
        {
          type: 'category',
          label: 'Workloads',
          items: [
            'platform/tenant/applications',
            'platform/tenant/system',
            {
              type: 'category',
              label: 'Autoscaling',
              items: [
                'platform/workloads/autoscaling/overview',
                'platform/workloads/autoscaling/keda',
                'platform/workloads/autoscaling/vpa',
              ],
            },
          ],
        },
      ],
    },
  ],
};

module.exports = sidebars;
```

- [ ] **Step 2: Commit**

```bash
git add docs/sidebars.js
git commit -m "chore: add docusaurus sidebar configuration"
```

---

## Task 4: Create `docs/src/css/custom.css`

**Files:**
- Create: `docs/src/css/custom.css`

Sets CSS custom properties to match the Material MkDocs indigo/deep-purple palette for both light and dark modes.

- [ ] **Step 1: Create directories and file**

```bash
mkdir -p docs/src/css
```

File content:

```css
/* Indigo primary – matches Material MkDocs indigo/deep-purple palette */
:root {
  --ifm-color-primary: #3f51b5;
  --ifm-color-primary-dark: #3949a3;
  --ifm-color-primary-darker: #36449a;
  --ifm-color-primary-darkest: #2c387f;
  --ifm-color-primary-light: #4559c7;
  --ifm-color-primary-lighter: #475ec8;
  --ifm-color-primary-lightest: #5c71cf;
  --ifm-code-font-size: 95%;
  --docusaurus-highlighted-code-line-bg: rgba(0, 0, 0, 0.1);
}

[data-theme='dark'] {
  --ifm-color-primary: #7986cb;
  --ifm-color-primary-dark: #6474c4;
  --ifm-color-primary-darker: #5a6bbf;
  --ifm-color-primary-darkest: #3f51b5;
  --ifm-color-primary-light: #8e98d2;
  --ifm-color-primary-lighter: #98a1d7;
  --ifm-color-primary-lightest: #b3bad8;
  --docusaurus-highlighted-code-line-bg: rgba(0, 0, 0, 0.3);
}

.image-center {
  text-align: center;
}

.image-center img {
  max-width: 100%;
}
```

- [ ] **Step 2: Commit**

```bash
git add docs/src/css/custom.css
git commit -m "chore: add docusaurus custom CSS with indigo theme"
```

---

## Task 5: Copy static image assets

**Files:**
- Create: `docs/static/img/` directory with 5 files (4 doc images + favicon)

The 4 source images live in `docs/docs/assets/images/`. The favicon is only available in the generated `docs/site/assets/images/` (MkDocs regenerated it from the Material theme). All 5 files go to `docs/static/img/` where Docusaurus will serve them at `/img/`.

- [ ] **Step 1: Create directory and copy files**

```bash
mkdir -p docs/static/img
cp docs/docs/assets/images/platform-banner.webp docs/static/img/
cp docs/docs/assets/images/architecture.png docs/static/img/
cp docs/docs/assets/images/argocd-hub-and-spoke.png docs/static/img/
cp docs/docs/assets/images/standalone-architecture.png docs/static/img/
cp docs/site/assets/images/favicon.png docs/static/img/
```

- [ ] **Step 2: Verify all 5 files are present**

```bash
ls docs/static/img/
```

Expected:
```
argocd-hub-and-spoke.png
architecture.png
favicon.png
platform-banner.webp
standalone-architecture.png
```

- [ ] **Step 3: Commit**

```bash
git add docs/static/
git commit -m "chore: add static image assets for docusaurus"
```

---

## Task 6: Write the markdown migration script

**Files:**
- Create: `scripts/migrate-docs.py`

This script converts four mkdocs-specific constructs in-place across every `.md` file under `docs/docs/`:

1. **Admonitions** – `!!! type "Title"\n    content` → `:::type[Title]\ncontent\n:::`
2. **Icon shortcodes** – `:octicons-name-24:`, `:material-name:`, `:simple/name:` → stripped
3. **Figure wrappers** – `<figure markdown="span">\n  ![alt](path){ align=center }\n</figure>` → `<div style={{textAlign: 'center'}}>\n\n![alt](newpath)\n\n</div>`
4. **Image paths** – `assets/images/`, `../assets/images/`, `/assets/images/` → `/img/`

The icon stripping will leave a leading space in some headings (e.g. `## ` after stripping `:octicons-stack-24: `); the script normalises heading whitespace to one space.

- [ ] **Step 1: Create the script**

```python
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
            '<div style={{textAlign: \'center\'}}>\n\n'
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
```

- [ ] **Step 2: Commit the script before running it**

```bash
git add scripts/migrate-docs.py
git commit -m "chore: add mkdocs-to-docusaurus markdown migration script"
```

---

## Task 7: Run the migration script

**Files:**
- Modify: all `docs/docs/**/*.md` files

- [ ] **Step 1: Run the script from the repo root**

```bash
python3 scripts/migrate-docs.py
```

Expected output (order may vary):
```
Migrating 23 markdown files in docs/docs...
  migrated: docs/docs/index.md
  migrated: docs/docs/architecture/overview.md
  migrated: docs/docs/development/hub.md
  migrated: docs/docs/development/local.md
  migrated: docs/docs/development/overview.md
  migrated: docs/docs/development/standalone.md
  migrated: docs/docs/development/validation.md
  migrated: docs/docs/getting-started/standalone.md
  migrated: docs/docs/getting-started/standalone-aws.md
  migrated: docs/docs/platform/notifications/overview.md
  migrated: docs/docs/platform/overview.md
  migrated: docs/docs/platform/security/cilium.md
  migrated: docs/docs/platform/security/cluster-roles.md
  migrated: docs/docs/platform/security/kyverno-policies.md
  migrated: docs/docs/platform/security/kyverno.md
  migrated: docs/docs/platform/tenant/applications.md
  migrated: docs/docs/platform/tenant/system.md
  migrated: docs/docs/platform/workloads/autoscaling/keda.md
  migrated: docs/docs/platform/workloads/autoscaling/vpa.md
  migrated: docs/docs/platform/workloads/autoscaling/overview.md
  ...
Done.
```

Files without any of the four constructs will show as `unchanged` — that is expected.

- [ ] **Step 2: Spot-check three files to verify the conversions**

Check `docs/docs/index.md` — should have no `!!!` lines, no `{ align=center }`, no `<figure markdown=`, and image path should start with `/img/`:

```bash
grep -n "!!!\|figure markdown\|align=center\|assets/images\|:octicons-\|:material-" docs/docs/index.md
```

Expected: no output.

Check `docs/docs/platform/workloads/autoscaling/keda.md` — should have `:::note`, `:::warning`, `:::caution` blocks instead of `!!!`:

```bash
grep -n ":::" docs/docs/platform/workloads/autoscaling/keda.md | head -20
```

Expected: lines like `:::note`, `:::warning`, `:::`.

Check `docs/docs/architecture/overview.md` — heading should no longer have icon prefix, image path should be `/img/`:

```bash
head -10 docs/docs/architecture/overview.md
```

Expected:
```markdown
# Architecture

The platform currently support both a standalone and hub and spoke architecture.

<div style={{textAlign: 'center'}}>

![Image title](/img/architecture.png)

</div>
```

- [ ] **Step 3: Commit migrated files**

```bash
git add docs/docs/
git commit -m "chore: migrate markdown from mkdocs syntax to docusaurus syntax"
```

---

## Task 8: Add `slug: /` frontmatter to `docs/docs/index.md`

**Files:**
- Modify: `docs/docs/index.md`

With `routeBasePath: '/'`, Docusaurus must know that `index.md` is the root page. Adding `slug: /` ensures it is served at `/` instead of `/index`.

- [ ] **Step 1: Prepend frontmatter to `docs/docs/index.md`**

The current file starts with `# Kubernetes Platform`. Prepend:

```markdown
---
slug: /
---

```

So the beginning of the file should become:

```markdown
---
slug: /
---

# Kubernetes Platform
```

- [ ] **Step 2: Verify**

```bash
head -5 docs/docs/index.md
```

Expected:
```
---
slug: /
---

# Kubernetes Platform
```

- [ ] **Step 3: Commit**

```bash
git add docs/docs/index.md
git commit -m "chore: add slug frontmatter to docs index for docusaurus root route"
```

---

## Task 9: Update `.gitignore`

**Files:**
- Modify: `.gitignore`

The existing `.gitignore` has `docs/site/` for the mkdocs build output. Docusaurus uses `build/` and `.docusaurus/` (cache) inside the `docs/` directory, and `node_modules/` for dependencies.

- [ ] **Step 1: Replace the mkdocs section in `.gitignore`**

Find the block:
```
# mkdocs
docs/site/
```

Replace it with:
```
# docs tooling
docs/site/
docs/build/
docs/.docusaurus/
docs/node_modules/
```

- [ ] **Step 2: Verify**

```bash
grep -A3 "# docs tooling" .gitignore
```

Expected:
```
# docs tooling
docs/site/
docs/build/
docs/.docusaurus/
docs/node_modules/
```

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: update gitignore for docusaurus build artifacts"
```

---

## Task 10: Update `Makefile` serve-docs target

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Replace the `serve-docs` target**

Find:
```makefile
serve-docs:
	@echo "--> Serving the documentation..."
	@cd docs && mkdocs serve
```

Replace with:
```makefile
serve-docs:
	@echo "--> Serving the documentation..."
	@cd docs && npm start
```

- [ ] **Step 2: Verify**

```bash
grep -A3 "serve-docs:" Makefile
```

Expected:
```
serve-docs:
	@echo "--> Serving the documentation..."
	@cd docs && npm start
```

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "chore: update serve-docs make target to use docusaurus"
```

---

## Task 11: Update `.github/workflows/ci.yml` publish-docs job

**Files:**
- Modify: `.github/workflows/ci.yml`

Replace the entire `publish-docs` job. The new job uses `actions/setup-node` instead of `actions/setup-python`, runs `npm ci && npm run build`, then deploys the `docs/build` directory to GitHub Pages via `peaceiris/actions-gh-pages@v3`.

The job's `if:` condition, `needs:`, and `permissions:` are unchanged. The `defaults.run.working-directory` is updated to `./docs` (was already `./docs` in the original, kept).

- [ ] **Step 1: Replace the `publish-docs` job**

Find the entire `publish-docs:` block (lines 142–179 in the current file) and replace it with:

```yaml
  publish-docs:
    name: Publish Docs
    if: needs.changes.outputs.docs == 'true' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    permissions:
      contents: write
    needs:
      - changes
      - validate-charts
      - validate-docs-spelling
      - validate-helm-addons
      - validate-kustomize
      - validate-kyverno
      - validate-schemas
      - validate-scripts
      - validate-yaml
    defaults:
      run:
        working-directory: ./docs
    steps:
      - uses: actions/checkout@v6
      - name: Configure Git Credentials
        run: |
          git config user.name github-actions[bot]
          git config user.email github-actions[bot]@users.noreply.github.com
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: docs/package-lock.json
      - run: npm ci
      - run: npm run build
      - uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./docs/build
```

- [ ] **Step 2: Verify the final state of the file**

```bash
grep -n "publish-docs\|setup-python\|setup-node\|mkdocs\|npm" .github/workflows/ci.yml
```

Expected output: lines referencing `setup-node` and `npm ci`/`npm run build`; no references to `setup-python` or `mkdocs`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: replace mkdocs publish step with docusaurus build and gh-pages deploy"
```

---

## Task 12: Install dependencies and verify the build

**Files:**
- Create: `docs/package-lock.json` (generated by npm)

- [ ] **Step 1: Install Docusaurus dependencies**

```bash
cd docs && npm install
```

Expected: npm resolves and installs ~300 packages, creates `docs/package-lock.json`.

- [ ] **Step 2: Run a development build to check for errors**

```bash
cd docs && npm run build 2>&1 | tail -30
```

Expected final lines:
```
[SUCCESS] Generated static files in "build".
[SUCCESS] Success! Generated static files in "build".
```

If you see broken link errors, look for the filename and fix the reference in the relevant `.md` file or `sidebars.js`.

- [ ] **Step 3: Smoke-test local server**

```bash
cd docs && npm start
```

Open `http://localhost:3000/kubernetes-platform/` (or `http://localhost:3000/` if baseUrl is `/`). Verify:
- Navigation sidebar matches the mkdocs structure
- Dark/light toggle works
- Admonitions render as coloured boxes (not raw `:::`)
- Mermaid diagram on `platform/security/cluster-roles` renders
- Images display correctly on `index` and `architecture/overview`

Stop the server with Ctrl+C when done.

- [ ] **Step 4: Commit the lockfile**

```bash
git add docs/package-lock.json
git commit -m "chore: add npm lockfile for docusaurus"
```

---

## Task 13: Remove `docs/mkdocs.yml`

**Files:**
- Delete: `docs/mkdocs.yml`

- [ ] **Step 1: Delete the file**

```bash
git rm docs/mkdocs.yml
```

- [ ] **Step 2: Commit**

```bash
git commit -m "chore: remove mkdocs.yml (replaced by docusaurus.config.js)"
```

---

## Self-Review Checklist

Checked against the spec:

| Requirement | Covered by |
|---|---|
| Convert mkdocs to Docusaurus | Tasks 1–3 (scaffold), Task 6 (migration script), Task 7 (run migration) |
| Same look and feel | Tasks 2 (indigo CSS), 3 (config with dark/light toggle), 7 (admonitions preserved, mermaid preserved) |
| Purely technology change | Markdown content unchanged; only syntax constructs converted |
| Update Makefile serve-docs | Task 10 |
| Update CI workflow | Task 11 |
| `getting-started/standalone-aws` orphan | Added to sidebar in Task 3 |
| Mermaid diagram support | `@docusaurus/theme-mermaid` in Tasks 1 & 2 |
| Static assets | Task 5 |
| .gitignore | Task 9 |
