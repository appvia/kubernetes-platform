#!/usr/bin/env bash
#
## This script validates the addons/kustomize/ directory structure of the YAML files
#
KUSTOMIZE_DIR="addons/kustomize"

set -e

# Find all kustomize.yaml files under the addons/kustomize/ directory
find "$KUSTOMIZE_DIR" -name "kustomize.yaml" | while IFS= read -r file; do
  echo "--> Validating $file"
  # Validate the YAML is valid
  if ! yq eval -e '.' "$file" >/dev/null 2>&1; then
    echo "Error: $file - invalid YAML syntax"
    exit 1
  fi
  # Extract and validate required fields
  feature=$(yq eval '.feature' "$file" 2>/dev/null || echo "")
  namespace=$(yq eval '.namespace' "$file" 2>/dev/null || echo "")

  # Check we have a feature flag
  if [[ -z $feature ]]; then
    echo "Error: $file - kustomize.feature is empty"
    exit 1
  fi

  ## Check we have a namespace
  if [[ -z $namespace ]]; then
    echo "Error: $file - kustomize.namespace is empty"
    exit 1
  fi
done
