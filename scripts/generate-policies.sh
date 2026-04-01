#!/usr/bin/env bash
#
## This script generates the policies documentation for the kyverno policies Helm chart
#
set -e

# Configuration
CHART_DIR="charts/kyverno-policies"
TEST_VALUES="scripts/test-kyverno-values.yaml"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Render the Helm chart to get actual policies
echo "Rendering chart..." >&2
helm template kyverno-policies "$CHART_DIR" -f "$TEST_VALUES" >"$TEMP_DIR/policies.yaml"

cat <<EOF
# Kyverno Policies

## Overview

Kyverno is a policy engine designed for Kubernetes that validates, mutates, and generates configurations using policies as Kubernetes resources. It provides key features like:

- Policy validation and enforcement
- Resource mutation and generation
- Image verification and security controls
- Audit logging and reporting
- Admission control webhooks

The following policies are shipped by default in this platform to enforce security best practices, resource management, and operational standards.

For detailed information about Kyverno's capabilities, refer to the [official documentation](https://kyverno.io/docs/) or [policy library](https://kyverno.io/policies/).

---
EOF

# Split rendered file by document separator and extract policies
mkdir -p "$TEMP_DIR/policies"

# Split documents using awk
awk '
BEGIN { 
  file_num = 0
  current_file = ""
}
/^---$/ {
  if (current_file != "" && NR > 1) {
    close(current_file)
    file_num++
  }
  next
}
{
  current_file = FILENAME ".policy_" file_num ".yaml"
  print $0 >> current_file
}
END {
  if (current_file != "") {
    close(current_file)
  }
}
' "$TEMP_DIR/policies.yaml"

# Now process each policy file
COUNT=0
for policy_file in "$TEMP_DIR/policies.yaml".policy_*.yaml; do
  [ -f "$policy_file" ] || continue

  # Skip empty files and comments
  if [ ! -s "$policy_file" ]; then
    continue
  fi

  # Check if this is actually a policy (has kind: ClusterPolicy or kind: Policy)
  if ! grep -q "^kind: ClusterPolicy\|^kind: Policy" "$policy_file"; then
    continue
  fi

  # Extract policy details using yq
  POLICY_NAME=$(yq e '.metadata.name' "$policy_file" 2>/dev/null || echo "")
  POLICY_KIND=$(yq e '.kind' "$policy_file" 2>/dev/null || echo "")

  if [ -z "$POLICY_NAME" ]; then
    continue
  fi

  POLICY_DESCRIPTION=$(yq e '.metadata.annotations."policies.kyverno.io/description" // "No description provided"' "$policy_file" 2>/dev/null || echo "No description provided")
  POLICY_CATEGORY=$(yq e '.metadata.annotations."policies.kyverno.io/category" // "Uncategorized"' "$policy_file" 2>/dev/null || echo "Uncategorized")
  POLICY_SEVERITY=$(yq e '.metadata.annotations."policies.kyverno.io/severity" // "medium"' "$policy_file" 2>/dev/null || echo "medium")

  # Determine if this is a cluster or namespaced policy
  POLICY_SCOPE="Namespaced"
  if [[ "$POLICY_KIND" == "ClusterPolicy" ]]; then
    POLICY_SCOPE="Cluster-wide"
  fi

  # Output policy as markdown
  echo "## :material-shield-lock: Rule: $POLICY_NAME"
  echo ""
  echo "**Category:** $POLICY_CATEGORY | **Severity:** $POLICY_SEVERITY | **Scope:** $POLICY_SCOPE"
  echo ""
  echo "$POLICY_DESCRIPTION"
  echo ""

  # Section for rules
  echo "**Rules**"
  echo ""

  # Extract number of rules
  RULE_COUNT=$(yq e '.spec.rules | length' "$policy_file" 2>/dev/null || echo 0)

  for ((j = 0; j < RULE_COUNT; j++)); do
    RULE_NAME=$(yq e ".spec.rules[$j].name" "$policy_file" 2>/dev/null || echo "")

    if [ ! -z "$RULE_NAME" ]; then
      # Determine rule type
      RULE_TYPE="Unknown"

      HAS_VALIDATE=$(yq e ".spec.rules[$j] | has(\"validate\")" "$policy_file" 2>/dev/null || echo "false")
      HAS_MUTATE=$(yq e ".spec.rules[$j] | has(\"mutate\")" "$policy_file" 2>/dev/null || echo "false")
      HAS_GENERATE=$(yq e ".spec.rules[$j] | has(\"generate\")" "$policy_file" 2>/dev/null || echo "false")

      if [[ "$HAS_VALIDATE" == "true" ]]; then
        RULE_TYPE="Validation"
      elif [[ "$HAS_MUTATE" == "true" ]]; then
        RULE_TYPE="Mutation"
      elif [[ "$HAS_GENERATE" == "true" ]]; then
        RULE_TYPE="Generation"
      fi

      echo "- **$RULE_NAME** ($RULE_TYPE)"

      # Try to extract match resources for additional context
      RESOURCES=$(yq e ".spec.rules[$j].match.resources.kinds[]" "$policy_file" 2>/dev/null || echo "")
      if [ ! -z "$RESOURCES" ]; then
        RESOURCES_STR=$(echo "$RESOURCES" | tr '\n' ', ' | sed 's/, $//')
        echo "  - Applies to: $RESOURCES_STR"
      fi

      echo ""
    fi
  done

  echo "---"
  echo ""

  COUNT=$((COUNT + 1))
done

echo "**Total Policies: $COUNT**"
