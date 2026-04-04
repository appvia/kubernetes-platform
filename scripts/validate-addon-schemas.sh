#!/usr/bin/env bash
#
# Validate addons/helm/**/*.yaml and addons/kustomize/**/kustomize.yaml against
# JSON Schemas (schemas/helm.json, schemas/kustomize.json).
#
# Prerequisites: check-jsonschema (pip install check-jsonschema)
#
set -euo pipefail

# Indicates we should validate them hlem addons
HELM_ADDONS=false
# Indicates we should validate them kustomize addons
KUSTOMIZE_ADDONS=false
# The location of the JSON Schema files
HELM_SCHEMA="schemas/helm.json"
# The location of the JSON Schema files
KUSTOMIZE_SCHEMA="schemas/kustomize.json"
# The number of validation errors found
ERRORS=0
# The root directory of the project (the parent of the
# directory containing this script)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat << EOF
Usage: $(basename "$0")
--helm  validate Helm addon YAML files (default: ${HELM_ADDONS})
--kustomize  validate Kustomize addon kustomize.yaml files (default: ${KUSTOMIZE_ADDONS})
--h, --help  show this help message and exit
EOF
  if [[ -n ${*}   ]]; then
    echo -e "\n[Error] ${*}"
    exit 1
  fi
  exit 0
}

validate-helm() {
  echo "=== Validating Helm addon YAML files ==="
  while IFS= read -r -d '' file; do
    rel="${file#./}"
    if check-jsonschema --schemafile "$HELM_SCHEMA" "$file" > /dev/null 2>&1; then
      echo "  PASS: $rel"
    else
      echo "  FAIL: $rel"
      check-jsonschema --schemafile "$HELM_SCHEMA" "$file" 2>&1 | sed 's/^/    /'
      ERRORS=$((ERRORS + 1))
    fi
  done < <(find "./addons/helm" -name "*.yaml" -print0)
  echo ""
}

validate-kustomize() {
  echo "=== Validating Kustomize addon kustomize.yaml files ==="
  while IFS= read -r -d '' file; do
    rel="${file#./}"
    if check-jsonschema --schemafile "$KUSTOMIZE_SCHEMA" "$file" > /dev/null 2>&1; then
      echo "  PASS: $rel"
    else
      echo "  FAIL: $rel"
      check-jsonschema --schemafile "$KUSTOMIZE_SCHEMA" "$file" 2>&1 | sed 's/^/    /'
      ERRORS=$((ERRORS + 1))
    fi
  done < <(find "./addons/kustomize" -name "kustomize.yaml" -print0)
  echo ""
}

# Ensure check-jsonschema is installed
if ! command -v check-jsonschema &> /dev/null; then
  usage "check-jsonschema not found. Install with: brew install check-jsonschema"
fi

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --helm)
      HELM_ADDONS=true
      shift
      ;;
    --kustomize)
      KUSTOMIZE_ADDONS=true
      shift
      ;;
    -h | --help)
      usage
      ;;
    *)
      usage "Unknown option: $1"
      ;;
  esac
done

cd "$ROOT_DIR"

# Check we have soeone specified at least one type of addon to validate
if [[ ${HELM_ADDONS} == false && ${KUSTOMIZE_ADDONS} == false ]]; then
  usage "At least one of --helm or --kustomize must be specified"
fi

# Ensure the schema files exist before we start validating
for schema in "$HELM_SCHEMA" "$KUSTOMIZE_SCHEMA" "schemas/addon-category.json"; do
  if [[ ! -f $schema ]]; then
    usage "Schema file not found: $schema"
  fi
done

# Run the helm validation if requested
[[ ${HELM_ADDONS} == true   ]] && validate-helm
# Run the kustomize validation if requested
[[ ${KUSTOMIZE_ADDONS} == true   ]] && validate-kustomize
# Exit with success if we found no errors
if [[ $ERRORS -eq 0 ]]; then
  echo "All addon definitions validated successfully."
  exit 0
fi

echo "Addon schema validation failed with $ERRORS error(s)."
exit 1
