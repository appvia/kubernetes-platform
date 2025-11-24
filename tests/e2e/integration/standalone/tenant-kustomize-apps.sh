# Description: these tests verify the tenant kustomize application is correctly configured 

load ../../lib/helper

setup() {
  [[ ! -f ${BATS_PARENT_TMPNAME}.skip ]] || skip "skip remaining tests"
}

teardown() {
  [[ -n $BATS_TEST_COMPLETED   ]] || touch ${BATS_PARENT_TMPNAME}.skip
}

@test "We should have a kustomize-app namespace" {
  kubectl "get namespace kustomize-app"
}

@test "We should have a kustomize-app application" {
  kubectl_argocd "get application kustomize-app-dev -n argocd"
}

@test "We should have a healthy kustomize-app application" {
  kubectl_argocd "get application kustomize-app-dev -n argocd -o yaml | yq .status.health.status | grep -i healthy"
}

@test "We should have a kustomize-app deployment" {
  kubectl "get deployment kustomize-app -n kustomize-app"
}

@test "We should have a kustomize-app label using a metadata key" {
  kubectl "get deployment kustomize-app -n kustomize-app -o yaml | yq .metadata.labels | grep -i 'parameter_metadata: dev'"
}

@test "We should have a kustomize-app label using a metadata key with a missing value" {
  kubectl "get deployment kustomize-app -n kustomize-app -o yaml | yq .metadata.labels | grep -i 'parameter_metadata_missing: missing'"
}

@test "We should have a kustomize-app deployment label using a metadata key with a missing value and a prefix" {
  kubectl "get deployment kustomize-app -n kustomize-app -o yaml | yq .metadata.labels | grep -i 'parameter_metadata_missing_prefix: prefix-dev'"
}