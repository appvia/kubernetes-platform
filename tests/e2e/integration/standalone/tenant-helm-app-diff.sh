# Description: the purpose of these checks is to ensure the ignoreDifferences feature works as expected

load ../../lib/helper

setup() {
  [[ ! -f ${BATS_PARENT_TMPNAME}.skip ]] || skip "skip remaining tests"
}

teardown() {
  [[ -n $BATS_TEST_COMPLETED   ]] || touch "${BATS_PARENT_TMPNAME}.skip"
}

@test "We should have an helm-app-ignore helm application" {
  kubectl_argocd "get application -l app.kubernetes.io/name=helm-app-ignore"
}

@test "We should have a healthy helm-app-ignore application" {
  kubectl_argocd "get application -l app.kubernetes.io/name=helm-app-ignore -o yaml | yq .items[0].status.sync.status | grep -i synced"
}

@test "We should have ignoreDifferences configured in the application" {
  kubectl_argocd "get application -l app.kubernetes.io/name=helm-app-ignore -o yaml | yq '.items[0].spec.ignoreDifferences[0].kind' | grep -i ConfigMap"
}

@test "We should have the correct name in ignoreDifferences" {
  kubectl_argocd "get application -l app.kubernetes.io/name=helm-app-ignore -o yaml | yq '.items[0].spec.ignoreDifferences[0].name' | grep -i 'test-ignore-difference'"
}

@test "We should have jsonPointers configured in ignoreDifferences" {
  kubectl_argocd "get application -l app.kubernetes.io/name=helm-app-ignore -o yaml | yq '.items[0].spec.ignoreDifferences[0].jsonPointers[0]' | grep -i '/data'"
}

@test "We should have the helm-app-ignore namespace" {
  kubectl "get namespace tenant-helm-app-ignore"
  kubectl "get namespace tenant-helm-app-ignore -o yaml | yq .metadata.labels | grep -i 'platform.local/namespace: tenant'"
}

@test "We should have a label indicating a tenant application type" {
  kubectl "get namespace tenant-helm-app-ignore -o yaml | yq .metadata.labels | grep -i 'platform.local/namespace-type: tenant-application'"
}

@test "We should have a hello-world deployment" {
  kubectl "get deployment helm-app-ignore-hello-world -n tenant-ignore-difference-app"
  kubectl "get pod -l app.kubernetes.io/name=hello-world --no-headers -n tenant-helm-app-ignore | grep hello"
}
