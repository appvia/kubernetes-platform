# Description: these tests verify the tenant kustomize application is correctly configured 

load ../../lib/helper

setup() {
  [[ ! -f ${BATS_PARENT_TMPNAME}.skip ]] || skip "skip remaining tests"
}

teardown() {
  [[ -n $BATS_TEST_COMPLETED   ]] || touch ${BATS_PARENT_TMPNAME}.skip
}

@test "We should have a tenant-kustomize-app namespace" {
  kubectl "get namespace tenant-kustomize-app"
}

@test "We should have a tenant-kustomize-app application" {
  kubectl "get application tenant-kustomize-app-dev -n argocd"
}

@test "We should have a healthy tenant-kustomize-app application" {
  kubectl "get application tenant-kustomize-app-dev -n argocd -o yaml | yq .status.health.status | grep -i healthy"
}

@test "We should have a tenant-kustomize-app deployment" {
  kubectl "get deployment tenant-kustomize-app-dev -n tenant-kustomize-app"
}

@test "We should have a tenant-kustomize-app label using a metadata key" {
  kubectl "get namespace tenant-kustomize-app -o yaml | yq .metadata.labels | grep -i 'parameter_metadata: ${CLUSTER_NAME}'"
}

@test "We should have a tenant-kustomize-app label using a metadata key with a missing value" {
  kubectl "get namespace tenant-kustomize-app -o yaml | yq .metadata.labels | grep -i 'parameter_metadata_missing: missing'"
}

@test "We should have a tenant-kustomize-app label using a metadata key with a missing value and a prefix" {
  kubectl "get namespace tenant-kustomize-app -o yaml | yq .metadata.labels | grep -i 'parameter_metadata_missing_prefix: prefix-${CLUSTER_NAME}'"
}