#!/usr/bin/env bash
set -euo pipefail

FILE="addons/helm/cloud/aws.yaml"
MODE="safe"

usage() {
  cat <<'EOF'
Usage: scripts/update-helm-addon-versions.sh [--file PATH] [--mode safe|latest]

Updates Helm addon chart versions in the YAML file by querying upstream Helm repos.

Modes:
  safe   - conservative: keep major the same (or for 0.x keep minor the same)
  latest - always take the newest version available in the repo

Notes:
  - OCI/ECR charts (e.g. repository: public.ecr.aws) are skipped.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --file)
    FILE="$2"
    shift 2
    ;;
  --mode)
    MODE="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if [[ ${MODE} != "safe" && ${MODE} != "latest" ]]; then
  echo "Invalid --mode: ${MODE} (expected safe|latest)" >&2
  exit 2
fi

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is required on PATH" >&2
  exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "yq is required on PATH" >&2
  exit 1
fi

if [[ ! -f ${FILE} ]]; then
  echo "File not found: ${FILE}" >&2
  exit 1
fi

declare -A REPO_NAME_BY_URL=()
repo_name_for_url() {
  local url="$1"
  local name
  name="$(echo "${url}" | sed -e 's#https\?://##' -e 's#[^a-zA-Z0-9]#-#g' | tr '[:upper:]' '[:lower:]' | cut -c1-50)"
  if [[ -z ${name} ]]; then
    name="repo"
  fi
  echo "${name}"
}

ensure_repo() {
  local url="$1"
  local name="${REPO_NAME_BY_URL[${url}]:-}"
  if [[ -z ${name} ]]; then
    name="$(repo_name_for_url "${url}")"
    REPO_NAME_BY_URL["${url}"]="${name}"
  fi

  if ! helm repo list 2>/dev/null | awk '{print $1}' | grep -qx "${name}"; then
    helm repo add "${name}" "${url}" >/dev/null
  fi
}

normalize_version() {
  echo "$1" | sed -e 's/^v//'
}

safe_prefix() {
  # For >=1.x: keep major the same.
  # For 0.x: keep 0.minor the same (patch-only bumps).
  local current_norm="$1"
  local major minor
  major="$(echo "${current_norm}" | cut -d. -f1)"
  minor="$(echo "${current_norm}" | cut -d. -f2)"
  if [[ ${major} == "0" ]]; then
    echo "0.${minor}."
  else
    echo "${major}."
  fi
}

latest_version_for() {
  local repo_name="$1"
  local chart="$2"
  local current="$3"
  local mode="$4"

  local current_norm prefix
  current_norm="$(normalize_version "${current}")"
  prefix="$(safe_prefix "${current_norm}")"

  # Output "norm raw" pairs, filter, then pick max by norm sort.
  # shellcheck disable=SC2016
  local candidates
  if ! candidates="$(helm search repo "${repo_name}/${chart}" --versions 2>/dev/null | awk 'NR>1 {print $2}')"; then
    return 1
  fi

  if [[ -z ${candidates} ]]; then
    return 1
  fi

  if [[ ${mode} == "safe" ]]; then
    echo "${candidates}" |
      awk '{raw=$1; norm=raw; sub(/^v/,"",norm); print norm "\t" raw}' |
      awk -v pfx="${prefix}" '$1 ~ ("^" pfx) {print}' |
      sort -V -k1,1 |
      tail -n 1 |
      cut -f2
  else
    echo "${candidates}" |
      awk '{raw=$1; norm=raw; sub(/^v/,"",norm); print norm "\t" raw}' |
      sort -V -k1,1 |
      tail -n 1 |
      cut -f2
  fi
}

tmp="$(mktemp)"
cp "${FILE}" "${tmp}"

count="$(yq eval 'length' "${FILE}")"
if [[ ${count} -lt 1 ]]; then
  echo "No entries found in ${FILE}" >&2
  exit 1
fi

changed=0
skipped=0
failed=0

for i in $(seq 0 $((count - 1))); do
  feature="$(yq eval ".[$i].feature // \"\"" "${FILE}")"
  chart="$(yq eval ".[$i].chart // \"\"" "${FILE}")"
  repo="$(yq eval ".[$i].repository // \"\"" "${FILE}")"
  current="$(yq eval ".[$i].version // \"\"" "${FILE}")"

  if [[ -z ${feature} || -z ${chart} || -z ${repo} || -z ${current} ]]; then
    continue
  fi

  if [[ ${repo} == "public.ecr.aws" ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  # Skip built-in repositories (e.g., "platform" for local charts)
  if [[ ${repo} != https://* && ${repo} != http://* ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  ensure_repo "${repo}"
done

helm repo update >/dev/null

for i in $(seq 0 $((count - 1))); do
  feature="$(yq eval ".[$i].feature // \"\"" "${FILE}")"
  chart="$(yq eval ".[$i].chart // \"\"" "${FILE}")"
  repo="$(yq eval ".[$i].repository // \"\"" "${FILE}")"
  current="$(yq eval ".[$i].version // \"\"" "${FILE}")"

  if [[ -z ${feature} || -z ${chart} || -z ${repo} || -z ${current} ]]; then
    continue
  fi

  if [[ ${repo} == "public.ecr.aws" ]]; then
    echo "SKIP  ${feature}: OCI repo (${repo})"
    continue
  fi

  # Skip built-in repositories (e.g., "platform" for local charts)
  if [[ ${repo} != https://* && ${repo} != http://* ]]; then
    echo "SKIP  ${feature}: built-in repository (${repo})"
    continue
  fi

  repo_name="${REPO_NAME_BY_URL[${repo}]:-}"
  if [[ -z ${repo_name} ]]; then
    echo "FAIL  ${feature}: could not map repo url ${repo}" >&2
    failed=$((failed + 1))
    continue
  fi

  if ! latest="$(latest_version_for "${repo_name}" "${chart}" "${current}" "${MODE}")"; then
    echo "FAIL  ${feature}: could not resolve versions for ${repo_name}/${chart}" >&2
    failed=$((failed + 1))
    continue
  fi

  if [[ -z ${latest} ]]; then
    echo "FAIL  ${feature}: no candidate versions found for ${repo_name}/${chart}" >&2
    failed=$((failed + 1))
    continue
  fi

  if [[ ${latest} != "${current}" ]]; then
    echo "BUMP  ${feature}: ${current} -> ${latest}"
    yq eval -i ".[$i].version = \"${latest}\"" "${tmp}"
    changed=$((changed + 1))
  else
    echo "KEEP  ${feature}: ${current}"
  fi
done

if [[ ${failed} -gt 0 ]]; then
  echo "One or more entries failed to resolve versions (${failed})." >&2
  exit 1
fi

if ! diff -q "${FILE}" "${tmp}" >/dev/null 2>&1; then
  mv "${tmp}" "${FILE}"
  echo "Updated: ${FILE} (${changed} bumps, ${skipped} skipped)"
else
  rm -f "${tmp}"
  echo "No changes needed: ${FILE} (${skipped} skipped)"
fi
