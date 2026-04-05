#!/usr/bin/env bash
set -e

CHART_DIR="charts/kyverno-policies"
TEST_VALUES="${1:-scripts/test-kyverno-values.yaml}"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Validation checks
check_kyverno() {
  if ! command -v kyverno &>/dev/null; then
    echo -e "${RED}✗ Kyverno CLI could not be found. Please install it first.${NC}"
    exit 1
  fi
}

check_helm() {
  if ! command -v helm &>/dev/null; then
    echo -e "${RED}✗ Helm could not be found. Please install it first.${NC}"
    exit 1
  fi
}

render_chart() {
  local values_file=$1
  echo -e "${YELLOW}→ Rendering Kyverno policies chart (${values_file})...${NC}"

  if ! helm template kyverno-policies "$CHART_DIR" -f "$values_file" >"$TEMP_DIR/rendered-policies.yaml" 2>&1; then
    echo -e "${RED}✗ Failed to render Kyverno policies chart${NC}"
    cat "$TEMP_DIR/rendered-policies.yaml"
    exit 1
  fi

  echo -e "${GREEN}✓ Chart rendered successfully${NC}"
}

validate_rendered_policies() {
  echo -e "${YELLOW}→ Validating rendered policies structure...${NC}"

  POLICY_COUNT=$(grep -c "^kind: ClusterPolicy" "$TEMP_DIR/rendered-policies.yaml" || true)
  if [ "$POLICY_COUNT" -eq 0 ]; then
    echo -e "${RED}✗ No policies were rendered from the chart${NC}"
    exit 1
  fi

  echo -e "${GREEN}✓ Found $POLICY_COUNT policies${NC}"
}

wipe_policy_directories() {
  find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -exec rm -rf {} + 2>/dev/null || true
}

split_rendered_policies() {
  current_policy=""
  current_file=""

  while IFS= read -r line; do
    if [[ "$line" == "# Source: kyverno-policies/templates/"* ]]; then
      policy_name=$(echo "$line" | sed 's/.*templates\/\([^.]*\)\.yaml.*/\1/')
      current_policy="$policy_name"
      current_file="$TEMP_DIR/$policy_name/policy.yaml"
      mkdir -p "$TEMP_DIR/$policy_name/.kyverno-test"
    elif [[ "$line" == "---" ]]; then
      if [ ! -z "$current_file" ] && [ ! -z "$current_policy" ]; then
        current_policy=""
        current_file=""
      fi
    elif [ ! -z "$current_file" ]; then
      echo "$line" >>"$current_file"
    fi
  done <"$TEMP_DIR/rendered-policies.yaml"
}

copy_chart_tests() {
  for test_policy_dir in "$CHART_DIR/tests"/*; do
    if [ -d "$test_policy_dir" ]; then
      policy_name=$(basename "$test_policy_dir")
      target_test_dir="$TEMP_DIR/$policy_name/.kyverno-test"

      if [ -d "$target_test_dir" ]; then
        for test_file in "$test_policy_dir"/*; do
          if [ -f "$test_file" ]; then
            cp "$test_file" "$target_test_dir/" 2>/dev/null || true
          fi
        done
      fi
    fi
  done
}

run_kyverno_cli_tests() {
  echo -e "${YELLOW}→ Running Kyverno unit tests...${NC}"

  if [ ! -d "$CHART_DIR/tests" ]; then
    echo -e "${YELLOW}⚠ No tests directory found, skipping tests${NC}"
    return 0
  fi

  if ! kyverno test "$TEMP_DIR" 2>&1 | tee "$TEMP_DIR/test-results.txt"; then
    echo -e "${RED}✗ Kyverno policy tests failed${NC}"
    exit 1
  fi

  echo -e "${GREEN}✓ Kyverno tests passed for this values set${NC}"
}

validate_with_tests() {
  local values_file=$1
  local deny_external_secrets_test_override=${2:-}

  render_chart "$values_file"
  validate_rendered_policies
  wipe_policy_directories
  split_rendered_policies
  copy_chart_tests

  if [ -n "$deny_external_secrets_test_override" ]; then
    override_src="$CHART_DIR/tests/deny-external-secrets/$deny_external_secrets_test_override"
    override_dst="$TEMP_DIR/deny-external-secrets/.kyverno-test/kyverno-test.yaml"
    if [ -f "$override_src" ] && [ -f "$override_dst" ]; then
      cp "$override_src" "$override_dst"
    fi
  fi

  run_kyverno_cli_tests
}

validate_chart_structure() {
  echo -e "${YELLOW}→ Validating Helm chart structure...${NC}"

  if [ ! -f "$CHART_DIR/Chart.yaml" ]; then
    echo -e "${RED}✗ Chart.yaml not found${NC}"
    exit 1
  fi

  if [ ! -f "$CHART_DIR/values.yaml" ]; then
    echo -e "${RED}✗ values.yaml not found${NC}"
    exit 1
  fi

  if [ -f "$CHART_DIR/.helmignore" ]; then
    if ! grep -q "^tests/" "$CHART_DIR/.helmignore"; then
      echo -e "${YELLOW}⚠ Warning: tests/ not in .helmignore${NC}"
    fi
  fi

  echo -e "${GREEN}✓ Chart structure valid${NC}"
}

# Main execution
main() {
  echo -e "${YELLOW}========================================${NC}"
  echo -e "${YELLOW}Kyverno Policies Validation${NC}"
  echo -e "${YELLOW}========================================${NC}"
  echo ""

  check_kyverno
  check_helm
  validate_chart_structure
  validate_with_tests "$TEST_VALUES"
  validate_with_tests "scripts/test-kyverno-external-secrets-aws-values.yaml" "kyverno-test-aws.yaml"

  echo ""
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}✓ All validations passed!${NC}"
  echo -e "${GREEN}========================================${NC}"
}

main "$@"
