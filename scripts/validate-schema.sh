#!/usr/bin/env bash
#
# This script validates all cluster and workload definitions in the release
# directory using check-jsonschema.
#
# Usage: scripts/validate-schema.sh
#
# Prerequisites:
#   - check-jsonschema installed (pip install check-jsonschema)
#

set -euo pipefail

# The location of the release directory and schema files
RELEASE_DIR="./release"
# The location of the JSON schema files (relative to the repository root)
CLUSTER_SCHEMA="schemas/clusters.json"
# The location of the workload schema file (relative to the repository root)
WORKLOAD_SCHEMA="schemas/applications.json"

ERRORS=0

## Check dependencies
if ! command -v check-jsonschema &> /dev/null; then
  echo "ERROR: check-jsonschema is not installed."
  echo "Install with: pip install check-jsonschema"
  exit 1
fi

## Check schemas exist
for schema in "$CLUSTER_SCHEMA" "$WORKLOAD_SCHEMA"; do
  if [[ ! -f $schema   ]]; then
    echo "ERROR: Schema file not found: $schema"
    exit 1
  fi
done

## Validate cluster definitions
echo "=== Validating cluster definitions ==="
while IFS= read -r -d '' cluster_file; do
  rel_path="${cluster_file}"
  if check-jsonschema --schemafile "$CLUSTER_SCHEMA" "$cluster_file" > /dev/null 2>&1; then
    echo "  PASS: $rel_path"
  else
    echo "  FAIL: $rel_path"
    check-jsonschema --schemafile "$CLUSTER_SCHEMA" "$cluster_file" 2>&1 | sed 's/^/    /'
    ERRORS=$((ERRORS + 1))
  fi
done < <(find "$RELEASE_DIR" -path "*/clusters/*.yaml" -print0)

## Validate workload definitions (applications and system workloads)
echo ""
echo "=== Validating workload definitions ==="
while IFS= read -r -d '' workload_file; do
  rel_path="${workload_file}"
  if check-jsonschema --schemafile "$WORKLOAD_SCHEMA" "$workload_file" > /dev/null 2>&1; then
    echo "  PASS: $rel_path"
  else
    echo "  FAIL: $rel_path"
    check-jsonschema --schemafile "$WORKLOAD_SCHEMA" "$workload_file" 2>&1 | sed 's/^/    /'
    ERRORS=$((ERRORS + 1))
  fi
done < <(find "$RELEASE_DIR" \( -path "*/workloads/applications/*" -o -path "*/workloads/system/*" \) -name "*.yaml" ! -name "kustomization.yaml" ! -name "deployment.yaml" -print0)

## Summary
echo ""
if [[ $ERRORS -eq 0 ]]; then
  echo "All definitions validated successfully."
  exit 0
else
  echo "Validation failed with $ERRORS error(s)."
  exit 1
fi
