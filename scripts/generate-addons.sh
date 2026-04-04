#!/usr/bin/env bash
#
# Generate docs/docs/catalog/features.md from addons/helm and addons/kustomize metadata.
#
# Prerequisites: yq (v4), jq
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT="docs/docs/catalog/features.md"

for cmd in yq jq; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "ERROR: $cmd is required"
    exit 1
  fi
done

category_title() {
  case "$1" in
    gitops) echo "GitOps" ;;
    security) echo "Security" ;;
    networking) echo "Networking" ;;
    observability) echo "Observability" ;;
    cost) echo "Cost" ;;
    storage) echo "Storage" ;;
    compute) echo "Compute" ;;
    workloads) echo "Workloads" ;;
    aws) echo "AWS" ;;
    platform) echo "Platform" ;;
    *) echo "$1" ;;
  esac
}

md_cell() {
  local s="${1:-}"
  s="${s//$'\n'/ }"
  s="${s//|/\\|}"
  printf '%s' "$s"
}

link_cell() {
  local link="${1:-}"
  local repo="${2:-}"
  local url="${link:-}"
  if [[ -z $url ]]; then
    if [[ $repo =~ ^https?:// ]]; then
      url="$repo"
    fi
  fi
  if [[ -n $url ]]; then
    printf '[docs](%s)' "$(md_cell "$url")"
  else
    printf '—'
  fi
}

ORDER=(gitops security networking observability cost storage compute workloads aws platform)

NDJSON="$(mktemp)"
trap 'rm -f "$NDJSON"' EXIT

while IFS= read -r -d '' helmfile; do
  yq -o=json '.' "$helmfile" | jq -c --arg src "${helmfile#./}" '.[] | . + {addon_kind: "helm", source: $src}'
done < <(find "./addons/helm" -name "*.yaml" -print0) >> "$NDJSON"

while IFS= read -r -d '' kfile; do
  yq -o=json '.' "$kfile" | jq -c --arg src "${kfile#./}" '{
    addon_kind: "kustomize",
    source: $src,
    feature: .kustomize.feature,
    category: .kustomize.category,
    description: .kustomize.description,
    link: (.kustomize.link // ""),
    namespace: .namespace.name,
    path: .kustomize.path,
    repository: (.kustomize.repository // "")
  }'
done < <(find "./addons/kustomize" -name "kustomize.yaml" -print0) >> "$NDJSON"

ALL_JSON=$(jq -s '.' "$NDJSON")

{
  echo "# Platform Addons"
  echo ""
  echo 'Each addon is enabled from the cluster definition using the feature flag label `enable_<feature>` (shown below as `enable_...`).'
  echo ""

  for cat in "${ORDER[@]}"; do
    title="$(category_title "$cat")"
    helm_json=$(echo "$ALL_JSON" | jq --arg c "$cat" '[.[] | select(.addon_kind == "helm" and .category == $c)] | sort_by(.feature)')
    kust_json=$(echo "$ALL_JSON" | jq --arg c "$cat" '[.[] | select(.addon_kind == "kustomize" and .category == $c)] | sort_by(.feature)')
    hcount=$(echo "$helm_json" | jq 'length')
    kcount=$(echo "$kust_json" | jq 'length')
    if [[ $hcount -eq 0 && $kcount -eq 0 ]]; then
      continue
    fi

    echo "## ${title}"
    echo ""

    if [[ $hcount -gt 0 ]]; then
      echo "### Helm"
      echo ""
      echo "| Chart | Namespace | Feature flag | Description | Link | Source |"
      echo "|-------|-----------|--------------|-------------|------|--------|"
      echo "$helm_json" | jq -c '.[]' | while IFS= read -r row; do
        feat=$(echo "$row" | jq -r '.feature')
        chart=$(echo "$row" | jq -r '.chart // "—"')
        ns=$(echo "$row" | jq -r '.namespace')
        desc=$(echo "$row" | jq -r '.description')
        link=$(echo "$row" | jq -r '.link // ""')
        repo=$(echo "$row" | jq -r '.repository')
        src=$(echo "$row" | jq -r '.source')
        flag="enable_${feat}"
        # shellcheck disable=SC2016
        printf '| %s | %s | `%s` | %s | %s | `%s` |\n' \
          "$(md_cell "$chart")" \
          "$(md_cell "$ns")" \
          "$flag" \
          "$(md_cell "$desc")" \
          "$(link_cell "$link" "$repo")" \
          "$(md_cell "$src")"
      done
      echo ""
    fi

    if [[ $kcount -gt 0 ]]; then
      echo "### Kustomize"
      echo ""
      echo "| Path | Namespace | Feature flag | Description | Link | Source |"
      echo "|------|-----------|--------------|-------------|------|--------|"
      echo "$kust_json" | jq -c '.[]' | while IFS= read -r row; do
        feat=$(echo "$row" | jq -r '.feature')
        path=$(echo "$row" | jq -r '.path')
        repo=$(echo "$row" | jq -r '.repository // empty')
        path_disp="$path"
        [[ -n $repo ]] && path_disp="${repo}@${path_disp}"
        ns=$(echo "$row" | jq -r '.namespace')
        desc=$(echo "$row" | jq -r '.description')
        link=$(echo "$row" | jq -r '.link // ""')
        src=$(echo "$row" | jq -r '.source')
        flag="enable_${feat}"
        # shellcheck disable=SC2016
        printf '| %s | %s | `%s` | %s | %s | `%s` |\n' \
          "$(md_cell "$path_disp")" \
          "$(md_cell "$ns")" \
          "$flag" \
          "$(md_cell "$desc")" \
          "$(link_cell "$link" "$repo")" \
          "$(md_cell "$src")"
      done
      echo ""
    fi
  done
} > "$OUT"

echo "Wrote $OUT"
